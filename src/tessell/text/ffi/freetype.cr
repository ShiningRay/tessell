# FreeType FFI 绑定（M2-WP2a）
#
# 链接决策（有界选型实验，Crystal 1.22.1 on Windows, ucrt64/MSYS2 环境）：
# - 尝试 `@[Link("freetype")]` 直接链接：无 BOM 的最小 `crystal build` 样例 BUILD_EXIT=0（成功）。
#   GNU 导入库 libfreetype.dll.a 在本机可被 Crystal/MSVC link 流程接受；未改用动态绑定。
# - 运行期依赖 `C:\msys64\ucrt64\bin\libfreetype-6.dll`（需在 PATH 中）。
# - 若库缺失/不可用，`Tessell::Text::FT.available?` / `FtMeasurer.available?` 返回 false 并给出清晰错误信息。
#
# 结构体布局以本机 gcc (ucrt64, 64-bit, sizeof(void*)=8) 探测值为准并在代码中断言，
# 防止 M0 踩过的 FT_Bitmap pad/偏移猜测错误。
#
module Tessell
  module Text
    module FT
      @[Link("freetype")]
      lib Lib
        alias Long   = Int32
        alias ULong  = UInt32
        alias Int    = Int32
        alias UInt   = UInt32
        alias Short  = Int16
        alias UShort = UInt16
        alias Char   = UInt8
        alias Pos    = Int32
        alias Fixed  = Int32
        alias F26Dot6 = Int32
        alias Error  = Int32

        type Library = Void*

        struct Vector
          x : Pos
          y : Pos
        end

        struct Generic
          data      : Void*
          finalizer : Void*
        end

        struct BitmapSize
          height : Short
          width  : Short
          size   : Pos
          x_ppem : Pos
          y_ppem : Pos
        end

        struct BBox
          x_min : Pos
          y_min : Pos
          x_max : Pos
          y_max : Pos
        end

        struct Bitmap
          rows         : UInt32
          width        : UInt32
          pitch        : Int32
          buffer       : UInt8*
          num_grays    : UInt16
          pixel_mode   : UInt8
          palette_mode : UInt8
          palette      : Void*
        end

        struct GlyphMetrics
          width          : Pos
          height         : Pos
          hori_bearing_x : Pos
          hori_bearing_y : Pos
          hori_advance   : Pos
          vert_bearing_x : Pos
          vert_bearing_y : Pos
          vert_advance   : Pos
        end

        struct Outline
          n_contours : Int16
          n_points   : Int16
          points     : Vector*
          tags       : UInt8*
          contours   : Int16*
          flags      : Int32
        end

        struct SizeMetrics
          x_ppem      : UShort
          y_ppem      : UShort
          x_scale     : Fixed
          y_scale     : Fixed
          ascender    : Pos
          descender   : Pos
          height      : Pos
          max_advance : Pos
        end

        struct GlyphSlotRec
          library             : Library
          face                : Void* # FT_Face back-ref
          next                : GlyphSlotRec*
          glyph_index         : UInt
          generic             : Generic
          metrics             : GlyphMetrics
          linear_hori_advance : Fixed
          linear_vert_advance : Fixed
          advance             : Vector
          format              : UInt32
          bitmap              : Bitmap
          bitmap_left         : Int
          bitmap_top          : Int
          outline             : Outline
          num_subglyphs       : UInt
          subglyphs           : Void*
          control_data        : Void*
          control_len         : Long
          lsb_delta           : Pos
          rsb_delta           : Pos
          other               : Void*
          internal            : Void*
        end
        type GlyphSlot = GlyphSlotRec*

        struct SizeRec
          face     : Void* # FT_Face back-ref
          generic  : Generic
          metrics  : SizeMetrics
          internal : Void*
        end
        type Size = SizeRec*

        struct FaceRec
          num_faces          : Long
          face_index         : Long
          face_flags         : Long
          style_flags        : Long
          num_glyphs         : Long
          family_name        : UInt8*
          style_name         : UInt8*
          num_fixed_sizes    : Int
          available_sizes    : Void* # BitmapSize*
          num_charmaps       : Int
          charmaps           : Void* # CharMap*
          generic            : Generic
          bbox               : BBox
          units_per_EM       : UShort
          ascender           : Short
          descender          : Short
          height             : Short
          max_advance_width  : Short
          max_advance_height : Short
          underline_position : Short
          underline_thickness : Short
          glyph              : GlyphSlot
          size               : Size
          charmap            : Void* # CharMap
          driver             : Void*
          memory             : Void*
          stream             : Void*
          sizes_list_head    : Void*
          sizes_list_tail    : Void*
          autohint           : Generic
          extensions         : Void*
          internal           : Void*
        end
        type Face = FaceRec*

        LOAD_DEFAULT    = 0_i32
        LOAD_NO_SCALE   = 1_i32 << 0
        LOAD_NO_HINTING = 1_i32 << 1
        LOAD_RENDER     = 1_i32 << 2
        LOAD_NO_BITMAP  = 1_i32 << 3

        fun init_free_type = FT_Init_FreeType(alibrary : Library*) : Error
        fun done_free_type = FT_Done_FreeType(alibrary : Library) : Error
        fun new_face = FT_New_Face(alibrary : Library, filepathname : UInt8*, face_index : Long, aface : Face*) : Error
        fun done_face = FT_Done_Face(face : Face) : Error
        fun set_pixel_sizes = FT_Set_Pixel_Sizes(face : Face, pixel_width : UInt, pixel_height : UInt) : Error
        fun set_char_size = FT_Set_Char_Size(face : Face, char_width : F26Dot6, char_height : F26Dot6, horz_resolution : UInt, vert_resolution : UInt) : Error
        fun get_char_index = FT_Get_Char_Index(face : Face, charcode : ULong) : UInt
        fun load_glyph = FT_Load_Glyph(face : Face, glyph_index : UInt, load_flags : Int32) : Error
        fun load_char = FT_Load_Char(face : Face, char_code : ULong, load_flags : Int32) : Error
        fun render_glyph = FT_Render_Glyph(slot : GlyphSlot, render_mode : Int32) : Error
      end

      # 布局断言（以本机 gcc 探测值为准，失败即 raise）
      def self.assert_layout! : Nil
        raise "FT: sizeof(Void*) expected 8 got #{sizeof(Void*)}" unless sizeof(Void*) == 8
        raise "FT: sizeof(GlyphMetrics) expected 32 got #{sizeof(Lib::GlyphMetrics)}" unless sizeof(Lib::GlyphMetrics) == 32
        raise "FT: sizeof(Bitmap) expected 40 got #{sizeof(Lib::Bitmap)}" unless sizeof(Lib::Bitmap) == 40
        raise "FT: sizeof(GlyphSlotRec) expected 248 got #{sizeof(Lib::GlyphSlotRec)}" unless sizeof(Lib::GlyphSlotRec) == 248
        raise "FT: sizeof(FaceRec) expected 216 got #{sizeof(Lib::FaceRec)}" unless sizeof(Lib::FaceRec) == 216
        raise "FT: sizeof(SizeRec) expected 64 got #{sizeof(Lib::SizeRec)}" unless sizeof(Lib::SizeRec) == 64
        raise "FT: sizeof(SizeMetrics) expected 28 got #{sizeof(Lib::SizeMetrics)}" unless sizeof(Lib::SizeMetrics) == 28

        # Bitmap field offsets (write via typed pointer at expected offset, read back via field)
        bm = uninitialized Lib::Bitmap
        ptr = pointerof(bm).as(UInt8*)
        sizeof(Lib::Bitmap).times { |i| ptr[i] = 0_u8 }
        (ptr + 0).as(UInt32*).value = 0x11223344_u32
        raise "FT: Bitmap.rows offset!=0" unless bm.rows == 0x11223344_u32
        (ptr + 4).as(UInt32*).value = 0x55667788_u32
        raise "FT: Bitmap.width offset!=4" unless bm.width == 0x55667788_u32
        (ptr + 8).as(Int32*).value = -12345_i32
        raise "FT: Bitmap.pitch offset!=8" unless bm.pitch == -12345_i32
        (ptr + 16).as(Pointer(UInt8)*).value = Pointer(UInt8).new(0x1020304050607080_u64)
        raise "FT: Bitmap.buffer offset!=16" unless bm.buffer.address == 0x1020304050607080_u64
        (ptr + 24).as(UInt16*).value = 0xBEEF_u16
        raise "FT: Bitmap.num_grays offset!=24" unless bm.num_grays == 0xBEEF_u16
        (ptr + 26).as(UInt8*).value = 0xAB_u8
        raise "FT: Bitmap.pixel_mode offset!=26" unless bm.pixel_mode == 0xAB_u8
        (ptr + 27).as(UInt8*).value = 0xCD_u8
        raise "FT: Bitmap.palette_mode offset!=27" unless bm.palette_mode == 0xCD_u8
        (ptr + 32).as(Pointer(Void)*).value = Pointer(Void).new(0x0102030405060708_u64)
        raise "FT: Bitmap.palette offset!=32" unless bm.palette.address == 0x0102030405060708_u64

        # GlyphSlotRec offsets
        gs = uninitialized Lib::GlyphSlotRec
        gsp = pointerof(gs).as(UInt8*)
        sizeof(Lib::GlyphSlotRec).times { |i| gsp[i] = 0_u8 }
        (gsp + 48).as(Lib::GlyphMetrics*).value.hori_advance = 777_i32
        raise "FT: GlyphSlot.metrics offset!=48" unless gs.metrics.hori_advance == 777_i32
        (gsp + 80).as(Lib::Fixed*).value = 888_i32
        raise "FT: GlyphSlot.linearHoriAdvance offset!=80" unless gs.linear_hori_advance == 888_i32
        (gsp + 88).as(Lib::Vector*).value.x = 999_i32
        raise "FT: GlyphSlot.advance offset!=88" unless gs.advance.x == 999_i32
        (gsp + 104).as(Lib::Bitmap*).value.rows = 123_u32
        raise "FT: GlyphSlot.bitmap offset!=104" unless gs.bitmap.rows == 123_u32

        # GlyphMetrics horiAdvance at 16
        gm = uninitialized Lib::GlyphMetrics
        gmp = pointerof(gm).as(UInt8*)
        sizeof(Lib::GlyphMetrics).times { |i| gmp[i] = 0_u8 }
        (gmp + 16).as(Lib::Pos*).value = 456_i32
        raise "FT: GlyphMetrics.horiAdvance offset!=16" unless gm.hori_advance == 456_i32

        # FaceRec offsets
        fr = uninitialized Lib::FaceRec
        frp = pointerof(fr).as(UInt8*)
        sizeof(Lib::FaceRec).times { |i| frp[i] = 0_u8 }
        (frp + 0).as(Lib::Long*).value = 11_i32
        raise "FT: FaceRec.num_faces offset!=0" unless fr.num_faces == 11_i32
        (frp + 4).as(Lib::Long*).value = 22_i32
        raise "FT: FaceRec.face_index offset!=4" unless fr.face_index == 22_i32
        (frp + 16).as(Lib::Long*).value = 33_i32
        raise "FT: FaceRec.num_glyphs offset!=16" unless fr.num_glyphs == 33_i32
        (frp + 24).as(Pointer(UInt8)*).value = Pointer(UInt8).new(0x1111_u64)
        raise "FT: FaceRec.family_name offset!=24" unless fr.family_name.address == 0x1111_u64
        (frp + 32).as(Pointer(UInt8)*).value = Pointer(UInt8).new(0x2222_u64)
        raise "FT: FaceRec.style_name offset!=32" unless fr.style_name.address == 0x2222_u64
        (frp + 104).as(Lib::UShort*).value = 2048_u16
        raise "FT: FaceRec.units_per_EM offset!=104" unless fr.units_per_EM == 2048_u16
        (frp + 106).as(Lib::Short*).value = 100_i16
        raise "FT: FaceRec.ascender offset!=106" unless fr.ascender == 100_i16
        (frp + 108).as(Lib::Short*).value = -50_i16
        raise "FT: FaceRec.descender offset!=108" unless fr.descender == -50_i16
        (frp + 110).as(Lib::Short*).value = 150_i16
        raise "FT: FaceRec.height offset!=110" unless fr.height == 150_i16
        (frp + 120).as(Lib::GlyphSlot*).value = Pointer(Void).new(0x3333_u64).as(Lib::GlyphSlot)
        raise "FT: FaceRec.glyph offset!=120" unless fr.glyph.address == 0x3333_u64
        (frp + 128).as(Lib::Size*).value = Pointer(Void).new(0x4444_u64).as(Lib::Size)
        raise "FT: FaceRec.size offset!=128" unless fr.size.address == 0x4444_u64

        # SizeRec / SizeMetrics offsets
        sr = uninitialized Lib::SizeRec
        srp = pointerof(sr).as(UInt8*)
        sizeof(Lib::SizeRec).times { |i| srp[i] = 0_u8 }
        (srp + 24).as(Lib::SizeMetrics*).value.ascender = 321_i32
        raise "FT: SizeRec.metrics offset!=24" unless sr.metrics.ascender == 321_i32

        sm = uninitialized Lib::SizeMetrics
        smp = pointerof(sm).as(UInt8*)
        sizeof(Lib::SizeMetrics).times { |i| smp[i] = 0_u8 }
        (smp + 12).as(Lib::Pos*).value = 111_i32
        raise "FT: SizeMetrics.ascender offset!=12" unless sm.ascender == 111_i32
        (smp + 16).as(Lib::Pos*).value = -222_i32
        raise "FT: SizeMetrics.descender offset!=16" unless sm.descender == -222_i32
        (smp + 20).as(Lib::Pos*).value = 333_i32
        raise "FT: SizeMetrics.height offset!=20" unless sm.height == 333_i32
      end
    end
  end
end
