# SDL2 + OpenGL demo host for Tessell Kit apps.
#
# 该文件只服务 examples，不进入 shard 核心。它负责：
#   - SDL2 窗口/事件循环/GL context
#   - 把 SDL 事件翻译成 Tessell::Input::Event
#   - 用 GLPainter 把 Kit::Painter 命令交给 GLBackend（形状 + 文本）
#
# 运行（macOS，Homebrew SDL2）：
#   crystal run examples/app_calculator.cr --link-flags "-L/opt/homebrew/lib"
# Windows 需要 SDL2 开发库并把 SDL2.dll 放到 PATH/可执行目录。
#
# 文本渲染仍走核心 FreeType/HarfBuzz + GLBackend；macOS 已在本机实测可测字与上屏。

require "../../src/tessell/kit"
require "../../src/tessell/render/gl/gl_backend"
require "../../src/tessell/render/text_renderer"
require "../../src/tessell/text/ft_measurer"
require "../../src/tessell/text/glyph_atlas"
require "../../src/tessell/text/rasterizer"
require "../../tools/lib/png"

module TessellKitSdl
  @[Link("SDL2")]
  lib LibSDL
    struct Keysym
      scancode : Int32
      sym : Int32
      mod : UInt16
      unused : UInt32
    end

    struct KeyboardEvent
      type : UInt32
      timestamp : UInt32
      window_id : UInt32
      state : UInt8
      repeat : UInt8
      padding2 : UInt8
      padding3 : UInt8
      keysym : Keysym
    end

    struct TextInputEvent
      type : UInt32
      timestamp : UInt32
      window_id : UInt32
      text : StaticArray(UInt8, 32)
    end

    struct MouseMotionEvent
      type : UInt32
      timestamp : UInt32
      window_id : UInt32
      which : UInt32
      state : UInt32
      x : Int32
      y : Int32
      xrel : Int32
      yrel : Int32
    end

    struct MouseButtonEvent
      type : UInt32
      timestamp : UInt32
      window_id : UInt32
      which : UInt32
      button : UInt8
      state : UInt8
      clicks : UInt8
      padding1 : UInt8
      x : Int32
      y : Int32
    end

    struct MouseWheelEvent
      type : UInt32
      timestamp : UInt32
      window_id : UInt32
      which : UInt32
      x : Int32
      y : Int32
      direction : UInt32
      precise_x : Float32
      precise_y : Float32
      mouse_x : Int32
      mouse_y : Int32
    end

    struct WindowEvent
      type : UInt32
      timestamp : UInt32
      window_id : UInt32
      event : UInt8
      padding1 : UInt8
      padding2 : UInt8
      padding3 : UInt8
      data1 : Int32
      data2 : Int32
    end

    # SDL_Event is a 56-byte union on 64-bit builds. We only read the first
    # word and cast to the concrete event structs above.
    struct Event
      type : UInt32
      padding : StaticArray(UInt8, 52)
    end

    fun SDL_Init(flags : UInt32) : Int32
    fun SDL_Quit : Void
    fun SDL_GetError : UInt8*
    fun SDL_CreateWindow(title : UInt8*, x : Int32, y : Int32,
                         w : Int32, h : Int32, flags : UInt32) : Void*
    fun SDL_DestroyWindow(window : Void*) : Void
    fun SDL_GetWindowSize(window : Void*, w : Int32*, h : Int32*) : Void
    fun SDL_GL_SetAttribute(attr : Int32, value : Int32) : Int32
    fun SDL_GL_CreateContext(window : Void*) : Void*
    fun SDL_GL_DeleteContext(context : Void*) : Void
    fun SDL_GL_MakeCurrent(window : Void*, context : Void*) : Int32
    fun SDL_GL_SetSwapInterval(interval : Int32) : Int32
    fun SDL_GL_SwapWindow(window : Void*) : Void
    fun SDL_GL_GetDrawableSize(window : Void*, w : Int32*, h : Int32*) : Void
    fun SDL_PollEvent(event : Event*) : Int32
    fun SDL_StartTextInput : Void
    fun SDL_StopTextInput : Void
    fun SDL_Delay(ms : UInt32) : Void
    fun SDL_GetTicks : UInt32
    fun SDL_GetClipboardText : UInt8*
    fun SDL_SetClipboardText(text : UInt8*) : Int32
    fun SDL_free(ptr : Void*) : Void
  end

  SDL_INIT_VIDEO           = 0x00000020_u32
  SDL_INIT_EVENTS          = 0x00004000_u32
  SDL_WINDOW_OPENGL        = 0x00000002_u32
  SDL_WINDOW_SHOWN         = 0x00000004_u32
  SDL_WINDOW_RESIZABLE     = 0x00000020_u32
  SDL_WINDOW_ALLOW_HIGHDPI = 0x00002000_u32
  SDL_WINDOWPOS_CENTERED   = 0x2FFF0000_u32

  SDL_QUIT                     = 0x100_u32
  SDL_WINDOWEVENT              = 0x200_u32
  SDL_KEYDOWN                  = 0x300_u32
  SDL_KEYUP                    = 0x301_u32
  SDL_TEXTINPUT                = 0x303_u32
  SDL_MOUSEMOTION              = 0x400_u32
  SDL_MOUSEBUTTONDOWN          = 0x401_u32
  SDL_MOUSEBUTTONUP            = 0x402_u32
  SDL_MOUSEWHEEL               = 0x403_u32
  SDL_WINDOWEVENT_CLOSE        =  0x0E_u32
  SDL_WINDOWEVENT_RESIZED      = 0x201_u32
  SDL_WINDOWEVENT_SIZE_CHANGED = 0x202_u32

  SDL_GL_DOUBLEBUFFER                  =      5_i32
  SDL_GL_DEPTH_SIZE                    =      6_i32
  SDL_GL_STENCIL_SIZE                  =      7_i32
  SDL_GL_CONTEXT_MAJOR_VERSION         =     17_i32
  SDL_GL_CONTEXT_MINOR_VERSION         =     18_i32
  SDL_GL_CONTEXT_PROFILE_MASK          =     21_i32
  SDL_GL_CONTEXT_PROFILE_COMPATIBILITY = 0x0002_i32

  KMOD_SHIFT = 0x0003_u16
  KMOD_CTRL  = 0x00C0_u16
  KMOD_ALT   = 0x0100_u16
  KMOD_GUI   = 0x0400_u16

  SDLK_BACKSPACE =          8
  SDLK_TAB       =          9
  SDLK_RETURN    =         13
  SDLK_ESCAPE    =         27
  SDLK_SPACE     =         32
  SDLK_DELETE    =        127
  SDLK_LEFT      = 0x40000050
  SDLK_RIGHT     = 0x4000004F
  SDLK_UP        = 0x40000052
  SDLK_DOWN      = 0x40000051
  SDLK_HOME      = 0x4000004A
  SDLK_END       = 0x4000004D
  SDLK_PAGEUP    = 0x4000004B
  SDLK_PAGEDOWN  = 0x4000004E
  SDLK_a         =         97
  SDLK_b         =         98
  SDLK_c         =         99
  SDLK_t         =        116
  SDLK_v         =        118
  SDLK_x         =        120
  SDLK_z         =        122
  SDLK_0         =         48
  SDLK_1         =         49
  SDLK_2         =         50
  SDLK_3         =         51
  SDLK_4         =         52
  SDLK_5         =         53
  SDLK_6         =         54
  SDLK_7         =         55
  SDLK_8         =         56
  SDLK_9         =         57

  class SdlClipboard < Tessell::Kit::Clipboard
    def get : String?
      ptr = LibSDL.SDL_GetClipboardText
      return nil if ptr.null?
      text = String.new(ptr)
      LibSDL.SDL_free(ptr.as(Void*))
      text
    end

    def set(text : String) : Nil
      LibSDL.SDL_SetClipboardText(text.to_unsafe)
    end
  end

  class GLPainter < Tessell::Kit::Painter
    getter scale : Float32

    @draw : Tessell::Kit::DrawListPainter
    @renderer : Tessell::Render::TextRenderer
    @atlas : Tessell::Text::GlyphAtlas
    @width : Int32
    @height : Int32
    @scale : Float32
    @sink : Array(Tessell::Text::GlyphPlacement)
    # per-text-call batch boundary snapshots (issue #15): text quads stay
    # batched, but flush splits them at each text() call site so shapes and
    # text submit in exact command order
    @text_marks : Array(Int32)
    @submitted_batches : Int32

    def initialize(@renderer : Tessell::Render::TextRenderer,
                   @atlas : Tessell::Text::GlyphAtlas,
                   @width : Int32, @height : Int32, @scale : Float32)
      @draw = Tessell::Kit::DrawListPainter.new
      @sink = [] of Tessell::Text::GlyphPlacement
      @text_marks = [] of Int32
      @submitted_batches = 0
    end

    def resize(width : Int32, height : Int32, scale : Float32) : Nil
      @width = width
      @height = height
      @scale = scale
    end

    def fill_rect(rect : Tessell::Rect, color : UInt32) : Nil
      @draw.fill_rect(scale_rect(rect), color)
    end

    def stroke_rect(rect : Tessell::Rect, color : UInt32, width : Float32 = 1.0_f32) : Nil
      @draw.stroke_rect(scale_rect(rect), color, width * @scale)
    end

    def fill_round_rect(rect : Tessell::Rect, radius : Float32, color : UInt32) : Nil
      @draw.fill_round_rect(scale_rect(rect), radius * @scale, color)
    end

    def stroke_round_rect(rect : Tessell::Rect, radius : Float32, color : UInt32,
                          width : Float32 = 1.0_f32) : Nil
      @draw.stroke_round_rect(scale_rect(rect), radius * @scale, color, width * @scale)
    end

    def line(x1 : Float32, y1 : Float32, x2 : Float32, y2 : Float32,
             color : UInt32, width : Float32 = 1.0_f32) : Nil
      @draw.line(x1 * @scale, y1 * @scale, x2 * @scale, y2 * @scale,
        color, width * @scale)
    end

    def text(x : Float32, baseline_y : Float32, text : String,
             color : UInt32, size : Float32) : Nil
      px_size = (size * @scale).round.to_i
      return if px_size <= 0
      dx = x * @scale
      dy = baseline_y * @scale
      @renderer.append_text_cached(@sink, text, dx, dy, px_size, @width, @height, color)
      # Marker in the command list keeps call-order z-order and carries the
      # active clip for scissoring (issue #15). draw_draw_list skips Text
      # commands, so the marker is never drawn as geometry. The mark snapshot
      # lets flush submit exactly this call's text batches.
      @draw.text(dx, dy, text, color, px_size.to_f32)
      @text_marks << @renderer.batch_count
    end

    def push_clip(rect : Tessell::Rect) : Nil
      @draw.push_clip(scale_rect(rect))
    end

    def pop_clip : Nil
      @draw.pop_clip
    end

    def flush(backend : Tessell::Render::GL::GLBackend) : Nil
      # Dynamic text inserts glyphs into existing pages; page_count is not a
      # change signal (issue #1). sync_atlas_dirty re-uploads only pages whose
      # content revision changed.
      backend.sync_atlas_dirty(@atlas)
      # Issue #15: command order == paint order. Walk the list; a Text marker
      # flushes the pending shape segment first, then exactly the text batches
      # recorded for that call (scissored to the marker's clip). Later fills
      # cover earlier text; text is clipped at scroll edges by the backend.
      @submitted_batches = 0
      list = @draw.list
      seg = 0
      i = 0
      mark = 0
      while i < list.size
        cmd = list[i]
        if cmd.kind == Tessell::Render::CmdKind::Text && mark < @text_marks.size
          backend.draw_draw_list(list, seg, i - seg) if i > seg
          backend.draw_text(@renderer.vertices, @renderer.batch_runs,
            @text_marks[mark], @submitted_batches, cmd.clip)
          @submitted_batches = @text_marks[mark]
          mark += 1
          seg = i + 1
        end
        i += 1
      end
      backend.draw_draw_list(list, seg, list.size - seg) if list.size > seg
      @draw.reset
      @renderer.reset
      @text_marks.clear
    end

    def clip_depth : Int32
      @draw.clip_depth
    end

    private def scale_rect(rect : Tessell::Rect) : Tessell::Rect
      Tessell::Rect.new(rect.origin.x * @scale, rect.origin.y * @scale,
        rect.size.width * @scale, rect.size.height * @scale)
    end
  end

  abstract class KitDemoApp
    abstract def title : String
    abstract def build_root(metrics : Tessell::Kit::TextMetrics,
                            clipboard : Tessell::Kit::Clipboard) : Tessell::Kit::Root

    def width : Int32
      900
    end

    def height : Int32
      680
    end

    def theme : Tessell::Kit::Theme
      Tessell::Kit::Theme.light
    end

    def handle_app_event(event : Tessell::Input::Event) : Bool
      false
    end

    def on_root_ready(root : Tessell::Kit::Root) : Nil
    end

    def run(args : Array(String)) : Nil
      frames_limit = 0
      screenshot_path : String? = nil
      args.each do |arg|
        if arg.starts_with?("--frames=")
          frames_limit = arg.split("=", 2)[1].to_i
        elsif arg.starts_with?("--screenshot=")
          screenshot_path = arg.split("=", 2)[1]
        end
      end

      unless LibSDL.SDL_Init(SDL_INIT_VIDEO | SDL_INIT_EVENTS) == 0
        STDERR.puts "SDL_Init failed: #{String.new(LibSDL.SDL_GetError)}"
        exit 1
      end

      LibSDL.SDL_GL_SetAttribute(SDL_GL_DOUBLEBUFFER, 1)
      LibSDL.SDL_GL_SetAttribute(SDL_GL_DEPTH_SIZE, 0)
      LibSDL.SDL_GL_SetAttribute(SDL_GL_STENCIL_SIZE, 8)
      LibSDL.SDL_GL_SetAttribute(SDL_GL_CONTEXT_MAJOR_VERSION, 2)
      LibSDL.SDL_GL_SetAttribute(SDL_GL_CONTEXT_MINOR_VERSION, 1)
      LibSDL.SDL_GL_SetAttribute(SDL_GL_CONTEXT_PROFILE_MASK, SDL_GL_CONTEXT_PROFILE_COMPATIBILITY)

      window = LibSDL.SDL_CreateWindow(title.to_unsafe,
        SDL_WINDOWPOS_CENTERED.to_i32, SDL_WINDOWPOS_CENTERED.to_i32,
        width, height, SDL_WINDOW_OPENGL | SDL_WINDOW_SHOWN |
                       SDL_WINDOW_RESIZABLE | SDL_WINDOW_ALLOW_HIGHDPI)
      if window.null?
        STDERR.puts "SDL_CreateWindow failed: #{String.new(LibSDL.SDL_GetError)}"
        LibSDL.SDL_Quit
        exit 1
      end

      context = LibSDL.SDL_GL_CreateContext(window)
      if context.null?
        STDERR.puts "SDL_GL_CreateContext failed: #{String.new(LibSDL.SDL_GetError)}"
        LibSDL.SDL_DestroyWindow(window)
        LibSDL.SDL_Quit
        exit 1
      end
      LibSDL.SDL_GL_MakeCurrent(window, context)
      LibSDL.SDL_GL_SetSwapInterval(1)
      LibSDL.SDL_StartTextInput

      logical_w = 0
      logical_h = 0
      drawable_w = 0
      drawable_h = 0
      update_sizes(window, pointerof(logical_w), pointerof(logical_h),
        pointerof(drawable_w), pointerof(drawable_h))
      scale = device_scale(logical_w, drawable_w)

      measurer = load_measurer
      atlas = Tessell::Text::GlyphAtlas.new(1024, 4096)
      rasterizer = Tessell::Text::Rasterizer.new(measurer, atlas, 0, 4096)
      renderer = Tessell::Render::TextRenderer.new(atlas, rasterizer)
      renderer.reserve_quads(4096)
      renderer.reserve_batches(128)

      backend = Tessell::Render::GL::GLBackend.new
      backend.init(drawable_w, drawable_h)
      backend.resize(drawable_w, drawable_h)

      clipboard = SdlClipboard.new
      metrics = Tessell::Kit::CoreTextMetrics.new(measurer, 0)
      root = build_root(metrics, clipboard)
      root.layout(logical_w.to_f32, logical_h.to_f32)
      root.build
      on_root_ready(root)

      painter = GLPainter.new(renderer, atlas, drawable_w, drawable_h, scale)
      @root = root
      @window = window
      @mouse_x = 0
      @mouse_y = 0

      frames = 0
      quit = false
      until quit
        quit = pump_events(root)
        break if quit

        if @resize_pending
          update_sizes(window, pointerof(logical_w), pointerof(logical_h),
            pointerof(drawable_w), pointerof(drawable_h))
          scale = device_scale(logical_w, drawable_w)
          backend.resize(drawable_w, drawable_h)
          painter.resize(drawable_w, drawable_h, scale)
          root.layout(logical_w.to_f32, logical_h.to_f32)
          @resize_pending = false
        end

        root.advance_time(LibSDL.SDL_GetTicks.to_i64)
        root.build

        backend.begin_frame(nil, theme.to_render)
        root.paint(painter)
        painter.flush(backend)
        backend.end_frame

        if path = screenshot_path
          if frames_limit == 0 || frames + 1 >= frames_limit
            if path.ends_with?(".png")
              capture_png(path, drawable_w, drawable_h)
            else
              capture_ppm(path, drawable_w, drawable_h)
            end
            screenshot_path = nil
          end
        end

        LibSDL.SDL_GL_SwapWindow(window)

        frames += 1
        break if frames_limit > 0 && frames >= frames_limit
        LibSDL.SDL_Delay(8)
      end

      LibSDL.SDL_StopTextInput
      LibSDL.SDL_GL_DeleteContext(context)
      LibSDL.SDL_DestroyWindow(window)
      LibSDL.SDL_Quit
      puts "KIT_DEMO_RUN app=#{title} frames=#{frames} size=#{logical_w}x#{logical_h} scale=#{scale}"
    end

    @root : Tessell::Kit::Root?
    @window : Void* = Pointer(Void).null
    @mouse_x : Int32 = 0
    @mouse_y : Int32 = 0
    @resize_pending : Bool = false

    # PNG 截图（issue #9）：--screenshot=xxx.png 直接出 PNG（stored zlib，
    # 标准解码器可读）；其他扩展名保留 P6 PPM。
    private def capture_png(path : String, width : Int32, height : Int32) : Nil
      return if width <= 0 || height <= 0
      rgba = Bytes.new(width * height * 4)
      TessellGL.glFinish
      TessellGL.glPixelStorei(TessellGL::GL_PACK_ALIGNMENT, 1)
      TessellGL.glReadPixels(0, 0, width, height, TessellGL::GL_RGBA,
        TessellGL::GL_UNSIGNED_BYTE, rgba.to_unsafe.as(Void*))
      top_down = Bytes.new(width * height * 4)
      row = width * 4
      y = 0
      while y < height
        src = (height - 1 - y) * row
        dst = y * row
        (top_down.to_unsafe + dst).copy_from(rgba.to_unsafe + src, row)
        y += 1
      end
      TessellPNG.write(path, width, height, top_down)
    end

    private def capture_ppm(path : String, width : Int32, height : Int32) : Nil
      return if width <= 0 || height <= 0
      dir = File.dirname(path)
      Dir.mkdir_p(dir) unless dir.empty? || Dir.exists?(dir)
      rgba = Bytes.new(width * height * 4)
      TessellGL.glFinish
      TessellGL.glPixelStorei(TessellGL::GL_PACK_ALIGNMENT, 1)
      TessellGL.glReadPixels(0, 0, width, height, TessellGL::GL_RGBA,
        TessellGL::GL_UNSIGNED_BYTE, rgba.to_unsafe.as(Void*))
      rgb = Bytes.new(width * height * 3)
      y = 0
      while y < height
        src_row = (height - 1 - y) * width * 4
        dst_row = y * width * 3
        x = 0
        while x < width
          si = src_row + x * 4
          di = dst_row + x * 3
          rgb[di] = rgba[si]
          rgb[di + 1] = rgba[si + 1]
          rgb[di + 2] = rgba[si + 2]
          x += 1
        end
        y += 1
      end
      File.open(path, "wb") do |io|
        io << "P6\n#{width} #{height}\n255\n"
        io.write(rgb)
      end
      puts "KIT_DEMO_SCREENSHOT path=#{path} size=#{width}x#{height}"
    end

    private def update_sizes(window : Void*, lw : Int32*, lh : Int32*,
                             dw : Int32*, dh : Int32*) : Nil
      LibSDL.SDL_GetWindowSize(window, lw, lh)
      LibSDL.SDL_GL_GetDrawableSize(window, dw, dh)
      lw.value = 1 if lw.value <= 0
      lh.value = 1 if lh.value <= 0
      dw.value = lw.value if dw.value <= 0
      dh.value = lh.value if dh.value <= 0
    end

    private def device_scale(logical_w : Int32, drawable_w : Int32) : Float32
      return 1.0_f32 if logical_w <= 0
      (drawable_w.to_f32 / logical_w.to_f32).clamp(1.0_f32, 4.0_f32)
    end

    private def load_measurer : Tessell::Text::FtMeasurer
      candidates = [] of String
      if path = ENV["TESSELL_FONT"]?
        candidates << path
      end
      {% if flag?(:darwin) %}
        candidates << "/System/Library/Fonts/Supplemental/Arial Unicode.ttf"
        candidates << "/System/Library/Fonts/Supplemental/Arial.ttf"
      {% elsif flag?(:windows) %}
        candidates << "C:/Windows/Fonts/msyh.ttc"
        candidates << "C:/Windows/Fonts/arial.ttf"
      {% else %}
        candidates << "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
      {% end %}
      candidates.each do |path|
        return Tessell::Text::FtMeasurer.open(path, 0) if File.exists?(path)
      end
      raise "no usable font found; set TESSELL_FONT to a TTF/TTC path"
    end

    private def pump_events(root : Tessell::Kit::Root) : Bool
      event = uninitialized LibSDL::Event
      while LibSDL.SDL_PollEvent(pointerof(event)) != 0
        case event.type
        when SDL_QUIT
          return true
        when SDL_WINDOWEVENT
          window_event = pointerof(event).as(LibSDL::WindowEvent*).value
          if window_event.event == SDL_WINDOWEVENT_CLOSE
            return true
          elsif window_event.event == SDL_WINDOWEVENT_RESIZED ||
                window_event.event == SDL_WINDOWEVENT_SIZE_CHANGED
            @resize_pending = true
          end
        when SDL_KEYDOWN
          key = pointerof(event).as(LibSDL::KeyboardEvent*).value
          if code = map_key(key.keysym.sym)
            dispatch(root, Tessell::Input::Event.key_down(code, modifiers(key.keysym.mod),
              key.timestamp.to_i64, key.repeat != 0))
          end
        when SDL_KEYUP
          key = pointerof(event).as(LibSDL::KeyboardEvent*).value
          if code = map_key(key.keysym.sym)
            dispatch(root, Tessell::Input::Event.key_up(code, modifiers(key.keysym.mod),
              key.timestamp.to_i64))
          end
        when SDL_TEXTINPUT
          text_event = pointerof(event).as(LibSDL::TextInputEvent*).value
          dispatch(root, Tessell::Input::Event.text_input(String.new(text_event.text.to_unsafe)))
        when SDL_MOUSEMOTION
          motion = pointerof(event).as(LibSDL::MouseMotionEvent*).value
          @mouse_x = motion.x
          @mouse_y = motion.y
          dispatch(root, Tessell::Input::Event.pointer_move(motion.x.to_f32, motion.y.to_f32))
        when SDL_MOUSEBUTTONDOWN
          button = pointerof(event).as(LibSDL::MouseButtonEvent*).value
          @mouse_x = button.x
          @mouse_y = button.y
          dispatch(root, Tessell::Input::Event.pointer_down(button.x.to_f32, button.y.to_f32,
            button.button.to_i32 - 1, modifiers(0), button.timestamp.to_i64))
        when SDL_MOUSEBUTTONUP
          button = pointerof(event).as(LibSDL::MouseButtonEvent*).value
          @mouse_x = button.x
          @mouse_y = button.y
          dispatch(root, Tessell::Input::Event.pointer_up(button.x.to_f32, button.y.to_f32,
            button.button.to_i32 - 1, modifiers(0), button.timestamp.to_i64))
        when SDL_MOUSEWHEEL
          wheel = pointerof(event).as(LibSDL::MouseWheelEvent*).value
          dispatch(root, Tessell::Input::Event.wheel(@mouse_x.to_f32, @mouse_y.to_f32,
            wheel.x.to_f32 * 40.0_f32, wheel.y.to_f32 * 40.0_f32))
        end
      end
      false
    end

    private def dispatch(root : Tessell::Kit::Root, event : Tessell::Input::Event) : Nil
      return if handle_app_event(event)
      root.handle(event)
    end

    private def modifiers(mod : UInt16) : Tessell::Input::Modifiers
      Tessell::Input::Modifiers.new(
        shift: (mod & KMOD_SHIFT) != 0,
        ctrl: (mod & KMOD_CTRL) != 0,
        alt: (mod & KMOD_ALT) != 0,
        meta: (mod & KMOD_GUI) != 0)
    end

    private def map_key(sym : Int32) : Tessell::Input::KeyCode?
      case sym
      when SDLK_ESCAPE    then Tessell::Input::KeyCode::Escape
      when SDLK_RETURN    then Tessell::Input::KeyCode::Enter
      when SDLK_BACKSPACE then Tessell::Input::KeyCode::Backspace
      when SDLK_TAB       then Tessell::Input::KeyCode::Tab
      when SDLK_DELETE    then Tessell::Input::KeyCode::Delete
      when SDLK_SPACE     then Tessell::Input::KeyCode::Space
      when SDLK_LEFT      then Tessell::Input::KeyCode::Left
      when SDLK_RIGHT     then Tessell::Input::KeyCode::Right
      when SDLK_UP        then Tessell::Input::KeyCode::Up
      when SDLK_DOWN      then Tessell::Input::KeyCode::Down
      when SDLK_HOME      then Tessell::Input::KeyCode::Home
      when SDLK_END       then Tessell::Input::KeyCode::End
      when SDLK_PAGEUP    then Tessell::Input::KeyCode::PageUp
      when SDLK_PAGEDOWN  then Tessell::Input::KeyCode::PageDown
      when SDLK_a         then Tessell::Input::KeyCode::KeyA
      when SDLK_b         then Tessell::Input::KeyCode::KeyB
      when SDLK_c         then Tessell::Input::KeyCode::KeyC
      when SDLK_t         then Tessell::Input::KeyCode::KeyT
      when SDLK_v         then Tessell::Input::KeyCode::KeyV
      when SDLK_x         then Tessell::Input::KeyCode::KeyX
      when SDLK_z         then Tessell::Input::KeyCode::KeyZ
      when SDLK_0         then Tessell::Input::KeyCode::Digit0
      when SDLK_1         then Tessell::Input::KeyCode::Digit1
      when SDLK_2         then Tessell::Input::KeyCode::Digit2
      when SDLK_3         then Tessell::Input::KeyCode::Digit3
      when SDLK_4         then Tessell::Input::KeyCode::Digit4
      when SDLK_5         then Tessell::Input::KeyCode::Digit5
      when SDLK_6         then Tessell::Input::KeyCode::Digit6
      when SDLK_7         then Tessell::Input::KeyCode::Digit7
      when SDLK_8         then Tessell::Input::KeyCode::Digit8
      when SDLK_9         then Tessell::Input::KeyCode::Digit9
      else
        nil
      end
    end
  end
end
