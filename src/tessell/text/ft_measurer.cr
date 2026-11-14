# FtMeasurer: FreeType + HarfBuzz 真实测量（M2-WP2a）
# 依赖：text/ffi/freetype.cr、text/ffi/harfbuzz.cr（FFI 仅在该层与本文件）
# 运行期需 PATH 包含 C:\msys64\ucrt64\bin（libfreetype-6.dll, libharfbuzz-0.dll）。
#
require "../geometry"
require "./measurer"
require "./ffi/freetype"
require "./ffi/harfbuzz"

module Tessell
  module Text
    class FtMeasurer < Measurer
      getter? closed : Bool = false
      getter measure_calls : Int32 = 0
      getter last_error : String?

      def ft_face_handle : FT::Lib::Face
        @ft_face
      end

      def upem_value : Int32
        @upem
      end

      @ft_library : FT::Lib::Library
      @ft_face : FT::Lib::Face
      @hb_blob : HB::Lib::Blob
      @hb_face : HB::Lib::Face
      @hb_font : HB::Lib::Font
      @hb_buffer : HB::Lib::Buffer
      @upem : Int32 = 0

      def self.available? : Bool
        begin
          FT.assert_layout!
          HB.assert_layout!
          ft_lib = uninitialized FT::Lib::Library
          err = FT::Lib.init_free_type(pointerof(ft_lib))
          if err != 0
            @@unavailable_reason = "FT_Init_FreeType failed: #{err}"
            return false
          end
          FT::Lib.done_free_type(ft_lib)
          @@unavailable_reason = nil
          true
        rescue ex
          @@unavailable_reason = ex.message || ex.class.name
          false
        end
      end

      @@unavailable_reason : String? = nil

      def self.unavailable_reason : String?
        @@unavailable_reason
      end

      def self.open(path : String, ttc_index : Int32 = 0) : FtMeasurer
        unless File.exists?(path)
          raise "FtMeasurer.open: font file not found: #{path}"
        end
        new(path, ttc_index)
      end

      private def initialize(@path : String, @ttc_index : Int32)
        FT.assert_layout!
        HB.assert_layout!
        @last_error = nil

        ft_lib = uninitialized FT::Lib::Library
        err = FT::Lib.init_free_type(pointerof(ft_lib))
        raise "FT_Init_FreeType failed: #{err}" unless err == 0
        @ft_library = ft_lib

        ft_face = uninitialized FT::Lib::Face
        err = FT::Lib.new_face(@ft_library, @path.to_unsafe, @ttc_index.to_i32, pointerof(ft_face))
        unless err == 0
          FT::Lib.done_free_type(@ft_library)
          raise "FT_New_Face failed (#{@path}, index=#{@ttc_index}): #{err}"
        end
        @ft_face = ft_face
        @upem = @ft_face.value.units_per_EM.to_i32
        @upem = 2048 if @upem <= 0

        @hb_blob = HB::Lib.blob_create_from_file(@path.to_unsafe)
        if @hb_blob.null?
          cleanup_ft
          raise "hb_blob_create_from_file failed: #{@path}"
        end
        @hb_face = HB::Lib.face_create(@hb_blob, @ttc_index.to_u32)
        if @hb_face.null?
          HB::Lib.blob_destroy(@hb_blob)
          cleanup_ft
          raise "hb_face_create failed"
        end
        @hb_font = HB::Lib.font_create(@hb_face)
        if @hb_font.null?
          HB::Lib.face_destroy(@hb_face)
          HB::Lib.blob_destroy(@hb_blob)
          cleanup_ft
          raise "hb_font_create failed"
        end
        HB::Lib.font_set_scale(@hb_font, @upem, @upem)
        @hb_buffer = HB::Lib.buffer_create
        if @hb_buffer.null?
          cleanup_hb_partial
          cleanup_ft
          raise "hb_buffer_create failed"
        end
      end

      private def cleanup_ft
        if @ft_face && !@ft_face.null?
          FT::Lib.done_face(@ft_face)
          @ft_face = Pointer(FT::Lib::FaceRec).null.as(FT::Lib::Face)
        end
        if @ft_library
          FT::Lib.done_free_type(@ft_library)
          @ft_library = Pointer(Void).null.as(FT::Lib::Library)
        end
      end

      private def cleanup_hb_partial
        HB::Lib.font_destroy(@hb_font) if @hb_font && !@hb_font.null?
        HB::Lib.face_destroy(@hb_face) if @hb_face && !@hb_face.null?
        HB::Lib.blob_destroy(@hb_blob) if @hb_blob && !@hb_blob.null?
        @hb_font = Pointer(Void).null.as(HB::Lib::Font)
        @hb_face = Pointer(Void).null.as(HB::Lib::Face)
        @hb_blob = Pointer(Void).null.as(HB::Lib::Blob)
      end

      def close : Nil
        return if @closed
        @closed = true
        if @hb_buffer && !@hb_buffer.null?
          HB::Lib.buffer_destroy(@hb_buffer)
          @hb_buffer = Pointer(Void).null.as(HB::Lib::Buffer)
        end
        cleanup_hb_partial
        cleanup_ft
      end

      def finalize
        close
      rescue
      end

      # 实现 Measurer 接口：font_id 被忽略（本实例绑定单一 face）
      def measure(text : String, font_id : Int32, size : Float32, max_width : Float32) : Size
        @measure_calls += 1
        return Size.new(0.0_f32, 0.0_f32) if @closed
        return Size.new(0.0_f32, 0.0_f32) if text.empty?

        px = size <= 0 ? 1_u32 : size.round.to_u32
        px = 1_u32 if px == 0
        err = FT::Lib.set_pixel_sizes(@ft_face, 0_u32, px)
        if err != 0
          @last_error = "FT_Set_Pixel_Sizes failed: #{err}"
          return Size.new(0.0_f32, 0.0_f32)
        end

        # line height from FT size metrics (26.6)
        sz = @ft_face.value.size
        line_height = 0.0_f32
        if sz && !sz.null?
          h26 = sz.value.metrics.height
          if h26 != 0
            line_height = (h26.abs.to_f32 / 64.0_f32)
          else
            asc = sz.value.metrics.ascender
            desc = sz.value.metrics.descender
            line_height = ((asc - desc).abs.to_f32 / 64.0_f32)
          end
        end
        line_height = size * 1.2_f32 if line_height <= 0.0_f32

        # HB shaping
        HB::Lib.buffer_reset(@hb_buffer)
        HB::Lib.buffer_add_utf8(@hb_buffer, text.to_unsafe, text.bytesize, 0_u32, text.bytesize)
        HB::Lib.buffer_guess_segment_properties(@hb_buffer)
        HB::Lib.shape(@hb_font, @hb_buffer, Pointer(Void).null, 0_u32)

        glyph_count = 0_u32
        infos = HB::Lib.buffer_get_glyph_infos(@hb_buffer, pointerof(glyph_count))
        positions = HB::Lib.buffer_get_glyph_positions(@hb_buffer, pointerof(glyph_count))

        scale = size.to_f64 * 64.0 / @upem.to_f64
        advances = Array(Float32).new(glyph_count.to_i)

        if glyph_count == 0
          # fallback: per-char FT advance
          text.each_char do |ch|
            advances << ft_char_advance(ch.ord.to_u32, scale)
          end
        else
          i = 0_u32
          while i < glyph_count
            adv_hb = positions[i].x_advance
            if adv_hb == 0
              # fallback for this glyph slot: try FT by glyph id/codepoint mapping is non-trivial;
              # use FT advance of corresponding cluster char if possible, else 0
              # easier: recompute per-char FT for whole text in fallback? keep simple:
              # fallback per-glyph via codepoint from infos? not available; use FT_Get_Char_Index+load
              gid = infos[i].codepoint
              advances << ft_glyph_advance(gid.to_u32, scale)
            else
              advances << (adv_hb.to_f64 * scale / 64.0).to_f32
            end
            i += 1
          end
          # if all became zero (unlikely) fallback to per-char
          if advances.all? { |a| a == 0.0_f32 } && !text.empty?
            advances.clear
            text.each_char do |ch|
              advances << ft_char_advance(ch.ord.to_u32, scale)
            end
          end
        end

        # wrapping
        if max_width > 0.0_f32
          lines = 1
          line_w = 0.0_f32
          max_line_w = 0.0_f32
          advances.each do |adv|
            if line_w > 0.0_f32 && (line_w + adv) > max_width
              max_line_w = line_w if line_w > max_line_w
              lines += 1
              line_w = adv
            else
              line_w += adv
            end
          end
          max_line_w = line_w if line_w > max_line_w
          max_line_w = max_width if max_line_w > max_width
          Size.new(max_line_w, line_height * lines)
        else
          total = 0.0_f32
          advances.each { |a| total += a }
          Size.new(total, line_height)
        end
      end

      # 字体度量（issue #6）：读 FT size metrics（26.6 定点 → px）。
      def font_metrics(font_id : Int32, size : Float32) : FontMetrics
        return FontMetrics.new(0.0_f32, 0.0_f32, size * 1.2_f32) if @closed
        px = size <= 0 ? 1_u32 : size.round.to_u32
        px = 1_u32 if px == 0
        err = FT::Lib.set_pixel_sizes(@ft_face, 0_u32, px)
        if err != 0
          @last_error = "FT_Set_Pixel_Sizes failed: #{err}"
          return FontMetrics.new(size * 0.8_f32, size * 0.2_f32, size * 1.2_f32)
        end
        sz = @ft_face.value.size
        ascent = size * 0.8_f32
        descent = size * 0.2_f32
        line_height = size * 1.2_f32
        if sz && !sz.null?
          m = sz.value.metrics
          if m.ascender != 0 || m.descender != 0
            ascent = (m.ascender.abs.to_f32 / 64.0_f32)
            descent = (m.descender.abs.to_f32 / 64.0_f32)
            line_height = ((m.ascender - m.descender).abs.to_f32 / 64.0_f32)
          end
          if m.height != 0
            lh = m.height.abs.to_f32 / 64.0_f32
            line_height = lh if lh > 0.0_f32
          end
        end
        FontMetrics.new(ascent, descent, line_height)
      end

      # cmap 覆盖检测（issue #7）：text 的每个码点在当前 face 的 cmap 中
      # 都有非零 glyph id 才返回 true。FontStack 按它选脸，零 FFI 新声明。
      def covers?(text : String) : Bool
        return false if @closed
        return true if text.empty?
        text.each_char do |ch|
          cp = ch.ord.to_u32
          return false if FT::Lib.get_char_index(@ft_face, cp) == 0
        end
        true
      end

      # 测量辅助：返回 HB shaping 的 glyph ids 与 x_advances(px) 供 spec 验证
      def shape_info(text : String, size : Float32) : NamedTuple(glyph_ids: Array(UInt32), advances_px: Array(Float32), ft_char_index: Hash(UInt32, UInt32))
        result_ids = [] of UInt32
        result_advs = [] of Float32
        ft_map = {} of UInt32 => UInt32
        return {glyph_ids: result_ids, advances_px: result_advs, ft_char_index: ft_map} if @closed || text.empty?

        px = size <= 0 ? 1_u32 : size.round.to_u32
        px = 1_u32 if px == 0
        FT::Lib.set_pixel_sizes(@ft_face, 0_u32, px)

        HB::Lib.buffer_reset(@hb_buffer)
        HB::Lib.buffer_add_utf8(@hb_buffer, text.to_unsafe, text.bytesize, 0_u32, text.bytesize)
        HB::Lib.buffer_guess_segment_properties(@hb_buffer)
        HB::Lib.shape(@hb_font, @hb_buffer, Pointer(Void).null, 0_u32)

        glyph_count = 0_u32
        infos = HB::Lib.buffer_get_glyph_infos(@hb_buffer, pointerof(glyph_count))
        positions = HB::Lib.buffer_get_glyph_positions(@hb_buffer, pointerof(glyph_count))
        scale = size.to_f64 * 64.0 / @upem.to_f64

        i = 0_u32
        while i < glyph_count
          result_ids << infos[i].codepoint
          result_advs << (positions[i].x_advance.to_f64 * scale / 64.0).to_f32
          i += 1
        end

        text.each_char do |ch|
          cp = ch.ord.to_u32
          unless ft_map.has_key?(cp)
            ft_map[cp] = FT::Lib.get_char_index(@ft_face, cp).to_u32
          end
        end
        {glyph_ids: result_ids, advances_px: result_advs, ft_char_index: ft_map}
      end

      private def ft_char_advance(charcode : UInt32, scale : Float64) : Float32
        gid = FT::Lib.get_char_index(@ft_face, charcode)
        return 0.0_f32 if gid == 0
        ft_glyph_advance(gid.to_u32, scale)
      end

      private def ft_glyph_advance(gid : UInt32, scale : Float64) : Float32
        err = FT::Lib.load_glyph(@ft_face, gid, FT::Lib::LOAD_NO_BITMAP)
        return 0.0_f32 unless err == 0
        slot = @ft_face.value.glyph
        return 0.0_f32 if slot.null?
        # advance.x is 26.6 in some modes but with LOAD_NO_BITMAP/FT_Set_Pixel_Sizes it's in 16.16? 
        # after FT_Set_Pixel_Sizes and LOAD_NO_BITMAP, slot.advance.x is in 26.6 format when using FT_LOAD_DEFAULT? 
        # FT_LOAD_NO_BITMAP means don't render bitmap but metrics are still computed; advance is in 26.6 for scaled face.
        adv26 = slot.value.advance.x
        (adv26.to_f64 / 64.0).to_f32
      end
    end
  end
end
