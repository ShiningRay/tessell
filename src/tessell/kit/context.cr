# Tessell::Kit — 组件上下文与文本度量（K0）
#
# Context 是组件能看到的全部外部环境：主题、文本度量、DPI scale、时间。
# 组件不得从 Context 之外读窗口/GPU/全局状态。

module Tessell
  module Kit
    abstract class TextMetrics
      abstract def measure(text : String, size : Float32) : Size

      # 带可用宽度的测量；默认忽略 max_width，支持换行的实现应覆盖。
      def measure(text : String, size : Float32, max_width : Float32) : Size
        measure(text, size)
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
    class CoreTextMetrics < TextMetrics
      def initialize(@measurer : Tessell::Text::Measurer, @font_id : Int32 = 0)
      end

      def measure(text : String, size : Float32) : Size
        @measurer.measure(text, @font_id, size, Float32::INFINITY)
      end

      def measure(text : String, size : Float32, max_width : Float32) : Size
        @measurer.measure(text, @font_id, size, max_width)
      end
    end

    class Context
      property theme : Theme
      getter metrics : TextMetrics
      getter scale : Float32
      getter now_ms : Int64

      def initialize(@theme : Theme = Theme.light,
                     @metrics : TextMetrics = StubTextMetrics.new,
                     @scale : Float32 = 1.0_f32,
                     @now_ms : Int64 = 0_i64)
      end

      def measure_text(text : String, size : Float32) : Size
        @metrics.measure(text, device_font_size(size))
      end

      def measure_text(text : String, size : Float32, max_width : Float32) : Size
        @metrics.measure(text, device_font_size(size), max_width)
      end

      def line_height(size : Float32) : Float32
        @metrics.line_height(device_font_size(size))
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
