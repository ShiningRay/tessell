# M0-WP3 minimal window + WGL submit probe (P-WIN-2)
# Pure FFI: user32/gdi32/opengl32, GL 1.1 immediate mode.
# Usage:
#   crystal build examples/m0_window_probe.cr -o bin/m0_window_probe.exe
#   bin/m0_window_probe.exe --frames=120

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
  fun CreateWindowExW(
    dwExStyle : UInt32,
    lpClassName : UInt16*,
    lpWindowName : UInt16*,
    dwStyle : UInt32,
    x : Int32, y : Int32,
    nWidth : Int32, nHeight : Int32,
    hWndParent : Void*,
    hMenu : Void*,
    hInstance : Void*,
    lpParam : Void*
  ) : Void*
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
  GL_COLOR_BUFFER_BIT = 0x00004000_u32
  GL_TRIANGLES        = 0x0004_u32
  GL_VERSION          = 0x1F02_u32
  GL_RENDERER         = 0x1F01_u32
  GL_RGBA             = 0x1908_u32
  GL_UNSIGNED_BYTE    = 0x1401_u32

  fun glViewport(x : Int32, y : Int32, width : Int32, height : Int32) : Void
  fun glClearColor(red : Float32, green : Float32, blue : Float32, alpha : Float32) : Void
  fun glClear(mask : UInt32) : Void
  fun glBegin(mode : UInt32) : Void
  fun glEnd : Void
  fun glColor3f(red : Float32, green : Float32, blue : Float32) : Void
  fun glVertex2f(x : Float32, y : Float32) : Void
  fun glFlush : Void
  fun glGetString(name : UInt32) : UInt8*
  fun glReadPixels(x : Int32, y : Int32, width : Int32, height : Int32, format : UInt32, type : UInt32, pixels : Void*) : Void
  fun glGetError : UInt32
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

def fail(msg : String)
  err = LibKernel32.GetLastError
  STDERR.puts "error=#{msg} win32_error=#{err}"
  exit 1
end

# Constants
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

# WndProc (closure-less proc for FFI callback)
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

frames_target = 180
ARGV.each_with_index do |arg, i|
  if arg.starts_with?("--frames=")
    frames_target = arg.split("=", 2)[1].to_i
  elsif arg == "--frames" && i + 1 < ARGV.size
    frames_target = ARGV[i + 1].to_i
  end
end

main_tid = Thread.current.object_id
result_ch = Channel({Bool, String}).new

iso_ctx = Fiber::ExecutionContext::Isolated.new("tessell-ui") do
  iso_tid = Thread.current.object_id
  begin
    hinstance = LibKernel32.GetModuleHandleW(Pointer(UInt16).null)
    fail("GetModuleHandleW") if hinstance.null?

    class_name = to_wstr("TessellM0WindowProbe")
    window_title = to_wstr("Tessell M0 Probe")

    wc = LibUser32::WNDCLASSEXW.new
    wc.cbSize = sizeof(LibUser32::WNDCLASSEXW).to_u32
    wc.style = CS_OWNDC
    wc.lpfnWndProc = WNDPROC
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
    if atom == 0
      fail("RegisterClassExW")
    end

    width = 320
    height = 240
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
    fail("CreateWindowExW") if hwnd.null?

    LibUser32.ShowWindow(hwnd, SW_SHOW)
    LibUser32.UpdateWindow(hwnd)

    hdc = LibUser32.GetDC(hwnd)
    fail("GetDC") if hdc.null?

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
    fail("ChoosePixelFormat") if pf == 0
    if LibGdi32.SetPixelFormat(hdc, pf, pointerof(pfd)) == 0
      fail("SetPixelFormat")
    end

    hglrc = LibWGL.wglCreateContext(hdc)
    fail("wglCreateContext") if hglrc.null?
    if LibWGL.wglMakeCurrent(hdc, hglrc) == 0
      fail("wglMakeCurrent")
    end

    gl_version = cstr_to_string(LibGL.glGetString(LibGL::GL_VERSION))
    gl_renderer = cstr_to_string(LibGL.glGetString(LibGL::GL_RENDERER))
    if gl_version.empty? || gl_renderer.empty?
      STDERR.puts "error=glGetString_empty gl_version=#{gl_version.inspect} gl_renderer=#{gl_renderer.inspect}"
      exit 1
    end

    # Clear and draw: large triangle covering center
    clear_r = 0.2_f32
    clear_g = 0.4_f32
    clear_b = 0.6_f32
    tri_r = 0.8_f32
    tri_g = 0.2_f32
    tri_b = 0.2_f32

    frames_done = 0
    swap_ok = 0
    msg = LibUser32::MSG.new

    start_ms = LibKernel32.GetTickCount64
    last_pixel = StaticArray(UInt8, 4).new(0_u8)

    while frames_done < frames_target && !ProbeState.quit_requested
      # non-blocking message pump
      while LibUser32.PeekMessageW(pointerof(msg), Pointer(Void).null, 0_u32, 0_u32, PM_REMOVE) != 0
        if msg.message == WM_QUIT
          ProbeState.quit_requested = true
          break
        end
        LibUser32.TranslateMessage(pointerof(msg))
        LibUser32.DispatchMessageW(pointerof(msg))
      end
      break if ProbeState.quit_requested

      LibGL.glViewport(0, 0, width, height)
      LibGL.glClearColor(clear_r, clear_g, clear_b, 1.0_f32)
      LibGL.glClear(LibGL::GL_COLOR_BUFFER_BIT)

      LibGL.glBegin(LibGL::GL_TRIANGLES)
      LibGL.glColor3f(tri_r, tri_g, tri_b)
      LibGL.glVertex2f(-1.0_f32, -1.0_f32)
      LibGL.glVertex2f(3.0_f32, -1.0_f32)
      LibGL.glVertex2f(-1.0_f32, 3.0_f32)
      LibGL.glEnd

      LibGL.glFlush
      LibGL.glReadPixels(width // 2, height // 2, 1, 1, LibGL::GL_RGBA, LibGL::GL_UNSIGNED_BYTE, last_pixel.to_unsafe.as(Void*))

      if LibGdi32.SwapBuffers(hdc) != 0
        swap_ok += 1
      end
      frames_done += 1
    end

    end_ms = LibKernel32.GetTickCount64
    elapsed_ms = end_ms >= start_ms ? end_ms - start_ms : 0_u64

    # Pixel match: expect triangle color at center (tolerance ±2)
    exp_r = (tri_r * 255.0_f32).round.to_i
    exp_g = (tri_g * 255.0_f32).round.to_i
    exp_b = (tri_b * 255.0_f32).round.to_i
    dr = (last_pixel[0].to_i - exp_r).abs
    dg = (last_pixel[1].to_i - exp_g).abs
    db = (last_pixel[2].to_i - exp_b).abs
    pixel_match = dr <= 2 && dg <= 2 && db <= 2

    # Cleanup (best effort)
    LibWGL.wglMakeCurrent(Pointer(Void).null, Pointer(Void).null)
    LibWGL.wglDeleteContext(hglrc)
    LibUser32.ReleaseDC(hwnd, hdc)
    LibUser32.DestroyWindow(hwnd) unless ProbeState.quit_requested

    glv = gl_version.gsub(/[\s=]+/, "_")
    glr = gl_renderer.gsub(/[\s=]+/, "_")
    line = "hwnd=#{hwnd.address} pixel_format=#{pf} gl_version=#{glv} gl_renderer=#{glr} frames=#{frames_done} swapbuffers=#{swap_ok} pixel_match=#{pixel_match} iso_tid=#{iso_tid} main_tid=#{main_tid} elapsed_ms=#{elapsed_ms} pixel_rgba=#{last_pixel[0]},#{last_pixel[1]},#{last_pixel[2]},#{last_pixel[3]} expected_rgb=#{exp_r},#{exp_g},#{exp_b}"

    ok = frames_done == frames_target && pixel_match && !gl_version.empty?
    result_ch.send({ok, line})
  rescue ex
    result_ch.send({false, "error=exception message=#{ex.message.inspect} iso_tid=#{Thread.current.object_id} main_tid=#{main_tid}"})
  end
end

ok, line = result_ch.receive
puts line
exit(ok ? 0 : 1)
