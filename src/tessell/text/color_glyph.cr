# Color glyph rasterization (M2-WP2, COLR/CPAL) — CPU only, no GL.
#
# Uses FreeType's color glyph layer API to composite layered grayscale masks
# tinted by CPAL palette colors into a premultiplied RGBA bitmap.

require "./ffi/freetype"
require "./ft_measurer"

module Tessell
  module Text
    # 预乘 RGBA，行优先、y 向下。pixels 长度 = w*h*4。
    struct ColorBitmap
      getter w : Int32
      getter h : Int32
      getter bearing_x : Int32
      getter bearing_y : Int32
      getter advance_px : Float32
      getter pixels : Bytes

      def initialize(@w, @h, @bearing_x, @bearing_y, @advance_px, @pixels)
      end

      def self.empty : ColorBitmap
        ColorBitmap.new(0, 0, 0, 0, 0.0_f32, Bytes.empty)
      end
    end

    class ColorRasterizer
      getter rasterize_calls : Int32 = 0

      def initialize(@measurer : FtMeasurer)
      end

      def color?(glyph_id : UInt32) : Bool
        return false if glyph_id == 0
        face = @measurer.ft_face_handle
        return false if face.null?
        flags = face.value.face_flags.to_u32
        return false if (flags & FT::FT_FACE_FLAG_COLOR) == 0_u32
        layers(glyph_id) > 0
      end

      def layers(glyph_id : UInt32) : Int32
        return 0 if glyph_id == 0
        face = @measurer.ft_face_handle
        return 0 if face.null?
        count = 0
        it = uninitialized FT::Lib::LayerIterator
        it.num_layers = 0_u32
        it.layer_index = 0_u32
        it.p = Pointer(UInt8).null
        ag = uninitialized UInt32
        ac = uninitialized UInt32
        loop do
          ret = FT::Lib.get_color_glyph_layer(face, glyph_id, pointerof(ag), pointerof(ac), pointerof(it))
          break if ret == 0
          count += 1
          break if count > 256
        end
        count
      end

      def rasterize_color(glyph_id : UInt32, size_px : Int32, fg : UInt32 = 0x000000ff_u32) : ColorBitmap
        @rasterize_calls += 1
        return ColorBitmap.empty if glyph_id == 0 || size_px <= 0
        face = @measurer.ft_face_handle
        return ColorBitmap.empty if face.null?

        px = size_px <= 0 ? 1_u32 : size_px.to_u32
        err = FT::Lib.set_pixel_sizes(face, 0_u32, px)
        return ColorBitmap.empty if err != 0

        # Advance from base glyph.
        adv_px = 0.0_f32
        if FT::Lib.load_glyph(face, glyph_id, FT::Lib::LOAD_DEFAULT) == 0
          slot = face.value.glyph
          unless slot.null?
            adv_px = (slot.value.advance.x.to_f32 / 64.0_f32)
          end
        end

        # Palette (may be null / unavailable).
        pdata = uninitialized FT::Lib::PaletteData
        pal_ptr = Pointer(FT::Lib::Color).null
        pal_count = 0_u32
        perr = FT::Lib.palette_data_get(face, pointerof(pdata))
        if perr == 0 && pdata.num_palettes > 0_u16
          serr = FT::Lib.palette_select(face, 0_u32, pointerof(pal_ptr))
          if serr == 0 && pal_ptr
            pal_count = pdata.num_palette_entries.to_u32
          else
            pal_ptr = Pointer(FT::Lib::Color).null
            pal_count = 0_u32
          end
        end

        # Collect layers with copied masks to compute union bbox.
        layer_list = [] of LayerMask
        it = uninitialized FT::Lib::LayerIterator
        it.num_layers = 0_u32
        it.layer_index = 0_u32
        it.p = Pointer(UInt8).null
        ag = uninitialized UInt32
        ac = uninitialized UInt32
        loop do
          ret = FT::Lib.get_color_glyph_layer(face, glyph_id, pointerof(ag), pointerof(ac), pointerof(it))
          break if ret == 0
          lerr = FT::Lib.load_glyph(face, ag, FT::Lib::LOAD_RENDER)
          if lerr == 0
            slot = face.value.glyph
            unless slot.null?
              bm = slot.value.bitmap
              mask = copy_bitmap_mask(bm)
              layer_list << LayerMask.new(mask, bm.width.to_i32, bm.rows.to_i32, slot.value.bitmap_left, slot.value.bitmap_top, ac)
            end
          end
          break if layer_list.size > 256
        end

        return ColorBitmap.new(0, 0, 0, 0, adv_px, Bytes.empty) if layer_list.empty?

        min_x = Int32::MAX
        max_x = Int32::MIN
        max_y = Int32::MIN
        min_y = Int32::MAX
        layer_list.each do |lm|
          l = lm.left
          t = lm.top
          r = l + lm.w
          b = t - lm.h
          min_x = l if l < min_x
          max_x = r if r > max_x
          max_y = t if t > max_y
          min_y = b if b < min_y
        end
        if min_x == Int32::MAX || max_x <= min_x || max_y <= min_y
          return ColorBitmap.new(0, 0, 0, 0, adv_px, Bytes.empty)
        end

        cw = max_x - min_x
        ch = max_y - min_y
        # Sanity cap.
        if cw <= 0 || ch <= 0 || cw > 4096 || ch > 4096
          return ColorBitmap.new(0, 0, 0, 0, adv_px, Bytes.empty)
        end

        canvas = Bytes.new(cw * ch * 4, 0_u8)

        layer_list.each do |lm|
          cr, cg, cb, ca = resolve_color(lm.color_index, pal_ptr, pal_count, fg)
          next if ca == 0_u8
          # Position in canvas: canvas origin (0,0) = (min_x, max_y) in FT bitmap coords
          ox = lm.left - min_x
          oy = max_y - lm.top
          lm.h.times do |y|
            sy = oy + y
            next if sy < 0 || sy >= ch
            lm.w.times do |x|
              sx = ox + x
              next if sx < 0 || sx >= cw
              mask = lm.mask[y * lm.w + x]
              next if mask == 0_u8
              src_a = ((ca.to_u32 * mask.to_u32 + 127_u32) // 255_u32).clamp(0_u32, 255_u32).to_u8
              next if src_a == 0_u8
              # premultiplied source
              sr = ((cr.to_u32 * src_a.to_u32 + 127_u32) // 255_u32).clamp(0_u32, 255_u32).to_u8
              sg = ((cg.to_u32 * src_a.to_u32 + 127_u32) // 255_u32).clamp(0_u32, 255_u32).to_u8
              sb = ((cb.to_u32 * src_a.to_u32 + 127_u32) // 255_u32).clamp(0_u32, 255_u32).to_u8
              di = (sy * cw + sx) * 4
              da = canvas[di + 3]
              inv = 255_u32 - src_a.to_u32
              canvas[di + 0] = (sr.to_u32 + (canvas[di + 0].to_u32 * inv + 127_u32) // 255_u32).clamp(0_u32, 255_u32).to_u8
              canvas[di + 1] = (sg.to_u32 + (canvas[di + 1].to_u32 * inv + 127_u32) // 255_u32).clamp(0_u32, 255_u32).to_u8
              canvas[di + 2] = (sb.to_u32 + (canvas[di + 2].to_u32 * inv + 127_u32) // 255_u32).clamp(0_u32, 255_u32).to_u8
              canvas[di + 3] = (src_a.to_u32 + (da.to_u32 * inv + 127_u32) // 255_u32).clamp(0_u32, 255_u32).to_u8
            end
          end
        end

        ColorBitmap.new(cw, ch, min_x, max_y, adv_px, canvas)
      end

      private struct LayerMask
        getter mask : Bytes
        getter w : Int32
        getter h : Int32
        getter left : Int32
        getter top : Int32
        getter color_index : UInt32

        def initialize(@mask, @w, @h, @left, @top, @color_index)
        end
      end

      private def copy_bitmap_mask(bm : FT::Lib::Bitmap) : Bytes
        w = bm.width.to_i32
        h = bm.rows.to_i32
        return Bytes.empty if w <= 0 || h <= 0 || bm.buffer.null?
        out = Bytes.new(w * h, 0_u8)
        pitch = bm.pitch
        src = bm.buffer
        h.times do |y|
          row_ptr = pitch >= 0 ? (src + y * pitch) : (src + (h - 1 - y) * (-pitch))
          w.times do |x|
            out[y * w + x] = row_ptr[x]
          end
        end
        out
      end

      # Returns straight RGBA tuple (r,g,b,a) for a color index.
      private def resolve_color(color_index : UInt32, pal : Pointer(FT::Lib::Color), pal_count : UInt32, fg : UInt32) : Tuple(UInt8, UInt8, UInt8, UInt8)
        if color_index == FT::FT_COLOR_FOREGROUND || pal.null? || pal_count == 0_u32 || color_index >= pal_count
          return unpack_rgba(fg)
        end
        c = pal[color_index]
        {c.red, c.green, c.blue, c.alpha}
      end

      # fg is 0xRRGGBBAA
      private def unpack_rgba(v : UInt32) : Tuple(UInt8, UInt8, UInt8, UInt8)
        r = ((v >> 24) & 0xFF).to_u8
        g = ((v >> 16) & 0xFF).to_u8
        b = ((v >> 8) & 0xFF).to_u8
        a = (v & 0xFF).to_u8
        {r, g, b, a}
      end
    end
  end
end
