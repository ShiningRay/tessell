# M0 FFI load probe: FreeType + HarfBuzz dynamic loading
# Writes fixed key=value lines and exits non-zero on any FFI/init failure.

@[Link("freetype")]
lib LibFT
  alias FT_Error = Int32
  type FT_Library = Void*

  fun FT_Init_FreeType(alibrary : FT_Library*) : FT_Error
  fun FT_Done_FreeType(library : FT_Library) : FT_Error
  fun FT_Library_Version(library : FT_Library, amajor : Int32*, aminor : Int32*, apatch : Int32*) : Void
end

@[Link("harfbuzz")]
lib LibHB
  fun hb_version_string : UInt8*
  fun hb_version(major : UInt32*, minor : UInt32*, micro : UInt32*) : Void
end

ft_library = uninitialized LibFT::FT_Library
ft_err = LibFT.FT_Init_FreeType(pointerof(ft_library))
if ft_err != 0 || ft_library.null?
  STDERR.puts "ft_init_error=#{ft_err}"
  exit 1
end

ft_major = 0
ft_minor = 0
ft_patch = 0
LibFT.FT_Library_Version(ft_library, pointerof(ft_major), pointerof(ft_minor), pointerof(ft_patch))

hb_ver_str_ptr = LibHB.hb_version_string
if hb_ver_str_ptr.null?
  STDERR.puts "hb_version_string_null=true"
  LibFT.FT_Done_FreeType(ft_library)
  exit 1
end
hb_ver_str = String.new(hb_ver_str_ptr)
hb_major = 0_u32
hb_minor = 0_u32
hb_micro = 0_u32
LibHB.hb_version(pointerof(hb_major), pointerof(hb_minor), pointerof(hb_micro))

ft_done_err = LibFT.FT_Done_FreeType(ft_library)
if ft_done_err != 0
  STDERR.puts "ft_done_error=#{ft_done_err}"
  exit 1
end

puts "ft_init_ok=true"
puts "ft_library_version=#{ft_major}.#{ft_minor}.#{ft_patch}"
puts "hb_version_string=#{hb_ver_str}"
puts "hb_version=#{hb_major}.#{hb_minor}.#{hb_micro}"

exit 0 if hb_ver_str.size > 0
STDERR.puts "hb_version_empty=true"
exit 1
