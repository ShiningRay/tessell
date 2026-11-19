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
require "../../src/tessell/platform/sdl2"

module TessellKitSdl

  class GLPainter < Tessell::Kit::Painter
    getter scale : Float32

    @draw : Tessell::Kit::DrawListPainter
    @renderer : Tessell::Render::TextRenderer
    @atlas : Tessell::Text::GlyphAtlas
    @width : Int32
    @height : Int32
    @scale : Float32
    @sink : Array(Tessell::Text::GlyphPlacement)

    def initialize(@renderer : Tessell::Render::TextRenderer,
                   @atlas : Tessell::Text::GlyphAtlas,
                   @width : Int32, @height : Int32, @scale : Float32)
      @draw = Tessell::Kit::DrawListPainter.new
      @sink = [] of Tessell::Text::GlyphPlacement
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
             color : UInt32, size : Float32, font_id : Int32 = 0) : Nil
      px_size = (size * @scale).round.to_i
      return if px_size <= 0
      dx = x * @scale
      dy = baseline_y * @scale
      # Text payload goes into the command itself (issue #21). flush() reads
      # cmd.text/font_size and submits in command order — no parallel
      # batch-boundary array to keep in sync. font_id (issue #29) is accepted
      # but this single-face example host ignores it; multi-face hosts build
      # a renderer table keyed by font_id.
      @draw.text(dx, dy, text, color, px_size.to_f32)
    end

    # 外部纹理四边形（issue #45）：进 DrawList，flush 交后端的 Image 通道。
    # 纹理由应用经 Backend#create_texture 创建（handle 跨帧稳定）。
    def image(texture_id : Int32, bounds : Tessell::Rect,
              tint : UInt32 = 0xffffffff_u32, src : Tessell::Rect? = nil) : Nil
      @draw.image(texture_id, scale_rect(bounds), tint,
        src.try { |r| scale_rect(r) })
    end

    def push_clip(rect : Tessell::Rect) : Nil
      @draw.push_clip(scale_rect(rect))
    end

    def pop_clip : Nil
      @draw.pop_clip
    end

    def flush(backend : Tessell::Render::Backend) : Nil
      # Issue #15: command order == paint order. Issue #21: the text payload
      # lives on the command itself, so one pass over the list is enough —
      # no parallel batch-boundary array. Shapes submit as contiguous
      # segments; each Text command shapes, syncs the atlas (incremental,
      # no-op when unchanged — issue #1/#22) and submits exactly its own
      # batches, scissored to the command's clip.
      list = @draw.list
      seg = 0
      i = 0
      while i < list.size
        cmd = list[i]
        if cmd.kind == Tessell::Render::CmdKind::Text
          backend.draw_draw_list(list, seg, i - seg) if i > seg
          before = @renderer.batch_count
          @renderer.append_text_cached(@sink, cmd.text, cmd.bounds.origin.x, cmd.bounds.origin.y,
            cmd.font_size.round.to_i, @width, @height, cmd.color)
          delta = @renderer.batch_count - before
          if delta > 0
            backend.sync_atlas_dirty(@atlas)
            backend.draw_text(@renderer.vertices, @renderer.batch_runs,
              delta, before, cmd.clip)
          end
          seg = i + 1
        end
        i += 1
      end
      backend.draw_draw_list(list, seg, list.size - seg) if list.size > seg
      @draw.reset
      @renderer.reset
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

      # X1（issue #61）：窗口/GL/事件/剪贴板全部来自可选平台宿主；
      # 本类只保留应用装配（Root 构建、字体、GLPainter 桥接）。
      host = Tessell::Platform::SDL2::Host.new(title, width, height)

      measurer = load_measurer
      atlas = Tessell::Text::GlyphAtlas.new(1024, 4096)
      rasterizer = Tessell::Text::Rasterizer.new(measurer, atlas, 0, 4096)
      renderer = Tessell::Render::TextRenderer.new(atlas, rasterizer)
      renderer.reserve_quads(4096)
      renderer.reserve_batches(128)

      backend = Tessell::Render::GL::GLBackend.new
      backend.init(host.drawable_width, host.drawable_height)
      backend.resize(host.drawable_width, host.drawable_height)

      clipboard = Tessell::Kit::HostClipboard.new(host.clipboard)
      metrics = Tessell::Kit::CoreTextMetrics.new(measurer, 0)
      root = build_root(metrics, clipboard)
      logical_w = host.logical_width
      logical_h = host.logical_height
      scale = host.scale
      root.layout(logical_w.to_f32, logical_h.to_f32)
      root.build
      on_root_ready(root)

      painter = GLPainter.new(renderer, atlas, host.drawable_width, host.drawable_height, scale)
      @root = root

      events = [] of Tessell::Input::Event
      runner = Tessell::App::Runner.new
      runner.frames_limit = frames_limit
      last_ticks = host.ticks_ms
      until host.quit_requested?
        break unless host.poll_events(events)
        events.each do |event|
          return if handle_app_event(event)
          root.handle(event)
        end
        events.clear
        break if host.quit_requested?

        # 帧调试 overlay（issue #11）：上一帧 stats + 本帧耗时；F1 由 Root 拦截
        now = host.ticks_ms
        root.debug_info = Tessell::Kit::DebugInfo.collect(backend.stats, atlas, root,
          (now - last_ticks).to_f32)
        last_ticks = now

        if host.resized?
          host.refresh_sizes
          scale = host.scale
          backend.resize(host.drawable_width, host.drawable_height)
          painter.resize(host.drawable_width, host.drawable_height, scale)
          root.layout(host.logical_width.to_f32, host.logical_height.to_f32)
        end

        root.advance_time(host.ticks_ms)
        root.build

        backend.begin_frame(nil, theme.to_render)
        root.paint(painter)
        painter.flush(backend)
        backend.end_frame

        if path = screenshot_path
          if frames_limit == 0 || runner.frame_count + 1 >= frames_limit
            if path.ends_with?(".png")
              capture_png(path, host.drawable_width, host.drawable_height)
            else
              host.screenshot(path)
              puts "KIT_DEMO_SCREENSHOT path=#{path} size=#{host.drawable_width}x#{host.drawable_height}"
            end
            screenshot_path = nil
          end
        end

        host.present

        # Runner 驱动退出（issue #3）：自动化帧数/stop() 统一在此判定
        break if runner.advance(host.ticks_ms)
        host.delay(8)
      end

      host.close
      puts "KIT_DEMO_RUN app=#{title} frames=#{runner.frame_count} size=#{logical_w}x#{logical_h} scale=#{scale}"
    end

    @root : Tessell::Kit::Root?

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



    private def load_measurer : Tessell::Text::FtMeasurer
      candidates = [] of String
      if path = ENV["TESSELL_FONT"]?
        candidates << path
      end
      {% if flag?(:darwin) %}
        candidates << "/System/Library/Fonts/Supplemental/Arial Unicode.ttf"
        candidates << "/System/Library/Fonts/Supplemental/Arial.ttf"
        candidates << "/System/Library/Fonts/Helvetica.ttc"
      {% elsif flag?(:windows) %}
        candidates << "C:/Windows/Fonts/msyh.ttc"
        candidates << "C:/Windows/Fonts/arial.ttf"
      {% else %}
        # issue #48：Linux 发行版的字体布局差异很大（Arch 只有 TTF/ 与
        # noto-cjk/，Debian 在 truetype/，Fedora 在 liberation/），只探
        # DejaVu 一条路径会让示例在多数机器上直接起不来。
        candidates << "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
        candidates << "/usr/share/fonts/TTF/DejaVuSans.ttf"
        candidates << "/usr/share/fonts/dejavu/DejaVuSans.ttf"
        candidates << "/usr/share/fonts/liberation/LiberationSans-Regular.ttf"
        candidates << "/usr/share/fonts/TTF/LiberationSans-Regular.ttf"
        candidates << "/usr/share/fonts/liberation-sans/LiberationSans-Regular.ttf"
        candidates << "/usr/share/fonts/noto/NotoSans-Regular.ttf"
        candidates << "/usr/share/fonts/noto-cjk/NotoSansCJK-Regular.ttc"
        candidates << "/usr/share/fonts/google-noto/NotoSans-Regular.ttf"
        candidates << "/usr/share/fonts/Adwaita/AdwaitaSans-Regular.ttf"
      {% end %}
      candidates.each do |path|
        return Tessell::Text::FtMeasurer.open(path, 0) if File.exists?(path)
      end
      raise "no usable font found; set TESSELL_FONT to a TTF/TTC path " \
            "(tried: #{candidates.join(", ")})"
    end

  end
end
