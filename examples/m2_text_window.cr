# M2-WP2d stage 2: text on screen via GL 1.1 immediate mode (R8 atlas -> GL_ALPHA)
# Reuses m0 window probe WGL/window pattern.
# Usage:
#   crystal run examples/m2_text_window.cr -- --frames=120 --verify
#   crystal run examples/m2_text_window.cr -- --emoji --frames=120 --verify
# Outputs (default): text_pixels_nonbg, cpu_coverage_sum, ratio, pixel_match, frame times p50/p95/p99
# Outputs (--emoji): emoji_quads, emoji_pixels_nonbg, emoji_pixel_match, frame_p50_ms (plus full mixed render evidence)
# Outputs (--emoji-color): emoji_color_quads/pixels/pixels_colored/dominant_rgb/batches/verify (COLR/CPAL RGBA path)
# If window/GL unavailable: records blocking error and exits 1 without faking pixel_match.

require "../src/tessell/text/ft_measurer"
require "../src/tessell/text/glyph_atlas"
require "../src/tessell/text/rasterizer"
require "../src/tessell/render/text_renderer"
require "../src/tessell/render/gl/gl_renderer"
require "./lib/shot"

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

def percentile(sorted : Array(Float64), p : Float64) : Float64
  return 0.0 if sorted.empty?
  idx = ((p / 100.0) * (sorted.size - 1)).round.to_i
  idx = 0 if idx < 0
  idx = sorted.size - 1 if idx >= sorted.size
  sorted[idx]
end

# cpu_coverage_sum: sum of nonzero alpha bytes in atlas page regions referenced by emitted drawable placements.
# Color placements read the RGBA page alpha byte (4B/px); gray placements read R8 coverage (1B/px).
def compute_cpu_coverage_sum(atlas : Tessell::Text::GlyphAtlas, sink : Array(Tessell::Text::GlyphPlacement)) : Int64
  sum = 0_i64
  sink.each do |p|
    next if p.w <= 0 || p.h <= 0
    slot = atlas.lookup(p.key, p.color)
    next unless slot
    ps = atlas.page_size
    y = 0
    while y < slot.h
      x = 0
      while x < slot.w
        if p.color
          data = atlas.rgba_page_data(slot.page)
          sum += 1 if data[((slot.y + y) * ps + (slot.x + x)) * 4 + 3] > 0_u8
        else
          data = atlas.page_data(slot.page)
          sum += 1 if data[(slot.y + y) * ps + (slot.x + x)] > 0_u8
        end
        x += 1
      end
      y += 1
    end
  end
  sum
end

# Color stats over a readback: colored pixels (max(r,g,b)-min(r,g,b)>30), dominant RGB among
# them (exact-tuple histogram), and a_opaque_ratio = non-bg pixels with readback alpha==255.
def count_color_stats(readback : Bytes, width : Int32, height : Int32) : NamedTuple(colored: Int64, dominant: String, a_opaque_ratio: Float64)
  total_px = width * height
  colored = 0_i64
  nonbg = 0_i64
  a255_nonbg = 0_i64
  hist = Hash(Tuple(Int32, Int32, Int32), Int32).new(0)
  i = 0
  while i < total_px
    off = i * 4
    r = readback[off].to_i
    g = readback[off + 1].to_i
    b = readback[off + 2].to_i
    a = readback[off + 3].to_i
    mx = r > g ? r : g
    mx = b if b > mx
    mn = r < g ? r : g
    mn = b if b < mn
    if mx - mn > 30
      colored += 1
      hist[{r, g, b}] += 1
    end
    if (r - 255).abs > 8 || (g - 255).abs > 8 || (b - 255).abs > 8
      nonbg += 1
      a255_nonbg += 1 if a == 255
    end
    i += 1
  end
  dom_r = 0
  dom_g = 0
  dom_b = 0
  dom_n = 0
  hist.each do |rgb, n|
    if n > dom_n
      dom_n = n
      dom_r = rgb[0]
      dom_g = rgb[1]
      dom_b = rgb[2]
    end
  end
  ratio = nonbg > 0 ? a255_nonbg.to_f64 / nonbg.to_f64 : 0.0
  {colored: colored, dominant: "#{dom_r},#{dom_g},#{dom_b}", a_opaque_ratio: ratio}
end

def count_nonbg(readback : Bytes, width : Int32, height : Int32, bg_r : Float32, bg_g : Float32, bg_b : Float32) : Int64
  text_pixels_nonbg = 0_i64
  total_px = width * height
  bg_ri = (bg_r * 255.0_f32).round.to_i
  bg_gi = (bg_g * 255.0_f32).round.to_i
  bg_bi = (bg_b * 255.0_f32).round.to_i
  i = 0
  while i < total_px
    off = i * 4
    r = readback[off].to_i
    g = readback[off + 1].to_i
    b = readback[off + 2].to_i
    dr = (r - bg_ri).abs
    dg = (g - bg_gi).abs
    db = (b - bg_bi).abs
    if dr > 8 || dg > 8 || db > 8
      text_pixels_nonbg += 1
    end
    i += 1
  end
  text_pixels_nonbg
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
emoji_mode = false
emoji_color_mode = false
screenshot_path = ""
ARGV.each_with_index do |arg, i|
  if arg.starts_with?("--frames=")
    frames_target = arg.split("=", 2)[1].to_i
  elsif arg == "--frames" && i + 1 < ARGV.size
    frames_target = ARGV[i + 1].to_i
  elsif arg == "--verify"
    verify_mode = true
  elsif arg == "--emoji"
    emoji_mode = true
  elsif arg == "--emoji-color"
    emoji_color_mode = true
  elsif arg.starts_with?("--screenshot=")
    screenshot_path = arg.split("=", 2)[1]
  elsif arg == "--screenshot" && i + 1 < ARGV.size
    screenshot_path = ARGV[i + 1]
  end
end

FONT_PATH = "C:/Windows/Fonts/msyh.ttc"
EMOJI_FONT_PATH = "C:/Windows/Fonts/seguiemj.ttf"
width = 800
height = 600
text_size = 32
text_x = 40.0_f32
text_y = 120.0_f32
bg_r = 1.0_f32; bg_g = 1.0_f32; bg_b = 1.0_f32

begin
  unless File.exists?(FONT_PATH)
    STDERR.puts "blocking=font_missing path=#{FONT_PATH}"
    exit 1
  end
  if (emoji_mode || emoji_color_mode) && !File.exists?(EMOJI_FONT_PATH)
    STDERR.puts "blocking=font_missing path=#{EMOJI_FONT_PATH}"
    exit 1
  end

  # --- text resources ---
  ft_c = Tessell::Text::FtMeasurer.open(FONT_PATH, 0)
  atlas_c = Tessell::Text::GlyphAtlas.new(1024, 4096)
  rast_c = Tessell::Text::Rasterizer.new(ft_c, atlas_c, 1)
  tr_c = Tessell::Render::TextRenderer.new(atlas_c, rast_c)
  sink_c = [] of Tessell::Text::GlyphPlacement

  ft_e : Tessell::Text::FtMeasurer? = nil
  atlas_e : Tessell::Text::GlyphAtlas? = nil
  rast_e : Tessell::Text::Rasterizer? = nil
  tr_e : Tessell::Render::TextRenderer? = nil
  sink_e = [] of Tessell::Text::GlyphPlacement
  emoji_text = "😀👍"
  rest_text = " Hello 你好"

  if emoji_mode || emoji_color_mode
    ft_e = Tessell::Text::FtMeasurer.open(EMOJI_FONT_PATH, 0)
    atlas_e = Tessell::Text::GlyphAtlas.new(1024, 4096)
    # --emoji-color opts in to the COLR/CPAL path (RGBA atlas pages); --emoji keeps the
    # pre-task-134 R8 gray-mask path (its 1171-pixel baseline must not move).
    rast_e = Tessell::Text::Rasterizer.new(ft_e.not_nil!, atlas_e.not_nil!, 1, 256, emoji_color_mode)
    tr_e = Tessell::Render::TextRenderer.new(atlas_e.not_nil!, rast_e.not_nil!)
  end

  # --- window + GL ---
  hinstance = LibKernel32.GetModuleHandleW(Pointer(UInt16).null)
  raise "GetModuleHandleW failed err=#{LibKernel32.GetLastError}" if hinstance.null?

  class_name = to_wstr(emoji_color_mode ? "TessellM2EmojiColorProbe" : emoji_mode ? "TessellM2EmojiProbe" : "TessellM2TextProbe")
  window_title = to_wstr(emoji_color_mode ? "Tessell M2 Emoji Color Probe" : emoji_mode ? "Tessell M2 Emoji Probe" : "Tessell M2 Text Probe")

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

  glr_c = Tessell::Render::GL::GlRenderer.new(atlas_c)
  glr_e : Tessell::Render::GL::GlRenderer? = (emoji_mode || emoji_color_mode) ? Tessell::Render::GL::GlRenderer.new(atlas_e.not_nil!) : nil

  last_readback = Bytes.new(width * height * 4)

  if emoji_color_mode
    te = tr_e.not_nil!
    ae = atlas_e.not_nil!
    ge = glr_e.not_nil!

    # build emoji-color segment (COLR/CPAL -> RGBA atlas pages, color_enabled=true)
    tex_e = ge.sync_atlas_textures
    pen_after = te.build_text(sink_e, emoji_text, text_x, text_y, text_size, width, height, tex_e)
    tex_e = ge.sync_atlas_textures
    pen_after = te.build_text(sink_e, emoji_text, text_x, text_y, text_size, width, height, tex_e)
    cpu_cov_e = compute_cpu_coverage_sum(ae, sink_e)
    emoji_color_quads = te.stats[:quads]
    emoji_color_batches = te.stats[:batches]

    # build rest segment (gray)
    tex_c = glr_c.sync_atlas_textures
    tr_c.build_text(sink_c, rest_text, pen_after, text_y, text_size, width, height, tex_c)
    tex_c = glr_c.sync_atlas_textures
    tr_c.build_text(sink_c, rest_text, pen_after, text_y, text_size, width, height, tex_c)

    # emoji-color-only measurement pass
    glr_c.begin_frame(width, height, bg_r, bg_g, bg_b, 1.0_f32) # clears
    ge.draw_text(te)
    glr_c.end_frame
    TessellGL.glPixelStorei(TessellGL::GL_PACK_ALIGNMENT, 1)
    TessellGL.glReadPixels(0, 0, width, height, TessellGL::GL_RGBA, TessellGL::GL_UNSIGNED_BYTE, last_readback.to_unsafe.as(Void*))
    emoji_color_pixels = count_nonbg(last_readback, width, height, bg_r, bg_g, bg_b)
    cs = count_color_stats(last_readback, width, height)
    emoji_color_pixels_colored = cs[:colored]
    emoji_color_dominant_rgb = cs[:dominant]
    a_opaque_ratio = cs[:a_opaque_ratio]
    emoji_color_ratio = cpu_cov_e > 0 ? (emoji_color_pixels.to_f64 / cpu_cov_e.to_f64) : 0.0
    emoji_color_verify = (emoji_color_pixels > 0) && (emoji_color_pixels_colored > 0) &&
                         (a_opaque_ratio > 0.5) && (emoji_color_ratio >= 0.5) && (emoji_color_ratio <= 1.5)

    # timed frames: render full mixed string
    frame_times = [] of Float64
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

      tex_e = ge.sync_atlas_textures
      te.build_text(sink_e, emoji_text, text_x, text_y, text_size, width, height, tex_e)
      tex_c = glr_c.sync_atlas_textures
      tr_c.build_text(sink_c, rest_text, pen_after, text_y, text_size, width, height, tex_c)

      glr_c.begin_frame(width, height, bg_r, bg_g, bg_b, 1.0_f32)
      ge.draw_text(te)
      glr_c.draw_text(tr_c)
      glr_c.end_frame

      TessellGL.glPixelStorei(TessellGL::GL_PACK_ALIGNMENT, 1)
      TessellGL.glReadPixels(0, 0, width, height, TessellGL::GL_RGBA, TessellGL::GL_UNSIGNED_BYTE, last_readback.to_unsafe.as(Void*))

      if LibGdi32.SwapBuffers(hdc) != 0
        swap_ok += 1
      end
      frames_done += 1
      frame_times << (Time.instant - t0).total_milliseconds
    end

    mixed_nonbg = count_nonbg(last_readback, width, height, bg_r, bg_g, bg_b)
    sorted = frame_times.sort
    p50 = percentile(sorted, 50.0)
    p95 = percentile(sorted, 95.0)
    p99 = percentile(sorted, 99.0)

    TessellShot.save(screenshot_path, width, height) unless screenshot_path.empty?
    ge.delete_textures
    glr_c.delete_textures
    LibWGL.wglMakeCurrent(Pointer(Void).null, Pointer(Void).null)
    LibWGL.wglDeleteContext(hglrc)
    LibUser32.ReleaseDC(hwnd, hdc)
    LibUser32.DestroyWindow(hwnd) unless ProbeState.quit_requested
    ft_e.not_nil!.close
    ft_c.close

    puts "emoji_color_quads=#{emoji_color_quads} emoji_color_pixels=#{emoji_color_pixels} emoji_color_pixels_colored=#{emoji_color_pixels_colored} emoji_color_dominant_rgb=#{emoji_color_dominant_rgb} emoji_color_batches=#{emoji_color_batches} emoji_color_verify=#{emoji_color_verify} a_opaque_ratio=#{a_opaque_ratio} emoji_color_ratio=#{emoji_color_ratio} cpu_cov=#{cpu_cov_e} mixed_pixels_nonbg=#{mixed_nonbg} frames=#{frames_done} swapbuffers=#{swap_ok} pen_after_emoji_x=#{pen_after} text_quads=#{tr_c.stats[:quads]} frame_p50_ms=#{p50} frame_p95_ms=#{p95} frame_p99_ms=#{p99}"
    puts "emoji_color_note=rendered \"😀👍 Hello 你好\" with COLR/CPAL color glyphs (seguiemj.ttf) into RGBA atlas pages + gray text (msyh.ttc); color texel is premultiplied RGBA submitted with glColor4f(1,1,1,1) (no second multiply); gray path unchanged R8->GL_INTENSITY with vertex tint. a_opaque_ratio = non-bg pixels with readback alpha==255 (opaque canvas is the documented side effect of the premultiplied blend)."
    puts "gl_path=GL1.1_compat R8->GL_INTENSITY_blend_one_minus_src_alpha + RGBA_premultiplied_blend_one_minus_src_alpha glPixelStorei(GL_UNPACK_ALIGNMENT,1) glTexCoord2f/glVertex2f"

    if verify_mode
      exit(emoji_color_verify ? 0 : 1)
    else
      exit(0)
    end
  elsif emoji_mode
    te = tr_e.not_nil!
    ae = atlas_e.not_nil!
    ge = glr_e.not_nil!

    # build emoji segment
    tex_e = ge.sync_atlas_textures
    pen_after = te.build_text(sink_e, emoji_text, text_x, text_y, text_size, width, height, tex_e)
    tex_e = ge.sync_atlas_textures
    pen_after = te.build_text(sink_e, emoji_text, text_x, text_y, text_size, width, height, tex_e)
    cpu_cov_e = compute_cpu_coverage_sum(ae, sink_e)
    emoji_quads = te.stats[:quads]

    # build rest segment
    tex_c = glr_c.sync_atlas_textures
    tr_c.build_text(sink_c, rest_text, pen_after, text_y, text_size, width, height, tex_c)
    tex_c = glr_c.sync_atlas_textures
    tr_c.build_text(sink_c, rest_text, pen_after, text_y, text_size, width, height, tex_c)

    # emoji-only measurement pass
    glr_c.begin_frame(width, height, bg_r, bg_g, bg_b, 1.0_f32) # clears
    ge.draw_text(te)
    glr_c.end_frame
    TessellGL.glPixelStorei(TessellGL::GL_PACK_ALIGNMENT, 1)
    TessellGL.glReadPixels(0, 0, width, height, TessellGL::GL_RGBA, TessellGL::GL_UNSIGNED_BYTE, last_readback.to_unsafe.as(Void*))
    emoji_pixels_nonbg = count_nonbg(last_readback, width, height, bg_r, bg_g, bg_b)
    emoji_ratio = cpu_cov_e > 0 ? (emoji_pixels_nonbg.to_f64 / cpu_cov_e.to_f64) : 0.0
    emoji_pixel_match = (emoji_pixels_nonbg > 0) && (emoji_ratio >= 0.5) && (emoji_ratio <= 1.5)

    # timed frames: render full mixed string
    frame_times = [] of Float64
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

      tex_e = ge.sync_atlas_textures
      te.build_text(sink_e, emoji_text, text_x, text_y, text_size, width, height, tex_e)
      tex_c = glr_c.sync_atlas_textures
      tr_c.build_text(sink_c, rest_text, pen_after, text_y, text_size, width, height, tex_c)

      glr_c.begin_frame(width, height, bg_r, bg_g, bg_b, 1.0_f32)
      ge.draw_text(te)
      glr_c.draw_text(tr_c)
      glr_c.end_frame

      TessellGL.glPixelStorei(TessellGL::GL_PACK_ALIGNMENT, 1)
      TessellGL.glReadPixels(0, 0, width, height, TessellGL::GL_RGBA, TessellGL::GL_UNSIGNED_BYTE, last_readback.to_unsafe.as(Void*))

      if LibGdi32.SwapBuffers(hdc) != 0
        swap_ok += 1
      end
      frames_done += 1
      frame_times << (Time.instant - t0).total_milliseconds
    end

    mixed_nonbg = count_nonbg(last_readback, width, height, bg_r, bg_g, bg_b)
    sorted = frame_times.sort
    p50 = percentile(sorted, 50.0)
    p95 = percentile(sorted, 95.0)
    p99 = percentile(sorted, 99.0)

    TessellShot.save(screenshot_path, width, height) unless screenshot_path.empty?
    ge.delete_textures
    glr_c.delete_textures
    LibWGL.wglMakeCurrent(Pointer(Void).null, Pointer(Void).null)
    LibWGL.wglDeleteContext(hglrc)
    LibUser32.ReleaseDC(hwnd, hdc)
    LibUser32.DestroyWindow(hwnd) unless ProbeState.quit_requested
    ft_e.not_nil!.close
    ft_c.close

    puts "emoji_quads=#{emoji_quads} emoji_pixels_nonbg=#{emoji_pixels_nonbg} emoji_pixel_match=#{emoji_pixel_match} frame_p50_ms=#{p50} frame_p95_ms=#{p95} frame_p99_ms=#{p99} emoji_cpu_coverage_sum=#{cpu_cov_e} emoji_ratio=#{emoji_ratio} mixed_pixels_nonbg=#{mixed_nonbg} frames=#{frames_done} swapbuffers=#{swap_ok} pen_after_emoji_x=#{pen_after} text_quads=#{tr_c.stats[:quads]}"
    puts "emoji_note=rendered \"😀👍 Hello 你好\" as emoji(seguiemj.ttf)+text(msyh.ttc) segments; emoji metrics from emoji-only pass (RGB delta>8 vs white bg, ratio tolerance [0.5,1.5]); display path R8->GL_INTENSITY with premultiplied blend (GL_ONE,GL_ONE_MINUS_SRC_ALPHA), gray coverage. If seguiemj bitmap were BGRA/color-only, this path could not show color and pixel_match would be false (not fabricated)."
    puts "gl_path=GL1.1_compat R8->GL_INTENSITY_blend_one_minus_src_alpha glPixelStorei(GL_UNPACK_ALIGNMENT,1) glTexCoord2f/glVertex2f"

    if verify_mode
      exit(emoji_pixel_match ? 0 : 1)
    else
      exit(0)
    end
  else
    # default non-emoji path (existing behavior)
    text_str = "Hello 你好 Tessell"

    tex_ids = glr_c.sync_atlas_textures
    pen_end = tr_c.build_text(sink_c, text_str, text_x, text_y, text_size, width, height, tex_ids)
    tex_ids = glr_c.sync_atlas_textures
    pen_end = tr_c.build_text(sink_c, text_str, text_x, text_y, text_size, width, height, tex_ids)

    cpu_coverage_sum = compute_cpu_coverage_sum(atlas_c, sink_c)

    frame_times = [] of Float64
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

      tex_ids = glr_c.sync_atlas_textures
      tr_c.build_text(sink_c, text_str, text_x, text_y, text_size, width, height, tex_ids)

      glr_c.begin_frame(width, height, bg_r, bg_g, bg_b, 1.0_f32)
      glr_c.draw_text(tr_c)
      glr_c.end_frame

      TessellGL.glPixelStorei(TessellGL::GL_PACK_ALIGNMENT, 1)
      TessellGL.glReadPixels(0, 0, width, height, TessellGL::GL_RGBA, TessellGL::GL_UNSIGNED_BYTE, last_readback.to_unsafe.as(Void*))

      if LibGdi32.SwapBuffers(hdc) != 0
        swap_ok += 1
      end
      frames_done += 1
      frame_times << (Time.instant - t0).total_milliseconds
    end

    text_pixels_nonbg = count_nonbg(last_readback, width, height, bg_r, bg_g, bg_b)
    ratio = cpu_coverage_sum > 0 ? (text_pixels_nonbg.to_f64 / cpu_coverage_sum.to_f64) : 0.0
    pixel_match = (text_pixels_nonbg > 0) && (ratio >= 0.5) && (ratio <= 1.5)

    sorted = frame_times.sort
    p50 = percentile(sorted, 50.0)
    p95 = percentile(sorted, 95.0)
    p99 = percentile(sorted, 99.0)

    TessellShot.save(screenshot_path, width, height) unless screenshot_path.empty?
    glr_c.delete_textures
    LibWGL.wglMakeCurrent(Pointer(Void).null, Pointer(Void).null)
    LibWGL.wglDeleteContext(hglrc)
    LibUser32.ReleaseDC(hwnd, hdc)
    LibUser32.DestroyWindow(hwnd) unless ProbeState.quit_requested
    ft_c.close

    puts "text_pixels_nonbg=#{text_pixels_nonbg} cpu_coverage_sum=#{cpu_coverage_sum} ratio=#{ratio} pixel_match=#{pixel_match} frames=#{frames_done} swapbuffers=#{swap_ok} frame_p50_ms=#{p50} frame_p95_ms=#{p95} frame_p99_ms=#{p99} pen_end_x=#{pen_end} quads=#{tr_c.stats[:quads]} batches=#{tr_c.stats[:batches]}"
    puts "criterion_note=non-bg counted as RGB delta>8 from white background; cpu_coverage_sum counts nonzero R8 atlas bytes over rendered glyph rects; ratio tolerance [0.5,1.5] accounts for GL_LINEAR filtering, blending edge coverage, and y-axis/sample-position differences vs source bitmap"
    puts "gl_path=GL1.1_compat R8->GL_INTENSITY_blend_one_minus_src_alpha glPixelStorei(GL_UNPACK_ALIGNMENT,1) glTexCoord2f/glVertex2f"

    if verify_mode
      exit(pixel_match ? 0 : 1)
    else
      exit(0)
    end
  end
rescue ex
  STDERR.puts "blocking=exception message=#{ex.message.inspect} backtrace_first=#{(ex.backtrace? || [] of String).first?.inspect}"
  STDERR.puts "note=window_or_gl_unavailable_or_runtime_error; pixel_match not fabricated"
  exit 1
end
