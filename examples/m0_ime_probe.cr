# M0-WP4-IME probe: IMM32 attach + IME message counting (M-1)
# Based on examples/m0_window_probe.cr structure (copied, original unchanged).
# Pure FFI: user32/gdi32/opengl32/imm32.
# Usage:
#   crystal run examples/m0_ime_probe.cr -- --frames=60
#   crystal run examples/m0_ime_probe.cr -- --frames=60 --ime-test

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
  fun SendMessageW(hWnd : Void*, msg : UInt32, wParam : UInt64, lParam : Int64) : Int64
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

  fun glViewport(x : Int32, y : Int32, width : Int32, height : Int32) : Void
  fun glClearColor(red : Float32, green : Float32, blue : Float32, alpha : Float32) : Void
  fun glClear(mask : UInt32) : Void
  fun glBegin(mode : UInt32) : Void
  fun glEnd : Void
  fun glColor3f(red : Float32, green : Float32, blue : Float32) : Void
  fun glVertex2f(x : Float32, y : Float32) : Void
  fun glFlush : Void
end

@[Link("imm32")]
lib LibImm32
  struct POINT
    x : Int32
    y : Int32
  end

  struct RECT
    left : Int32
    top : Int32
    right : Int32
    bottom : Int32
  end

  struct COMPOSITIONFORM
    dwStyle : UInt32
    ptCurrentPos : POINT
    rcArea : RECT
  end

  alias HIMC = Void*

  fun ImmGetContext(hWnd : Void*) : HIMC
  fun ImmReleaseContext(hWnd : Void*, hIMC : HIMC) : Int32
  fun ImmAssociateContext(hWnd : Void*, hIMC : HIMC) : HIMC
  fun ImmSetOpenStatus(hIMC : HIMC, fOpen : Int32) : Int32
  fun ImmGetOpenStatus(hIMC : HIMC) : Int32
  fun ImmSetCompositionWindow(hIMC : HIMC, lpCompForm : COMPOSITIONFORM*) : Int32
end

module ProbeState
  class_property quit_requested : Bool = false
  class_property ime_start : Int32 = 0
  class_property ime_composition : Int32 = 0
  class_property ime_end : Int32 = 0
  class_property ime_setcontext : Int32 = 0
  class_property ime_notify : Int32 = 0
  class_property ime_test_injected : Int32 = 0
end

def to_wstr(s : String) : Slice(UInt16)
  u = s.to_utf16
  buf = Slice(UInt16).new(u.size + 1, 0_u16)
  u.size.times { |i| buf[i] = u[i] }
  buf
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

WM_IME_STARTCOMPOSITION = 0x010D_u32
WM_IME_ENDCOMPOSITION   = 0x010E_u32
WM_IME_COMPOSITION      = 0x010F_u32
WM_IME_SETCONTEXT       = 0x0281_u32
WM_IME_NOTIFY           = 0x0282_u32

CFS_POINT = 0x0002_u32

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
  when WM_IME_STARTCOMPOSITION
    ProbeState.ime_start += 1
  when WM_IME_COMPOSITION
    ProbeState.ime_composition += 1
  when WM_IME_ENDCOMPOSITION
    ProbeState.ime_end += 1
  when WM_IME_SETCONTEXT
    ProbeState.ime_setcontext += 1
  when WM_IME_NOTIFY
    ProbeState.ime_notify += 1
  end
  LibUser32.DefWindowProcW(hwnd, msg, wparam, lparam)
end

frames_target = 60
ime_test_mode = false
ARGV.each_with_index do |arg, i|
  if arg.starts_with?("--frames=")
    frames_target = arg.split("=", 2)[1].to_i
  elsif arg == "--frames" && i + 1 < ARGV.size
    frames_target = ARGV[i + 1].to_i
  elsif arg == "--ime-test"
    ime_test_mode = true
  end
end

main_tid = Thread.current.object_id
result_ch = Channel({Bool, String}).new

iso_ctx = Fiber::ExecutionContext::Isolated.new("tessell-ui") do
  iso_tid = Thread.current.object_id
  begin
    hinstance = LibKernel32.GetModuleHandleW(Pointer(UInt16).null)
    fail("GetModuleHandleW") if hinstance.null?

    class_name = to_wstr("TessellM0ImeProbe")
    window_title = to_wstr("Tessell M0 IME Probe")

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
    fail("RegisterClassExW") if atom == 0

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

    # Minimal GL context (kept from window probe structure)
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
    fail("SetPixelFormat") if LibGdi32.SetPixelFormat(hdc, pf, pointerof(pfd)) == 0
    hglrc = LibWGL.wglCreateContext(hdc)
    fail("wglCreateContext") if hglrc.null?
    fail("wglMakeCurrent") if LibWGL.wglMakeCurrent(hdc, hglrc) == 0

    # --- IMM32 setup ---
    imm_error = "none"
    imm_available = false
    imm_open_status = -1
    imm_context_addr = "0x0"
    imm_associate_ret = "0x0"
    imm_set_open_ret = -1
    imm_set_comp_ret = -1

    himc = LibImm32.ImmGetContext(hwnd)
    imm_context_addr = "0x#{himc.address.to_s(16)}"
    if himc.null?
      imm_available = false
      err = LibKernel32.GetLastError
      imm_error = "ImmGetContext_null win32_error=#{err}"
      # Per spec: if ImmGetContext fails, print tokens with imm_available=false and exit 0
      frames_done = 0
      swap_ok = 0
      msg = LibUser32::MSG.new
      while frames_done < frames_target && !ProbeState.quit_requested
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
        LibGL.glClearColor(0.15_f32, 0.15_f32, 0.2_f32, 1.0_f32)
        LibGL.glClear(LibGL::GL_COLOR_BUFFER_BIT)
        LibGL.glFlush
        swap_ok += 1 if LibGdi32.SwapBuffers(hdc) != 0
        frames_done += 1
      end
      ime_messages = ProbeState.ime_start + ProbeState.ime_composition + ProbeState.ime_end + ProbeState.ime_setcontext + ProbeState.ime_notify
      LibWGL.wglMakeCurrent(Pointer(Void).null, Pointer(Void).null)
      LibWGL.wglDeleteContext(hglrc)
      LibUser32.ReleaseDC(hwnd, hdc)
      LibImm32.ImmReleaseContext(hwnd, himc) unless himc.null?
      line = "imm_available=false imm_open_status=#{imm_open_status} ime_messages=#{ime_messages} imm_error=#{imm_error} hwnd=0x#{hwnd.address.to_s(16)} imm_context=#{imm_context_addr} iso_tid=#{iso_tid} main_tid=#{main_tid} frames=#{frames_done}"
      puts "ime_start=#{ProbeState.ime_start} ime_composition=#{ProbeState.ime_composition} ime_end=#{ProbeState.ime_end} ime_setcontext=#{ProbeState.ime_setcontext} ime_notify=#{ProbeState.ime_notify} ime_test_injected=#{ProbeState.ime_test_injected}"
      puts line
      result_ch.send({true, ""})
    else
      imm_available = true
      assoc_prev = LibImm32.ImmAssociateContext(hwnd, himc)
      imm_associate_ret = "0x#{assoc_prev.address.to_s(16)}"

      imm_set_open_ret = LibImm32.ImmSetOpenStatus(himc, 1)
      imm_open_status = LibImm32.ImmGetOpenStatus(himc)

      comp = LibImm32::COMPOSITIONFORM.new
      comp.dwStyle = CFS_POINT
      comp.ptCurrentPos = LibImm32::POINT.new
      comp.ptCurrentPos.x = 10
      comp.ptCurrentPos.y = 10
      comp.rcArea = LibImm32::RECT.new
      comp.rcArea.left = 0
      comp.rcArea.top = 0
      comp.rcArea.right = width
      comp.rcArea.bottom = height
      imm_set_comp_ret = LibImm32.ImmSetCompositionWindow(himc, pointerof(comp))

      # Synthetic message injection to prove message path (if requested)
      if ime_test_mode
        LibUser32.SendMessageW(hwnd, WM_IME_SETCONTEXT, 1_u64, 0_i64)
        ProbeState.ime_test_injected += 1
      end

      frames_done = 0
      swap_ok = 0
      msg = LibUser32::MSG.new
      while frames_done < frames_target && !ProbeState.quit_requested
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
        LibGL.glClearColor(0.15_f32, 0.15_f32, 0.2_f32, 1.0_f32)
        LibGL.glClear(LibGL::GL_COLOR_BUFFER_BIT)
        LibGL.glFlush
        swap_ok += 1 if LibGdi32.SwapBuffers(hdc) != 0
        frames_done += 1
      end

      ime_messages = ProbeState.ime_start + ProbeState.ime_composition + ProbeState.ime_end + ProbeState.ime_setcontext + ProbeState.ime_notify

      LibWGL.wglMakeCurrent(Pointer(Void).null, Pointer(Void).null)
      LibWGL.wglDeleteContext(hglrc)
      LibUser32.ReleaseDC(hwnd, hdc)
      LibImm32.ImmReleaseContext(hwnd, himc)

      line = "imm_available=true imm_open_status=#{imm_open_status} ime_messages=#{ime_messages} imm_error=#{imm_error} hwnd=0x#{hwnd.address.to_s(16)} imm_context=#{imm_context_addr} imm_associate_ret=#{imm_associate_ret} imm_set_open_ret=#{imm_set_open_ret} imm_set_comp_ret=#{imm_set_comp_ret} iso_tid=#{iso_tid} main_tid=#{main_tid} frames=#{frames_done}"
      puts "ime_start=#{ProbeState.ime_start} ime_composition=#{ProbeState.ime_composition} ime_end=#{ProbeState.ime_end} ime_setcontext=#{ProbeState.ime_setcontext} ime_notify=#{ProbeState.ime_notify} ime_test_injected=#{ProbeState.ime_test_injected}"
      puts line
      result_ch.send({true, ""})
    end
  rescue ex
    result_ch.send({false, "error=exception message=#{ex.message.inspect} iso_tid=#{Thread.current.object_id} main_tid=#{main_tid}"})
  end
end

ok, errline = result_ch.receive
unless ok
  STDERR.puts errline
  exit 1
end
exit 0
