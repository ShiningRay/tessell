# M3-WP5 DPI scaling + Theme tokens: J1-J5 evidence (task-101)
# Usage:
#   crystal run examples/m3_dpi_theme.cr -- --dpi=1.5 --theme=dark --frames=20
#   crystal run examples/m3_dpi_theme.cr -- --verify
#   crystal run examples/m3_dpi_theme.cr -- --verify --dpi-aware
# --verify: runs J1 sweep (dpi 1.0/1.5/2.0), J3/J4 per case, J5 dirty-vs-full at dpi=1.5 dark.
# Outputs token line(s): dpi_scale theme_bg theme_fg text_pixels_nonbg corner_pixel_rgba expected_bg text_advance pen_end_x quads batches alloc_bytes alloc_windows retried attempt verify
# J1: text_pixels_nonbg strictly monotonic 1.0<1.5<2.0 and r15 in [1.5,3.5], r20 in [2.5,5.0]
# J3: corner (0,0 top-left) RGBA byte-exact == theme.bg; on mismatch prints bg_pixel_delta= and fails
# J4: steady-state zero alloc A delta_work<1000, B <=256, 3 windows max, GC.enable in ensure
# J5: dpi=1.5 dark dirty submit vs full redraw byte-exact RGBA diff_pixels==0 and diff_A_vs_C>0
# --dpi-aware: calls SetProcessDpiAwarenessContext(PER_MONITOR_AWARE_V2) in example only (not in src/)

require "../src/tessell"
require "../src/tessell/render/gl/gl_backend"

@[Link("kernel32")]
lib M3DTKernel32
  fun GetModuleHandleW(lpModuleName : UInt16*) : Void*
  fun GetLastError : UInt32
  fun QueryPerformanceCounter(lpPerformanceCount : Int64*) : Int32
  fun QueryPerformanceFrequency(lpFrequency : Int64*) : Int32
end

@[Link("user32")]
lib M3DTUser32
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
  fun SetProcessDpiAwarenessContext(value : Void*) : Int32
end

@[Link("gdi32")]
lib M3DTGdi32
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
lib M3DTWGL
  fun wglCreateContext(hdc : Void*) : Void*
  fun wglMakeCurrent(hdc : Void*, hglrc : Void*) : Int32
  fun wglDeleteContext(hglrc : Void*) : Int32
end

@[Link("opengl32")]
lib M3DTGL
  GL_RGBA           = 0x1908_u32
  GL_UNSIGNED_BYTE  = 0x1401_u32
  GL_PACK_ALIGNMENT = 0x0D05_u32
  fun glReadPixels(x : Int32, y : Int32, width : Int32, height : Int32, format : UInt32, type : UInt32, pixels : Void*) : Void
  fun glFinish : Void
  fun glPixelStorei(pname : UInt32, param : Int32) : Void
end

module M3DTState
  class_property quit_requested : Bool = false
end

def dt_to_wstr(s : String) : Slice(UInt16)
  u = s.to_utf16
  buf = Slice(UInt16).new(u.size + 1, 0_u16)
  u.size.times { |i| buf[i] = u[i] }
  buf
end

def dt_fail(msg : String)
  err = M3DTKernel32.GetLastError
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

DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2 = Pointer(Void).new((-4).to_u64!)

DT_WNDPROC = ->(hwnd : Void*, msg : UInt32, wparam : UInt64, lparam : Int64) : Int64 do
  case msg
  when WM_CLOSE
    M3DTUser32.DestroyWindow(hwnd)
    return 0_i64
  when WM_DESTROY
    M3DTUser32.PostQuitMessage(0)
    M3DTState.quit_requested = true
    return 0_i64
  when WM_KEYDOWN
    if wparam == VK_ESCAPE
      M3DTUser32.DestroyWindow(hwnd)
      return 0_i64
    end
  end
  M3DTUser32.DefWindowProcW(hwnd, msg, wparam, lparam)
end

def dt_now_us : Int64
  now = 0_i64
  M3DTKernel32.QueryPerformanceCounter(pointerof(now))
  freq = 0_i64
  M3DTKernel32.QueryPerformanceFrequency(pointerof(freq))
  return 0_i64 if freq == 0
  (now.to_f64 * 1_000_000.0 / freq.to_f64).to_i64
end

def dt_percentile(sorted : Array(Int64), p : Float64) : Int64
  return 0_i64 if sorted.empty?
  idx = ((sorted.size - 1).to_f64 * p).round.to_i
  idx = 0 if idx < 0
  idx = sorted.size - 1 if idx >= sorted.size
  sorted[idx]
end

def capture_pixels(w : Int32, h : Int32) : Bytes
  buf = Bytes.new(w * h * 4)
  M3DTGL.glPixelStorei(M3DTGL::GL_PACK_ALIGNMENT, 1)
  M3DTGL.glFinish
  M3DTGL.glReadPixels(0, 0, w, h, M3DTGL::GL_RGBA, M3DTGL::GL_UNSIGNED_BYTE, buf.to_unsafe.as(Void*))
  buf
end

# Top-left corner in y-down screen space is GL window coord (0, h-1)
def capture_corner_topleft(w : Int32, h : Int32) : Bytes
  buf = Bytes.new(4)
  M3DTGL.glPixelStorei(M3DTGL::GL_PACK_ALIGNMENT, 1)
  M3DTGL.glFinish
  M3DTGL.glReadPixels(0, h - 1, 1, 1, M3DTGL::GL_RGBA, M3DTGL::GL_UNSIGNED_BYTE, buf.to_unsafe.as(Void*))
  buf
end

def pixel_diff(a : Bytes, b : Bytes) : Int32
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

def count_text_pixels_nonbg(buf : Bytes, bg_r : UInt8, bg_g : UInt8, bg_b : UInt8, bg_a : UInt8) : Int64
  count = 0_i64
  i = 0
  n = buf.size
  while i < n
    if buf[i] != bg_r || buf[i + 1] != bg_g || buf[i + 2] != bg_b || buf[i + 3] != bg_a
      count += 1
    end
    i += 4
  end
  count
end

def rgba_hex(r : UInt8, g : UInt8, b : UInt8, a : UInt8) : String
  v = (r.to_u32 << 24) | (g.to_u32 << 16) | (b.to_u32 << 8) | a.to_u32
  sprintf("0x%08x", v)
end

# Build base scene (>=3 text segments). Coordinates in device pixels (logical*scale).
def build_scene(renderer : Tessell::Render::TextRenderer,
                placement_sink : Array(Tessell::Text::GlyphPlacement),
                scale : Float32, size_px : Int32, theme_fg : UInt32,
                viewport_w : Int32, viewport_h : Int32,
                move_x : Float32? = nil, move_y : Float32? = nil) : Float32
  renderer.reset
  lx = Tessell::Render::Dpi.logical_to_device(20.0_f32, scale)
  ly1 = Tessell::Render::Dpi.logical_to_device(48.0_f32, scale)
  ly2 = Tessell::Render::Dpi.logical_to_device(96.0_f32, scale)
  ly3 = Tessell::Render::Dpi.logical_to_device(144.0_f32, scale)
  pen = 0.0_f32
  pen = renderer.append_text_cached(placement_sink, "Hello DPI", lx, ly1, size_px, viewport_w, viewport_h, theme_fg)
  renderer.append_text_cached(placement_sink, "Theme Token", lx, ly2, size_px, viewport_w, viewport_h, theme_fg)
  renderer.append_text_cached(placement_sink, "Scale Test", lx, ly3, size_px, viewport_w, viewport_h, theme_fg)
  if mx = move_x
    if my = move_y
      renderer.append_text_cached(placement_sink, "MOVE", mx, my, size_px, viewport_w, viewport_h, theme_fg)
    end
  end
  pen
end

def render_full(backend : Tessell::Render::GL::GLBackend,
                renderer : Tessell::Render::TextRenderer,
                placement_sink : Array(Tessell::Text::GlyphPlacement),
                scale : Float32, size_px : Int32, theme : Tessell::Render::Theme,
                viewport_w : Int32, viewport_h : Int32,
                move_x : Float32? = nil, move_y : Float32? = nil) : {Int32, Float32}
  backend.begin_frame(nil, theme)
  pen = build_scene(renderer, placement_sink, scale, size_px, theme.fg, viewport_w, viewport_h, move_x, move_y)
  submitted = backend.draw_text(renderer.vertices, renderer.batch_runs, renderer.batch_count)
  backend.end_frame
  {submitted, pen}
end

def render_dirty(backend : Tessell::Render::GL::GLBackend,
                 renderer : Tessell::Render::TextRenderer,
                 placement_sink : Array(Tessell::Text::GlyphPlacement),
                 scale : Float32, size_px : Int32, theme : Tessell::Render::Theme,
                 viewport_w : Int32, viewport_h : Int32,
                 dirty_rects : Array(Tessell::Rect),
                 move_x : Float32, move_y : Float32) : {Int32, Int32, Float32}
  backend.begin_frame(dirty_rects, theme)
  pen = build_scene(renderer, placement_sink, scale, size_px, theme.fg, viewport_w, viewport_h, move_x, move_y)
  submitted = backend.draw_text(renderer.vertices, renderer.batch_runs, renderer.batch_count)
  st = backend.stats
  backend.end_frame
  {submitted, st.culled_quads, pen}
end

struct CaseResult
  property dpi_scale : Float32
  property theme_name : String
  property theme_bg : UInt32
  property theme_fg : UInt32
  property text_pixels_nonbg : Int64
  property corner_pixel_rgba : String
  property expected_bg : String
  property text_advance : Float32
  property pen_end_x : Float32
  property quads : Int32
  property batches : Int32
  property alloc_bytes : Int64
  property alloc_windows : String
  property retried : Bool
  property attempt : Int32
  property j3_pass : Bool
  property bg_pixel_delta : String
  property j4_pass : Bool

  def initialize(@dpi_scale, @theme_name, @theme_bg, @theme_fg, @text_pixels_nonbg,
                 @corner_pixel_rgba, @expected_bg, @text_advance, @pen_end_x,
                 @quads, @batches, @alloc_bytes, @alloc_windows, @retried, @attempt,
                 @j3_pass, @bg_pixel_delta, @j4_pass)
  end
end

dpi_arg = 1.0_f64
theme_arg = "light"
frames_target = 20
verify_mode = false
dpi_aware = false
ARGV.each_with_index do |arg, i|
  if arg.starts_with?("--dpi=")
    dpi_arg = arg.split("=", 2)[1].to_f64
  elsif arg == "--dpi" && i + 1 < ARGV.size
    dpi_arg = ARGV[i + 1].to_f64
  elsif arg.starts_with?("--theme=")
    theme_arg = arg.split("=", 2)[1]
  elsif arg == "--theme" && i + 1 < ARGV.size
    theme_arg = ARGV[i + 1]
  elsif arg.starts_with?("--frames=")
    frames_target = arg.split("=", 2)[1].to_i
  elsif arg == "--frames" && i + 1 < ARGV.size
    frames_target = ARGV[i + 1].to_i
  elsif arg == "--verify"
    verify_mode = true
  elsif arg == "--dpi-aware"
    dpi_aware = true
  end
end

result_ch = Channel({Bool, String}).new

iso_ctx = Fiber::ExecutionContext::Isolated.new("tessell-m3-dpi-theme") do
  begin
    if dpi_aware
      M3DTUser32.SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2)
    end

    hinstance = M3DTKernel32.GetModuleHandleW(Pointer(UInt16).null)
    dt_fail("GetModuleHandleW") if hinstance.null?

    class_name = dt_to_wstr("TessellM3DpiThemeProbe")
    window_title = dt_to_wstr("Tessell M3 DPI Theme")

    wc = M3DTUser32::WNDCLASSEXW.new
    wc.cbSize = sizeof(M3DTUser32::WNDCLASSEXW).to_u32
    wc.style = CS_OWNDC
    wc.lpfnWndProc = DT_WNDPROC
    wc.cbClsExtra = 0
    wc.cbWndExtra = 0
    wc.hInstance = hinstance
    wc.hIcon = Pointer(Void).null
    wc.hCursor = M3DTUser32.LoadCursorW(Pointer(Void).null, IDC_ARROW)
    wc.hbrBackground = Pointer(Void).null
    wc.lpszMenuName = Pointer(UInt16).null
    wc.lpszClassName = class_name.to_unsafe
    wc.hIconSm = Pointer(Void).null
    atom = M3DTUser32.RegisterClassExW(pointerof(wc))
    dt_fail("RegisterClassExW") if atom == 0

    width = 640
    height = 360
    rect = M3DTUser32::RECT.new
    rect.left = 0; rect.top = 0; rect.right = width; rect.bottom = height
    style = WS_OVERLAPPEDWINDOW
    M3DTUser32.AdjustWindowRectEx(pointerof(rect), style, 0, 0)
    win_w = rect.right - rect.left
    win_h = rect.bottom - rect.top

    hwnd = M3DTUser32.CreateWindowExW(0_u32, class_name.to_unsafe, window_title.to_unsafe,
                                      style | WS_VISIBLE, CW_USEDEFAULT, CW_USEDEFAULT,
                                      win_w, win_h, Pointer(Void).null, Pointer(Void).null,
                                      hinstance, Pointer(Void).null)
    dt_fail("CreateWindowExW") if hwnd.null?
    M3DTUser32.ShowWindow(hwnd, SW_SHOW)
    M3DTUser32.UpdateWindow(hwnd)

    hdc = M3DTUser32.GetDC(hwnd)
    dt_fail("GetDC") if hdc.null?

    pfd = M3DTGdi32::PIXELFORMATDESCRIPTOR.new
    pfd.nSize = sizeof(M3DTGdi32::PIXELFORMATDESCRIPTOR).to_u16
    pfd.nVersion = 1_u16
    pfd.dwFlags = PFD_DRAW_TO_WINDOW | PFD_SUPPORT_OPENGL | PFD_DOUBLEBUFFER
    pfd.iPixelType = PFD_TYPE_RGBA
    pfd.cColorBits = 32_u8
    pfd.cDepthBits = 24_u8
    pfd.cStencilBits = 8_u8
    pfd.iLayerType = PFD_MAIN_PLANE
    pf = M3DTGdi32.ChoosePixelFormat(hdc, pointerof(pfd))
    dt_fail("ChoosePixelFormat") if pf == 0
    dt_fail("SetPixelFormat") if M3DTGdi32.SetPixelFormat(hdc, pf, pointerof(pfd)) == 0

    hglrc = M3DTWGL.wglCreateContext(hdc)
    dt_fail("wglCreateContext") if hglrc.null?
    dt_fail("wglMakeCurrent") if M3DTWGL.wglMakeCurrent(hdc, hglrc) == 0

    unless Tessell::Text::FtMeasurer.available?
      result_ch.send({false, "error=ft_unavailable reason=#{Tessell::Text::FtMeasurer.unavailable_reason.inspect}"})
      next
    end

    font_path = "C:/Windows/Fonts/msyh.ttc"
    unless File.exists?(font_path)
      result_ch.send({false, "error=font_missing path=#{font_path}"})
      next
    end
    measurer = Tessell::Text::FtMeasurer.open(font_path, 0)
    atlas = Tessell::Text::GlyphAtlas.new(1024, 4096)
    rasterizer = Tessell::Text::Rasterizer.new(measurer, atlas, 1)
    renderer = Tessell::Render::TextRenderer.new(atlas, rasterizer)
    backend = Tessell::Render::GL::GLBackend.new
    backend.init(width, height)
    backend.resize(width, height)

    placement_sink = [] of Tessell::Text::GlyphPlacement

    theme_for = ->(name : String) : Tessell::Render::Theme do
      name == "dark" ? Tessell::Render::Theme.dark : Tessell::Render::Theme.light
    end

    run_one = ->(scale : Float32, theme_name : String, do_alloc_probe : Bool, frames_n : Int32) : CaseResult do
      theme = theme_for.call(theme_name)
      size_px_f = Tessell::Render::Dpi.size_px(16.0_f32, scale)
      size_px = size_px_f.to_i

      # warmup + atlas sync
      3.times do
        render_full(backend, renderer, placement_sink, scale, size_px, theme, width, height)
        backend.sync_atlas(atlas)
      end
      sub, pen = render_full(backend, renderer, placement_sink, scale, size_px, theme, width, height)
      backend.sync_atlas(atlas)
      sub, pen = render_full(backend, renderer, placement_sink, scale, size_px, theme, width, height)

      # J3 corner (top-left) - capture before swap (back buffer)
      corner = capture_corner_topleft(width, height)
      cr = corner[0]; cg = corner[1]; cb = corner[2]; ca = corner[3]
      er = Tessell::Render::Theme.rb(theme.bg)
      eg = Tessell::Render::Theme.gb(theme.bg)
      eb = Tessell::Render::Theme.bb(theme.bg)
      ea = Tessell::Render::Theme.ab(theme.bg)
      corner_str = rgba_hex(cr, cg, cb, ca)
      expected_str = rgba_hex(er, eg, eb, ea)
      j3_pass = (cr == er && cg == eg && cb == eb && ca == ea)
      delta_str = "none"
      unless j3_pass
        dr = (cr.to_i - er.to_i).abs
        dg = (cg.to_i - eg.to_i).abs
        db = (cb.to_i - eb.to_i).abs
        da = (ca.to_i - ea.to_i).abs
        delta_str = "bg_pixel_delta=#{dr},#{dg},#{db},#{da} actual=#{corner_str} expected=#{expected_str}"
      end

      # text_pixels_nonbg on current frame (before swap)
      frame_buf = capture_pixels(width, height)
      nonbg = count_text_pixels_nonbg(frame_buf, er, eg, eb, ea)
      M3DTGdi32.SwapBuffers(hdc)

      # text_advance via measurer (device px at size_px)
      text = "Hello DPI"
      adv = measurer.measure(text, 1, size_px_f, 10000.0_f32).width

      quads = renderer.vertex_count // 4
      batches = renderer.batch_count

      # J4 steady-state alloc probe (3 windows max)
      alloc_bytes = 0_i64
      alloc_windows = "[0,0,0]"
      retried = false
      attempt = 1
      j4_pass = true
      if do_alloc_probe
        n_alloc = 1000
        # warmup to absorb one-time allocations
        (frames_n * 3).times { render_full(backend, renderer, placement_sink, scale, size_px, theme, width, height) }
        3.times { GC.collect }
        windows = [0_i64, 0_i64, 0_i64]
        # attempt 1
        wi = 0
        while wi < 3
          before = GC.stats.bytes_since_gc
          GC.disable
          begin
            k = 0
            while k < n_alloc
              render_full(backend, renderer, placement_sink, scale, size_px, theme, width, height)
              k += 1
            end
            after = GC.stats.bytes_since_gc
            delta = after >= before ? (after - before).to_i64 : 0_i64
            windows[wi] = delta
          ensure
            GC.enable
          end
          wi += 1
        end
        mxw = windows.max
        # criterion A < 1000, B <= 256
        if mxw >= 1000_i64 || mxw > 256_i64
          # retry once on failure
          retried = true
          attempt = 2
          3.times { GC.collect }
          wi = 0
          while wi < 3
            before = GC.stats.bytes_since_gc
            GC.disable
            begin
              k = 0
              while k < n_alloc
                render_full(backend, renderer, placement_sink, scale, size_px, theme, width, height)
                k += 1
              end
              after = GC.stats.bytes_since_gc
              delta = after >= before ? (after - before).to_i64 : 0_i64
              windows[wi] = delta
            ensure
              GC.enable
            end
            wi += 1
          end
        end
        alloc_bytes = windows.max
        alloc_windows = "[#{windows[0]},#{windows[1]},#{windows[2]}]"
        j4_pass = alloc_bytes < 1000_i64 && alloc_bytes <= 256_i64
      end

      CaseResult.new(scale, theme_name, theme.bg, theme.fg, nonbg,
                     corner_str, expected_str, adv, pen, quads, batches,
                     alloc_bytes, alloc_windows, retried, attempt, j3_pass, delta_str, j4_pass)
    end

    token_line = ->(r : CaseResult, ver : String) : String do
      String.build do |s|
        s << "dpi_scale=" << sprintf("%.2f", r.dpi_scale)
        s << " theme_bg=" << sprintf("0x%08x", r.theme_bg)
        s << " theme_fg=" << sprintf("0x%08x", r.theme_fg)
        s << " text_pixels_nonbg=" << r.text_pixels_nonbg
        s << " corner_pixel_rgba=" << r.corner_pixel_rgba
        s << " expected_bg=" << r.expected_bg
        s << " text_advance=" << sprintf("%.6f", r.text_advance)
        s << " pen_end_x=" << sprintf("%.6f", r.pen_end_x)
        s << " quads=" << r.quads
        s << " batches=" << r.batches
        s << " alloc_bytes=" << r.alloc_bytes
        s << " alloc_windows=" << r.alloc_windows
        s << " retried=" << r.retried
        s << " attempt=" << r.attempt
        if r.bg_pixel_delta != "none"
          s << " " << r.bg_pixel_delta
        end
        s << " verify=" << ver
      end
    end

    if verify_mode
      # J1 sweep at 1.0,1.5,2.0 (light theme)
      r10 = run_one.call(1.0_f32, "light", true, frames_target)
      r15 = run_one.call(1.5_f32, "light", true, frames_target)
      r20 = run_one.call(2.0_f32, "light", true, frames_target)

      px10 = r10.text_pixels_nonbg.to_f64
      px15 = r15.text_pixels_nonbg.to_f64
      px20 = r20.text_pixels_nonbg.to_f64
      r15_ratio = px10 > 0.0 ? (px15 / px10) : 0.0
      r20_ratio = px10 > 0.0 ? (px20 / px10) : 0.0
      j1_mono = (r10.text_pixels_nonbg < r15.text_pixels_nonbg) && (r15.text_pixels_nonbg < r20.text_pixels_nonbg)
      j1_r15_ok = r15_ratio >= 1.5 && r15_ratio <= 3.5
      j1_r20_ok = r20_ratio >= 2.5 && r20_ratio <= 5.0
      j1_pass = j1_mono && j1_r15_ok && j1_r20_ok

      # J5 at dpi=1.5 dark: dirty submit vs full redraw
      j5_theme = Tessell::Render::Theme.dark
      j5_scale = 1.5_f32
      j5_size_px = Tessell::Render::Dpi.size_px(16.0_f32, j5_scale).to_i
      # move element positions (device px), logical coords chosen to stay visible
      # Use a clear displacement so A vs C differs (anti-vacuity: diff_A_vs_C>0)
      move_y_log = 120.0_f32
      move_y = Tessell::Render::Dpi.logical_to_device(move_y_log, j5_scale)
      move_x0 = Tessell::Render::Dpi.logical_to_device(20.0_f32, j5_scale)
      move_x1 = Tessell::Render::Dpi.logical_to_device(40.0_f32, j5_scale)
      move_text = "MOVE"
      move_w = measurer.measure(move_text, 1, j5_size_px.to_f32, 10000.0_f32).width
      pad = 4.0_f32 * j5_scale
      old_rect = Tessell::Rect.new(move_x0 - 1.0_f32, move_y - j5_size_px.to_f32 - pad, move_w + 6.0_f32 * j5_scale, j5_size_px.to_f32 + pad * 3.0_f32)
      new_rect = Tessell::Rect.new(move_x1 - 1.0_f32, move_y - j5_size_px.to_f32 - pad, move_w + 6.0_f32 * j5_scale, j5_size_px.to_f32 + pad * 3.0_f32)
      dirty_union = old_rect.union(new_rect)
      dirty_src = [dirty_union]
      dirty_rects = [] of Tessell::Rect
      dirty_rects << dirty_union
      Tessell::Render::Dirty.merge_into(dirty_src, dirty_rects, 8)

      # warmup including MOVE so glyphs are rasterized and synced to atlas textures
      render_full(backend, renderer, placement_sink, j5_scale, j5_size_px, j5_theme, width, height, move_x0, move_y)
      backend.sync_atlas(atlas)
      render_full(backend, renderer, placement_sink, j5_scale, j5_size_px, j5_theme, width, height, move_x0, move_y)
      backend.sync_atlas(atlas)

      render_full(backend, renderer, placement_sink, j5_scale, j5_size_px, j5_theme, width, height, move_x0, move_y)
      pixels_a = capture_pixels(width, height)
      sub_dirty, culled_dirty, _ = render_dirty(backend, renderer, placement_sink, j5_scale, j5_size_px, j5_theme, width, height, dirty_rects, move_x1, move_y)
      pixels_b = capture_pixels(width, height)
      sub_full_c, _ = render_full(backend, renderer, placement_sink, j5_scale, j5_size_px, j5_theme, width, height, move_x1, move_y)
      pixels_c = capture_pixels(width, height)
      corner_j5 = capture_corner_topleft(width, height)
      M3DTGdi32.SwapBuffers(hdc)

      j5_diff_pixels = pixel_diff(pixels_b, pixels_c)
      j5_diff_a_vs_c = pixel_diff(pixels_a, pixels_c)
      # locate first A vs C diff for diagnostics
      j5_ac_loc = "none"
      if j5_diff_a_vs_c > 0
        i = 0
        while i < pixels_a.size
          if pixels_a[i] != pixels_c[i] || pixels_a[i+1] != pixels_c[i+1] || pixels_a[i+2] != pixels_c[i+2] || pixels_a[i+3] != pixels_c[i+3]
            px = (i // 4) % width
            py = (i // 4) // width
            j5_ac_loc = "x=#{px} y=#{py} a=#{pixels_a[i]},#{pixels_a[i+1]},#{pixels_a[i+2]},#{pixels_a[i+3]} c=#{pixels_c[i]},#{pixels_c[i+1]},#{pixels_c[i+2]},#{pixels_c[i+3]}"
            break
          end
          i += 4
        end
      end
      erd = Tessell::Render::Theme.rb(j5_theme.bg); egd = Tessell::Render::Theme.gb(j5_theme.bg)
      ebd = Tessell::Render::Theme.bb(j5_theme.bg); ead = Tessell::Render::Theme.ab(j5_theme.bg)
      j5_a_nonbg = count_text_pixels_nonbg(pixels_a, erd, egd, ebd, ead)
      j5_c_nonbg = count_text_pixels_nonbg(pixels_c, erd, egd, ebd, ead)
      j5_b_nonbg = count_text_pixels_nonbg(pixels_b, erd, egd, ebd, ead)
      j5_pass = j5_diff_pixels == 0 && j5_diff_a_vs_c > 0 && sub_dirty < sub_full_c

      # J3 check for dark J5 frame (corner, captured before swap)
      j5_j3_pass = (corner_j5[0] == erd && corner_j5[1] == egd && corner_j5[2] == ebd && corner_j5[3] == ead)
      j5_bg_delta = "none"
      unless j5_j3_pass
        dr = (corner_j5[0].to_i - erd.to_i).abs
        dg = (corner_j5[1].to_i - egd.to_i).abs
        db = (corner_j5[2].to_i - ebd.to_i).abs
        da = (corner_j5[3].to_i - ead.to_i).abs
        j5_bg_delta = "bg_pixel_delta=#{dr},#{dg},#{db},#{da} actual=#{rgba_hex(corner_j5[0],corner_j5[1],corner_j5[2],corner_j5[3])} expected=#{rgba_hex(erd,egd,ebd,ead)}"
      end

      overall = j1_pass && j5_pass && j5_j3_pass && r10.j3_pass && r15.j3_pass && r20.j3_pass && r10.j4_pass && r15.j4_pass && r20.j4_pass
      overall_str = overall ? "pass" : "fail"

      lines = String.build do |s|
        s << token_line.call(r10, overall_str) << "\n"
        s << token_line.call(r15, overall_str) << "\n"
        s << token_line.call(r20, overall_str) << "\n"
        s << "J1 mono=" << j1_mono << " px10=" << r10.text_pixels_nonbg << " px15=" << r15.text_pixels_nonbg << " px20=" << r20.text_pixels_nonbg
        s << " r15=" << sprintf("%.6f", r15_ratio) << " r20=" << sprintf("%.6f", r20_ratio)
        s << " r15_ok=" << j1_r15_ok << " r20_ok=" << j1_r20_ok << " j1_pass=" << j1_pass << "\n"
        s << "J5 dpi_scale=1.50 theme=dark diff_pixels=" << j5_diff_pixels << " diff_A_vs_C=" << j5_diff_a_vs_c
        s << " a_nonbg=" << j5_a_nonbg << " b_nonbg=" << j5_b_nonbg << " c_nonbg=" << j5_c_nonbg
        s << " ac_loc=" << j5_ac_loc
        s << " submitted_quads_dirty=" << sub_dirty << " submitted_quads_full=" << sub_full_c
        s << " culled_quads=" << culled_dirty << " dirty_rects=" << dirty_rects.size
        s << " corner_pixel_rgba=" << rgba_hex(corner_j5[0],corner_j5[1],corner_j5[2],corner_j5[3])
        s << " expected_bg=" << rgba_hex(erd,egd,ebd,ead)
        if j5_bg_delta != "none"
          s << " " << j5_bg_delta
        end
        s << " j5_pass=" << j5_pass << " j5_j3_pass=" << j5_j3_pass << "\n"
        s << "verify=" << overall_str
      end

      measurer.close
      backend.close
      M3DTWGL.wglMakeCurrent(Pointer(Void).null, Pointer(Void).null)
      M3DTWGL.wglDeleteContext(hglrc)
      M3DTUser32.ReleaseDC(hwnd, hdc)
      M3DTUser32.DestroyWindow(hwnd) unless M3DTState.quit_requested

      result_ch.send({overall, lines})
    else
      scale = dpi_arg.to_f32
      res = run_one.call(scale, theme_arg, true, frames_target)
      ver = (res.j3_pass && res.j4_pass) ? "pass" : "fail"
      line = token_line.call(res, ver)
      measurer.close
      backend.close
      M3DTWGL.wglMakeCurrent(Pointer(Void).null, Pointer(Void).null)
      M3DTWGL.wglDeleteContext(hglrc)
      M3DTUser32.ReleaseDC(hwnd, hdc)
      M3DTUser32.DestroyWindow(hwnd) unless M3DTState.quit_requested
      result_ch.send({(res.j3_pass && res.j4_pass), line})
    end
  rescue ex
    result_ch.send({false, "error=exception message=#{ex.message.inspect} backtrace=#{ex.backtrace.first(3).join(" | ").inspect}"})
  end
end

ok, line = result_ch.receive
puts line
exit(ok ? 0 : 1)
