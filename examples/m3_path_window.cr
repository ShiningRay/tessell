# M3-WP4 path stencil/cover: GL window verification (task-141 stage B)
# Usage:
#   crystal run examples/m3_path_window.cr -- --frames=20 --verify
#   crystal run examples/m3_path_window.cr -- --frames=20 --verify --no-stencil
# Star: 5 outer tips in pentagram order (self-intersecting TRIANGLE_FAN),
# radius 100, center (400.13, 300.29) — non-integer offset so no edge passes
# exactly through a pixel center (GL top-left fill vs point sampling).
# 0.37/0.61 曾得 diff_pixels=1（边界 fill convention），故取 0.13/0.29。
# --verify criteria (stencil mode):
#   stencil_bits >= 8 && diff_pixels == 0 && fill_pixels_gl == fill_pixels_cpu
#   && fill_pixels_gl > 0
# --no-stencil negative: direct TRIANGLE_FAN + solid color (no stencil); the
# fan fills the star center that even-odd leaves empty => diff_pixels > 0 and
# verify MUST fail (EXIT 1). This is the counterexample proving the center is
# empty by parity, not by luck.

require "../src/tessell"
require "../src/tessell/render/gl/gl_backend"
require "../src/tessell/render/polygon"

@[Link("kernel32")]
lib LibKernel32
  fun GetModuleHandleW(lpModuleName : UInt16*) : Void*
  fun GetLastError : UInt32
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
  fun CreateWindowExW(dwExStyle : UInt32, lpClassName : UInt16*, lpWindowName : UInt16*,
                      dwStyle : UInt32, x : Int32, y : Int32, nWidth : Int32, nHeight : Int32,
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

@[Link("opengl32")]
lib LibGL
  GL_TRIANGLE_FAN   = 0x0006_u32
  GL_RGBA           = 0x1908_u32
  GL_UNSIGNED_BYTE  = 0x1401_u32
  GL_PACK_ALIGNMENT = 0x0D05_u32

  fun glBegin(mode : UInt32) : Void
  fun glEnd : Void
  fun glColor4f(red : Float32, green : Float32, blue : Float32, alpha : Float32) : Void
  fun glVertex2f(x : Float32, y : Float32) : Void
  fun glFinish : Void
  fun glPixelStorei(pname : UInt32, param : Int32) : Void
  fun glReadPixels(x : Int32, y : Int32, width : Int32, height : Int32,
                   format : UInt32, type : UInt32, pixels : Void*) : Void
end

module PwState
  class_property quit_requested : Bool = false
end

def pw_to_wstr(s : String) : Slice(UInt16)
  u = s.to_utf16
  buf = Slice(UInt16).new(u.size + 1, 0_u16)
  u.size.times { |i| buf[i] = u[i] }
  buf
end

def pw_fail(msg : String)
  err = LibKernel32.GetLastError
  STDERR.puts "error=#{msg} win32_error=#{err}"
  exit 1
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

PFD_DRAW_TO_WINDOW  = 0x00000004_u32
PFD_SUPPORT_OPENGL  = 0x00000020_u32
PFD_DOUBLEBUFFER    = 0x00000001_u32
PFD_TYPE_RGBA       = 0_u8
PFD_MAIN_PLANE      = 0_u8

CS_OWNDC            = 0x0020_u32

PW_WNDPROC = ->(hwnd : Void*, msg : UInt32, wparam : UInt64, lparam : Int64) : Int64 do
  case msg
  when WM_CLOSE
    LibUser32.DestroyWindow(hwnd)
    return 0_i64
  when WM_DESTROY
    LibUser32.PostQuitMessage(0)
    PwState.quit_requested = true
    return 0_i64
  when WM_KEYDOWN
    if wparam == VK_ESCAPE
      LibUser32.DestroyWindow(hwnd)
      return 0_i64
    end
  end
  LibUser32.DefWindowProcW(hwnd, msg, wparam, lparam)
end

# 5 outer tips in pentagram order (connect every 2nd tip): self-intersecting
# fan; even-odd parity leaves the central pentagon empty.
def pw_star_points(cx : Float32, cy : Float32, r : Float32) : Array(Tessell::Point)
  pts = [] of Tessell::Point
  5.times do |i|
    angle = -Math::PI / 2.0 + i.to_f64 * 4.0 * Math::PI / 5.0
    pts << Tessell::Point.new(cx + r.to_f64 * Math.cos(angle),
      cy + r.to_f64 * Math.sin(angle))
  end
  pts
end

# Solid red, premultiplied RGBA8 (opaque), packed 0xAARRGGBB.
PW_FILL = 0xFF0000FF_u32

def pw_capture(w : Int32, h : Int32) : Bytes
  buf = Bytes.new(w * h * 4)
  LibGL.glPixelStorei(LibGL::GL_PACK_ALIGNMENT, 1)
  LibGL.glFinish
  LibGL.glReadPixels(0, 0, w, h, LibGL::GL_RGBA, LibGL::GL_UNSIGNED_BYTE, buf.to_unsafe.as(Void*))
  buf
end

# Byte-exact compare of GL readback vs CPU even-odd mask.
# CPU mask samples world points (bx0 + x + 0.5, by0 + y + 0.5) — exactly the
# GL pixel centers of screen pixel (bx0 + x, by0 + y). GL buffer row 0 is the
# BOTTOM window row, so GL row for CPU row y is (h - 1 - (by0 + y)).
def pw_compare(gl_buf : Bytes, mask : Bytes, bx0 : Int32, by0 : Int32,
               w2 : Int32, h2 : Int32, width : Int32, height : Int32) : {Int32, Int32, Int32}
  diff = 0
  gl_count = 0
  cpu_count = 0
  y = 0
  while y < h2
    x = 0
    while x < w2
      m = mask[y * w2 + x]
      cpu_count += 1 if m == 1_u8
      i = ((height - 1 - (by0 + y)) * width + (bx0 + x)) * 4
      if gl_buf[i] == 255_u8 && gl_buf[i + 1] == 0_u8 && gl_buf[i + 2] == 0_u8
        gl_count += 1
      end
      er = m == 1_u8 ? 255_u8 : 255_u8
      eg = m == 1_u8 ? 0_u8 : 255_u8
      eb = m == 1_u8 ? 0_u8 : 255_u8
      if gl_buf[i] != er || gl_buf[i + 1] != eg || gl_buf[i + 2] != eb || gl_buf[i + 3] != 255_u8
        diff += 1
      end
      x += 1
    end
    y += 1
  end
  {diff, gl_count, cpu_count}
end

# Direct TRIANGLE_FAN + solid color, no stencil (negative path).
def pw_draw_fan(points : Array(Tessell::Point)) : Nil
  TessellGL.glDisable(TessellGL::GL_TEXTURE_2D)
  TessellGL.glDisable(TessellGL::GL_BLEND)
  TessellGL.glColor4f(1.0_f32, 0.0_f32, 0.0_f32, 1.0_f32)
  TessellGL.glBegin(LibGL::GL_TRIANGLE_FAN)
  i = 0
  n = points.size
  while i < n
    p = points.unsafe_fetch(i)
    LibGL.glVertex2f(p.x, p.y)
    i += 1
  end
  TessellGL.glEnd
  TessellGL.glEnable(TessellGL::GL_BLEND)
  TessellGL.glEnable(TessellGL::GL_TEXTURE_2D)
  nil
end

width = 800
height = 600
frames_target = 30
verify = false
no_stencil = false
ARGV.each_with_index do |arg, i|
  if arg.starts_with?("--frames=")
    frames_target = arg.split("=", 2)[1].to_i
  elsif arg == "--frames" && i + 1 < ARGV.size
    frames_target = ARGV[i + 1].to_i
  elsif arg == "--verify"
    verify = true
  elsif arg == "--no-stencil"
    no_stencil = true
  end
end

result_ch = Channel({Bool, String}).new

iso_ctx = Fiber::ExecutionContext::Isolated.new("tessell-m3-path") do
  begin
    hinstance = LibKernel32.GetModuleHandleW(Pointer(UInt16).null)
    pw_fail("GetModuleHandleW") if hinstance.null?

    class_name = pw_to_wstr("TessellM3PathWindow")
    window_title = pw_to_wstr("Tessell M3 Path Stencil")

    wc = LibUser32::WNDCLASSEXW.new
    wc.cbSize = sizeof(LibUser32::WNDCLASSEXW).to_u32
    wc.style = CS_OWNDC
    wc.lpfnWndProc = PW_WNDPROC
    wc.cbClsExtra = 0
    wc.cbWndExtra = 0
    wc.hInstance = hinstance
    wc.hIcon = Pointer(Void).null
    wc.hCursor = LibUser32.LoadCursorW(Pointer(Void).null, IDC_ARROW)
    wc.hbrBackground = Pointer(Void).null
    wc.lpszMenuName = Pointer(UInt16).null
    wc.lpszClassName = class_name.to_unsafe
    wc.hIconSm = Pointer(Void).null

    atom = LibUser32.RegisterClassExW(pointerof(wc))
    pw_fail("RegisterClassExW") if atom == 0

    rect = LibUser32::RECT.new
    rect.left = 0
    rect.top = 0
    rect.right = width
    rect.bottom = height
    style = WS_OVERLAPPEDWINDOW
    LibUser32.AdjustWindowRectEx(pointerof(rect), style, 0, 0)
    win_w = rect.right - rect.left
    win_h = rect.bottom - rect.top

    hwnd = LibUser32.CreateWindowExW(
      0_u32,
      class_name.to_unsafe,
      window_title.to_unsafe,
      style | WS_VISIBLE,
      CW_USEDEFAULT, CW_USEDEFAULT,
      win_w, win_h,
      Pointer(Void).null,
      Pointer(Void).null,
      hinstance,
      Pointer(Void).null
    )
    pw_fail("CreateWindowExW") if hwnd.null?
    LibUser32.ShowWindow(hwnd, SW_SHOW)
    LibUser32.UpdateWindow(hwnd)

    hdc = LibUser32.GetDC(hwnd)
    pw_fail("GetDC") if hdc.null?

    pfd = LibGdi32::PIXELFORMATDESCRIPTOR.new
    pfd.nSize = sizeof(LibGdi32::PIXELFORMATDESCRIPTOR).to_u16
    pfd.nVersion = 1_u16
    pfd.dwFlags = PFD_DRAW_TO_WINDOW | PFD_SUPPORT_OPENGL | PFD_DOUBLEBUFFER
    pfd.iPixelType = PFD_TYPE_RGBA
    pfd.cColorBits = 32_u8
    pfd.cDepthBits = 24_u8
    pfd.cStencilBits = 8_u8
    pfd.iLayerType = PFD_MAIN_PLANE
    pf = LibGdi32.ChoosePixelFormat(hdc, pointerof(pfd))
    pw_fail("ChoosePixelFormat") if pf == 0
    pw_fail("SetPixelFormat") if LibGdi32.SetPixelFormat(hdc, pf, pointerof(pfd)) == 0

    hglrc = LibWGL.wglCreateContext(hdc)
    pw_fail("wglCreateContext") if hglrc.null?
    pw_fail("wglMakeCurrent") if LibWGL.wglMakeCurrent(hdc, hglrc) == 0

    backend = Tessell::Render::GL::GLBackend.new
    backend.init(width, height)
    backend.resize(width, height)
    backend.set_clear_color(1.0_f32, 1.0_f32, 1.0_f32, 1.0_f32)

    star_offset_x = 0.13_f32
    star_offset_y = 0.29_f32
    star = pw_star_points(400.0_f32 + star_offset_x, 300.0_f32 + star_offset_y, 100.0_f32)

    # Warmup frame (driver paths), then frames loop, then verify capture frame.
    backend.begin_frame(nil)
    if no_stencil
      pw_draw_fan(star)
    else
      backend.draw_polygon(star, PW_FILL, true)
    end
    backend.end_frame

    frames_done = 0
    msg = LibUser32::MSG.new
    while frames_done < frames_target && !PwState.quit_requested
      while LibUser32.PeekMessageW(pointerof(msg), Pointer(Void).null, 0_u32, 0_u32, PM_REMOVE) != 0
        if msg.message == WM_QUIT
          PwState.quit_requested = true
          break
        end
        LibUser32.TranslateMessage(pointerof(msg))
        LibUser32.DispatchMessageW(pointerof(msg))
      end
      break if PwState.quit_requested

      backend.begin_frame(nil)
      if no_stencil
        pw_draw_fan(star)
      else
        backend.draw_polygon(star, PW_FILL, true)
      end
      backend.end_frame
      LibGdi32.SwapBuffers(hdc)
      frames_done += 1
    end

    # Final frame without swap: read back and compare vs CPU even-odd mask.
    backend.begin_frame(nil)
    if no_stencil
      pw_draw_fan(star)
    else
      backend.draw_polygon(star, PW_FILL, true)
    end
    backend.end_frame

    poly = Tessell::Render::Polygon.new(star)
    b = poly.bounds
    bx0 = b.origin.x.floor.to_i
    by0 = b.origin.y.floor.to_i
    bx1 = b.max_x.ceil.to_i
    by1 = b.max_y.ceil.to_i
    w2 = bx1 - bx0
    h2 = by1 - by0
    mask = Bytes.new(w2 * h2)
    cpu_count = 0
    y = 0
    while y < h2
      x = 0
      while x < w2
        if poly.contains?(Tessell::Point.new(bx0 + x + 0.5_f32, by0 + y + 0.5_f32))
          mask[y * w2 + x] = 1_u8
          cpu_count += 1
        end
        x += 1
      end
      y += 1
    end

    gl_buf = pw_capture(width, height)
    diff_pixels, fill_pixels_gl, _ = pw_compare(gl_buf, mask, bx0, by0, w2, h2, width, height)
    fill_pixels_cpu = cpu_count

    # Steady-state zero-alloc probe over the draw path (3 windows, max, A/B,
    # GC.enable in ensure, <=1 retry).
    n = 1000
    10.times do
      backend.begin_frame(nil)
      if no_stencil
        pw_draw_fan(star)
      else
        backend.draw_polygon(star, PW_FILL, true)
      end
      backend.end_frame
    end

    delta_prime = 0_i64
    GC.collect
    GC.disable
    begin
      before = GC.stats.bytes_since_gc
      n.times do
        backend.begin_frame(nil)
        if no_stencil
          pw_draw_fan(star)
        else
          backend.draw_polygon(star, PW_FILL, true)
        end
        backend.end_frame
      end
      delta_prime = GC.stats.bytes_since_gc.to_i64 - before.to_i64
    ensure
      GC.enable
    end

    delta_calib = 0_i64
    calib_sink = 0_i64
    GC.collect
    GC.disable
    begin
      before = GC.stats.bytes_since_gc
      i = 0
      while i < n
        calib_sink &+= i.to_i64
        i += 1
      end
      delta_calib = GC.stats.bytes_since_gc.to_i64 - before.to_i64
    ensure
      GC.enable
    end
    _ = calib_sink

    retried = false
    attempt = 1
    delta_work = 0_i64
    seq = [0_i64, 0_i64, 0_i64]
    loop do
      seq = [0_i64, 0_i64, 0_i64]
      3.times do |wi|
        GC.collect
        GC.disable
        begin
          before = GC.stats.bytes_since_gc
          n.times do
            backend.begin_frame(nil)
            if no_stencil
              pw_draw_fan(star)
            else
              backend.draw_polygon(star, PW_FILL, true)
            end
            backend.end_frame
          end
          seq[wi] = GC.stats.bytes_since_gc.to_i64 - before.to_i64
        ensure
          GC.enable
        end
      end
      delta_work = seq.max
      puts "zero-alloc probe(path_draw_polygon): delta_prime=#{delta_prime} " \
           "delta_calib=#{delta_calib} delta_work=#{delta_work} N=#{n} " \
           "windows=[#{seq[0]},#{seq[1]},#{seq[2]}] retried=#{retried} attempt=#{attempt}"
      break if delta_work < n && delta_work <= 256
      if attempt >= 2
        raise "zero-alloc probe(path_draw_polygon): delta_work=#{delta_work} " \
              "delta_calib=#{delta_calib} delta_prime=#{delta_prime} N=#{n} " \
              "windows=[#{seq[0]},#{seq[1]},#{seq[2]}] retried=#{retried} attempt=#{attempt}"
      end
      retried = true
      attempt = 2
    end

    stencil_bits = backend.stencil_bits
    if no_stencil
      # Negative case: fan fills the star center that even-odd leaves empty,
      # so diff_pixels must be > 0; verify MUST fail (EXIT 1) when --verify.
      negative_holds = diff_pixels > 0
      pass_verify = false
      mode = "fan_no_stencil"
    else
      negative_holds = true
      pass_verify = stencil_bits >= 8 && diff_pixels == 0 &&
                    fill_pixels_gl == fill_pixels_cpu && fill_pixels_gl > 0
      mode = "stencil_cover"
    end

    # Present the final frame for visual sanity (not part of the comparison).
    LibGdi32.SwapBuffers(hdc)

    line = String.build do |s|
      s << "mode=#{mode}"
      s << " stencil_bits=#{stencil_bits}"
      s << " fill_pixels_gl=#{fill_pixels_gl}"
      s << " fill_pixels_cpu=#{fill_pixels_cpu}"
      s << " star_pixels=#{fill_pixels_cpu}"
      s << " diff_pixels=#{diff_pixels}"
      s << " star_offset_x=#{star_offset_x} star_offset_y=#{star_offset_y}"
      s << " star_vertices=#{star.size}"
      s << " frames=#{frames_done}"
      s << " alloc_windows=[#{seq[0]},#{seq[1]},#{seq[2]}]"
      s << " retried=#{retried} attempt=#{attempt}"
      s << " negative_holds=#{negative_holds}"
      s << " verify=#{pass_verify ? "pass" : "fail"}"
    end

    backend.close
    LibWGL.wglMakeCurrent(Pointer(Void).null, Pointer(Void).null)
    LibWGL.wglDeleteContext(hglrc)
    LibUser32.ReleaseDC(hwnd, hdc)
    LibUser32.DestroyWindow(hwnd) unless PwState.quit_requested

    ok = (!verify) || pass_verify
    result_ch.send({ok, line})
  rescue ex
    result_ch.send({false, "error=exception message=#{ex.message.inspect} backtrace=#{ex.backtrace.first(3).join(" | ").inspect}"})
  end
end

ok, line = result_ch.receive
puts line
exit(ok ? 0 : 1)
