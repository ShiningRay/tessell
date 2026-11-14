# M4-WP3 real example app: DSL state chain + VirtualList + editable text +
# theme/DPI + dirty-rect partial submit, in a real Win32/WGL window (pure FFI).
#
# Usage:
#   crystal run examples/app_demo.cr -- --frames=120
#   crystal run examples/app_demo.cr -- --frames=120 --verify
#   crystal run examples/app_demo.cr -- --theme=dark --dpi=1.5 --verify
#
# Keys: Tab moves focus (top edit -> list -> status), typing edits the top line,
# mouse wheel scrolls the 10k-row list, T toggles theme while the list is focused,
# Esc quits. Layout: 800x668 window = 40px top bar + 800x600 list viewport + 28px status.
#
# Per frame: UI.build -> UI.apply -> Node.collect_dirty -> render -> UI.consume.
# Dirty frames submit only the changed rects (list on scroll, top bar on typing,
# full window on theme switch); clean frames skip drawing but still SwapBuffers.
#
# --verify: (1) after wheel scroll, dirty pixels == same-state full redraw
# (diff_pixels==0, diff_A_vs_C>0); (2) theme switch result == direct launch with
# that theme (diff_theme==0, plus round-trip diff_theme_roundtrip==0);
# (3) steady frame zero-alloc (A<1000, B<=256, 3 windows max, GC.enable in ensure,
# <=1 retry, attempt printed). Exit 0 iff all hold.

require "../src/tessell"
require "../src/tessell/render/gl/gl_backend"
require "./lib/shot"

@[Link("kernel32")]
lib M4DKernel32
  fun GetModuleHandleW(lpModuleName : UInt16*) : Void*
  fun GetLastError : UInt32
end

@[Link("user32")]
lib M4DUser32
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
lib M4DGdi32
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
lib M4DWGL
  fun wglCreateContext(hdc : Void*) : Void*
  fun wglMakeCurrent(hdc : Void*, hglrc : Void*) : Int32
  fun wglDeleteContext(hglrc : Void*) : Int32
end

@[Link("opengl32")]
lib M4DGL
  GL_RGBA           = 0x1908_u32
  GL_UNSIGNED_BYTE  = 0x1401_u32
  GL_PACK_ALIGNMENT = 0x0D05_u32
  fun glReadPixels(x : Int32, y : Int32, width : Int32, height : Int32, format : UInt32, type : UInt32, pixels : Void*) : Void
  fun glFinish : Void
  fun glPixelStorei(pname : UInt32, param : Int32) : Void
end

module M4DState
  class_property quit_requested : Bool = false
  class_property wheel_delta : Int32 = 0
  class_property char_code : UInt32 = 0
  class_property key_code : UInt32 = 0
  class_property mouse_x : Int32 = 0
  class_property mouse_y : Int32 = 0
  class_property mouse_moved : Bool = false
  class_property mouse_down : Bool = false
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
WM_CHAR             = 0x0102_u32
WM_MOUSEMOVE        = 0x0200_u32
WM_LBUTTONDOWN      = 0x0201_u32
WM_MOUSEWHEEL       = 0x020A_u32
VK_ESCAPE           = 0x1B_u64
IDC_ARROW           = Pointer(UInt16).new(32512_u64)
CS_OWNDC            = 0x0020_u32

PFD_DRAW_TO_WINDOW = 0x00000004_u32
PFD_SUPPORT_OPENGL = 0x00000020_u32
PFD_DOUBLEBUFFER   = 0x00000001_u32
PFD_TYPE_RGBA      = 0_u8
PFD_MAIN_PLANE     = 0_u8

M4D_WNDPROC = ->(hwnd : Void*, msg : UInt32, wparam : UInt64, lparam : Int64) : Int64 do
  case msg
  when WM_CLOSE
    M4DUser32.DestroyWindow(hwnd)
    return 0_i64
  when WM_DESTROY
    M4DUser32.PostQuitMessage(0)
    M4DState.quit_requested = true
    return 0_i64
  when WM_KEYDOWN
    if wparam == VK_ESCAPE
      M4DUser32.DestroyWindow(hwnd)
      return 0_i64
    end
    M4DState.key_code = (wparam & 0xFFFF_u64).to_u32
  when WM_CHAR
    cp = (wparam & 0xFFFF_u64).to_u32
    M4DState.char_code = cp if cp >= 0x20_u32 && cp != 0x7F_u32
  when WM_MOUSEMOVE
    x = (lparam & 0xFFFF_u64).to_i32
    x -= 65536 if x > 32767
    y = ((lparam >> 16) & 0xFFFF_u64).to_i32
    y -= 65536 if y > 32767
    M4DState.mouse_x = x
    M4DState.mouse_y = y
    M4DState.mouse_moved = true
  when WM_LBUTTONDOWN
    M4DState.mouse_down = true
  when WM_MOUSEWHEEL
    d = ((wparam >> 16) & 0xFFFF_u64).to_i32
    d -= 65536 if d > 32767
    M4DState.wheel_delta = d
  end
  M4DUser32.DefWindowProcW(hwnd, msg, wparam, lparam)
end

def m4d_to_wstr(s : String) : Slice(UInt16)
  u = s.to_utf16
  buf = Slice(UInt16).new(u.size + 1, 0_u16)
  u.size.times { |i| buf[i] = u[i] }
  buf
end

def m4d_fail(msg : String)
  err = M4DKernel32.GetLastError
  STDERR.puts "error=#{msg} win32_error=#{err}"
  exit 1
end

def m4d_capture(w : Int32, h : Int32) : Bytes
  buf = Bytes.new(w * h * 4)
  M4DGL.glPixelStorei(M4DGL::GL_PACK_ALIGNMENT, 1)
  M4DGL.glFinish
  M4DGL.glReadPixels(0, 0, w, h, M4DGL::GL_RGBA, M4DGL::GL_UNSIGNED_BYTE, buf.to_unsafe.as(Void*))
  buf
end

def m4d_pixel_diff(a : Bytes, b : Bytes) : Int32
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

include Tessell
include Tessell::UI

# Real app: state + retained tree + DSL chain + VirtualList + text rendering.
class M4DApp
  WIDTH    = 800
  TOP_H    = 40
  LIST_H   = 600
  STATUS_H = 28
  HEIGHT   = 668
  ROWS     = 10_000
  ROW_H    = 20

  @theme : Render::Theme
  @status : String
  @top_node : Node?
  @list_node : Node?
  @status_node : Node?
  @a11y : Tessell::A11y::Builder
  @a11y_sink : Array(Tessell::A11y::Node)
  @row_name : Proc(Int32, String)
  @a11y_count : Int32
  @screenshot_path : String

  getter width : Int32
  getter height : Int32

  def initialize(@hdc : Void*, @initial_dark : Bool, @scale : Float32, @dpi_label : String, screenshot_path : String = "")
    @screenshot_path = screenshot_path
    @width = WIDTH
    @text_size = Render::Dpi.size_px(16.0_f32, @scale).to_i32
    @top_h = @text_size + 32
    @status_h = @text_size + 24
    @list_h = LIST_H
    @height = @top_h + @list_h + @status_h
    @list_top = @top_h
    @rows = ROWS
    @row_h = ROW_H

    @dark = @initial_dark
    @theme = theme_of(@dark)
    @status = status_text
    @initial_text = "Hello Tessell"
    @input_text = @initial_text

    @top_rect = Rect.new(0.0_f32, 0.0_f32, @width.to_f32, @top_h.to_f32)
    @list_rect = Rect.new(0.0_f32, @list_top.to_f32, @width.to_f32, @list_h.to_f32)
    @status_rect = Rect.new(0.0_f32, (@height - @status_h).to_f32, @width.to_f32, @status_h.to_f32)
    # Scroll dirty rect is the list viewport expanded by text_size so glyph
    # bitmaps that straddle the list edge (text_size > row_h at high dpi) are
    # also resubmitted; without this, B (dirty) would keep stale straddle pixels.
    st = @list_top - @text_size
    st = 0 if st < 0
    sb = @list_top + @list_h + @text_size
    sb = @height if sb > @height
    @scroll_rect = Rect.new(0.0_f32, st.to_f32, @width.to_f32, (sb - st).to_f32)

    @measurer = Text::FtMeasurer.open("C:/Windows/Fonts/msyh.ttc", 0)
    @atlas = Text::GlyphAtlas.new(1024, 4096)
    @rasterizer = Text::Rasterizer.new(@measurer, @atlas, 0, ROWS + 64)
    @renderer = Render::TextRenderer.new(@atlas, @rasterizer)
    @backend = Render::GL::GLBackend.new
    @backend.init(@width, @height)
    @backend.resize(@width, @height)
    @renderer.reserve_quads(2048)
    @renderer.reserve_batches(64)
    @placement_sink = [] of Text::GlyphPlacement

    # 10k labels built once at init (hot path only indexes this array).
    @labels = Array(String).new(@rows)
    i = 0
    while i < @rows
      @labels << "Row #{i}"
      i += 1
    end

    # Warm shaped-run cache + atlas for every label and the fixed strings, so the
    # steady scroll path never misses (no HB/FT shaping or cache growth per frame).
    @labels.each { |t| @rasterizer.shape_run_into(t, @text_size, @placement_sink) }
    @rasterizer.shape_run_into(@input_text, @text_size, @placement_sink)
    @rasterizer.shape_run_into(@status, @text_size, @placement_sink)
    @backend.sync_atlas(@atlas)

    fetch_cb = ->(_i : Int32) { nil }
    @vl = Widgets::VirtualList.new(@rows, @row_h, @list_h, fetch_cb, @width)
    @max_scroll = @vl.total_height - @list_h
    @max_scroll = 0 if @max_scroll < 0

    @root = Node.new("root", Rect.new(0.0_f32, 0.0_f32, @width.to_f32, @height.to_f32))
    @pool = Pool.new
    buf = [] of Decl
    64.times { buf << Decl.new(UiKey.root, UiKey.root, DeclKind::Node) }
    buf.clear
    stack = [] of UiKey
    16.times { stack << UiKey.root }
    stack.clear
    @builder = Builder.new(buf, stack)

    @top_key = UiKey.root.child(1_u64)
    @list_key = UiKey.root.child(2_u64)
    @status_key = UiKey.root.child(3_u64)

    @dirty_sink = [] of Node
    @dirty_in = [] of Rect
    @dirty_out = [] of Rect
    8.times do
      @dirty_in << Rect.new(0.0_f32, 0.0_f32, 0.0_f32, 0.0_f32)
      @dirty_out << Rect.new(0.0_f32, 0.0_f32, 0.0_f32, 0.0_f32)
    end
    @dirty_in.clear
    @dirty_out.clear

    @router = Input::Router.new

    # a11y mirror of the DSL tree (M4-WP1 S3): meta is synced by UI.apply and
    # the tree is emitted into a pre-sized sink every frame (no materialization
    # of the 10k virtual rows; only the visible window becomes ListItem nodes).
    @a11y = Tessell::A11y::Builder.new(@router.focus_manager)
    @a11y_sink = [] of Tessell::A11y::Node
    64.times do
      @a11y_sink << Tessell::A11y::Node.new(0_u64, Tessell::A11y::Role::Group, "",
        "", Rect.new(0.0_f32, 0.0_f32, 0.0_f32, 0.0_f32), false, false, true, 0, 0)
    end
    @a11y_sink.clear
    @row_name = ->(i : Int32) { @labels[i] }
    @a11y_count = 0

    @force_full = true
    @ignore_input = false
    @vis_sum = 0_i64
    @vis_frames = 0_i64
    @quads_full = 0
    @quads_dirty = 0
    @culled = 0
    @seg = [0_i64, 0_i64, 0_i64, 0_i64, 0_i64, 0_i64, 0_i64, 0_i64]

    # First frame: create nodes, then remember the pooled nodes.
    build_ui
    UI.apply(@builder.buf, @root, @pool, @a11y)
    Node.collect_dirty(@root, @dirty_sink)
    UI.consume(@dirty_sink)
    @top_node = @pool.map[@top_key]?
    @list_node = @pool.map[@list_key]?
    @status_node = @pool.map[@status_key]?
    if top = @top_node
      @router.focus_manager.focus(top)
    end
    emit_a11y
  end

  def ignore_input=(v : Bool) : Nil
    @ignore_input = v
  end

  private def theme_of(dark : Bool) : Render::Theme
    dark ? Render::Theme.dark : Render::Theme.light
  end

  private def status_text : String
    "theme=#{@dark ? "dark" : "light"} dpi=#{@dpi_label}"
  end

  private def sync_atlas_if_needed : Nil
    # Dynamic text inserts glyphs into EXISTING pages, so page_count is not a
    # change signal. Drive uploads from the atlas revision contract (issue #1):
    # sync_atlas_dirty only re-uploads pages whose content revision changed.
    @backend.sync_atlas_dirty(@atlas)
  end

  # ---- DSL chain: declarations are rebuilt every frame from external state. ----
  # a11y_* carries the accessible surface: the top line is an editable Text
  # (focusable), the list is a List container (its rows are virtual), the status
  # line is a read-only Text.
  def build_ui : Nil
    UI.build(UiKey.root, @builder) do |x|
      x.text(@top_key, @input_text, @top_rect,
        a11y_role: Tessell::A11y::Role::Text, a11y_name: "input",
        a11y_value: @input_text, a11y_focusable: true)
      x.node(@list_key, @list_rect,
        a11y_role: Tessell::A11y::Role::List, a11y_name: "rows")
      x.text(@status_key, @status, @status_rect,
        a11y_role: Tessell::A11y::Role::Text, a11y_name: "status",
        a11y_value: @status)
    end
  end

  # Emit the a11y mirror into the reused sink. ListItem rows come from the
  # VirtualList visible window only (children_count carries the logical 10k).
  private def emit_a11y : Nil
    ln = @list_node
    if ln
      @a11y_count = UI.a11y_emit(@root, @a11y, @a11y_sink, @vl, ln, @row_name)
    else
      @a11y_count = UI.a11y_emit(@root, @a11y, @a11y_sink)
    end
  end

  private def render_text : Nil
    @renderer.reset
    @renderer.append_text_cached(@placement_sink, @input_text, 8.0_f32,
      (@top_h - 12).to_f32, @text_size, @width, @height, @theme.fg)
    i = @vl.visible_first
    last = @vl.visible_last
    while i <= last
      oy = @vl.node_offset(i).to_f32 + @list_top.to_f32 + (@row_h - 4).to_f32
      @renderer.append_text_cached(@placement_sink, @labels[i], 8.0_f32, oy,
        @text_size, @width, @height, @theme.fg)
      i += 1
    end
    @renderer.append_text_cached(@placement_sink, @status, 8.0_f32,
      (@height - 12).to_f32, @text_size, @width, @height, @theme.fg)
  end

  def render_full : Int32
    sync_atlas_if_needed
    @backend.begin_frame(nil, @theme)
    render_text
    submitted = @backend.draw_text(@renderer.vertices, @renderer.batch_runs, @renderer.batch_count)
    @backend.end_frame
    submitted
  end

  def render_dirty(rects : Array(Rect)) : {Int32, Int32}
    sync_atlas_if_needed
    @backend.begin_frame(rects, @theme)
    render_text
    submitted = @backend.draw_text(@renderer.vertices, @renderer.batch_runs, @renderer.batch_count)
    st = @backend.stats
    @backend.end_frame
    {submitted, st.culled_quads}
  end

  # Map the UI dirty set to submit rects: list node -> list viewport, top/status
  # -> their bars, root -> full window. Unknown nodes fall back to node bounds.
  private def compute_dirty_rects : Nil
    @dirty_in.clear
    i = 0
    while i < @dirty_sink.size
      n = @dirty_sink[i]
      if n == @root
        @dirty_in << @root.bounds
      elsif n == @list_node
        @dirty_in << @scroll_rect
      elsif n == @top_node
        @dirty_in << @top_rect
      elsif n == @status_node
        @dirty_in << @status_rect
      else
        @dirty_in << n.bounds
      end
      i += 1
    end
    Render::Dirty.merge_into(@dirty_in, @dirty_out, 8)
  end

  private def settle_render_full : Int32
    build_ui
    UI.apply(@builder.buf, @root, @pool)
    Node.collect_dirty(@root, @dirty_sink)
    submitted = render_full
    UI.consume(@dirty_sink)
    submitted
  end

  private def settle_render_dirty : {Int32, Int32}
    build_ui
    UI.apply(@builder.buf, @root, @pool)
    Node.collect_dirty(@root, @dirty_sink)
    compute_dirty_rects
    q, c = render_dirty(@dirty_out)
    UI.consume(@dirty_sink)
    {q, c}
  end

  # ---- input (all through Router) ----
  def pump_messages : Nil
    msg = M4DUser32::MSG.new
    while M4DUser32.PeekMessageW(pointerof(msg), Pointer(Void).null, 0_u32, 0_u32, PM_REMOVE) != 0
      if msg.message == WM_QUIT
        M4DState.quit_requested = true
        break
      end
      M4DUser32.TranslateMessage(pointerof(msg))
      M4DUser32.DispatchMessageW(pointerof(msg))
    end
  end

  def apply_pending_input : Nil
    return if @ignore_input
    if M4DState.mouse_moved
      M4DState.mouse_moved = false
      @router.handle(Input::Event.pointer_move(M4DState.mouse_x.to_f32, M4DState.mouse_y.to_f32), @root)
    end
    if M4DState.mouse_down
      M4DState.mouse_down = false
      @router.handle(Input::Event.pointer_down(M4DState.mouse_x.to_f32, M4DState.mouse_y.to_f32), @root)
    end
    d = M4DState.wheel_delta
    if d != 0
      M4DState.wheel_delta = 0
      apply_wheel_event(d)
    end
    cp = M4DState.char_code
    if cp != 0
      M4DState.char_code = 0
      apply_text_event(cp)
    end
    vk = M4DState.key_code
    if vk != 0
      M4DState.key_code = 0
      apply_key_event(vk)
    end
  end

  def apply_wheel_event(delta : Int32) : Nil
    ev = Input::Event.wheel(@width.to_f32 / 2.0_f32, delta > 0 ? 1.0_f32 : -1.0_f32)
    target = @router.handle(ev, @root)
    return unless target == @list_node
    do_scroll(delta > 0 ? -@row_h : @row_h)
  end

  def apply_text_event(cp : UInt32) : Nil
    ch = cp.chr
    target = @router.handle(Input::Event.text_input(ch.to_s), @root)
    if target == @top_node
      @input_text += ch.to_s
    elsif target == @list_node
      toggle_theme if ch == 't' || ch == 'T'
    end
  end

  def apply_key_event(vk : UInt32) : Nil
    kc = case vk
         when 0x1B_u32 then Input::KeyCode::Escape
         when 0x09_u32 then Input::KeyCode::Tab
         when 0x08_u32 then Input::KeyCode::Backspace
         when 0x0D_u32 then Input::KeyCode::Enter
         else
           return
         end
    target = @router.handle(Input::Event.key_down(kc), @root)
    case kc
    when Input::KeyCode::Escape
      M4DState.quit_requested = true
    when Input::KeyCode::Tab
      @router.focus_manager.next(@root)
    when Input::KeyCode::Backspace
      if target == @top_node && !@input_text.empty?
        @input_text = @input_text[0...-1]
      end
    end
  end

  def toggle_theme : Nil
    @dark = !@dark
    @theme = theme_of(@dark)
    @status = status_text
    @force_full = true
  end

  def do_scroll(dy : Int32) : Nil
    before = @vl.scroll_y
    @vl.scroll_by(dy)
    @vl.scroll_to(0) if @max_scroll > 0 && @vl.scroll_y >= @max_scroll
    if @vl.scroll_y != before
      node = @list_node
      node.mark_dirty(Invalidation::Paint) if node
    end
  end

  # ---- frames ----
  def run_frame : Nil
    pump_messages
    apply_pending_input
    build_ui
    UI.apply(@builder.buf, @root, @pool, @a11y)
    emit_a11y
    Node.collect_dirty(@root, @dirty_sink)
    if @force_full
      @quads_full = render_full
      @force_full = false
    elsif !@dirty_sink.empty?
      compute_dirty_rects
      @quads_dirty, @culled = render_dirty(@dirty_out)
    end
    UI.consume(@dirty_sink)
    M4DGdi32.SwapBuffers(@hdc)
  end

  # Steady frame used by the zero-alloc probe: one wheel-sized scroll + dirty
  # submit + swap (the app's main work path, no cache misses after warmup).
  # @seg accumulates per-segment bytes (in-situ attribution; segments sum to the
  # frame total; residual vs GC counter is printed by the probe).
  def steady_frame : Nil
    t = GC.stats.bytes_since_gc.to_i64
    pump_messages
    t2 = GC.stats.bytes_since_gc.to_i64; @seg[0] += t2 - t; t = t2
    apply_pending_input
    t2 = GC.stats.bytes_since_gc.to_i64; @seg[1] += t2 - t; t = t2
    do_scroll(@row_h)
    t2 = GC.stats.bytes_since_gc.to_i64; @seg[2] += t2 - t; t = t2
    build_ui
    UI.apply(@builder.buf, @root, @pool, @a11y)
    emit_a11y
    Node.collect_dirty(@root, @dirty_sink)
    t2 = GC.stats.bytes_since_gc.to_i64; @seg[3] += t2 - t; t = t2
    unless @dirty_sink.empty?
      compute_dirty_rects
      t2 = GC.stats.bytes_since_gc.to_i64; @seg[4] += t2 - t; t = t2
      @quads_dirty, @culled = render_dirty(@dirty_out)
    end
    t2 = GC.stats.bytes_since_gc.to_i64; @seg[5] += t2 - t; t = t2
    UI.consume(@dirty_sink)
    t2 = GC.stats.bytes_since_gc.to_i64; @seg[6] += t2 - t; t = t2
    M4DGdi32.SwapBuffers(@hdc)
    t2 = GC.stats.bytes_since_gc.to_i64; @seg[7] += t2 - t
    vis = @vl.visible_last >= @vl.visible_first ? (@vl.visible_last - @vl.visible_first + 1) : 0
    @vis_sum += vis
    @vis_frames += 1
  end

  def capture_pixels : Bytes
    m4d_capture(@width, @height)
  end

  # ---- verification ----
  def run_verify(frames_target : Int32) : {Bool, String}
    @ignore_input = true
    2.times { run_frame }

    # (1) scroll: A full -> B dirty on A -> C full at same state.
    @vl.scroll_to(0)
    @input_text = @initial_text
    settle_render_full
    pixels_a = capture_pixels

    focus_list
    apply_wheel_event(-1)
    quads_dirty, culled = settle_render_dirty
    pixels_b = capture_pixels

    quads_full = settle_render_full
    pixels_c = capture_pixels
    M4DGdi32.SwapBuffers(@hdc)

    diff_pixels = m4d_pixel_diff(pixels_b, pixels_c)
    diff_a_vs_c = m4d_pixel_diff(pixels_a, pixels_c)

    # (2) theme switch: toggle T1 render vs programmatic T1 render, and a
    # round-trip back to T0 vs the direct T0 capture (A).
    reset_view_state
    settle_render_full
    focus_list
    apply_text_event('T'.ord.to_u32)
    settle_render_full
    pixels_toggle = capture_pixels

    reset_view_state
    @dark = !@initial_dark
    @theme = theme_of(@dark)
    @status = status_text
    settle_render_full
    pixels_direct = capture_pixels
    diff_theme = m4d_pixel_diff(pixels_toggle, pixels_direct)

    reset_view_state
    @dark = !@initial_dark
    @theme = theme_of(@dark)
    @status = status_text
    focus_list
    apply_text_event('T'.ord.to_u32)
    settle_render_full
    pixels_roundtrip = capture_pixels
    diff_theme_roundtrip = m4d_pixel_diff(pixels_roundtrip, pixels_a)

    # (3) steady-frame zero-alloc: 3 windows x N frames, GC.enable in ensure.
    alloc = run_alloc_probe(1000)

    # Leave the window in the initial state.
    reset_view_state
    @dark = @initial_dark
    @theme = theme_of(@dark)
    @status = status_text
    settle_render_full
    M4DGdi32.SwapBuffers(@hdc)
    TessellShot.save(@screenshot_path, @width, @height) unless @screenshot_path.empty?

    visible_avg = @vis_frames > 0 ? (@vis_sum.to_f64 / @vis_frames.to_f64) : 0.0
    pass_alloc = alloc[:delta_max] < 1000 && alloc[:delta_max] <= 256
    pass = diff_pixels == 0 && diff_a_vs_c > 0 && diff_theme == 0 &&
           diff_theme_roundtrip == 0 && pass_alloc
    line = String.build do |s|
      s << "frames=" << frames_target
      s << " rows=" << @rows
      s << " row_h=" << @row_h
      s << " viewport=" << @width << "x" << @height
      s << " list_viewport=" << @width << "x" << @list_h
      s << " theme=" << (@dark ? "dark" : "light")
      s << " dpi=" << @dpi_label
      s << " text_size=" << @text_size
      s << " visible_avg=" << sprintf("%.4f", visible_avg)
      s << " quads_dirty=" << quads_dirty
      s << " quads_full=" << quads_full
      s << " culled=" << culled
      s << " diff_pixels=" << diff_pixels
      s << " diff_A_vs_C=" << diff_a_vs_c
      s << " diff_theme=" << diff_theme
      s << " diff_theme_roundtrip=" << diff_theme_roundtrip
      s << " alloc_windows=[" << alloc[:seq][0] << "," << alloc[:seq][1] << "," << alloc[:seq][2] << "]"
      s << " retried=" << alloc[:retried]
      s << " attempt=" << alloc[:attempt]
      s << " scroll=" << @vl.scroll_y
      s << " a11y_nodes=" << @a11y_count
      s << " verify=" << (pass ? "pass" : "fail")
    end
    {pass, line}
  end

  private def reset_view_state : Nil
    @vl.scroll_to(0)
    @input_text = @initial_text
  end

  private def focus_list : Nil
    if node = @list_node
      @router.focus_manager.focus(node)
    end
  end

  private def run_alloc_probe(n : Int32) : NamedTuple(seq: Array(Int64), retried: Bool, attempt: Int32, delta_max: Int64)
    60.times { steady_frame }
    # Prime pass: run the full 3-window sequence once discarded, so first-run
    # noise (lazy driver/GC bookkeeping) is absorbed before the measured pass.
    prime_total = 0_i64
    pw = 0
    while pw < 6
      40.times { steady_frame }
      GC.collect
      GC.disable
      @seg.fill(0_i64)
      begin
        pbefore = GC.stats.bytes_since_gc.to_i64
        n.times { steady_frame }
        prime_total += GC.stats.bytes_since_gc.to_i64 - pbefore
      ensure
        GC.enable
      end
      puts "INSITU_PRIME pw=#{pw} pump=#{@seg[0]} input=#{@seg[1]} scroll=#{@seg[2]} ui=#{@seg[3]} rects=#{@seg[4]} draw=#{@seg[5]} consume=#{@seg[6]} swap=#{@seg[7]} seg_sum=#{@seg.sum} window=#{GC.stats.bytes_since_gc.to_i64 - pbefore}"
      pw += 1
    end
    puts "ALLOC_PRIME discarded_total=#{prime_total}"
    seq = [0_i64, 0_i64, 0_i64]
    seq1 = [0_i64, 0_i64, 0_i64]
    delta1 = 0_i64
    retried = false
    attempt = 1
    delta_work = 0_i64
    loop do
      w = 0
      while w < 3
        40.times { steady_frame }
        GC.collect
        GC.disable
        @seg.fill(0_i64)
        begin
          before = GC.stats.bytes_since_gc.to_i64
          n.times { steady_frame }
          seq[w] = GC.stats.bytes_since_gc.to_i64 - before
        ensure
          GC.enable
        end
        puts "INSITU w=#{w} pump=#{@seg[0]} input=#{@seg[1]} scroll=#{@seg[2]} ui=#{@seg[3]} rects=#{@seg[4]} draw=#{@seg[5]} consume=#{@seg[6]} swap=#{@seg[7]} seg_sum=#{@seg.sum} window=#{seq[w]}"
        w += 1
      end
      delta_work = seq[0]
      delta_work = seq[1] if seq[1] > delta_work
      delta_work = seq[2] if seq[2] > delta_work
      if attempt == 1
        seq1[0] = seq[0]
        seq1[1] = seq[1]
        seq1[2] = seq[2]
        delta1 = delta_work
        puts "ALLOC_ATTEMPT1 alloc_windows=[#{seq1[0]},#{seq1[1]},#{seq1[2]}] delta_max=#{delta1} attempt1=1 pass=#{delta1 < 1000 && delta1 <= 256} fail_reason=#{delta1 < 1000 && delta1 <= 256 ? "none" : (delta1 >= 1000 ? "delta>=1000" : "delta>256")}"
      end
      break if delta_work < 1000 && delta_work <= 256
      break if attempt >= 2
      retried = true
      attempt = 2
    end
    {seq: seq, retried: retried, attempt: attempt, delta_max: delta_work}
  end
end

frames_target = 120
verify = false
dark = false
dpi_label = "1.0"
scale = 1.0_f32
screenshot_path = ""
ARGV.each_with_index do |arg, i|
  if arg.starts_with?("--frames=")
    frames_target = arg.split("=", 2)[1].to_i
  elsif arg == "--frames" && i + 1 < ARGV.size
    frames_target = ARGV[i + 1].to_i
  elsif arg == "--verify"
    verify = true
  elsif arg.starts_with?("--theme=")
    dark = arg.split("=", 2)[1] == "dark"
  elsif arg.starts_with?("--dpi=")
    dpi_label = arg.split("=", 2)[1]
    scale = dpi_label.to_f32
  elsif arg.starts_with?("--screenshot=")
    screenshot_path = arg.split("=", 2)[1]
  elsif arg == "--screenshot" && i + 1 < ARGV.size
    screenshot_path = ARGV[i + 1]
  end
end

result_ch = Channel({Bool, String}).new

iso_ctx = Fiber::ExecutionContext::Isolated.new("tessell-app-demo") do
  begin
    hinstance = M4DKernel32.GetModuleHandleW(Pointer(UInt16).null)
    m4d_fail("GetModuleHandleW") if hinstance.null?

    class_name = m4d_to_wstr("TessellAppDemo")
    window_title = m4d_to_wstr("Tessell App Demo")

    wc = M4DUser32::WNDCLASSEXW.new
    wc.cbSize = sizeof(M4DUser32::WNDCLASSEXW).to_u32
    wc.style = CS_OWNDC
    wc.lpfnWndProc = M4D_WNDPROC
    wc.cbClsExtra = 0
    wc.cbWndExtra = 0
    wc.hInstance = hinstance
    wc.hIcon = Pointer(Void).null
    wc.hCursor = M4DUser32.LoadCursorW(Pointer(Void).null, IDC_ARROW)
    wc.hbrBackground = Pointer(Void).null
    wc.lpszMenuName = Pointer(UInt16).null
    wc.lpszClassName = class_name.to_unsafe
    wc.hIconSm = Pointer(Void).null
    atom = M4DUser32.RegisterClassExW(pointerof(wc))
    m4d_fail("RegisterClassExW") if atom == 0

    width = 800
    # Layout mirrors M4DApp: top_h = text_size + 32, list 600, status_h = text_size + 24.
    text_size_for_layout = Render::Dpi.size_px(16.0_f32, scale).to_i32
    height = text_size_for_layout + 32 + 600 + text_size_for_layout + 24
    rect = M4DUser32::RECT.new
    rect.left = 0
    rect.top = 0
    rect.right = width
    rect.bottom = height
    style = WS_OVERLAPPEDWINDOW
    M4DUser32.AdjustWindowRectEx(pointerof(rect), style, 0, 0)
    win_w = rect.right - rect.left
    win_h = rect.bottom - rect.top

    hwnd = M4DUser32.CreateWindowExW(0_u32, class_name.to_unsafe, window_title.to_unsafe,
      style | WS_VISIBLE, CW_USEDEFAULT, CW_USEDEFAULT, win_w, win_h,
      Pointer(Void).null, Pointer(Void).null, hinstance, Pointer(Void).null)
    m4d_fail("CreateWindowExW") if hwnd.null?
    M4DUser32.ShowWindow(hwnd, SW_SHOW)
    M4DUser32.UpdateWindow(hwnd)

    hdc = M4DUser32.GetDC(hwnd)
    m4d_fail("GetDC") if hdc.null?

    pfd = M4DGdi32::PIXELFORMATDESCRIPTOR.new
    pfd.nSize = sizeof(M4DGdi32::PIXELFORMATDESCRIPTOR).to_u16
    pfd.nVersion = 1_u16
    pfd.dwFlags = PFD_DRAW_TO_WINDOW | PFD_SUPPORT_OPENGL | PFD_DOUBLEBUFFER
    pfd.iPixelType = PFD_TYPE_RGBA
    pfd.cColorBits = 32_u8
    pfd.cDepthBits = 24_u8
    pfd.cStencilBits = 8_u8
    pfd.iLayerType = PFD_MAIN_PLANE
    pf = M4DGdi32.ChoosePixelFormat(hdc, pointerof(pfd))
    m4d_fail("ChoosePixelFormat") if pf == 0
    m4d_fail("SetPixelFormat") if M4DGdi32.SetPixelFormat(hdc, pf, pointerof(pfd)) == 0

    hglrc = M4DWGL.wglCreateContext(hdc)
    m4d_fail("wglCreateContext") if hglrc.null?
    m4d_fail("wglMakeCurrent") if M4DWGL.wglMakeCurrent(hdc, hglrc) == 0

    unless Text::FtMeasurer.available?
      result_ch.send({false, "error=ft_unavailable reason=#{Text::FtMeasurer.unavailable_reason.inspect} verify=fail"})
      next
    end

    app = M4DApp.new(hdc, dark, scale, dpi_label, screenshot_path)

    if verify
      pass, line = app.run_verify(frames_target)
      result_ch.send({pass, line})
    else
      frames_target.times do
        break if M4DState.quit_requested
        app.run_frame
      end
      TessellShot.save(screenshot_path, app.width, app.height) unless screenshot_path.empty?
      result_ch.send({true, "frames=#{frames_target} mode=interactive theme=#{dark ? "dark" : "light"} dpi=#{dpi_label} verify=n/a"})
    end

    app.pump_messages
    M4DWGL.wglMakeCurrent(Pointer(Void).null, Pointer(Void).null)
    M4DWGL.wglDeleteContext(hglrc)
    M4DUser32.ReleaseDC(hwnd, hdc)
    M4DUser32.DestroyWindow(hwnd) unless M4DState.quit_requested
  rescue ex
    bt = ex.backtrace?
    bt_s = bt ? bt.first(5).join(" | ") : ""
    result_ch.send({false, "error=exception message=#{ex.message.inspect} backtrace=#{bt_s.inspect} verify=fail"})
  end
end

ok, line = result_ch.receive
puts line
exit(ok ? 0 : 1)
