# M0-WP4 text probe: FreeType raster + HarfBuzz shaping (zh + complex script)
# Pure FFI, no shards. Outputs fixed token lines. Exits 1 on any failure.
# Target: x86_64-w64-windows-gnu (LLP64: C long = 32-bit)

@[Link("freetype")]
lib LibFT
  alias FT_Error = Int32
  alias FT_Long = Int32
  alias FT_ULong = UInt32
  alias FT_Pos = Int32
  alias FT_Fixed = Int32
  alias FT_UInt = UInt32
  alias FT_Int = Int32
  alias FT_UShort = UInt16
  alias FT_Short = Int16

  type FT_Library = Void*
  type FT_Face = Void*

  FT_LOAD_DEFAULT = 0
  FT_LOAD_RENDER  = 4

  struct FT_Vector
    x : FT_Pos
    y : FT_Pos
  end

  # Exact FT_Bitmap per freetype ftimage.h (x86_64 Windows LLP64):
  #   unsigned int rows; unsigned int width; int pitch; unsigned char* buffer;
  #   unsigned short num_grays; unsigned char pixel_mode; unsigned char palette_mode; void* palette;
  # Natural alignment => sizeof == 40 (no extra pad fields).
  struct FT_Bitmap
    rows : UInt32
    width : UInt32
    pitch : Int32
    buffer : Pointer(UInt8)
    num_grays : UInt16
    pixel_mode : UInt8
    palette_mode : UInt8
    palette : Pointer(Void)
  end

  # FT_GlyphSlotRec layout for freetype 2.x on x86_64 Windows LLP64 (32-bit long)
  struct FT_GlyphSlotRec
    library : FT_Library          # 0
    face : FT_Face                # 8
    next : Void*                  # 16
    glyph_index : FT_UInt         # 24
    reserved : FT_UInt            # 28 (padding/reserved to align generic)
    # FT_Generic generic (16)
    generic_data : Void*          # 32
    generic_finalizer : Void*     # 40
    # FT_Glyph_Metrics metrics (32) - 8 * FT_Pos(Int32)
    m_width : FT_Pos              # 48
    m_height : FT_Pos             # 52
    m_horiBearingX : FT_Pos       # 56
    m_horiBearingY : FT_Pos       # 60
    m_horiAdvance : FT_Pos        # 64
    m_vertBearingX : FT_Pos       # 68
    m_vertBearingY : FT_Pos       # 72
    m_vertAdvance : FT_Pos        # 76
    linearHoriAdvance : FT_Fixed  # 80
    linearVertAdvance : FT_Fixed  # 84
    advance : FT_Vector           # 88 (8 bytes) -> 96
    format : UInt32               # 96 (FT_Glyph_Format / 4 bytes)
    pad_format : UInt32           # 100 (align bitmap to 8)
    bitmap : FT_Bitmap            # 104 (sizeof=40) -> 144
    bitmap_left : FT_Int          # 144 (C header order: bitmap, bitmap_left, bitmap_top)
    bitmap_top : FT_Int           # 148
    # remainder of FT_GlyphSlotRec not needed; we only read up to bitmap_top
  end

  fun FT_Init_FreeType(alibrary : FT_Library*) : FT_Error
  fun FT_Done_FreeType(library : FT_Library) : FT_Error
  fun FT_Library_Version(library : FT_Library, amajor : Int32*, aminor : Int32*, apatch : Int32*) : Void
  fun FT_New_Face(library : FT_Library, filepathname : UInt8*, face_index : Int32, aface : FT_Face*) : FT_Error
  fun FT_Done_Face(face : FT_Face) : FT_Error
  fun FT_Set_Char_Size(face : FT_Face, char_width : Int32, char_height : Int32, horz_resolution : UInt32, vert_resolution : UInt32) : FT_Error
  fun FT_Load_Char(face : FT_Face, char_code : UInt64, load_flags : Int32) : FT_Error
  fun FT_Get_Char_Index(face : FT_Face, charcode : UInt64) : FT_UInt
end

@[Link("harfbuzz")]
lib LibHB
  type HbBlobT = Void*
  type HbFaceT = Void*
  type HbFontT = Void*
  type HbBufferT = Void*

  struct HbGlyphInfoT
    codepoint : UInt32
    mask : UInt32
    cluster : UInt32
    var1 : UInt32
    var2 : UInt32
  end

  struct HbGlyphPositionT
    x_advance : Int32
    y_advance : Int32
    x_offset : Int32
    y_offset : Int32
    var1 : UInt32
  end

  fun hb_version_string : UInt8*
  fun hb_version(major : UInt32*, minor : UInt32*, micro : UInt32*) : Void

  fun hb_blob_create_from_file(file_name : UInt8*) : HbBlobT
  fun hb_blob_destroy(blob : HbBlobT) : Void

  fun hb_face_create(blob : HbBlobT, index : UInt32) : HbFaceT
  fun hb_face_destroy(face : HbFaceT) : Void

  fun hb_font_create(face : HbFaceT) : HbFontT
  fun hb_font_set_scale(font : HbFontT, x_scale : Int32, y_scale : Int32) : Void
  fun hb_font_destroy(font : HbFontT) : Void

  fun hb_buffer_create : HbBufferT
  fun hb_buffer_add_utf8(buffer : HbBufferT, text : UInt8*, text_length : Int32, item_offset : UInt32, item_length : Int32) : Void
  fun hb_buffer_guess_segment_properties(buffer : HbBufferT) : Void
  fun hb_buffer_get_length(buffer : HbBufferT) : UInt32
  fun hb_buffer_get_glyph_infos(buffer : HbBufferT, length : UInt32*) : HbGlyphInfoT*
  fun hb_buffer_get_glyph_positions(buffer : HbBufferT, length : UInt32*) : HbGlyphPositionT*
  fun hb_buffer_clear_contents(buffer : HbBufferT) : Void
  fun hb_buffer_destroy(buffer : HbBufferT) : Void

  fun hb_shape(font : HbFontT, buffer : HbBufferT, features : Void*, num_features : UInt32) : Void
end

def fail(msg : String)
  STDERR.puts msg
  exit 1
end

def cstr(s : String)
  s.to_unsafe
end

def count_nonzero_pixels(bitmap : LibFT::FT_Bitmap) : Int32
  rows = bitmap.rows.to_i
  width = bitmap.width.to_i
  return 0 if rows <= 0 || width <= 0 || bitmap.buffer.null?
  pitch = bitmap.pitch
  count = 0
  rows.times do |y|
    row_base = bitmap.buffer + y * pitch
    width.times do |x|
      v = row_base[x]
      count += 1 if v != 0_u8
    end
  end
  count
end

# Read FT_FaceRec->glyph pointer (FT_GlyphSlot) from face.
# FT_FaceRec layout (x86_64 Windows, 32-bit long): num_faces(0,i32), face_index(4,i32),
# face_flags(8,i32), style_flags(12,i32), num_glyphs(16,i32), pad(20,i32),
# family_name(24,ptr), style_name(32,ptr), num_fixed_sizes(40,i32), pad(44,i32),
# available_sizes(48,ptr), num_charmaps(56,i32), pad(60,i32), charmaps(64,ptr),
# generic(72,16)=88, bbox(88,16)=104, units_per_EM(104,u16), ascender(106,i16),
# descender(108,i16), height(110,i16), max_advance_width(112,i16),
# max_advance_height(114,i16), underline_position(116,i16), underline_thickness(118,i16),
# glyph(120,ptr)
def read_face_strings_and_glyph(face : LibFT::FT_Face)
  base = face.as(Pointer(UInt8))
  family_ptr = (base + 24).as(Pointer(Pointer(UInt8))).value
  style_ptr = (base + 32).as(Pointer(Pointer(UInt8))).value
  glyph_slot = (base + 120).as(Pointer(Pointer(LibFT::FT_GlyphSlotRec))).value
  family = family_ptr.null? ? "" : String.new(family_ptr)
  style = style_ptr.null? ? "" : String.new(style_ptr)
  {family, style, glyph_slot}
end

# --- D1 layout assertions: FT_Bitmap sizeof must be 40 (C semantics),
# --- and bitmap_left/bitmap_top offsets inside FT_GlyphSlotRec must match the C
# --- header layout (bitmap@104 size 40 -> bitmap_left@144, bitmap_top@148).
# Crystal has no offsetof for struct fields, so prove offsets bidirectionally:
# write a sentinel via field access and read it back at the C byte offset, then
# write a sentinel at the byte offset and read it back via field access.
ft_bitmap_sizeof = sizeof(LibFT::FT_Bitmap)
unless ft_bitmap_sizeof == 40
  STDERR.puts "assert_fail=ft_bitmap_sizeof=#{ft_bitmap_sizeof} expected=40"
  exit 1
end
_slot_tmp = uninitialized LibFT::FT_GlyphSlotRec
_base = pointerof(_slot_tmp).as(Pointer(UInt8))
_slot_tmp.bitmap_left = 0x11223344
_ok_left_write = (_base + 144).as(Pointer(Int32)).value == 0x11223344
_slot_tmp.bitmap_top = 0x55667788
_ok_top_write = (_base + 148).as(Pointer(Int32)).value == 0x55667788
(_base + 144).as(Pointer(Int32)).value = 0x0A0B0C0D
_ok_left_read = _slot_tmp.bitmap_left == 0x0A0B0C0D
(_base + 148).as(Pointer(Int32)).value = 0x0E0F1011
_ok_top_read = _slot_tmp.bitmap_top == 0x0E0F1011
unless _ok_left_write && _ok_top_write && _ok_left_read && _ok_top_read
  STDERR.puts "assert_fail=ft_slot_offsets bitmap_left_at144(write=#{_ok_left_write} read=#{_ok_left_read}) bitmap_top_at148(write=#{_ok_top_write} read=#{_ok_top_read})"
  exit 1
end

# --- FreeType init ---
ft_lib = uninitialized LibFT::FT_Library
ft_err = LibFT.FT_Init_FreeType(pointerof(ft_lib))
fail("ft_init_error=#{ft_err}") if ft_err != 0 || ft_lib.null?

ft_major = 0; ft_minor = 0; ft_patch = 0
LibFT.FT_Library_Version(ft_lib, pointerof(ft_major), pointerof(ft_minor), pointerof(ft_patch))
ft_version = "#{ft_major}.#{ft_minor}.#{ft_patch}"

# --- HarfBuzz version ---
hb_ver_ptr = LibHB.hb_version_string
fail("hb_version_string_null=true") if hb_ver_ptr.null?
hb_version = String.new(hb_ver_ptr)
fail("hb_version_empty=true") if hb_version.empty?

# --- FreeType face: msyh.ttc ---
msyh_path = "C:\\Windows\\Fonts\\msyh.ttc"
fail("font_missing=#{msyh_path}") unless File.exists?(msyh_path)
ft_face = uninitialized LibFT::FT_Face
ft_err = LibFT.FT_New_Face(ft_lib, cstr(msyh_path), 0, pointerof(ft_face))
fail("ft_new_face_msyh_error=#{ft_err}") if ft_err != 0 || ft_face.null?

ft_err = LibFT.FT_Set_Char_Size(ft_face, 0, 24 * 64, 96_u32, 96_u32)
fail("ft_set_char_size_error=#{ft_err}") if ft_err != 0

family, style, _ = read_face_strings_and_glyph(ft_face)

# Render "你" (U+4F60)
char_ni = 0x4F60_u64
glyph_index_lookup = LibFT.FT_Get_Char_Index(ft_face, char_ni)
fail("ft_glyph_index_zero_for_ni=#{glyph_index_lookup}") if glyph_index_lookup == 0

# warmup render
10.times do
  err = LibFT.FT_Load_Char(ft_face, char_ni, LibFT::FT_LOAD_RENDER)
  fail("ft_load_char_warmup_error=#{err}") if err != 0
end

render_total = Time::Span.zero
render_px = 0
glyph_index = 0_u32
advance_x26 = 0_i64
bm_w = 0_u32
bm_rows = 0_u32
bm_left = 0
bm_top = 0
100.times do
  t0 = Time.instant
  err = LibFT.FT_Load_Char(ft_face, char_ni, LibFT::FT_LOAD_RENDER)
  fail("ft_load_char_error=#{err}") if err != 0
  render_total += Time.instant - t0
  _, _, slot = read_face_strings_and_glyph(ft_face)
  fail("ft_glyph_slot_null=true") if slot.null?
  slot_val = slot.value
  glyph_index = slot_val.glyph_index
  advance_x26 = slot_val.advance.x.to_i64
  bm_w = slot_val.bitmap.width
  bm_rows = slot_val.bitmap.rows
  bm_left = slot_val.bitmap_left
  bm_top = slot_val.bitmap_top
  render_px = count_nonzero_pixels(slot_val.bitmap)
end
render_us_avg = (render_total.total_microseconds / 100.0)

# --- HarfBuzz: Chinese "你好 Tessell" with msyh.ttc ---
zh_text = "你好 Tessell"
blob = LibHB.hb_blob_create_from_file(cstr(msyh_path))
fail("hb_blob_create_msyh_null=true") if blob.null?
hb_face = LibHB.hb_face_create(blob, 0_u32)
fail("hb_face_create_msyh_null=true") if hb_face.null?
hb_font = LibHB.hb_font_create(hb_face)
fail("hb_font_create_msyh_null=true") if hb_font.null?
LibHB.hb_font_set_scale(hb_font, 24 * 64, 24 * 64)

buffer = LibHB.hb_buffer_create
fail("hb_buffer_create_null=true") if buffer.null?
LibHB.hb_buffer_add_utf8(buffer, cstr(zh_text), zh_text.bytesize, 0_u32, zh_text.bytesize)
LibHB.hb_buffer_guess_segment_properties(buffer)
LibHB.hb_shape(hb_font, buffer, Pointer(Void).null, 0_u32)
zh_glyphs = LibHB.hb_buffer_get_length(buffer).to_i
info_len = 0_u32
pos_len = 0_u32
infos = LibHB.hb_buffer_get_glyph_infos(buffer, pointerof(info_len))
positions = LibHB.hb_buffer_get_glyph_positions(buffer, pointerof(pos_len))
fail("hb_glyph_info_null=true") if infos.null? || info_len == 0
fail("hb_glyph_pos_null=true") if positions.null? || pos_len == 0
zh_glyphs.times do |i|
  cp = infos[i].codepoint
  adv = positions[i].x_advance
  puts "zh_glyph[#{i}].codepoint=#{cp}"
  puts "zh_glyph[#{i}].advance=#{adv}"
end
zh_advance = positions[0].x_advance

# --- HarfBuzz: Arabic "سلام" with segoeui.ttf (fallback arial.ttf) ---
ar_text = "سلام"
ar_codepoints = ar_text.size # Unicode codepoints in Crystal String#size
ar_font_path = "C:\\Windows\\Fonts\\segoeui.ttf"
unless File.exists?(ar_font_path)
  ar_font_path = "C:\\Windows\\Fonts\\arial.ttf"
end
fail("ar_font_missing=true path=#{ar_font_path}") unless File.exists?(ar_font_path)

ar_blob = LibHB.hb_blob_create_from_file(cstr(ar_font_path))
fail("hb_blob_create_ar_null=true") if ar_blob.null?
ar_face = LibHB.hb_face_create(ar_blob, 0_u32)
fail("hb_face_create_ar_null=true") if ar_face.null?
ar_font = LibHB.hb_font_create(ar_face)
fail("hb_font_create_ar_null=true") if ar_font.null?
LibHB.hb_font_set_scale(ar_font, 24 * 64, 24 * 64)

ar_buffer = LibHB.hb_buffer_create
fail("hb_buffer_create_ar_null=true") if ar_buffer.null?
LibHB.hb_buffer_add_utf8(ar_buffer, cstr(ar_text), ar_text.bytesize, 0_u32, ar_text.bytesize)
LibHB.hb_buffer_guess_segment_properties(ar_buffer)
LibHB.hb_shape(ar_font, ar_buffer, Pointer(Void).null, 0_u32)
ar_glyphs = LibHB.hb_buffer_get_length(ar_buffer).to_i
ar_info_len = 0_u32
ar_pos_len = 0_u32
ar_infos = LibHB.hb_buffer_get_glyph_infos(ar_buffer, pointerof(ar_info_len))
ar_positions = LibHB.hb_buffer_get_glyph_positions(ar_buffer, pointerof(ar_pos_len))
fail("hb_ar_info_null=true") if ar_infos.null? || ar_info_len == 0
fail("hb_ar_pos_null=true") if ar_positions.null? || ar_pos_len == 0
ar_glyphs.times do |i|
  cp = ar_infos[i].codepoint
  adv = ar_positions[i].x_advance
  puts "ar_glyph[#{i}].codepoint=#{cp}"
  puts "ar_glyph[#{i}].advance=#{adv}"
end

# --- D2: multi-font lam-alef "لا" (U+0644 U+0627) shaping evidence ---
# For each existing font: shape "لا", print glyph_count + glyph ids, and compare
# against isolated-form glyph ids (shape "ل" and "ا" separately). glyph_count==1
# would be lam-alef ligature evidence; count>=2 with ids differing from isolated
# forms proves contextual substitution only (NOT single-glyph merging).
lam_alef_text = "لا"
lam_alef_fonts = [
  "C:\\Windows\\Fonts\\tahoma.ttf",
  "C:\\Windows\\Fonts\\arial.ttf",
  "C:\\Windows\\Fonts\\segoeui.ttf",
  "C:\\Windows\\Fonts\\times.ttf",
]
lam_alef_ligature_font = "none"
lam_alef_min_glyphs = -1
lam_alef_fonts_tested = 0
lam_alef_fonts.each do |font_path|
  unless File.exists?(font_path)
    puts "ar_lam_alef[#{font_path}].skipped=missing"
    next
  end
  la_blob = LibHB.hb_blob_create_from_file(cstr(font_path))
  if la_blob.null?
    puts "ar_lam_alef[#{font_path}].blob_null=true"
    next
  end
  la_face = LibHB.hb_face_create(la_blob, 0_u32)
  if la_face.null?
    puts "ar_lam_alef[#{font_path}].face_null=true"
    LibHB.hb_blob_destroy(la_blob)
    next
  end
  la_font = LibHB.hb_font_create(la_face)
  if la_font.null?
    puts "ar_lam_alef[#{font_path}].font_null=true"
    LibHB.hb_face_destroy(la_face)
    LibHB.hb_blob_destroy(la_blob)
    next
  end
  LibHB.hb_font_set_scale(la_font, 24 * 64, 24 * 64)

  la_buf = LibHB.hb_buffer_create
  unless la_buf.null?
    LibHB.hb_buffer_add_utf8(la_buf, cstr(lam_alef_text), lam_alef_text.bytesize, 0_u32, lam_alef_text.bytesize)
    LibHB.hb_buffer_guess_segment_properties(la_buf)
    LibHB.hb_shape(la_font, la_buf, Pointer(Void).null, 0_u32)
    la_count = LibHB.hb_buffer_get_length(la_buf).to_i
    la_info_len = 0_u32
    la_infos = LibHB.hb_buffer_get_glyph_infos(la_buf, pointerof(la_info_len))
    la_ids = Array(UInt32).new
    unless la_infos.null?
      la_count.times { |k| la_ids << la_infos[k].codepoint }
    end
    puts "ar_lam_alef[#{font_path}].glyph_count=#{la_count}"
    puts "ar_lam_alef[#{font_path}].glyph_ids=#{la_ids.join(",")}"

    # isolated-form references: shape "ل" and "ا" separately
    iso_ids = Array(UInt32).new
    ["ل", "ا"].each do |ch|
      iso_buf = LibHB.hb_buffer_create
      unless iso_buf.null?
        LibHB.hb_buffer_add_utf8(iso_buf, cstr(ch), ch.bytesize, 0_u32, ch.bytesize)
        LibHB.hb_buffer_guess_segment_properties(iso_buf)
        LibHB.hb_shape(la_font, iso_buf, Pointer(Void).null, 0_u32)
        iso_len = LibHB.hb_buffer_get_length(iso_buf).to_i
        iso_info_len = 0_u32
        iso_infos = LibHB.hb_buffer_get_glyph_infos(iso_buf, pointerof(iso_info_len))
        iso_ids << iso_infos[0].codepoint if !iso_infos.null? && iso_len > 0
        LibHB.hb_buffer_destroy(iso_buf)
      end
    end
    puts "ar_lam_alef[#{font_path}].isolated_lam_alef_ids=#{iso_ids.join(",")}"
    puts "ar_lam_alef[#{font_path}].ids_differ_from_isolated=#{la_ids != iso_ids}"
    puts "ar_lam_alef[#{font_path}].ligature_candidate=#{(la_count == 1)}"

    lam_alef_fonts_tested += 1
    lam_alef_ligature_font = font_path if la_count == 1
    lam_alef_min_glyphs = la_count if lam_alef_min_glyphs < 0 || la_count < lam_alef_min_glyphs
    LibHB.hb_buffer_destroy(la_buf)
  else
    puts "ar_lam_alef[#{font_path}].buffer_null=true"
  end
  LibHB.hb_font_destroy(la_font)
  LibHB.hb_face_destroy(la_face)
  LibHB.hb_blob_destroy(la_blob)
end
lam_alef_min_glyphs = 0 if lam_alef_min_glyphs < 0

# --- Timing: shape "你好世界" 1000 times avg µs, warmup 10 ---
shape_text = "你好世界"
shape_buf = LibHB.hb_buffer_create
fail("hb_shape_timing_buffer_null=true") if shape_buf.null?
10.times do
  LibHB.hb_buffer_clear_contents(shape_buf)
  LibHB.hb_buffer_add_utf8(shape_buf, cstr(shape_text), shape_text.bytesize, 0_u32, shape_text.bytesize)
  LibHB.hb_buffer_guess_segment_properties(shape_buf)
  LibHB.hb_shape(hb_font, shape_buf, Pointer(Void).null, 0_u32)
end
shape_total = Time::Span.zero
1000.times do
  t0 = Time.instant
  LibHB.hb_buffer_clear_contents(shape_buf)
  LibHB.hb_buffer_add_utf8(shape_buf, cstr(shape_text), shape_text.bytesize, 0_u32, shape_text.bytesize)
  LibHB.hb_buffer_guess_segment_properties(shape_buf)
  LibHB.hb_shape(hb_font, shape_buf, Pointer(Void).null, 0_u32)
  shape_total += Time.instant - t0
end
shape_us_avg = (shape_total.total_microseconds / 1000.0)

# --- Cleanup ---
LibHB.hb_buffer_destroy(shape_buf)
LibHB.hb_buffer_destroy(ar_buffer)
LibHB.hb_font_destroy(ar_font)
LibHB.hb_face_destroy(ar_face)
LibHB.hb_blob_destroy(ar_blob)
LibHB.hb_buffer_destroy(buffer)
LibHB.hb_font_destroy(hb_font)
LibHB.hb_face_destroy(hb_face)
LibHB.hb_blob_destroy(blob)
LibFT.FT_Done_Face(ft_face)
LibFT.FT_Done_FreeType(ft_lib)

# --- Output tokens ---
puts "ft_version=#{ft_version}"
puts "hb_version=#{hb_version}"
puts "ft_face_family=#{family}"
puts "ft_face_style=#{style}"
puts "ft_glyph_index=#{glyph_index}"
puts "ft_advance_x26=#{advance_x26}"
puts "ft_bitmap_w=#{bm_w}"
puts "ft_bitmap_rows=#{bm_rows}"
puts "render_px=#{render_px}"
puts "zh_text=#{zh_text}"
puts "zh_glyphs=#{zh_glyphs}"
puts "zh_advance=#{zh_advance}"
puts "ar_text=#{ar_text}"
puts "ar_font=#{ar_font_path}"
puts "ar_glyphs=#{ar_glyphs}"
puts "ar_codepoints=#{ar_codepoints}"
puts "ar_shaping_diff=#{ar_glyphs != ar_codepoints}"
puts "ft_bitmap_sizeof=#{ft_bitmap_sizeof}"
puts "ft_slot_bitmap_left_at144=#{_ok_left_write && _ok_left_read}"
puts "ft_slot_bitmap_top_at148=#{_ok_top_write && _ok_top_read}"
puts "ft_layout_assert=pass"
puts "ft_bitmap_left=#{bm_left}"
puts "ft_bitmap_top=#{bm_top}"
puts "ar_lam_alef_fonts_tested=#{lam_alef_fonts_tested}"
puts "ar_lam_alef_min_glyphs=#{lam_alef_min_glyphs}"
puts "ar_lam_alef_ligature_font=#{lam_alef_ligature_font}"
puts "shape_us_avg=#{shape_us_avg.round(3)}"
puts "render_us_avg=#{render_us_avg.round(3)}"
exit 0
