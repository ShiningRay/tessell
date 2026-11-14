# Tessell::Text::GlyphAtlas (M2-WP2b)
# R8 single-channel glyph atlas with shelf packing, FNV-1a keyed cache, LRU eviction.
# Constraints: no FFI (pure Crystal + Bytes); steady path must not rearrange existing glyphs (UV stable).
# Frame contract: no LRU eviction inside begin_frame/end_frame (raises).
#
# GPU sync contract (issue #1): page_count/used_pixels/evicted_total are observability
# counters, NOT change detectors — glyphs are inserted into existing pages, so a
# stable page_count does not mean stable pixel content. Consumers must drive uploads
# from `revision` (any pixel mutation anywhere) or per-page `page_revision(page)` /
# `rgba_page_revision(page)`. GLBackend#sync_atlas_dirty consumes exactly that; a
# consumer that only compares page_count will miss in-frame glyph insertions and the
# GPU texture goes stale (missing characters at runtime).

module Tessell
  module Text
    struct GlyphKey
      getter font_id : Int32
      getter glyph_id : UInt32
      getter size_px : Int32
      getter subpixel : UInt8
      getter flags : UInt8
      getter key_hash : UInt64

      def initialize(@font_id : Int32, @glyph_id : UInt32, @size_px : Int32, @subpixel : UInt8, @flags : UInt8)
        @key_hash = GlyphKey.compute_hash(@font_id, @glyph_id, @size_px, @subpixel, @flags)
      end

      def self.compute_hash(font_id : Int32, glyph_id : UInt32, size_px : Int32, subpixel : UInt8, flags : UInt8) : UInt64
        h = 0xcbf29ce484222325_u64
        # font_id (Int32, little-endian bytes)
        v = font_id.to_u32!
        4.times do
          h ^= (v & 0xFF_u32).to_u64
          h &*= 0x100000001b3_u64
          v >>= 8
        end
        # glyph_id
        v = glyph_id
        4.times do
          h ^= (v & 0xFF_u32).to_u64
          h &*= 0x100000001b3_u64
          v >>= 8
        end
        # size_px
        v = size_px.to_u32!
        4.times do
          h ^= (v & 0xFF_u32).to_u64
          h &*= 0x100000001b3_u64
          v >>= 8
        end
        # subpixel, flags
        h ^= subpixel.to_u64
        h &*= 0x100000001b3_u64
        h ^= flags.to_u64
        h &*= 0x100000001b3_u64
        h
      end

      def ==(other : GlyphKey) : Bool
        font_id == other.font_id &&
          glyph_id == other.glyph_id &&
          size_px == other.size_px &&
          subpixel == other.subpixel &&
          flags == other.flags
      end

      def hash : UInt64
        @key_hash
      end

      def hash(hasher)
        hasher.int(@key_hash.to_i64!)
        hasher
      end
    end

    struct GlyphSlot
      getter page : Int32
      getter x : Int32
      getter y : Int32
      getter w : Int32
      getter h : Int32
      getter bearing_x : Int32
      getter bearing_y : Int32
      getter advance : Float32
      # true: slot lives in an RGBA page (color glyph, premultiplied 4B/px); false: R8 page.
      getter color : Bool

      def initialize(@page : Int32, @x : Int32, @y : Int32, @w : Int32, @h : Int32,
                     @bearing_x : Int32, @bearing_y : Int32, @advance : Float32,
                     @color : Bool = false)
      end
    end

    class GlyphAtlas
      class FrameEvictionError < Exception
      end

      struct Shelf
        getter y : Int32
        getter h : Int32
        property x : Int32

        def initialize(@y : Int32, @h : Int32, @x : Int32)
        end
      end

      class Page
        getter data : Bytes
        getter size : Int32
        getter shelves : Array(Shelf)
        property used_pixels : Int32
        property live_count : Int32
        # Monotonic per-page content version. Bumped on every pixel mutation
        # (glyph placement, page reset). GPU sync compares this against the
        # last-uploaded version to skip unchanged pages.
        getter revision : UInt64
        # bytes per pixel: 1 = R8 coverage page, 4 = premultiplied RGBA page.
        getter bpp : Int32

        def initialize(@size : Int32, @bpp : Int32 = 1)
          @data = Bytes.new(@size * @size * @bpp)
          @shelves = [] of Shelf
          @used_pixels = 0
          @live_count = 0
          @revision = 0_u64
        end

        def reset! : Nil
          # zeroing not required for correctness; keep buffer for reuse
          @shelves.clear
          @used_pixels = 0
          @live_count = 0
          @revision += 1_u64
        end

        def bump_revision : Nil
          @revision += 1_u64
        end
      end

      private class Entry
        property slot : GlyphSlot
        property tick : UInt64
        property font_id : Int32

        def initialize(@slot : GlyphSlot, @tick : UInt64, @font_id : Int32)
        end
      end

      getter page_size : Int32
      getter capacity : Int32
      # Monotonic atlas-wide content version. Bumped whenever any page's pixels
      # change (glyph inserted into an existing page included). This is the only
      # reliable "did the atlas content change" signal for GPU sync.
      getter revision : UInt64

      def initialize(@page_size : Int32 = 1024, @capacity : Int32 = 4096)
        @pages = [] of Page
        @free_page_indices = [] of Int32
        @cache = Hash(GlyphKey, Entry).new
        @tick = 0_u64
        @in_frame = 0
        @evicted_total = 0
        @revision = 0_u64
        # RGBA pages (color glyphs) are counted and packed independently of R8 pages:
        # page_count/used_pixels/waste_ratio keep R8-only semantics.
        @rgba_pages = [] of Page
        @rgba_free_page_indices = [] of Int32
        @rgba_cache = Hash(GlyphKey, Entry).new
      end

      def page_count : Int32
        @pages.size
      end

      def rgba_page_count : Int32
        @rgba_pages.size
      end

      def page_revision(page : Int32) : UInt64
        @pages[page].revision
      end

      def rgba_page_revision(page : Int32) : UInt64
        @rgba_pages[page].revision
      end

      def used_pixels : Int32
        total = 0
        @pages.each { |p| total += p.used_pixels }
        total
      end

      def waste_ratio : Float64
        pc = @pages.size
        return 0.0 if pc == 0
        total = pc.to_i64 * @page_size.to_i64 * @page_size.to_i64
        return 0.0 if total == 0
        1.0 - used_pixels.to_f64 / total.to_f64
      end

      def begin_frame : Nil
        @in_frame += 1
      end

      def end_frame : Nil
        @in_frame -= 1 if @in_frame > 0
      end

      def in_frame? : Bool
        @in_frame > 0
      end

      def evicted_total : Int32
        @evicted_total
      end

      def lookup(key : GlyphKey, color : Bool = false) : GlyphSlot?
        e = color ? @rgba_cache[key]? : @cache[key]?
        return nil unless e
        e.tick = @tick
        @tick += 1_u64
        e.slot
      end

      def insert(key : GlyphKey, w : Int32, h : Int32,
                 bearing_x : Int32 = 0, bearing_y : Int32 = 0, advance : Float32 = 0.0_f32) : GlyphSlot
        # P3-2 (0-size): zero/negative area is invalid input. Reject before any page/cache
        # mutation so zero-area slots cannot pollute shelves, used_pixels, waste_ratio or LRU.
        if w <= 0 || h <= 0
          raise ArgumentError.new("GlyphAtlas.insert: glyph size must be > 0 (got #{w}x#{h})")
        end
        # P3-2 (duplicate key): first insert wins. A later insert with the same key is
        # idempotent: bump the LRU tick and return the ORIGINAL slot, ignoring the new
        # w/h/bearing/advance (existing pixels/UV must never move or resize).
        if e = @cache[key]?
          e.tick = @tick
          @tick += 1_u64
          @cache[key] = e
          return e.slot
        end

        ensure_capacity_for_insert

        slot = place(key, w, h, bearing_x, bearing_y, advance)
        @cache[key] = Entry.new(slot, @tick, key.font_id)
        @tick += 1_u64
        slot
      end

      # Color-glyph insert into an RGBA page. Same duplicate-key/idempotent and
      # zero-size rules as insert; page indices address @rgba_pages only.
      def insert_rgba(key : GlyphKey, w : Int32, h : Int32,
                      bearing_x : Int32 = 0, bearing_y : Int32 = 0, advance : Float32 = 0.0_f32) : GlyphSlot
        if w <= 0 || h <= 0
          raise ArgumentError.new("GlyphAtlas.insert_rgba: glyph size must be > 0 (got #{w}x#{h})")
        end
        if e = @rgba_cache[key]?
          e.tick = @tick
          @tick += 1_u64
          @rgba_cache[key] = e
          return e.slot
        end

        ensure_capacity_for_insert

        slot = place_rgba(key, w, h, bearing_x, bearing_y, advance)
        @rgba_cache[key] = Entry.new(slot, @tick, key.font_id)
        @tick += 1_u64
        slot
      end

      def page_data(page : Int32) : Bytes
        @pages[page].data
      end

      def rgba_page_data(page : Int32) : Bytes
        @rgba_pages[page].data
      end

      def slot_rect(slot : GlyphSlot) : NamedTuple(x: Int32, y: Int32, w: Int32, h: Int32)
        {x: slot.x, y: slot.y, w: slot.w, h: slot.h}
      end

      def invalidate_font(font_id : Int32) : Int32
        to_remove = [] of GlyphKey
        @cache.each do |k, e|
          to_remove << k if e.font_id == font_id
        end
        @rgba_cache.each do |k, e|
          to_remove << k if e.font_id == font_id
        end
        to_remove.each do |k|
          remove_key(k)
        end
        to_remove.size
      end

      def evict_lru(count : Int32 = 1) : Int32
        raise FrameEvictionError.new("evict_lru called inside frame") if @in_frame > 0
        evicted = 0
        count.times do
          break if @cache.empty? && @rgba_cache.empty?
          victim = find_lru_key
          break unless victim
          remove_key(victim)
          evicted += 1
        end
        evicted
      end

      def clear : Nil
        @cache.clear
        @rgba_cache.clear
        @pages.each(&.reset!)
        @rgba_pages.each(&.reset!)
        @free_page_indices.clear
        @rgba_free_page_indices.clear
        # all pages become reusable
        i = 0
        while i < @pages.size
          @free_page_indices << i
          i += 1
        end
        i = 0
        while i < @rgba_pages.size
          @rgba_free_page_indices << i
          i += 1
        end
        @tick = 0_u64
        @evicted_total = 0
        @revision += 1_u64
      end

      private def ensure_capacity_for_insert : Nil
        return if @cache.size + @rgba_cache.size < @capacity
        if @in_frame > 0
          raise FrameEvictionError.new("LRU eviction during frame is forbidden")
        end
        evict_lru(1)
      end

      private def find_lru_key : GlyphKey?
        min_key : GlyphKey? = nil
        min_tick = UInt64::MAX
        @cache.each do |k, e|
          if e.tick < min_tick
            min_tick = e.tick
            min_key = k
          end
        end
        @rgba_cache.each do |k, e|
          if e.tick < min_tick
            min_tick = e.tick
            min_key = k
          end
        end
        min_key
      end

      private def remove_key(key : GlyphKey) : Nil
        e = @cache.delete(key)
        if e
          @evicted_total += 1
          page = @pages[e.slot.page]
          page.live_count -= 1
          # used_pixels kept (holes) unless page becomes fully free
          if page.live_count <= 0
            page.reset!
            unless @free_page_indices.includes?(e.slot.page)
              @free_page_indices << e.slot.page
            end
          end
          return
        end
        e2 = @rgba_cache.delete(key)
        if e2
          @evicted_total += 1
          page = @rgba_pages[e2.slot.page]
          page.live_count -= 1
          if page.live_count <= 0
            page.reset!
            unless @rgba_free_page_indices.includes?(e2.slot.page)
              @rgba_free_page_indices << e2.slot.page
            end
          end
        end
      end

      private def place(key : GlyphKey, w : Int32, h : Int32,
                        bearing_x : Int32, bearing_y : Int32, advance : Float32) : GlyphSlot
        # try existing pages
        i = 0
        while i < @pages.size
          p = @pages[i]
          if (slot = try_place_in_page(i, p, w, h, bearing_x, bearing_y, advance))
            return slot
          end
          i += 1
        end
        # P3-1: reject oversized glyph BEFORE acquiring a page. Previously we allocated a
        # fresh page and then raised, leaving a stray empty page (page_count grew) while
        # old slots stayed valid. Pre-check keeps page_count, cache and pages untouched.
        if w > @page_size || h > @page_size
          raise "Glyph (#{w}x#{h}) does not fit in empty page of size #{@page_size}"
        end
        # need new page
        page_index = acquire_page
        p = @pages[page_index]
        slot = try_place_in_page(page_index, p, w, h, bearing_x, bearing_y, advance)
        unless slot
          raise "Glyph (#{w}x#{h}) does not fit in empty page of size #{@page_size}"
        end
        slot
      end

      private def place_rgba(key : GlyphKey, w : Int32, h : Int32,
                             bearing_x : Int32, bearing_y : Int32, advance : Float32) : GlyphSlot
        # try existing RGBA pages
        i = 0
        while i < @rgba_pages.size
          p = @rgba_pages[i]
          if (slot = try_place_in_page(i, p, w, h, bearing_x, bearing_y, advance, true))
            return slot
          end
          i += 1
        end
        if w > @page_size || h > @page_size
          raise "Color glyph (#{w}x#{h}) does not fit in empty RGBA page of size #{@page_size}"
        end
        page_index = acquire_rgba_page
        p = @rgba_pages[page_index]
        slot = try_place_in_page(page_index, p, w, h, bearing_x, bearing_y, advance, true)
        unless slot
          raise "Color glyph (#{w}x#{h}) does not fit in empty RGBA page of size #{@page_size}"
        end
        slot
      end

      private def acquire_rgba_page : Int32
        if @rgba_free_page_indices.size > 0
          idx = @rgba_free_page_indices.pop
          @rgba_pages[idx].reset!
          return idx
        end
        idx = @rgba_pages.size
        @rgba_pages << Page.new(@page_size, 4)
        idx
      end

      private def acquire_page : Int32
        if @free_page_indices.size > 0
          idx = @free_page_indices.pop
          @pages[idx].reset!
          return idx
        end
        idx = @pages.size
        @pages << Page.new(@page_size)
        idx
      end

      private def try_place_in_page(page_index : Int32, page : Page, w : Int32, h : Int32,
                                    bearing_x : Int32, bearing_y : Int32, advance : Float32,
                                    color : Bool = false) : GlyphSlot?
        # try existing shelves
        si = 0
        while si < page.shelves.size
          sh = page.shelves[si]
          if h <= sh.h && sh.x + w <= @page_size
            x = sh.x
            y = sh.y
            sh.x = sh.x + w
            page.shelves[si] = sh
            page.used_pixels += w * h
            page.live_count += 1
            page.bump_revision
            @revision += 1_u64
            return GlyphSlot.new(page_index, x, y, w, h, bearing_x, bearing_y, advance, color)
          end
          si += 1
        end
        # try new shelf
        y_start = 0
        if page.shelves.size > 0
          last = page.shelves.last
          y_start = last.y + last.h
        end
        if y_start + h <= @page_size && w <= @page_size
          sh = Shelf.new(y_start, h, w)
          page.shelves << sh
          page.used_pixels += w * h
          page.live_count += 1
          page.bump_revision
          @revision += 1_u64
          return GlyphSlot.new(page_index, 0, y_start, w, h, bearing_x, bearing_y, advance, color)
        end
        nil
      end
    end
  end
end