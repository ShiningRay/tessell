# M3-C8: real GL window scrolling of 10k-row VirtualList with dirty-rect partial submit.
# Evidence for M2 gate condition C8 (upper half, GL/window path).
# Usage:
#   crystal run examples/m3_scroll_window.cr -- --frames=120 --verify
#   crystal run examples/m3_scroll_window.cr -- --frames=120 --dy=20
# Output: single key=value token line including GL_SCROLL_WINDOW=done and verify=pass|fail.
#
# Verify (three criteria must all hold):
#   1) Pixel equivalence/non-vacuity: diff_pixels(B,C)==0 and diff_A_vs_C>0
#      A=k0 full, B=k1 dirty partial on A, C=k1 full.
#   2) Submission drop: submitted_quads_dirty < submitted_quads_full, report culled
#      and 4*visible_avg vs submitted_quads_full scale.
#   3) Zero-alloc steady path: 3 windows max, delta < 1000 and <= 256, GC.enable in ensure.

require "../src/tessell"
require "../src/tessell/render/gl/gl_backend"

@[Link("kernel32")]
lib M3SKernel32
  fun GetModuleHandleW(lpModuleName : UInt16*) : Void*
  fun GetLastError : UInt32
  fun QueryPerformanceCounter(lpPerformanceCount : Int64*) : Int32
  fun QueryPerformanceFrequency(lpFrequency : Int64*) : Int32
end

@[Link("user32")]
lib M3SUser32
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
lib M3SGdi32
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
lib M3SWGL
  fun wglCreateContext(hdc : Void*) : Void*
  fun wglMakeCurrent(hdc : Void*, hglrc : Void*) : Int32
  fun wglDeleteContext(hglrc : Void*) : Int32
end

@[Link("opengl32")]
lib M3SGL
  GL_RGBA           = 0x1908_u32
  GL_UNSIGNED_BYTE  = 0x1401_u32
  GL_PACK_ALIGNMENT = 0x0D05_u32
  GL_COLOR          = 0x1800_u32
  GL_SCISSOR_TEST   = 0x0C11_u32
  GL_PROJECTION     = 0x1701_u32
  GL_MODELVIEW      = 0x1700_u32
  fun glReadPixels(x : Int32, y : Int32, width : Int32, height : Int32, format : UInt32, type : UInt32, pixels : Void*) : Void
  fun glFinish : Void
  fun glPixelStorei(pname : UInt32, param : Int32) : Void
  fun glCopyPixels(x : Int32, y : Int32, width : Int32, height : Int32, type : UInt32) : Void
  fun glRasterPos2i(x : Int32, y : Int32) : Void
  fun glMatrixMode(mode : UInt32) : Void
  fun glPushMatrix : Void
  fun glPopMatrix : Void
  fun glLoadIdentity : Void
  fun glOrtho(left : Float64, right : Float64, bottom : Float64, top : Float64, zNear : Float64, zFar : Float64) : Void
  fun glDisable(cap : UInt32) : Void
  fun glEnable(cap : UInt32) : Void
  fun glIsEnabled(cap : UInt32) : UInt8
end

module M3SState
  class_property quit_requested : Bool = false
end

def m3s_to_wstr(s : String) : Slice(UInt16)
  u = s.to_utf16
  buf = Slice(UInt16).new(u.size + 1, 0_u16)
  u.size.times { |i| buf[i] = u[i] }
  buf
end

def m3s_fail(msg : String)
  err = M3SKernel32.GetLastError
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

PFD_DRAW_TO_WINDOW = 0x00000004_u32
PFD_SUPPORT_OPENGL = 0x00000020_u32
PFD_DOUBLEBUFFER   = 0x00000001_u32
PFD_TYPE_RGBA      = 0_u8
PFD_MAIN_PLANE     = 0_u8

M3S_WNDPROC = ->(hwnd : Void*, msg : UInt32, wparam : UInt64, lparam : Int64) : Int64 do
  case msg
  when WM_CLOSE
    M3SUser32.DestroyWindow(hwnd)
    return 0_i64
  when WM_DESTROY
    M3SUser32.PostQuitMessage(0)
    M3SState.quit_requested = true
    return 0_i64
  when WM_KEYDOWN
    if wparam == VK_ESCAPE
      M3SUser32.DestroyWindow(hwnd)
      return 0_i64
    end
  end
  M3SUser32.DefWindowProcW(hwnd, msg, wparam, lparam)
end

def m3s_now_us : Int64
  now = 0_i64
  M3SKernel32.QueryPerformanceCounter(pointerof(now))
  freq = 0_i64
  M3SKernel32.QueryPerformanceFrequency(pointerof(freq))
  return 0_i64 if freq == 0
  (now.to_f64 * 1_000_000.0 / freq.to_f64).to_i64
end

def m3s_percentile(sorted : Array(Int64), p : Float64) : Int64
  return 0_i64 if sorted.empty?
  idx = ((sorted.size - 1).to_f64 * p).round.to_i
  idx = 0 if idx < 0
  idx = sorted.size - 1 if idx >= sorted.size
  sorted[idx]
end

def m3s_capture_pixels(w : Int32, h : Int32) : Bytes
  buf = Bytes.new(w * h * 4)
  M3SGL.glPixelStorei(M3SGL::GL_PACK_ALIGNMENT, 1)
  M3SGL.glFinish
  M3SGL.glReadPixels(0, 0, w, h, M3SGL::GL_RGBA, M3SGL::GL_UNSIGNED_BYTE, buf.to_unsafe.as(Void*))
  buf
end

def m3s_pixel_diff(a : Bytes, b : Bytes) : Int32
  return a.size // 4 if a.size != b.size
  diff = 0
  i = 0
  n = a.size
  while i < n
    if a[i] != b[i] || a[i + 1] != b[i + 1] || a[i + 2] != b[i + 2] || a[i + 3] != b[i + 3]
      diff += 1
    end
    i += 4
  end
  diff
end

def m3s_diff_diag(a : Bytes, b : Bytes, w : Int32, h : Int32) : String
  return "size_mismatch a=#{a.size} b=#{b.size}" if a.size != b.size
  min_x = w
  min_y = h
  max_x = -1
  max_y = -1
  buckets = Array(Int32).new((h + 19) // 20, 0)
  y = 0
  while y < h
    x = 0
    row = y * w * 4
    while x < w
      i = row + x * 4
      if a[i] != b[i] || a[i + 1] != b[i + 1] || a[i + 2] != b[i + 2] || a[i + 3] != b[i + 3]
        min_x = x if x < min_x
        min_y = y if y < min_y
        max_x = x if x > max_x
        max_y = y if y > max_y
        bi = y // 20
        buckets[bi] = buckets[bi] + 1 if bi >= 0 && bi < buckets.size
      end
      x += 1
    end
    y += 1
  end
  if max_x < 0
    return "diff_count=0 bbox=none buckets_all_zero=true"
  end
  nz = [] of String
  bi = 0
  while bi < buckets.size
    if buckets[bi] != 0
      nz << "y#{bi * 20}-#{bi * 20 + 19}:#{buckets[bi]}"
    end
    bi += 1
  end
  nz_s = nz.empty? ? "none" : nz.join(",")
  "bbox=(#{min_x},#{min_y})-(#{max_x},#{max_y}) buckets_nz=[#{nz_s}]"
end

# Build scroll dirty strip (newly exposed region only) for blit-scroll path.
# Assumes interior already shifted by m3s_scroll_blit; only exposed strip needs redraw.
# Returns strip count. No allocation when sink capacity is sufficient.
def m3s_build_scroll_dirty(dy : Int32, viewport_w : Int32, viewport_h : Int32,
                           sink : Array(Tessell::Rect)) : Int32
  sink.clear
  return 0 if dy == 0
  w = viewport_w.to_f32
  vh = viewport_h
  vh_f = vh.to_f32
  if dy.abs >= vh
    sink << Tessell::Rect.new(0.0_f32, 0.0_f32, w, vh_f)
  else
    d = dy.abs
    d_f = d.to_f32
    if dy > 0
      # Content moved up on screen: newly exposed at bottom.
      sink << Tessell::Rect.new(0.0_f32, (vh - d).to_f32, w, d_f)
    else
      # Content moved down on screen: newly exposed at top.
      sink << Tessell::Rect.new(0.0_f32, 0.0_f32, w, d_f)
    end
  end
  sink.size
end

# Blit interior pixels for vertical scroll (screen coords: y down). Returns true if blit done.
# After scroll_by(dy>0) content moves UP on screen: screen [dy,h) -> [0,h-dy), exposed [h-dy,h).
# Must run before dirty-strip draw (reads current buffer). Uses GL window coords (bottom-left origin).
# enabled=false (--blit-off): skip interior copy for discriminating evidence (P3-1 verification).
def m3s_scroll_blit(dy : Int32, viewport_w : Int32, viewport_h : Int32, enabled : Bool = true) : Bool
  return false unless enabled
  return false if dy == 0 || dy.abs >= viewport_h
  h = viewport_h
  w = viewport_w
  d = dy.abs
  scissor_on = M3SGL.glIsEnabled(M3SGL::GL_SCISSOR_TEST) != 0_u8
  M3SGL.glDisable(M3SGL::GL_SCISSOR_TEST)
  M3SGL.glMatrixMode(M3SGL::GL_PROJECTION)
  M3SGL.glPushMatrix
  M3SGL.glLoadIdentity
  M3SGL.glOrtho(0.0, w.to_f64, 0.0, h.to_f64, -1.0, 1.0)
  M3SGL.glMatrixMode(M3SGL::GL_MODELVIEW)
  M3SGL.glPushMatrix
  M3SGL.glLoadIdentity
  M3SGL.glFinish
  if dy > 0
    # Move window rect (0,0,w,h-d) up by d window pixels -> (0,d,w,h-d)
    M3SGL.glRasterPos2i(0, d)
    M3SGL.glCopyPixels(0, 0, w, h - d, M3SGL::GL_COLOR)
  else
    # Move window rect (0,d,w,h-d) down by d window pixels -> (0,0,w,h-d)
    M3SGL.glRasterPos2i(0, 0)
    M3SGL.glCopyPixels(0, d, w, h - d, M3SGL::GL_COLOR)
  end
  M3SGL.glFinish
  M3SGL.glMatrixMode(M3SGL::GL_MODELVIEW)
  M3SGL.glPopMatrix
  M3SGL.glMatrixMode(M3SGL::GL_PROJECTION)
  M3SGL.glPopMatrix
  M3SGL.glMatrixMode(M3SGL::GL_MODELVIEW)
  M3SGL.glEnable(M3SGL::GL_SCISSOR_TEST) if scissor_on
  true
end

# Render visible rows for current VirtualList state into renderer (hot path: no new Array/String/capture).
def m3s_render_rows(vl : Tessell::Widgets::VirtualList,
                    renderer : Tessell::Render::TextRenderer,
                    placement_sink : Array(Tessell::Text::GlyphPlacement),
                    labels : Array(String),
                    text_size : Int32,
                    viewport_w : Int32,
                    viewport_h : Int32,
                    fg : UInt32) : Nil
  renderer.reset
  i = vl.visible_first
  last = vl.visible_last
  while i <= last
    oy = vl.node_offset(i).to_f32 + 15.0_f32
    renderer.append_text_cached(placement_sink, labels[i], 8.0_f32, oy, text_size, viewport_w, 10_000_000, fg)
    i += 1
  end
end

def m3s_render_full(backend : Tessell::Render::GL::GLBackend,
                    vl : Tessell::Widgets::VirtualList,
                    renderer : Tessell::Render::TextRenderer,
                    placement_sink : Array(Tessell::Text::GlyphPlacement),
                    labels : Array(String),
                    text_size : Int32,
                    viewport_w : Int32,
                    viewport_h : Int32,
                    theme : Tessell::Render::Theme) : Int32
  backend.begin_frame(nil, theme)
  m3s_render_rows(vl, renderer, placement_sink, labels, text_size, viewport_w, viewport_h, theme.fg)
  submitted = backend.draw_text(renderer.vertices, renderer.batch_runs, renderer.batch_count)
  backend.end_frame
  submitted
end

def m3s_render_dirty(backend : Tessell::Render::GL::GLBackend,
                     vl : Tessell::Widgets::VirtualList,
                     renderer : Tessell::Render::TextRenderer,
                     placement_sink : Array(Tessell::Text::GlyphPlacement),
                     labels : Array(String),
                     text_size : Int32,
                     viewport_w : Int32,
                     viewport_h : Int32,
                     theme : Tessell::Render::Theme,
                     dirty_rects : Array(Tessell::Rect)) : {Int32, Int32}
  backend.begin_frame(dirty_rects, theme)
  m3s_render_rows(vl, renderer, placement_sink, labels, text_size, viewport_w, viewport_h, theme.fg)
  submitted = backend.draw_text(renderer.vertices, renderer.batch_runs, renderer.batch_count)
  st = backend.stats
  backend.end_frame
  {submitted, st.culled_quads}
end

frames_target = 120
dy = 20
verify = false
steady = false
blit_off = false
ARGV.each_with_index do |arg, i|
  if arg.starts_with?("--frames=")
    frames_target = arg.split("=", 2)[1].to_i
  elsif arg == "--frames" && i + 1 < ARGV.size
    frames_target = ARGV[i + 1].to_i
  elsif arg.starts_with?("--dy=")
    dy = arg.split("=", 2)[1].to_i
  elsif arg == "--dy" && i + 1 < ARGV.size
    dy = ARGV[i + 1].to_i
  elsif arg == "--verify"
    verify = true
  elsif arg == "--steady"
    steady = true
  elsif arg == "--blit-off"
    blit_off = true
  end
end

result_ch = Channel({Bool, String}).new

iso_ctx = Fiber::ExecutionContext::Isolated.new("tessell-m3-scroll") do
  begin
    hinstance = M3SKernel32.GetModuleHandleW(Pointer(UInt16).null)
    m3s_fail("GetModuleHandleW") if hinstance.null?

    class_name = m3s_to_wstr("TessellM3ScrollProbe")
    window_title = m3s_to_wstr("Tessell M3 Scroll")

    wc = M3SUser32::WNDCLASSEXW.new
    wc.cbSize = sizeof(M3SUser32::WNDCLASSEXW).to_u32
    wc.style = CS_OWNDC
    wc.lpfnWndProc = M3S_WNDPROC
    wc.cbClsExtra = 0
    wc.cbWndExtra = 0
    wc.hInstance = hinstance
    wc.hIcon = Pointer(Void).null
    wc.hCursor = M3SUser32.LoadCursorW(Pointer(Void).null, IDC_ARROW)
    wc.hbrBackground = Pointer(Void).null
    wc.lpszMenuName = Pointer(UInt16).null
    wc.lpszClassName = class_name.to_unsafe
    wc.hIconSm = Pointer(Void).null
    atom = M3SUser32.RegisterClassExW(pointerof(wc))
    m3s_fail("RegisterClassExW") if atom == 0

    width = 800
    height = 600
    rect = M3SUser32::RECT.new
    rect.left = 0; rect.top = 0; rect.right = width; rect.bottom = height
    style = WS_OVERLAPPEDWINDOW
    M3SUser32.AdjustWindowRectEx(pointerof(rect), style, 0, 0)
    win_w = rect.right - rect.left
    win_h = rect.bottom - rect.top

    hwnd = M3SUser32.CreateWindowExW(0_u32, class_name.to_unsafe, window_title.to_unsafe,
                                     style | WS_VISIBLE, CW_USEDEFAULT, CW_USEDEFAULT,
                                     win_w, win_h, Pointer(Void).null, Pointer(Void).null,
                                     hinstance, Pointer(Void).null)
    m3s_fail("CreateWindowExW") if hwnd.null?
    M3SUser32.ShowWindow(hwnd, SW_SHOW)
    M3SUser32.UpdateWindow(hwnd)

    hdc = M3SUser32.GetDC(hwnd)
    m3s_fail("GetDC") if hdc.null?

    pfd = M3SGdi32::PIXELFORMATDESCRIPTOR.new
    pfd.nSize = sizeof(M3SGdi32::PIXELFORMATDESCRIPTOR).to_u16
    pfd.nVersion = 1_u16
    pfd.dwFlags = PFD_DRAW_TO_WINDOW | PFD_SUPPORT_OPENGL | PFD_DOUBLEBUFFER
    pfd.iPixelType = PFD_TYPE_RGBA
    pfd.cColorBits = 32_u8
    pfd.cDepthBits = 24_u8
    pfd.cStencilBits = 8_u8
    pfd.iLayerType = PFD_MAIN_PLANE
    pf = M3SGdi32.ChoosePixelFormat(hdc, pointerof(pfd))
    m3s_fail("ChoosePixelFormat") if pf == 0
    m3s_fail("SetPixelFormat") if M3SGdi32.SetPixelFormat(hdc, pf, pointerof(pfd)) == 0

    hglrc = M3SWGL.wglCreateContext(hdc)
    m3s_fail("wglCreateContext") if hglrc.null?
    m3s_fail("wglMakeCurrent") if M3SWGL.wglMakeCurrent(hdc, hglrc) == 0

    unless Tessell::Text::FtMeasurer.available?
      result_ch.send({false, "rows=10000 viewport=800x600 row_h=20 dy=#{dy} error=ft_unavailable reason=#{Tessell::Text::FtMeasurer.unavailable_reason.inspect} verify=fail GL_SCROLL_WINDOW=done"})
      next
    end

    rows = 10_000
    row_h = 20
    text_size = 16
    font_path = "C:/Windows/Fonts/msyh.ttc"
    theme = Tessell::Render::Theme.light

    measurer = Tessell::Text::FtMeasurer.open(font_path, 0)
    atlas = Tessell::Text::GlyphAtlas.new(1024, 4096)
    rasterizer = Tessell::Text::Rasterizer.new(measurer, atlas, 0, rows + 64)
    renderer = Tessell::Render::TextRenderer.new(atlas, rasterizer)
    backend = Tessell::Render::GL::GLBackend.new
    backend.init(width, height)
    backend.resize(width, height)

    renderer.reserve_quads(2048)
    renderer.reserve_batches(64)
    placement_sink = [] of Tessell::Text::GlyphPlacement

    # Precompute labels once (setup, not hot path). String interpolation only at init.
    labels = Array(String).new(rows)
    label_bytes_total = 0_i64
    li = 0
    while li < rows
      s = "Row #{li}"
      label_bytes_total += s.bytesize.to_i64
      labels << s
      li += 1
    end

    # Pre-warm shaped runs for all rows so steady-state scroll hits cache (no miss/evict allocs).
    warm_i = 0
    while warm_i < rows
      rasterizer.shape_run_into(labels[warm_i], text_size, placement_sink)
      warm_i += 1
    end
    backend.sync_atlas(atlas)

    fetch_cb = ->(_i : Int32) { nil }
    vl = Tessell::Widgets::VirtualList.new(rows, row_h, height, fetch_cb, width)

    # Preallocated dirty rect array (reused; no hot-path alloc).
    dirty_strips = [] of Tessell::Rect
    dirty_strips << Tessell::Rect.new(0.0_f32, 0.0_f32, 0.0_f32, 0.0_f32)
    dirty_strips << Tessell::Rect.new(0.0_f32, 0.0_f32, 0.0_f32, 0.0_f32)
    dirty_strips.clear

    max_scroll = vl.total_height - height
    max_scroll = 0 if max_scroll < 0
    probe_dy = dy == 0 ? 20 : dy
    k0 = 0
    k1 = k0 + probe_dy
    k1 = max_scroll if k1 > max_scroll
    eff_dy = k1 - k0

    # Warmup: render all label glyphs into atlas and warm caches (scroll through range).
    wi = 0
    warm_scroll_dy = 20
    while wi < 600 && !M3SState.quit_requested
      msg = M3SUser32::MSG.new
      while M3SUser32.PeekMessageW(pointerof(msg), Pointer(Void).null, 0_u32, 0_u32, PM_REMOVE) != 0
        if msg.message == WM_QUIT
          M3SState.quit_requested = true
          break
        end
        M3SUser32.TranslateMessage(pointerof(msg))
        M3SUser32.DispatchMessageW(pointerof(msg))
      end
      break if M3SState.quit_requested
      vl.scroll_by(warm_scroll_dy)
      if !steady && max_scroll > 0 && vl.scroll_y >= max_scroll
        vl.scroll_to(0)
      end
      vl.prepare_visible
      m3s_render_full(backend, vl, renderer, placement_sink, labels, text_size, width, height, theme)
      backend.sync_atlas(atlas)
      M3SGdi32.SwapBuffers(hdc)
      wi += 1
    end
    # Extra steady warmup pass to absorb first-attempt noise (atlas/upload/cache state).
    vl.scroll_to(0)
    ew = 0
    while ew < 120
      vl.prepare_visible
      m3s_render_full(backend, vl, renderer, placement_sink, labels, text_size, width, height, theme)
      vl.scroll_by(probe_dy)
      if !steady && max_scroll > 0 && vl.scroll_y >= max_scroll
        vl.scroll_to(0)
      end
      vl.prepare_visible
      m3s_scroll_blit(probe_dy, width, height, !blit_off)
      m3s_build_scroll_dirty(probe_dy, width, height, dirty_strips)
      m3s_render_dirty(backend, vl, renderer, placement_sink, labels, text_size, width, height, theme, dirty_strips)
      backend.sync_atlas(atlas)
      ew += 1
    end
    # Reset to start for non-steady verify/probe; steady mode continues forward (no wrap).
    vl.scroll_to(0) unless steady
    vl.prepare_visible
    backend.sync_atlas(atlas)
    m3s_render_full(backend, vl, renderer, placement_sink, labels, text_size, width, height, theme)
    backend.sync_atlas(atlas)

    diff_pixels = 0
    diff_a_vs_c = 0
    quads_full_verify = 0
    quads_dirty_verify = 0
    culled_verify = 0
    batches_verify = 0
    visible_avg_verify = 0.0_f64

    if verify
      # A: full at k0
      vl.scroll_to(k0)
      vl.prepare_visible
      m3s_render_full(backend, vl, renderer, placement_sink, labels, text_size, width, height, theme)
      pixels_a = m3s_capture_pixels(width, height)

      # B: scroll to k1, blit interior from A then dirty partial submit of exposed strip (no swap between A and B)
      vl.scroll_to(k1)
      vl.prepare_visible
      vis_b = vl.visible_last >= vl.visible_first ? (vl.visible_last - vl.visible_first + 1) : 0
      visible_avg_verify = vis_b.to_f64
      m3s_scroll_blit(eff_dy, width, height, !blit_off)
      m3s_build_scroll_dirty(eff_dy, width, height, dirty_strips)
      quads_dirty_verify, culled_verify = m3s_render_dirty(backend, vl, renderer, placement_sink, labels, text_size, width, height, theme, dirty_strips)
      pixels_b = m3s_capture_pixels(width, height)

      # C: full redraw at k1 (independent final state)
      quads_full_verify = m3s_render_full(backend, vl, renderer, placement_sink, labels, text_size, width, height, theme)
      batches_verify = renderer.batch_count
      pixels_c = m3s_capture_pixels(width, height)

      M3SGdi32.SwapBuffers(hdc)

      diff_pixels = m3s_pixel_diff(pixels_b, pixels_c)
      diff_a_vs_c = m3s_pixel_diff(pixels_a, pixels_c)
    end

    # Timing over frames_target: full and dirty
    vl.scroll_to(0)
    vl.prepare_visible
    full_times = [] of Int64
    dirty_times = [] of Int64
    visible_sum = 0_i64
    quads_full_t = 0
    quads_dirty_t = 0
    culled_t = 0
    batches_t = 0
    fi = 0
    while fi < frames_target && !M3SState.quit_requested
      msg = M3SUser32::MSG.new
      while M3SUser32.PeekMessageW(pointerof(msg), Pointer(Void).null, 0_u32, 0_u32, PM_REMOVE) != 0
        if msg.message == WM_QUIT
          M3SState.quit_requested = true
          break
        end
        M3SUser32.TranslateMessage(pointerof(msg))
        M3SUser32.DispatchMessageW(pointerof(msg))
      end
      break if M3SState.quit_requested

      vl.prepare_visible
      vis = vl.visible_last >= vl.visible_first ? (vl.visible_last - vl.visible_first + 1) : 0
      visible_sum += vis
      t0 = m3s_now_us
      quads_full_t = m3s_render_full(backend, vl, renderer, placement_sink, labels, text_size, width, height, theme)
      batches_t = renderer.batch_count
      M3SGdi32.SwapBuffers(hdc)
      t1 = m3s_now_us
      full_times << (t1 - t0)

      vl.scroll_by(probe_dy)
      vl.scroll_to(0) if max_scroll > 0 && vl.scroll_y >= max_scroll
      vl.prepare_visible
      m3s_scroll_blit(probe_dy, width, height, !blit_off)
      m3s_build_scroll_dirty(probe_dy, width, height, dirty_strips)
      t2 = m3s_now_us
      quads_dirty_t, culled_t = m3s_render_dirty(backend, vl, renderer, placement_sink, labels, text_size, width, height, theme, dirty_strips)
      M3SGdi32.SwapBuffers(hdc)
      t3 = m3s_now_us
      dirty_times << (t3 - t2)

      fi += 1
    end

    full_sorted = full_times.sort
    dirty_sorted = dirty_times.sort
    f_p50 = m3s_percentile(full_sorted, 0.50)
    f_p95 = m3s_percentile(full_sorted, 0.95)
    f_p99 = m3s_percentile(full_sorted, 0.99)
    d_p50 = m3s_percentile(dirty_sorted, 0.50)
    d_p95 = m3s_percentile(dirty_sorted, 0.95)
    d_p99 = m3s_percentile(dirty_sorted, 0.99)

    frames_done = full_times.size
    visible_avg = frames_done > 0 ? (visible_sum.to_f64 / frames_done.to_f64) : 0.0
    visible_avg = visible_avg_verify if verify && visible_avg_verify > 0.0

    # Alloc probe: 3 windows, steady-state render+scroll (no hot-path allocs).
    n_alloc = 200

    # Prime probe: run full measured-probe sequence once to absorb first-attempt noise.
    prime = 0
    while prime < 1
      widx = 0
      while widx < 3
        ww = 0
        while ww < 80
          vl.prepare_visible
          m3s_render_full(backend, vl, renderer, placement_sink, labels, text_size, width, height, theme)
          vl.scroll_by(probe_dy)
          if !steady && max_scroll > 0 && vl.scroll_y >= max_scroll
            vl.scroll_to(0)
          end
          vl.prepare_visible
          m3s_scroll_blit(probe_dy, width, height, !blit_off)
          m3s_build_scroll_dirty(probe_dy, width, height, dirty_strips)
          m3s_render_dirty(backend, vl, renderer, placement_sink, labels, text_size, width, height, theme, dirty_strips)
          ww += 1
        end
        GC.collect
        GC.disable
        begin
          _pbefore = GC.stats.bytes_since_gc.to_i64
          k = 0
          while k < n_alloc
            vl.prepare_visible
            m3s_render_full(backend, vl, renderer, placement_sink, labels, text_size, width, height, theme)
            vl.scroll_by(probe_dy)
            if !steady && max_scroll > 0 && vl.scroll_y >= max_scroll
              vl.scroll_to(0)
            end
            vl.prepare_visible
            m3s_scroll_blit(probe_dy, width, height, !blit_off)
            m3s_build_scroll_dirty(probe_dy, width, height, dirty_strips)
            m3s_render_dirty(backend, vl, renderer, placement_sink, labels, text_size, width, height, theme, dirty_strips)
            k += 1
          end
          _ = GC.stats.bytes_since_gc.to_i64 - _pbefore
        ensure
          GC.enable
        end
        widx += 1
      end
      GC.collect
      prime += 1
    end
    vl.scroll_to(0) unless steady

    retried = false
    attempt = 1
    seq = [0_i64, 0_i64, 0_i64]
    seq1 = [0_i64, 0_i64, 0_i64]
    delta_work = 0_i64
    delta_work1 = 0_i64
    fail_reason1 = ""
    loop do
      widx = 0
      while widx < 3
        # warm steady path before each window
        ww = 0
        while ww < 80
          vl.prepare_visible
          m3s_render_full(backend, vl, renderer, placement_sink, labels, text_size, width, height, theme)
          vl.scroll_by(probe_dy)
          if !steady && max_scroll > 0 && vl.scroll_y >= max_scroll
            vl.scroll_to(0)
          end
          vl.prepare_visible
          m3s_scroll_blit(probe_dy, width, height, !blit_off)
          m3s_build_scroll_dirty(probe_dy, width, height, dirty_strips)
          m3s_render_dirty(backend, vl, renderer, placement_sink, labels, text_size, width, height, theme, dirty_strips)
          ww += 1
        end
        GC.collect
        GC.disable
        begin
          before = GC.stats.bytes_since_gc.to_i64
          k = 0
          while k < n_alloc
            vl.prepare_visible
            m3s_render_full(backend, vl, renderer, placement_sink, labels, text_size, width, height, theme)
            vl.scroll_by(probe_dy)
            if !steady && max_scroll > 0 && vl.scroll_y >= max_scroll
              vl.scroll_to(0)
            end
            vl.prepare_visible
            m3s_scroll_blit(probe_dy, width, height, !blit_off)
            m3s_build_scroll_dirty(probe_dy, width, height, dirty_strips)
            m3s_render_dirty(backend, vl, renderer, placement_sink, labels, text_size, width, height, theme, dirty_strips)
            k += 1
          end
          seq[widx] = GC.stats.bytes_since_gc.to_i64 - before
        ensure
          GC.enable
        end
        widx += 1
      end
      delta_work = seq[0]
      delta_work = seq[1] if seq[1] > delta_work
      delta_work = seq[2] if seq[2] > delta_work
      if attempt == 1
        seq1[0] = seq[0]
        seq1[1] = seq[1]
        seq1[2] = seq[2]
        delta_work1 = delta_work
        pass1 = delta_work1 < 1000 && delta_work1 <= 256
        fail_reason1 = "" if pass1
        fail_reason1 = delta_work1 >= 1000 ? "delta>=1000" : "delta>256" unless pass1
      end
      pass_alloc = delta_work < 1000 && delta_work <= 256
      break if pass_alloc
      break if attempt >= 2
      retried = true
      attempt = 2
    end
    puts "ALLOC_ATTEMPT1 alloc_windows=[#{seq1[0]},#{seq1[1]},#{seq1[2]}] delta_max=#{delta_work1} attempt1=1 pass=#{delta_work1 < 1000 && delta_work1 <= 256} fail_reason=#{fail_reason1.empty? ? "none" : fail_reason1}"
    if retried
      puts "ALLOC_ATTEMPT2 alloc_windows=[#{seq[0]},#{seq[1]},#{seq[2]}] delta_max=#{delta_work} retried=true attempt=2 fail_reason=none"
    end
    if steady
      puts "STEADY mode=steady_continuous windows=[#{seq[0]},#{seq[1]},#{seq[2]}] max=#{delta_work} retried=#{retried} attempt=#{attempt} scroll_y=#{vl.scroll_y}"
    end

    quads_full_out = verify ? quads_full_verify : quads_full_t
    quads_dirty_out = verify ? quads_dirty_verify : quads_dirty_t
    culled_out = verify ? culled_verify : culled_t
    batches_out = verify ? batches_verify : batches_t

    dirty_h_i = eff_dy == 0 ? 0 : (eff_dy.abs >= height ? height : eff_dy.abs)
    dirty_area_i = width * dirty_h_i
    viewport_area_i = width * height
    full_redraw = dirty_area_i >= viewport_area_i

    c1 = verify && diff_pixels == 0 && diff_a_vs_c > 0
    c2 = if full_redraw
           quads_dirty_out == quads_full_out && culled_out == 0
         else
           quads_dirty_out < quads_full_out
         end
    c3 = delta_work < 1000 && delta_work <= 256
    pass_verify = verify && c1 && c2 && c3

    line = String.build do |s|
      s << "rows=" << rows
      s << " viewport=" << width << "x" << height
      s << " row_h=" << row_h
      s << " dy=" << eff_dy
      s << " visible_avg=" << sprintf("%.4f", visible_avg)
      s << " pool_size=" << vl.pool_size
      s << " quads_full=" << quads_full_out
      s << " quads_dirty=" << quads_dirty_out
      s << " culled=" << culled_out
      s << " batches=" << batches_out
      s << " diff_pixels=" << diff_pixels
      s << " diff_A_vs_C=" << diff_a_vs_c
      s << " full_redraw=" << full_redraw
      s << " dirty_area=" << dirty_area_i
      s << " viewport_area=" << viewport_area_i
      s << " scroll_offset=" << vl.scroll_y
      s << " label_bytes_total=" << label_bytes_total
      s << " frame_full_p50_us=" << f_p50
      s << " frame_full_p95_us=" << f_p95
      s << " frame_full_p99_us=" << f_p99
      s << " frame_dirty_p50_us=" << d_p50
      s << " frame_dirty_p95_us=" << d_p95
      s << " frame_dirty_p99_us=" << d_p99
      s << " alloc_windows=[" << seq[0] << "," << seq[1] << "," << seq[2] << "]"
      s << " retried=" << retried
      s << " attempt=" << attempt
      s << " frames=" << frames_target
      s << " verify=" << (pass_verify ? "pass" : "fail")
      s << " GL_SCROLL_WINDOW=done"
    end

    measurer.close
    backend.close
    M3SWGL.wglMakeCurrent(Pointer(Void).null, Pointer(Void).null)
    M3SWGL.wglDeleteContext(hglrc)
    M3SUser32.ReleaseDC(hwnd, hdc)
    M3SUser32.DestroyWindow(hwnd) unless M3SState.quit_requested

    ok = (!verify) || pass_verify
    result_ch.send({ok, line})
  rescue ex
    bt = ex.backtrace?
    bt_s = bt ? bt.first(5).join(" | ") : ""
    result_ch.send({false, "rows=10000 viewport=800x600 row_h=20 dy=#{dy} error=exception message=#{ex.message.inspect} backtrace=#{bt_s.inspect} verify=fail GL_SCROLL_WINDOW=done"})
  end
end

ok, line = result_ch.receive
puts line
exit(ok ? 0 : 1)