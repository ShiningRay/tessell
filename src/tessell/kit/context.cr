# Tessell::Kit — 组件上下文与文本度量（K0）
#
# Context 是组件能看到的全部外部环境：主题、文本度量、DPI scale、时间。
# 组件不得从 Context 之外读窗口/GPU/全局状态。

module Tessell
  module Kit
    abstract class TextMetrics
      # 单位契约（issue #14）：`measure` / `line_height` 的入参 size 与返回值
      # 一律为**设备像素**单位（宿主渲染字形所用的实际字号）。逻辑单位的换算
      # 由 `Context#measure_text` / `Context#line_height` 统一负责——组件层只
      # 见逻辑单位，宿主不需要再包一层除法适配器。
      abstract def measure(text : String, size : Float32) : Size

      # 带可用宽度的测量；默认忽略 max_width，支持换行的实现应覆盖。
      def measure(text : String, size : Float32, max_width : Float32) : Size
        measure(text, size)
      end

      # 字体度量（issue #6）：设备像素单位。默认与 line_height(size)=1.25*size
      # 口径一致（ascent+descent=line_height）；CoreTextMetrics 委托给底层
      # Measurer#font_metrics（FT size metrics）。
      def font_metrics(size : Float32) : Tessell::Text::FontMetrics
        Tessell::Text::FontMetrics.new(size * 1.0_f32, size * 0.25_f32, size * 1.25_f32)
      end

      def line_height(size : Float32) : Float32
        size * 1.25_f32
      end
    end

    # 确定性桩：ASCII 0.6*size，非 ASCII 1.0*size。仅用于布局/测试。
    class StubTextMetrics < TextMetrics
      def measure(text : String, size : Float32) : Size
        width = 0.0_f32
        text.each_char do |ch|
          width += advance(ch, size)
        end
        Size.new(width, line_height(size))
      end

      def measure(text : String, size : Float32, max_width : Float32) : Size
        return measure(text, size) if max_width.infinite? || max_width <= 0.0_f32
        line_width = 0.0_f32
        max_line = 0.0_f32
        lines = 1
        text.each_char do |ch|
          w = advance(ch, size)
          if line_width > 0.0_f32 && line_width + w > max_width
            max_line = line_width if line_width > max_line
            lines += 1
            line_width = w
          else
            line_width += w
          end
        end
        max_line = line_width if line_width > max_line
        Size.new(max_line, line_height(size) * lines)
      end

      def advance(ch : Char, size : Float32) : Float32
        ch.ascii? ? size * 0.6_f32 : size
      end
    end

    # 适配核心 Text::Measurer。真实实现由调用方注入，Kit 不直接碰 FFI。
    # 建议：注入 `CachingMeasurer.new(ft_measurer)` 复用按
    # (font_id, size, text_hash, max_width) 的测量缓存（issue #6）。
    class CoreTextMetrics < TextMetrics
      def initialize(@measurer : Tessell::Text::Measurer, @font_id : Int32 = 0)
      end

      def measure(text : String, size : Float32) : Size
        @measurer.measure(text, @font_id, size, Float32::INFINITY)
      end

      def measure(text : String, size : Float32, max_width : Float32) : Size
        @measurer.measure(text, @font_id, size, max_width)
      end

      def font_metrics(size : Float32) : Tessell::Text::FontMetrics
        @measurer.font_metrics(@font_id, size)
      end
    end

    class Context
      getter theme : Theme
      # 核心 Render::Theme 镜像（issue #8）：Kit Palette 覆盖组件语义，
      # 行情/网格/涨跌等扩展 token（panel/grid/up/down 等）从这里读，
      # 应用不再自建平行 Palette。
      getter render_theme : Tessell::Render::Theme
      getter metrics : TextMetrics
      getter scale : Float32
      getter now_ms : Int64
      property overlay_host : OverlayHost?

      @measure_cache : Hash({String, Float32, Float32}, Size)

      def initialize(theme : Theme = Theme.light,
                     @metrics : TextMetrics = StubTextMetrics.new,
                     @scale : Float32 = 1.0_f32,
                     @now_ms : Int64 = 0_i64)
        @theme = theme
        @render_theme = theme.to_render
        @overlay_host = nil
        @measure_cache = {} of {String, Float32, Float32} => Size
      end

      def theme=(theme : Theme) : Nil
        @theme = theme
        @render_theme = theme.to_render
      end

      # 逻辑单位契约（issue #14）：以设备字号测量（与 Painter 提交的实际
      # 字形尺寸一致），再除回 scale 返回**逻辑**尺寸。组件在 scale=1 与
      # scale=2 下得到相同逻辑 bounds，宿主无须自写除法适配器。
      # measure 结果缓存（issue #6）：key=(text,size,max_width)，与应用的
      # 文本清单规模同阶；文本集合变化时调用 clear_text_cache。
      def measure_text(text : String, size : Float32) : Size
        if (hit = @measure_cache[{text, size, Float32::INFINITY}]?)
          return hit
        end
        s = @metrics.measure(text, device_font_size(size))
        result = Size.new(s.width / @scale, s.height / @scale)
        @measure_cache[{text, size, Float32::INFINITY}] = result
        result
      end

      def measure_text(text : String, size : Float32, max_width : Float32) : Size
        # 设备空间整体放大 scale 倍：设备字号 = size*scale，设备 max_width
        # 也必须 = max_width*scale，换行行为才与逻辑空间一致。
        if (hit = @measure_cache[{text, size, max_width}]?)
          return hit
        end
        s = @metrics.measure(text, device_font_size(size), max_width * @scale)
        result = Size.new(s.width / @scale, s.height / @scale)
        @measure_cache[{text, size, max_width}] = result
        result
      end

      # 字体度量（逻辑单位，issue #6）：组件不再猜 baseline（旧 hack 是
      # `0.36 * size`），用 ascent/descent/line_height 做垂直居中。
      def text_metrics(size : Float32) : Tessell::Text::FontMetrics
        m = @metrics.font_metrics(device_font_size(size))
        Tessell::Text::FontMetrics.new(m.ascent / @scale, m.descent / @scale,
          m.line_height / @scale)
      end

      def clear_text_cache : Nil
        @measure_cache.clear
      end

      def line_height(size : Float32) : Float32
        @metrics.line_height(device_font_size(size)) / @scale
      end

      # DPI 只影响文本设备字号；逻辑布局尺寸仍由 Metrics 给出。
      def device_font_size(size : Float32) : Float32
        Render::Dpi.size_px(size, @scale)
      end

      def advance_time(now_ms : Int64) : Nil
        @now_ms = now_ms if now_ms > @now_ms
      end
    end
  end
end
