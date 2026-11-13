# M2-WP2d stage 2: text on screen via GL 1.1 immediate mode (R8 atlas -> GL_ALPHA)
# Reuses m0 window probe WGL/window pattern.
# Usage:
#   crystal run examples/m2_text_window.cr -- --frames=120 --verify
# Outputs: text_pixels_nonbg, cpu_coverage_sum, ratio, pixel_match, frame times p50/p95/p99
# Criterion: text_pixels_nonbg > 0 and ratio in [0.5,1.5] (tolerance for GL linear sampling/blend/raster differences)
# If window/GL unavailable: records blocking error and exits 1 without faking pixel_match.

require "../src/tessell/text/ft_measurer"
require "../src/tessell/text/glyph_atlas"
require "../src/tessell/text/rasterizer"
require "../src/tessell/render/text_renderer"
require "../src/tessell/render/gl/gl_renderer"

@[Link("kernel32")]
lib LibKernel32
  fun GetModuleHandleW(lpModuleName : UInt16*) : Void*
  fun GetLastError : UInt32
  fun GetTickCount64 : UInt64
end

@[Link("user32")]
lib LibUser32
  struct WNDCLASSEXW
    cbSize : UInt32
    style : UInt32
    lpfnWndProc : (Void*, UInt32, UInt64, Int64 -> Int64)
    cbClsExtra : Int32
    cbWndExtra : Int32
    hInstance : Void*
    hIcon : Void*
    hCursor : Void*
    hbrBackground : Void*
    lpszMenuName : UInt16*
    lpszClassName : UInt16*
    hIconSm : Void*
  end

  struct POINT
    x : Int32
    y : Int32
  end

  struct MSG
    hwnd : Void*
    message : UInt32
    wParam : UInt64
    lParam : Int64
    time : UInt32
    pt : POINT
  end

  struct RECT
    left : Int32
    top : Int32
    right : Int32
    bottom : Int32
  end

  fun RegisterClassExW(lpWndClass : WNDCLASSEXW*) : UInt16
  fun CreateWindowExW(dwExStyle : UInt32, lpClassName : UInt16*, lpWindowName : UInt16*, dwStyle : UInt32,
                      x : Int32, y : Int32, nWidth : Int32, nHeight : Int32,
                      hWndParent : Void*, hMenu : Void*, hInstance : Void*, lpParam : Void*) : Void*
  fun ShowWindow(hWnd : Void*, nCmdShow : Int32) : Int32
  fun UpdateWindow(hWnd : Void*) : Int32
  fun DestroyWindow(hWnd : Void*) : Int32
  fun PostQuitMessage(nExitCode : Int32) : Void
  fun DefWindowProcW(hWnd : Void*, msg : UInt32, wParam : UInt64, lParam : Int64) : Int64
  fun PeekMessageW(lpMsg : MSG*, hWnd : Void*, wMsgFilterMin : UInt32, wMsgFilterMax : UInt32, wRemoveMsg : UInt32) : Int32
  fun TranslateMessage(lpMsg : MSG*) : Int32
  fun DispatchMessageW(lpMsg : MSG*) : Int64
  fun GetDC(hWnd : Void*) : Void*
  fun ReleaseDC(hWnd : Void*, hDC : Void*) : Int32
  fun LoadCursorW(hInstance : Void*, lpCursorName : UInt16*) : Void*
  fun AdjustWindowRectEx(lpRect : RECT*, dwStyle : UInt32, bMenu : Int32, dwExStyle : UInt32) : Int32
end

@[Link("gdi32")]
lib LibGdi32
  struct PIXELFORMATDESCRIPTOR
    nSize : UInt16
    nVersion : UInt16
    dwFlags : UInt32
    iPixelType : UInt8
    cColorBits : UInt8
    cRedBits : UInt8
    cRedShift : UInt8
    cGreenBits : UInt8
    cGreenShift : UInt8
    cBlueBits : UInt8
    cBlueShift : UInt8
    cAlphaBits : UInt8
    cAlphaShift : UInt8
    cAccumBits : UInt8
    cAccumRedBits : UInt8
    cAccumGreenBits : UInt8
    cAccumBlueBits : UInt8
    cAccumAlphaBits : UInt8
    cDepthBits : UInt8
    cStencilBits : UInt8
    cAuxBuffers : UInt8
    iLayerType : UInt8
    bReserved : UInt8
    dwLayerMask : UInt32
    dwVisibleMask : UInt32
    dwDamageMask : UInt32
  end

  fun ChoosePixelFormat(hdc : Void*, ppfd : PIXELFORMATDESCRIPTOR*) : Int32
  fun SetPixelFormat(hdc : Void*, format : Int32, ppfd : PIXELFORMATDESCRIPTOR*) : Int32
  fun SwapBuffers(hdc : Void*) : Int32
end

@[Link("opengl32")]
lib LibWGL
  fun wglCreateContext(hdc : Void*) : Void*
  fun wglMakeCurrent(hdc : Void*, hglrc : Void*) : Int32
  fun wglDeleteContext(hglrc : Void*) : Int32
end

module ProbeState
  class_property quit_requested : Bool = false
end

def to_wstr(s : String) : Slice(UInt16)
  u = s.to_utf16
  buf = Slice(UInt16).new(u.size + 1, 0_u16)
  u.size.times { |i| buf[i] = u[i] }
  buf
end

def cstr_to_string(ptr : UInt8*) : String
  return "" if ptr.null?
  String.new(ptr)
end

WS_OVERLAPPEDWINDOW = 0x00CF0000_u32
WS_VISIBLE          = 0x10000000_u32
CW_USEDEFAULT       = 0x80000000_u32.to_i32!
SW_SHOW             = 5
PM_REMOVE           = 0x0001_u32
WM_CLOSE            = 0x0010_u32
WM_DESTROY          = 0x0002_u32
WM_QUIT             = 0x0012_u32
WM_KEYDOWN          = 0x0100_u32
VK_ESCAPE           = 0x1B_u64
IDC_ARROW           = Pointer(UInt16).new(32512_u64)

PFD_DRAW_TO_WINDOW = 0x00000004_u32
PFD_SUPPORT_OPENGL = 0x00000020_u32
PFD_DOUBLEBUFFER   = 0x00000001_u32
PFD_TYPE_RGBA      = 0_u8
PFD_MAIN_PLANE     = 0_u8
CS_OWNDC           = 0x0020_u32

WNDPROC = ->(hwnd : Void*, msg : UInt32, wparam : UInt64, lparam : Int64) : Int64 do
  case msg
  when WM_CLOSE
    LibUser32.DestroyWindow(hwnd)
    return 0_i64
  when WM_DESTROY
    LibUser32.PostQuitMessage(0)
    ProbeState.quit_requested = true
    return 0_i64
  when WM_KEYDOWN
    if wparam == VK_ESCAPE
      LibUser32.DestroyWindow(hwnd)
      return 0_i64
    end
  end
  LibUser32.DefWindowProcW(hwnd, msg, wparam, lparam)
end

frames_target = 120
verify_mode = false
ARGV.each_with_index do |arg, i|
  if arg.starts_with?("--frames=")
    frames_target = arg.split("=", 2)[1].to_i
  elsif arg == "--frames" && i + 1 < ARGV.size
    frames_target = ARGV[i + 1].to_i
  elsif arg == "--verify"
    verify_mode = true
  end
end

FONT_PATH = "C:/Windows/Fonts/msyh.ttc"
width = 800
height = 600
text_str = "Hello 你好 Tessell"
text_size = 32
text_x = 40.0_f32
text_y = 120.0_f32
bg_r = 1.0_f32; bg_g = 1.0_f32; bg_b = 1.0_f32

def percentile(sorted : Array(Float64), p : Float64) : Float64
  return 0.0 if sorted.empty?
  idx = ((p / 100.0) * (sorted.size - 1)).round.to_i
  idx = 0 if idx < 0
  idx = sorted.size - 1 if idx >= sorted.size
  sorted[idx]
end

# cpu_coverage_sum: sum of nonzero alpha bytes in atlas page regions referenced by emitted drawable placements.
# This approximates "source text pixels" available; readback non-bg pixels approximate rendered result.
def compute_cpu_coverage_sum(atlas : Tessell::Text::GlyphAtlas, sink : Array(Tessell::Text::GlyphPlacement)) : Int64
  sum = 0_i64
  sink.each do |p|
    next if p.w <= 0 || p.h <= 0
    slot = atlas.lookup(p.key)
    next unless slot
    data = atlas.page_data(slot.page)
    ps = atlas.page_size
    y = 0
    while y < slot.h
      x = 0
      base = (slot.y + y) * ps + slot.x
      while x < slot.w
        v = data[base + x]
        sum += 1 if v > 0_u8
        x += 1
      end
      y += 1
    end
  end
  sum
end

begin
  unless File.exists?(FONT_PATH)
    STDERR.puts "blocking=font_missing path=#{FONT_PATH}"
    exit 1
  end

  ft = Tessell::Text::FtMeasurer.open(FONT_PATH, 0)
  atlas = Tessell::Text::GlyphAtlas.new(1024, 4096)
  rast = Tessell::Text::Rasterizer.new(ft, atlas, 1)
  tr = Tessell::Render::TextRenderer.new(atlas, rast)
  sink = [] of Tessell::Text::GlyphPlacement

  # pre-raster/build to allocate resources and know layout
  pen_end = tr.build_text(sink, text_str, text_x, text_y, text_size, width, height, [] of Int32)
  tr.reserve_quads(tr.stats[:quads])
  tr.reserve_batches(tr.stats[:batches])

  hinstance = LibKernel32.GetModuleHandleW(Pointer(UInt16).null)
  raise "GetModuleHandleW failed err=#{LibKernel32.GetLastError}" if hinstance.null?

  class_name = to_wstr("TessellM2TextProbe")
  window_title = to_wstr("Tessell M2 Text Probe")

  wc = LibUser32::WNDCLASSEXW.new
  wc.cbSize = sizeof(LibUser32::WNDCLASSEXW).to_u32
  wc.style = CS_OWNDC
  wc.lpfnWndProc = WNDPROC
  wc.hInstance = hinstance
  wc.hCursor = LibUser32.LoadCursorW(Pointer(Void).null, IDC_ARROW)
  wc.lpszClassName = class_name.to_unsafe

  atom = LibUser32.RegisterClassExW(pointerof(wc))
  raise "RegisterClassExW failed err=#{LibKernel32.GetLastError}" if atom == 0

  rect = LibUser32::RECT.new
  rect.right = width
  rect.bottom = height
  LibUser32.AdjustWindowRectEx(pointerof(rect), WS_OVERLAPPEDWINDOW, 0, 0)
  win_w = rect.right - rect.left
  win_h = rect.bottom - rect.top

  hwnd = LibUser32.CreateWindowExW(0_u32, class_name.to_unsafe, window_title.to_unsafe,
                                    WS_OVERLAPPEDWINDOW | WS_VISIBLE,
                                    CW_USEDEFAULT, CW_USEDEFAULT, win_w, win_h,
                                    Pointer(Void).null, Pointer(Void).null, hinstance, Pointer(Void).null)
  raise "CreateWindowExW failed err=#{LibKernel32.GetLastError}" if hwnd.null?

  LibUser32.ShowWindow(hwnd, SW_SHOW)
  LibUser32.UpdateWindow(hwnd)

  hdc = LibUser32.GetDC(hwnd)
  raise "GetDC failed err=#{LibKernel32.GetLastError}" if hdc.null?

  pfd = LibGdi32::PIXELFORMATDESCRIPTOR.new
  pfd.nSize = sizeof(LibGdi32::PIXELFORMATDESCRIPTOR).to_u16
  pfd.nVersion = 1_u16
  pfd.dwFlags = PFD_DRAW_TO_WINDOW | PFD_SUPPORT_OPENGL | PFD_DOUBLEBUFFER
  pfd.iPixelType = PFD_TYPE_RGBA
  pfd.cColorBits = 32_u8
  pfd.cDepthBits = 24_u8
  pfd.iLayerType = PFD_MAIN_PLANE

  pf = LibGdi32.ChoosePixelFormat(hdc, pointerof(pfd))
  raise "ChoosePixelFormat failed err=#{LibKernel32.GetLastError}" if pf == 0
  raise "SetPixelFormat failed err=#{LibKernel32.GetLastError}" if LibGdi32.SetPixelFormat(hdc, pf, pointerof(pfd)) == 0

  hglrc = LibWGL.wglCreateContext(hdc)
  raise "wglCreateContext failed err=#{LibKernel32.GetLastError}" if hglrc.null?
  raise "wglMakeCurrent failed err=#{LibKernel32.GetLastError}" if LibWGL.wglMakeCurrent(hdc, hglrc) == 0

  glr = Tessell::Render::GL::GlRenderer.new(atlas)

  # initial sync & build with textures
  tex_ids = glr.sync_atlas_textures
  tr.build_text(sink, text_str, text_x, text_y, text_size, width, height, tex_ids)
  # pages may grow on first build; resync
  tex_ids = glr.sync_atlas_textures
  tr.build_text(sink, text_str, text_x, text_y, text_size, width, height, tex_ids)

  cpu_coverage_sum = compute_cpu_coverage_sum(atlas, sink)

  frame_times = [] of Float64
  last_readback = Bytes.new(width * height * 4)
  msg = LibUser32::MSG.new
  frames_done = 0
  swap_ok = 0

  while frames_done < frames_target && !ProbeState.quit_requested
    t0 = Time.instant
    while LibUser32.PeekMessageW(pointerof(msg), Pointer(Void).null, 0_u32, 0_u32, PM_REMOVE) != 0
      if msg.message == WM_QUIT
        ProbeState.quit_requested = true
        break
      end
      LibUser32.TranslateMessage(pointerof(msg))
      LibUser32.DispatchMessageW(pointerof(msg))
    end
    break if ProbeState.quit_requested

    tex_ids = glr.sync_atlas_textures
    tr.build_text(sink, text_str, text_x, text_y, text_size, width, height, tex_ids)

    glr.begin_frame(width, height, bg_r, bg_g, bg_b, 1.0_f32)
    glr.draw_text(tr)
    glr.end_frame

    # readback (origin bottom-left in GL); used for pixel_match on last frame
    TessellGL.glPixelStorei(TessellGL::GL_PACK_ALIGNMENT, 1)
    TessellGL.glReadPixels(0, 0, width, height, TessellGL::GL_RGBA, TessellGL::GL_UNSIGNED_BYTE, last_readback.to_unsafe.as(Void*))

    if LibGdi32.SwapBuffers(hdc) != 0
      swap_ok += 1
    end
    frames_done += 1
    frame_times << (Time.instant - t0).total_milliseconds
  end

  # text_pixels_nonbg: count readback pixels whose RGB differs from background (white) beyond tolerance.
  # Blending/modulation over white bg: text darkens pixels; any darkening indicates text coverage.
  text_pixels_nonbg = 0_i64
  i = 0
  total_px = width * height
  bg_ri = (bg_r * 255.0_f32).round.to_i
  bg_gi = (bg_g * 255.0_f32).round.to_i
  bg_bi = (bg_b * 255.0_f32).round.to_i
  while i < total_px
    off = i * 4
    r = last_readback[off].to_i
    g = last_readback[off + 1].to_i
    b = last_readback[off + 2].to_i
    dr = (r - bg_ri).abs
    dg = (g - bg_gi).abs
    db = (b - bg_bi).abs
    # threshold 8 to tolerate minor GL rounding; text is black so difference will be large where covered
    if dr > 8 || dg > 8 || db > 8
      text_pixels_nonbg += 1
    end
    i += 1
  end

  ratio = cpu_coverage_sum > 0 ? (text_pixels_nonbg.to_f64 / cpu_coverage_sum.to_f64) : 0.0
  pixel_match = (text_pixels_nonbg > 0) && (ratio >= 0.5) && (ratio <= 1.5)

  sorted = frame_times.sort
  p50 = percentile(sorted, 50.0)
  p95 = percentile(sorted, 95.0)
  p99 = percentile(sorted, 99.0)

  # cleanup
  glr.delete_textures
  LibWGL.wglMakeCurrent(Pointer(Void).null, Pointer(Void).null)
  LibWGL.wglDeleteContext(hglrc)
  LibUser32.ReleaseDC(hwnd, hdc)
  LibUser32.DestroyWindow(hwnd) unless ProbeState.quit_requested
  ft.close

  puts "text_pixels_nonbg=#{text_pixels_nonbg} cpu_coverage_sum=#{cpu_coverage_sum} ratio=#{ratio} pixel_match=#{pixel_match} frames=#{frames_done} swapbuffers=#{swap_ok} frame_p50_ms=#{p50} frame_p95_ms=#{p95} frame_p99_ms=#{p99} pen_end_x=#{pen_end} quads=#{tr.stats[:quads]} batches=#{tr.stats[:batches]}"
  puts "criterion_note=non-bg counted as RGB delta>8 from white background; cpu_coverage_sum counts nonzero R8 atlas bytes over rendered glyph rects; ratio tolerance [0.5,1.5] accounts for GL_LINEAR filtering, blending edge coverage, and y-axis/sample-position differences vs source bitmap"
  puts "gl_path=GL1.1_compat R8->GL_ALPHA glPixelStorei(GL_UNPACK_ALIGNMENT,1) glTexCoord2f/glVertex2f"

  if verify_mode
    exit(pixel_match ? 0 : 1)
  else
    # non-verify still report factual outcome
    exit(0)
  end
rescue ex
  STDERR.puts "blocking=exception message=#{ex.message.inspect} backtrace_first=#{(ex.backtrace? || [] of String).first?.inspect}"
  STDERR.puts "note=window_or_gl_unavailable_or_runtime_error; pixel_match not fabricated"
  exit 1
end
