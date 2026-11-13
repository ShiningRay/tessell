# Tessell::Text::Rasterizer (M2-WP2c, M2-WP4 shaped-run cache task-73)
# FT rasterization -> glyph atlas. FFI calls go through FT::Lib / FtMeasurer; no new lib declarations.
# Requires FtMeasurer (face/font) and GlyphAtlas. Steady-state hit path does not rasterize again.
# M2-WP4: shaped-run cache keyed by (font_id, size_px, text_hash) caches whole shaped placement runs;
# frame-guarded LRU (no eviction inside begin_frame/end_frame), bounded capacity.

require "./ffi/freetype"
require "./ffi/harfbuzz"
require "./ft_measurer"
require "./glyph_atlas"

module Tessell
  module Text
    # Placement of one shaped glyph in atlas space.
    # uv in [0,1] over atlas page: (u0,v0)=top-left, (u1,v1)=bottom-right of glyph rect.
    # page: atlas page index for drawable glyphs, -1 for zero-bitmap/non-atlas placements.
    struct GlyphPlacement
      getter key : GlyphKey
      getter glyph_id : UInt32
      getter advance_px : Float32
      getter offset_x : Int32
      getter offset_y : Int32
      getter w : Int32
      getter h : Int32
      getter u0 : Float32
      getter v0 : Float32
      getter u1 : Float32
      getter v1 : Float32
      getter page : Int32

      def initialize(@key : GlyphKey, @glyph_id : UInt32, @advance_px : Float32,
                     @offset_x : Int32, @offset_y : Int32,
                     @w : Int32, @h : Int32,
                     @u0 : Float32, @v0 : Float32, @u1 : Float32, @v1 : Float32,
                     @page : Int32 = -1)
      end
    end

    struct ShapedRunKey
      getter font_id : Int32
      getter size_px : Int32
      getter text_hash : UInt64
      getter key_hash : UInt64

      def initialize(@font_id : Int32, @size_px : Int32, @text_hash : UInt64)
        h = 0xcbf29ce484222325_u64
        v = @font_id.to_u32!
        4.times do
          h ^= (v & 0xFF_u32).to_u64
          h &*= 0x100000001b3_u64
          v >>= 8
        end
        v = @size_px.to_u32!
        4.times do
          h ^= (v & 0xFF_u32).to_u64
          h &*= 0x100000001b3_u64
          v >>= 8
        end
        v = @text_hash
        8.times do
          h ^= (v & 0xFF_u64).to_u64
          h &*= 0x100000001b3_u64
          v >>= 8
        end
        @key_hash = h
      end

      def ==(other : ShapedRunKey) : Bool
        font_id == other.font_id && size_px == other.size_px && text_hash == other.text_hash
      end

      def hash : UInt64
        @key_hash
      end

      def hash(hasher)
        hasher.int(@key_hash.to_i64!)
        hasher
      end
    end

    class Rasterizer
      class FrameEvictionError < Exception
      end

      private class ShapedRunEntry
        property placements : Array(GlyphPlacement)
        property tick : UInt64

        def initialize(@placements : Array(GlyphPlacement), @tick : UInt64)
        end
      end

      getter hits : Int32
      getter misses : Int32
      getter rasters : Int32

      @measurer : FtMeasurer
      @atlas : GlyphAtlas
      @font_id : Int32
      @run_cache : Hash(ShapedRunKey, ShapedRunEntry)
      @run_cache_capacity : Int32
      @run_tick : UInt64
      @run_in_frame : Int32

      def initialize(@measurer : FtMeasurer, @atlas : GlyphAtlas, @font_id : Int32 = 0, run_cache_capacity : Int32 = 256)
        @hits = 0
        @misses = 0
        @rasters = 0
        @run_cache = Hash(ShapedRunKey, ShapedRunEntry).new
        @run_cache_capacity = run_cache_capacity
        @run_tick = 0_u64
        @run_in_frame = 0
      end

      def atlas : GlyphAtlas
        @atlas
      end

      def stats : NamedTuple(hits: Int32, misses: Int32, rasters: Int32)
        {hits: @hits, misses: @misses, rasters: @rasters}
      end

      def run_cache_size : Int32
        @run_cache.size
      end

      def begin_frame : Nil
        @run_in_frame += 1
      end

      def end_frame : Nil
        @run_in_frame -= 1 if @run_in_frame > 0
      end

      def in_run_frame? : Bool
        @run_in_frame > 0
      end

      # Alpha coverage of a placement: number of pixels with value > 0 in the atlas slot.
      def coverage(p : GlyphPlacement) : Int32
        slot = @atlas.lookup(p.key)
        return 0 unless slot
        return 0 if slot.w <= 0 || slot.h <= 0
        d = @atlas.page_data(slot.page)
        ps = @atlas.page_size
        count = 0
        y = 0
        while y < slot.h
          x = 0
          while x < slot.w
            count += 1 if d[(slot.y + y) * ps + (slot.x + x)] > 0
            x += 1
          end
          y += 1
        end
        count
      end

      def rasterize(text : String, size_px : Int32) : Array(GlyphPlacement)
        sink = [] of GlyphPlacement
        rasterize_into(text, size_px, sink)
        sink
      end

      # Zero-allocation entry for shaped run reuse. On hit: copies cached placements into sink (no HB/FT shaping).
      # Returns number of placements written.
      def shape_run_into(text : String, size_px : Int32, sink : Array(GlyphPlacement)) : Int32
        sink.clear
        return 0 if text.empty?

        key = ShapedRunKey.new(@font_id, size_px, text.hash.to_u64!)
        if entry = @run_cache[key]?
          entry.tick = @run_tick
          @run_tick += 1_u64
          cached = entry.placements
          i = 0
          n = cached.size
          while i < n
            sink << cached[i]
            i += 1
          end
          return n
        end

        # miss: shape+rasterize into sink, then cache a snapshot
        shape_and_rasterize_into(text, size_px, sink)
        store_run(key, sink)
        sink.size
      end

      # Non-allocating w.r.t. Array object: reuses sink (clear + push). Caller should
      # pre-size/capacity-reuse sink across calls for zero-allocation steady path.
      # Preserves per-glyph atlas hit/miss/raster stats semantics (HB/FT path each call).
      def rasterize_into(text : String, size_px : Int32, sink : Array(GlyphPlacement)) : Nil
        shape_and_rasterize_into(text, size_px, sink)
        nil
      end

      private def shape_and_rasterize_into(text : String, size_px : Int32, sink : Array(GlyphPlacement)) : Nil
        sink.clear
        return if text.empty?

        measurer = @measurer
        raise "FtMeasurer is closed" if measurer.closed?

        face = measurer.ft_face_handle
        hb_font = measurer.hb_font_handle
        hb_buffer = measurer.hb_buffer_handle
        upem = measurer.upem_value

        px = size_px <= 0 ? 1_u32 : size_px.to_u32
        err = FT::Lib.set_pixel_sizes(face, 0_u32, px)
        raise "FT_Set_Pixel_Sizes failed: #{err}" unless err == 0

        HB::Lib.buffer_reset(hb_buffer)
        HB::Lib.buffer_add_utf8(hb_buffer, text.to_unsafe, text.bytesize, 0_u32, text.bytesize)
        HB::Lib.buffer_guess_segment_properties(hb_buffer)
        HB::Lib.shape(hb_font, hb_buffer, Pointer(Void).null, 0_u32)

        glyph_count = 0_u32
        infos = HB::Lib.buffer_get_glyph_infos(hb_buffer, pointerof(glyph_count))
        positions = HB::Lib.buffer_get_glyph_positions(hb_buffer, pointerof(glyph_count))

        scale = size_px.to_f64 * 64.0 / upem.to_f64
        page_size_f = @atlas.page_size.to_f32

        i = 0_u32
        while i < glyph_count
          gid = infos[i].codepoint.to_u32
          pos = positions[i]
          adv_px = (pos.x_advance.to_f64 * scale / 64.0).to_f32

          placement = rasterize_glyph(gid, face, size_px, adv_px, page_size_f)
          sink << placement
          i += 1
        end
      end

      private def store_run(key : ShapedRunKey, sink : Array(GlyphPlacement)) : Nil
        ensure_run_capacity_for_insert
        # snapshot placements (allocates on miss/warmup only)
        cached = Array(GlyphPlacement).new(sink.size)
        i = 0
        n = sink.size
        while i < n
          cached << sink[i]
          i += 1
        end
        @run_cache[key] = ShapedRunEntry.new(cached, @run_tick)
        @run_tick += 1_u64
      end

      private def ensure_run_capacity_for_insert : Nil
        return if @run_cache.size < @run_cache_capacity
        if @run_in_frame > 0
          raise FrameEvictionError.new("shaped-run LRU eviction during frame is forbidden")
        end
        evict_run_lru(1)
      end

      def evict_run_lru(count : Int32 = 1) : Int32
        raise FrameEvictionError.new("shaped-run evict_lru called inside frame") if @run_in_frame > 0
        evicted = 0
        count.times do
          break if @run_cache.empty?
          victim = find_run_lru_key
          break unless victim
          @run_cache.delete(victim)
          evicted += 1
        end
        evicted
      end

      private def find_run_lru_key : ShapedRunKey?
        min_key : ShapedRunKey? = nil
        min_tick = UInt64::MAX
        @run_cache.each do |k, e|
          if e.tick < min_tick
            min_tick = e.tick
            min_key = k
          end
        end
        min_key
      end

      private def rasterize_glyph(gid : UInt32, face : FT::Lib::Face, size_px : Int32,
                                  advance_px : Float32, page_size_f : Float32) : GlyphPlacement
        key = GlyphKey.new(@font_id, gid, size_px, 0_u8, 0_u8)
        if slot = @atlas.lookup(key)
          @hits += 1
          return placement_from_slot(key, gid, advance_px, slot, page_size_f)
        end

        # glyph_id==0 means the font has no mapping for the codepoint (.notdef).
        # Emit a zero-bitmap placement (no atlas insert, no raster) so placement count
        # stays == HB glyph count and HB advance is preserved. Drawable area is empty.
        if gid == 0
          return GlyphPlacement.new(key, gid, advance_px, 0, 0, 0, 0,
                                    0.0_f32, 0.0_f32, 0.0_f32, 0.0_f32, -1)
        end

        @misses += 1
        @rasters += 1

        # FT_LOAD_RENDER: render outline to 8bpp gray bitmap (pixel_mode=2), no hinting/LCD.
        err = FT::Lib.load_glyph(face, gid, FT::Lib::LOAD_RENDER)
        raise "FT_Load_Glyph failed (glyph_id=#{gid}): #{err}" unless err == 0

        gslot = face.value.glyph
        raise "FT glyph slot is null (glyph_id=#{gid})" if gslot.null?

        bm = gslot.value.bitmap
        w = bm.width.to_i32
        h = bm.rows.to_i32
        bearing_x = gslot.value.bitmap_left.to_i32
        bearing_y = gslot.value.bitmap_top.to_i32

        # Empty bitmap (e.g. space, tab, some whitespace/control glyphs): do not insert into
        # atlas (GlyphAtlas rejects 0-size), but still emit placement with w=h=0, uv=0 and
        # correct HB advance so text layout/advance accumulation remains correct.
        if w <= 0 || h <= 0
          return GlyphPlacement.new(key, gid, advance_px, bearing_x, bearing_y, 0, 0,
                                    0.0_f32, 0.0_f32, 0.0_f32, 0.0_f32, -1)
        end

        atlas_slot = @atlas.insert(key, w, h, bearing_x, bearing_y, advance_px)
        copy_bitmap_to_atlas(bm, atlas_slot)
        placement_from_slot(key, gid, advance_px, atlas_slot, page_size_f)
      end

      private def copy_bitmap_to_atlas(bm : FT::Lib::Bitmap, slot : GlyphSlot) : Nil
        w = slot.w
        h = slot.h
        return if w <= 0 || h <= 0
        return if bm.buffer.null?

        pitch = bm.pitch
        src = bm.buffer
        dst_page = @atlas.page_data(slot.page)
        page_size = @atlas.page_size

        # FT pitch semantics (ftimage.h): positive pitch = top-down flow (row r at buffer + r*pitch);
        # negative pitch = bottom-up flow (row r at buffer + (rows-1-r)*(-pitch)).
        row = 0
        while row < h
          if pitch >= 0
            src_row = src + row * pitch
          else
            src_row = src + (h - 1 - row) * (-pitch)
          end
          dst_index = (slot.y + row) * page_size + slot.x
          col = 0
          while col < w
            dst_page[dst_index + col] = src_row[col]
            col += 1
          end
          row += 1
        end
      end

      private def placement_from_slot(key : GlyphKey, gid : UInt32, advance_px : Float32,
                                      slot : GlyphSlot, page_size_f : Float32) : GlyphPlacement
        if slot.w <= 0 || slot.h <= 0
          u0 = 0.0_f32; v0 = 0.0_f32; u1 = 0.0_f32; v1 = 0.0_f32
        else
          u0 = slot.x.to_f32 / page_size_f
          v0 = slot.y.to_f32 / page_size_f
          u1 = (slot.x + slot.w).to_f32 / page_size_f
          v1 = (slot.y + slot.h).to_f32 / page_size_f
        end
        GlyphPlacement.new(key, gid, advance_px, slot.bearing_x, slot.bearing_y,
                           slot.w, slot.h, u0, v0, u1, v1, slot.page)
      end
    end

    # Expose internals needed by Rasterizer without modifying ft_measurer.cr source file.
    # (Allowed: same module, no FFI added.)
    class FtMeasurer
      def ft_face_handle : FT::Lib::Face
        @ft_face
      end

      def hb_font_handle : HB::Lib::Font
        @hb_font
      end

      def hb_buffer_handle : HB::Lib::Buffer
        @hb_buffer
      end

      def upem_value : Int32
        @upem
      end
    end
  end
end
