# HarfBuzz FFI 绑定（M2-WP2a）
#
# 链接决策（有界选型实验，Crystal 1.22.1 on Windows, ucrt64/MSYS2 环境）：
# - 采用 `@[Link("harfbuzz")]` 直接链接（与 FreeType 同策略；本机可用 libharfbuzz.dll.a）。
#   运行期依赖 `C:\msys64\ucrt64\bin\libharfbuzz-0.dll`（需在 PATH 中）。
# - 若库缺失/不可用，`Tessell::Text::HB.available?` 返回 false 并给出清晰错误信息。
#
# 结构体布局以本机 gcc 探测值为准并在代码中断言。
#
module Tessell
  module Text
    module HB
      @[Link("harfbuzz")]
      lib Lib
        alias Bool32   = Int32
        alias Codepoint = UInt32
        alias Position  = Int32
        alias Mask      = UInt32
        alias Tag       = UInt32

        type Blob = Void*
        type Face = Void*
        type Font = Void*
        type Buffer = Void*
        type Language = Void*

        struct GlyphInfo
          codepoint : Codepoint
          mask      : Mask
          cluster   : UInt32
          var1      : UInt32
          var2      : UInt32
        end

        struct GlyphPosition
          x_advance : Position
          y_advance : Position
          x_offset  : Position
          y_offset  : Position
          var       : UInt32
        end

        # directions
        DIRECTION_INVALID = 0_i32
        DIRECTION_LTR     = 4_i32
        DIRECTION_RTL     = 5_i32
        DIRECTION_TTB     = 6_i32
        DIRECTION_BTT     = 7_i32

        fun blob_create_from_file = hb_blob_create_from_file(file_name : UInt8*) : Blob
        fun blob_destroy = hb_blob_destroy(blob : Blob) : Void

        fun face_create = hb_face_create(blob : Blob, index : UInt32) : Face
        fun face_destroy = hb_face_destroy(face : Face) : Void

        fun font_create = hb_font_create(face : Face) : Font
        fun font_destroy = hb_font_destroy(font : Font) : Void
        fun font_set_scale = hb_font_set_scale(font : Font, x_scale : Int32, y_scale : Int32) : Void
        fun font_get_scale = hb_font_get_scale(font : Font, x_scale : Int32*, y_scale : Int32*) : Void

        fun buffer_create = hb_buffer_create : Buffer
        fun buffer_destroy = hb_buffer_destroy(buffer : Buffer) : Void
        fun buffer_reset = hb_buffer_reset(buffer : Buffer) : Void
        fun buffer_add_utf8 = hb_buffer_add_utf8(buffer : Buffer, text : UInt8*, text_length : Int32, item_offset : UInt32, item_length : Int32) : Void
        fun buffer_set_direction = hb_buffer_set_direction(buffer : Buffer, direction : Int32) : Void
        fun buffer_set_script = hb_buffer_set_script(buffer : Buffer, script : Tag) : Void
        fun buffer_guess_segment_properties = hb_buffer_guess_segment_properties(buffer : Buffer) : Void

        fun shape = hb_shape(font : Font, buffer : Buffer, features : Void*, num_features : UInt32) : Void

        fun buffer_get_glyph_infos = hb_buffer_get_glyph_infos(buffer : Buffer, length : UInt32*) : GlyphInfo*
        fun buffer_get_glyph_positions = hb_buffer_get_glyph_positions(buffer : Buffer, length : UInt32*) : GlyphPosition*

        fun language_from_string = hb_language_from_string(str : UInt8*, len : Int32) : Language
        fun buffer_set_language = hb_buffer_set_language(buffer : Buffer, language : Language) : Void
      end

      def self.assert_layout! : Nil
        raise "HB: sizeof(GlyphInfo) expected 20 got #{sizeof(Lib::GlyphInfo)}" unless sizeof(Lib::GlyphInfo) == 20
        raise "HB: sizeof(GlyphPosition) expected 20 got #{sizeof(Lib::GlyphPosition)}" unless sizeof(Lib::GlyphPosition) == 20

        gi = uninitialized Lib::GlyphInfo
        gip = pointerof(gi).as(UInt8*)
        sizeof(Lib::GlyphInfo).times { |i| gip[i] = 0_u8 }
        (gip + 0).as(Lib::Codepoint*).value = 0x12345678_u32
        raise "HB: GlyphInfo.codepoint offset!=0" unless gi.codepoint == 0x12345678_u32
        (gip + 8).as(UInt32*).value = 0x87654321_u32
        raise "HB: GlyphInfo.cluster offset!=8" unless gi.cluster == 0x87654321_u32

        gp = uninitialized Lib::GlyphPosition
        gpp = pointerof(gp).as(UInt8*)
        sizeof(Lib::GlyphPosition).times { |i| gpp[i] = 0_u8 }
        (gpp + 0).as(Lib::Position*).value = 100_i32
        raise "HB: GlyphPosition.x_advance offset!=0" unless gp.x_advance == 100_i32
        (gpp + 4).as(Lib::Position*).value = 200_i32
        raise "HB: GlyphPosition.y_advance offset!=4" unless gp.y_advance == 200_i32
        (gpp + 8).as(Lib::Position*).value = 300_i32
        raise "HB: GlyphPosition.x_offset offset!=8" unless gp.x_offset == 300_i32
        (gpp + 12).as(Lib::Position*).value = 400_i32
        raise "HB: GlyphPosition.y_offset offset!=12" unless gp.y_offset == 400_i32
      end
    end
  end
end
