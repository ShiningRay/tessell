# m3_sdl_dirty_probe — draw_polygon dirty 裁切像素探针（issue #2，SDL/macOS 可跑）。
#
# 方法论（比照 app_demo --verify 的 A/C 对比，改造为可暴露脏区外误写）：
#   A：整帧渲染（bg + 三角形多边形）→ capture A。
#   B0：整帧只清底色（无多边形）→ capture base。
#   B：begin_frame([dirty]) 后 draw_polygon 同一三角形 → capture B。
#       正确实现：dirty 内 == A 内（bg+多边形），dirty 外 == base（未动）。
#       缺陷实现：颜色覆盖包围盒写出脏区 → dirty 外出现多边形像素。
# 退出码 0=pass，1=fail。Windows 真机回归仍走 examples/m3_path_window --verify。
#
# 运行：crystal build examples/m3_sdl_dirty_probe.cr -o bin/m3_sdl_dirty_probe
#       ./bin/m3_sdl_dirty_probe

require "../src/tessell"
require "../src/tessell/render/gl/gl_backend"
require "../src/tessell/render/polygon"
require "./lib/shot"

module DirtyProbe
  @[Link("SDL2")]
  lib SDL2
    fun SDL_Init(flags : UInt32) : Int32
    fun SDL_CreateWindow(title : UInt8*, x : Int32, y : Int32, w : Int32, h : Int32,
                         flags : UInt32) : Void*
    fun SDL_GL_CreateContext(window : Void*) : Void*
    fun SDL_GL_MakeCurrent(window : Void*, context : Void*) : Int32
    fun SDL_GL_SetAttribute(attr : UInt32, value : Int32) : Int32
    fun SDL_DestroyWindow(window : Void*) : Void
    fun SDL_GL_DeleteContext(context : Void*) : Void
    fun SDL_Quit : Void
    fun SDL_GetError : UInt8*
  end

  VIDEO_INIT = 0x20_u32
  WINDOW_OPENGL  = 0x2_u32
  WINDOW_HIDDEN  = 0x8_u32
  GL_DOUBLEBUFFER  = 5_u32
  GL_STENCIL_SIZE  = 7_u32
  GL_CONTEXT_MAJOR_VERSION = 17_u32
  GL_CONTEXT_MINOR_VERSION = 18_u32
  GL_CONTEXT_PROFILE_MASK  = 21_u32
  GL_CONTEXT_PROFILE_COMPATIBILITY = 0x0002_u32

  W = 320
  H = 240

  # 三角形：横跨左右两半，dirty 只覆盖左半，右半必须保持 bg。
  TRIANGLE = [
    Tessell::Point.new(40.0_f32, 30.0_f32),
    Tessell::Point.new(280.0_f32, 60.0_f32),
    Tessell::Point.new(160.0_f32, 210.0_f32),
  ]
  DIRTY = Tessell::Rect.new(0.0_f32, 0.0_f32, 160.0_f32, 120.0_f32)
  POLY_COLOR = 0xff2222ff_u32 # 0xRRGGBBAA，红色不透明

  def self.capture : Bytes
    buf = Bytes.new(W * H * 4)
    TessellGL.glPixelStorei(TessellGL::GL_PACK_ALIGNMENT, 1)
    TessellGL.glFinish
    TessellGL.glReadPixels(0, 0, W, H, TessellGL::GL_RGBA, TessellGL::GL_UNSIGNED_BYTE,
      buf.to_unsafe.as(Void*))
    buf
  end

  def self.render_full(backend : Tessell::Render::GL::GLBackend) : Nil
    backend.begin_frame(nil, Tessell::Render::Theme.light)
    backend.draw_polygon(TRIANGLE, POLY_COLOR)
    backend.end_frame
  end

  def self.render_bg_only(backend : Tessell::Render::GL::GLBackend) : Nil
    backend.begin_frame(nil, Tessell::Render::Theme.light)
    backend.end_frame
  end

  def self.render_dirty(backend : Tessell::Render::GL::GLBackend) : Nil
    backend.begin_frame([DIRTY], Tessell::Render::Theme.light)
    backend.draw_polygon(TRIANGLE, POLY_COLOR)
    backend.end_frame
  end

  def self.pixel_at(buf : Bytes, x : Int32, y : Int32) : UInt32
    # GL 坐标系 y 翻转（ReadPixels 自底向上）；Tessell y-down。
    gl_y = H - 1 - y
    i = (gl_y * W + x) * 4
    (buf[i].to_u32 << 24) | (buf[i + 1].to_u32 << 16) |
      (buf[i + 2].to_u32 << 8) | buf[i + 3].to_u32
  end

  def self.diff_region(a : Bytes, b : Bytes, rect : Tessell::Rect) : Int32
    x0 = rect.origin.x.to_i
    y0 = rect.origin.y.to_i
    x1 = Math.min(rect.max_x.to_i, W)
    y1 = Math.min(rect.max_y.to_i, H)
    diff = 0
    y = y0
    while y < y1
      x = x0
      while x < x1
        diff += 1 if pixel_at(a, x, y) != pixel_at(b, x, y)
        x += 1
      end
      y += 1
    end
    diff
  end

  def self.run : Int32
    unless SDL2.SDL_Init(VIDEO_INIT) == 0
      STDERR.puts "SDL_Init failed"
      return 1
    end
    SDL2.SDL_GL_SetAttribute(GL_DOUBLEBUFFER, 1)
    SDL2.SDL_GL_SetAttribute(GL_STENCIL_SIZE, 8)
    SDL2.SDL_GL_SetAttribute(GL_CONTEXT_MAJOR_VERSION, 2)
    SDL2.SDL_GL_SetAttribute(GL_CONTEXT_MINOR_VERSION, 1)
    SDL2.SDL_GL_SetAttribute(GL_CONTEXT_PROFILE_MASK, GL_CONTEXT_PROFILE_COMPATIBILITY)
    window = SDL2.SDL_CreateWindow("dirty-probe", 0, 0, W, H,
      WINDOW_OPENGL | WINDOW_HIDDEN)
    if window.null?
      STDERR.puts "SDL_CreateWindow failed: #{String.new(SDL2.SDL_GetError)}"
      SDL2.SDL_Quit
      return 1
    end
    context = SDL2.SDL_GL_CreateContext(window)
    if context.null?
      STDERR.puts "SDL_GL_CreateContext failed"
      SDL2.SDL_DestroyWindow(window)
      SDL2.SDL_Quit
      return 1
    end
    SDL2.SDL_GL_MakeCurrent(window, context)

    backend = Tessell::Render::GL::GLBackend.new
    backend.init(W, H)
    backend.resize(W, H)

    DirtyProbe.render_full(backend)
    pixels_a = DirtyProbe.capture
    DirtyProbe.render_bg_only(backend)
    base = DirtyProbe.capture
    DirtyProbe.render_dirty(backend)
    pixels_b = DirtyProbe.capture

    # 脏区内：B 必须与 A 一致（bg+多边形正确重画）。
    inside_diff = DirtyProbe.diff_region(pixels_a, pixels_b, DIRTY)
    # 脏区外（补集：右条带 + 左下条带）：B 必须与纯底色一致（覆盖不得写出脏区）。
    outside_diff = DirtyProbe.diff_region(base, pixels_b,
      Tessell::Rect.new(160.0_f32, 0.0_f32, 160.0_f32, 240.0_f32)) +
      DirtyProbe.diff_region(base, pixels_b,
        Tessell::Rect.new(0.0_f32, 120.0_f32, 160.0_f32, 120.0_f32))
    # A 与 base 在脏区外应不同（整帧多边形 vs 纯底色），证明用例本身有区分度。
    a_vs_base_outside = DirtyProbe.diff_region(pixels_a, base,
      Tessell::Rect.new(160.0_f32, 0.0_f32, 160.0_f32, 240.0_f32)) +
      DirtyProbe.diff_region(pixels_a, base,
        Tessell::Rect.new(0.0_f32, 120.0_f32, 160.0_f32, 120.0_f32))

    # dirty 内 base vs A 也应不同（那里有三角形）
    a_vs_base_inside = DirtyProbe.diff_region(pixels_a, base, DIRTY)

    ok = inside_diff == 0 && outside_diff == 0 &&
         a_vs_base_outside > 0 && a_vs_base_inside > 0
    puts "M3_SDL_DIRTY_PROBE inside_diff=#{inside_diff} outside_diff=#{outside_diff} " \
         "a_vs_base_inside=#{a_vs_base_inside} a_vs_base_outside=#{a_vs_base_outside} " \
         "stencil=#{backend.stats.stencil_fills} verify=#{ok ? "pass" : "fail"}"

    SDL2.SDL_GL_DeleteContext(context)
    SDL2.SDL_DestroyWindow(window)
    SDL2.SDL_Quit
    ok ? 0 : 1
  end
end

exit DirtyProbe.run
