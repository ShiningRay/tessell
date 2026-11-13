# M3-WP1 dirty-rect partial submit: pixel equivalence proof (stage B)
# Usage:
#   crystal run examples/m3_dirty_window.cr -- --frames=20 --verify
#   crystal run examples/m3_dirty_window.cr -- --frames=20 --verify --no-move
# Outputs key=value lines including diff_pixels (B vs C), diff_A_vs_C (A vs C),
# submitted_quads_dirty/full, dirty_area_ratio, culled_quads, frame_full_p50/p95/p99, frame_dirty_p50/p95/p99.
# --verify exit 0 iff diff_pixels==0 && diff_A_vs_C>0 && submitted_quads_dirty < submitted_quads_full && dirty_area_ratio < 0.35
# --no-move: move_x1==move_x0 (no element motion) => diff_A_vs_C==0, so --verify must fail (anti-vacuity proof).

require "../src/tessell"
require "../src/tessell/render/gl/gl_backend"

@[Link("kernel32")]
lib M3Kernel32
  fun GetModuleHandleW(lpModuleName : UInt16*) : Void*
  fun GetLastError : UInt32
  fun QueryPerformanceCounter(lpPerformanceCount : Int64*) : Int32
  fun QueryPerformanceFrequency(lpFrequency : Int64*) : Int32
end

@[Link("user32")]
lib M3User32
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
lib M3Gdi32
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
lib M3WGL
  fun wglCreateContext(hdc : Void*) : Void*
  fun wglMakeCurrent(hdc : Void*, hglrc : Void*) : Int32
  fun wglDeleteContext(hglrc : Void*) : Int32
end

@[Link("opengl32")]
lib M3GL
  GL_RGBA          = 0x1908_u32
  GL_UNSIGNED_BYTE = 0x1401_u32
  GL_PACK_ALIGNMENT = 0x0D05_u32
  fun glReadPixels(x : Int32, y : Int32, width : Int32, height : Int32, format : UInt32, type : UInt32, pixels : Void*) : Void
  fun glFinish : Void
  fun glPixelStorei(pname : UInt32, param : Int32) : Void
end

module M3ProbeState
  class_property quit_requested : Bool = false
end

def m3_to_wstr(s : String) : Slice(UInt16)
  u = s.to_utf16
  buf = Slice(UInt16).new(u.size + 1, 0_u16)
  u.size.times { |i| buf[i] = u[i] }
  buf
end

def m3_fail(msg : String)
  err = M3Kernel32.GetLastError
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
CS_OWNDC            = 0x0020_u32

PFD_DRAW_TO_WINDOW  = 0x00000004_u32
PFD_SUPPORT_OPENGL  = 0x00000020_u32
PFD_DOUBLEBUFFER    = 0x00000001_u32
PFD_TYPE_RGBA       = 0_u8
PFD_MAIN_PLANE      = 0_u8

M3_WNDPROC = ->(hwnd : Void*, msg : UInt32, wparam : UInt64, lparam : Int64) : Int64 do
  case msg
  when WM_CLOSE
    M3User32.DestroyWindow(hwnd)
    return 0_i64
  when WM_DESTROY
    M3User32.PostQuitMessage(0)
    M3ProbeState.quit_requested = true
    return 0_i64
  when WM_KEYDOWN
    if wparam == VK_ESCAPE
      M3User32.DestroyWindow(hwnd)
      return 0_i64
    end
  end
  M3User32.DefWindowProcW(hwnd, msg, wparam, lparam)
end

def m3_now_us : Int64
  now = 0_i64
  M3Kernel32.QueryPerformanceCounter(pointerof(now))
  freq = 0_i64
  M3Kernel32.QueryPerformanceFrequency(pointerof(freq))
  return 0_i64 if freq == 0
  (now.to_f64 * 1_000_000.0 / freq.to_f64).to_i64
end

def m3_percentile(sorted : Array(Int64), p : Float64) : Int64
  return 0_i64 if sorted.empty?
  idx = ((sorted.size - 1).to_f64 * p).round.to_i
  idx = 0 if idx < 0
  idx = sorted.size - 1 if idx >= sorted.size
  sorted[idx]
end

# Scene: >=3 text segments + block "rectangles" (all via TextRenderer/backend)
# moved element: "MOVE" at move_x, move_y
def build_scene(renderer : Tessell::Render::TextRenderer,
                placement_sink : Array(Tessell::Text::GlyphPlacement),
                move_x : Float32, move_y : Float32, size_px : Int32,
                viewport_w : Int32, viewport_h : Int32) : Nil
  renderer.reset
  renderer.append_text_cached(placement_sink, "Hello M3 Dirty", 20.0_f32, 40.0_f32, size_px, viewport_w, viewport_h)
  renderer.append_text_cached(placement_sink, "Backend + Scissor", 20.0_f32, 90.0_f32, size_px, viewport_w, viewport_h)
  renderer.append_text_cached(placement_sink, "RectA ########", 20.0_f32, 140.0_f32, size_px, viewport_w, viewport_h)
  renderer.append_text_cached(placement_sink, "RectB ########", 20.0_f32, 190.0_f32, size_px, viewport_w, viewport_h)
  renderer.append_text_cached(placement_sink, "MOVE", move_x, move_y, size_px, viewport_w, viewport_h)
end

def render_full(backend : Tessell::Render::GL::GLBackend,
                renderer : Tessell::Render::TextRenderer,
                placement_sink : Array(Tessell::Text::GlyphPlacement),
                move_x : Float32, move_y : Float32, size_px : Int32,
                viewport_w : Int32, viewport_h : Int32) : Int32
  backend.begin_frame(nil)
  build_scene(renderer, placement_sink, move_x, move_y, size_px, viewport_w, viewport_h)
  submitted = backend.draw_text(renderer.vertices, renderer.batch_runs, renderer.batch_count)
  backend.end_frame
  submitted
end

def render_dirty(backend : Tessell::Render::GL::GLBackend,
                 renderer : Tessell::Render::TextRenderer,
                 placement_sink : Array(Tessell::Text::GlyphPlacement),
                 move_x : Float32, move_y : Float32, size_px : Int32,
                 viewport_w : Int32, viewport_h : Int32,
                 dirty_rects : Array(Tessell::Rect)) : {Int32, Int32}
  backend.begin_frame(dirty_rects)
  build_scene(renderer, placement_sink, move_x, move_y, size_px, viewport_w, viewport_h)
  submitted = backend.draw_text(renderer.vertices, renderer.batch_runs, renderer.batch_count)
  st = backend.stats
  backend.end_frame
  {submitted, st.culled_quads}
end

def capture_pixels(w : Int32, h : Int32) : Bytes
  buf = Bytes.new(w * h * 4)
  M3GL.glPixelStorei(M3GL::GL_PACK_ALIGNMENT, 1)
  M3GL.glFinish
  M3GL.glReadPixels(0, 0, w, h, M3GL::GL_RGBA, M3GL::GL_UNSIGNED_BYTE, buf.to_unsafe.as(Void*))
  buf
end

def pixel_diff(a : Bytes, b : Bytes) : Int32
  return a.size // 4 if a.size != b.size
  diff = 0
  i = 0
  n = a.size
  while i < n
    # compare RGB(A) - small tolerance 0 for exact
    if a[i] != b[i] || a[i + 1] != b[i + 1] || a[i + 2] != b[i + 2] || a[i + 3] != b[i + 3]
      diff += 1
    end
    i += 4
  end
  diff
end

frames_target = 20
verify = false
no_move = false
ARGV.each_with_index do |arg, i|
  if arg.starts_with?("--frames=")
    frames_target = arg.split("=", 2)[1].to_i
  elsif arg == "--frames" && i + 1 < ARGV.size
    frames_target = ARGV[i + 1].to_i
  elsif arg == "--verify"
    verify = true
  elsif arg == "--no-move"
    no_move = true
  end
end

result_ch = Channel({Bool, String}).new

iso_ctx = Fiber::ExecutionContext::Isolated.new("tessell-m3-dirty") do
  begin
    hinstance = M3Kernel32.GetModuleHandleW(Pointer(UInt16).null)
    m3_fail("GetModuleHandleW") if hinstance.null?

    class_name = m3_to_wstr("TessellM3DirtyProbe")
    window_title = m3_to_wstr("Tessell M3 Dirty")

    wc = M3User32::WNDCLASSEXW.new
    wc.cbSize = sizeof(M3User32::WNDCLASSEXW).to_u32
    wc.style = CS_OWNDC
    wc.lpfnWndProc = M3_WNDPROC
    wc.cbClsExtra = 0
    wc.cbWndExtra = 0
    wc.hInstance = hinstance
    wc.hIcon = Pointer(Void).null
    wc.hCursor = M3User32.LoadCursorW(Pointer(Void).null, IDC_ARROW)
    wc.hbrBackground = Pointer(Void).null
    wc.lpszMenuName = Pointer(UInt16).null
    wc.lpszClassName = class_name.to_unsafe
    wc.hIconSm = Pointer(Void).null
    atom = M3User32.RegisterClassExW(pointerof(wc))
    m3_fail("RegisterClassExW") if atom == 0

    width = 640
    height = 360
    rect = M3User32::RECT.new
    rect.left = 0; rect.top = 0; rect.right = width; rect.bottom = height
    style = WS_OVERLAPPEDWINDOW
    M3User32.AdjustWindowRectEx(pointerof(rect), style, 0, 0)
    win_w = rect.right - rect.left
    win_h = rect.bottom - rect.top

    hwnd = M3User32.CreateWindowExW(0_u32, class_name.to_unsafe, window_title.to_unsafe,
                                    style | WS_VISIBLE, CW_USEDEFAULT, CW_USEDEFAULT,
                                    win_w, win_h, Pointer(Void).null, Pointer(Void).null,
                                    hinstance, Pointer(Void).null)
    m3_fail("CreateWindowExW") if hwnd.null?
    M3User32.ShowWindow(hwnd, SW_SHOW)
    M3User32.UpdateWindow(hwnd)

    hdc = M3User32.GetDC(hwnd)
    m3_fail("GetDC") if hdc.null?

    pfd = M3Gdi32::PIXELFORMATDESCRIPTOR.new
    pfd.nSize = sizeof(M3Gdi32::PIXELFORMATDESCRIPTOR).to_u16
    pfd.nVersion = 1_u16
    pfd.dwFlags = PFD_DRAW_TO_WINDOW | PFD_SUPPORT_OPENGL | PFD_DOUBLEBUFFER
    pfd.iPixelType = PFD_TYPE_RGBA
    pfd.cColorBits = 32_u8
    pfd.cDepthBits = 24_u8
    pfd.cStencilBits = 8_u8
    pfd.iLayerType = PFD_MAIN_PLANE
    pf = M3Gdi32.ChoosePixelFormat(hdc, pointerof(pfd))
    m3_fail("ChoosePixelFormat") if pf == 0
    m3_fail("SetPixelFormat") if M3Gdi32.SetPixelFormat(hdc, pf, pointerof(pfd)) == 0

    hglrc = M3WGL.wglCreateContext(hdc)
    m3_fail("wglCreateContext") if hglrc.null?
    m3_fail("wglMakeCurrent") if M3WGL.wglMakeCurrent(hdc, hglrc) == 0

    unless Tessell::Text::FtMeasurer.available?
      result_ch.send({false, "error=ft_unavailable reason=#{Tessell::Text::FtMeasurer.unavailable_reason.inspect}"})
      next
    end

    font_path = "C:/Windows/Fonts/msyh.ttc"
    measurer = Tessell::Text::FtMeasurer.open(font_path, 0)
    atlas = Tessell::Text::GlyphAtlas.new(1024, 4096)
    rasterizer = Tessell::Text::Rasterizer.new(measurer, atlas, 1)
    renderer = Tessell::Render::TextRenderer.new(atlas, rasterizer)
    backend = Tessell::Render::GL::GLBackend.new
    backend.init(width, height)
    backend.resize(width, height)
    backend.set_clear_color(1.0_f32, 1.0_f32, 1.0_f32, 1.0_f32)

    size_px = 24
    move_y = 240.0_f32
    move_x0 = 20.0_f32
    move_x1 = no_move ? move_x0 : 22.0_f32 # moved right by 2px unless --no-move
    placement_sink = [] of Tessell::Text::GlyphPlacement

    # Warmup & atlas sync
    render_full(backend, renderer, placement_sink, move_x0, move_y, size_px, width, height)
    backend.sync_atlas(atlas)
    render_full(backend, renderer, placement_sink, move_x0, move_y, size_px, width, height)
    backend.sync_atlas(atlas)

    # Compute dirty rect covering old and new MOVE position
    move_text = "MOVE"
    move_w = measurer.measure(move_text, 1, size_px.to_f32, 10000.0_f32).width
    # conservative bounds (ascent/descent margin) in y-down coords
    pad = 4.0_f32
    old_rect = Tessell::Rect.new(move_x0 - 1.0_f32, move_y - size_px.to_f32 - pad, move_w + 6.0_f32, size_px.to_f32 + pad * 3.0_f32)
    new_rect = Tessell::Rect.new(move_x1 - 1.0_f32, move_y - size_px.to_f32 - pad, move_w + 6.0_f32, size_px.to_f32 + pad * 3.0_f32)
    dirty_union = old_rect.union(new_rect)
    dirty_src = [dirty_union]
    dirty_rects = [] of Tessell::Rect
    dirty_rects << dirty_union # capacity/prefill
    Tessell::Render::Dirty.merge_into(dirty_src, dirty_rects, 8)
    dirty_area_ratio = Tessell::Render::Dirty.area(dirty_rects) / (width.to_f64 * height.to_f64)

    # Phase A: full-frame baseline with MOVE at old position (back buffer, no swap)
    render_full(backend, renderer, placement_sink, move_x0, move_y, size_px, width, height)
    pixels_a = capture_pixels(width, height)

    # Phase B: only submit dirty regions on top of A (back buffer intact, no swap)
    sub_dirty, culled_dirty = render_dirty(backend, renderer, placement_sink, move_x1, move_y, size_px, width, height, dirty_rects)
    pixels_b = capture_pixels(width, height)

    # Phase C: full-frame redraw of same final state (independent full render)
    sub_full_c = render_full(backend, renderer, placement_sink, move_x1, move_y, size_px, width, height)
    pixels_c = capture_pixels(width, height)

    # Present C once for visual sanity (not part of equivalence comparison)
    M3Gdi32.SwapBuffers(hdc)

    diff_pixels = pixel_diff(pixels_b, pixels_c)   # B (dirty partial) vs C (full redraw, final state)
    diff_a_vs_c = pixel_diff(pixels_a, pixels_c)   # A (baseline/moved-before) vs C (final) — must be >0 when element moved


    # Timing over frames_target: full vs dirty of final state
    full_times = [] of Int64
    dirty_times = [] of Int64
    submitted_quads_full = sub_full_c
    submitted_quads_dirty = sub_dirty
    culled_quads = culled_dirty

    fi = 0
    while fi < frames_target && !M3ProbeState.quit_requested
      msg = M3User32::MSG.new
      while M3User32.PeekMessageW(pointerof(msg), Pointer(Void).null, 0_u32, 0_u32, PM_REMOVE) != 0
        if msg.message == WM_QUIT
          M3ProbeState.quit_requested = true
          break
        end
        M3User32.TranslateMessage(pointerof(msg))
        M3User32.DispatchMessageW(pointerof(msg))
      end
      break if M3ProbeState.quit_requested

      t0 = m3_now_us
      submitted_quads_full = render_full(backend, renderer, placement_sink, move_x1, move_y, size_px, width, height)
      M3Gdi32.SwapBuffers(hdc)
      t1 = m3_now_us
      full_times << (t1 - t0)

      t2 = m3_now_us
      submitted_quads_dirty, culled_quads = render_dirty(backend, renderer, placement_sink, move_x1, move_y, size_px, width, height, dirty_rects)
      M3Gdi32.SwapBuffers(hdc)
      t3 = m3_now_us
      dirty_times << (t3 - t2)
      fi += 1
    end

    # If diff found, locate first differing pixel
    diff_loc = "none"
    if diff_pixels > 0
      i = 0
      found = false
      while i < pixels_b.size && !found
        if pixels_b[i] != pixels_c[i] || pixels_b[i+1] != pixels_c[i+1] || pixels_b[i+2] != pixels_c[i+2] || pixels_b[i+3] != pixels_c[i+3]
          px = (i // 4) % width
          py = (i // 4) // width
          diff_loc = "x=#{px} y=#{py} b=#{pixels_b[i]},#{pixels_b[i+1]},#{pixels_b[i+2]},#{pixels_b[i+3]} c=#{pixels_c[i]},#{pixels_c[i+1]},#{pixels_c[i+2]},#{pixels_c[i+3]}"
          found = true
        end
        i += 4
      end
    end

    full_sorted = full_times.sort
    dirty_sorted = dirty_times.sort
    f_p50 = m3_percentile(full_sorted, 0.50)
    f_p95 = m3_percentile(full_sorted, 0.95)
    f_p99 = m3_percentile(full_sorted, 0.99)
    d_p50 = m3_percentile(dirty_sorted, 0.50)
    d_p95 = m3_percentile(dirty_sorted, 0.95)
    d_p99 = m3_percentile(dirty_sorted, 0.99)

    pass_verify = diff_pixels == 0 && diff_a_vs_c > 0 && submitted_quads_dirty < submitted_quads_full && dirty_area_ratio < 0.35

    line = String.build do |s|
      s << "diff_pixels=" << diff_pixels
      s << " diff_A_vs_C=" << diff_a_vs_c
      s << " dirty_area_ratio=" << sprintf("%.6f", dirty_area_ratio)
      s << " submitted_quads_dirty=" << submitted_quads_dirty
      s << " submitted_quads_full=" << submitted_quads_full
      s << " culled_quads=" << culled_quads
      s << " frame_full_p50_us=" << f_p50
      s << " frame_full_p95_us=" << f_p95
      s << " frame_full_p99_us=" << f_p99
      s << " frame_dirty_p50_us=" << d_p50
      s << " frame_dirty_p95_us=" << d_p95
      s << " frame_dirty_p99_us=" << d_p99
      s << " dirty_rects=" << dirty_rects.size
      s << " frames=" << frames_target
      s << " no_move=" << no_move
      s << " diff_loc=" << diff_loc
      s << " verify=" << (pass_verify ? "pass" : "fail")
    end

    measurer.close
    backend.close
    M3WGL.wglMakeCurrent(Pointer(Void).null, Pointer(Void).null)
    M3WGL.wglDeleteContext(hglrc)
    M3User32.ReleaseDC(hwnd, hdc)
    M3User32.DestroyWindow(hwnd) unless M3ProbeState.quit_requested

    ok = (!verify) || pass_verify
    result_ch.send({ok, line})
  rescue ex
    result_ch.send({false, "error=exception message=#{ex.message.inspect} backtrace=#{ex.backtrace.first(3).join(" | ").inspect}"})
  end
end

ok, line = result_ch.receive
puts line
exit(ok ? 0 : 1)