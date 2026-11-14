# Tessell::Kit — 组件上下文与文本度量（K0）
#
# Context 是组件能看到的全部外部环境：主题、文本度量、DPI scale、时间。
# 组件不得从 Context 之外读窗口/GPU/全局状态。

require "../text/font_stack"

module Tessell
  module Kit
    # 组件层字重（issue #29）。映射到 FontStack::Weight：Normal→Regular、
    # Bold→Bold。选脸结果（font_id）一路传到 Painter——组件层只声明
    # "这是粗体"，不持有 face 对象。
    enum FontWeight
      Normal
      Bold
    end

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

      # face 维度测量（issue #29）：默认实现忽略 font_id（单 face 桩）；
      # 多 face 实现应按 font_id 选底层 measurer。
      def measure(text : String, size : Float32, font_id : Int32) : Size
        measure(text, size)
      end

      def measure(text : String, size : Float32, max_width : Float32,
                  font_id : Int32) : Size
        measure(text, size, max_width)
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
    # 行高口径（issue #19）：桩显式走基类 1.25*size 系数（line_height 与
    # font_metrics 同为 1.25*size，与单行 measure 高度一致）——这是桩的
    # 已文档化口径，不跟随真实字体 FT metrics。
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

      # face 维度测量（issue #29）：font_id 透传给底层 Measurer。
      def measure(text : String, size : Float32, font_id : Int32) : Size
        @measurer.measure(text, font_id, size, Float32::INFINITY)
      end

      def measure(text : String, size : Float32, max_width : Float32,
                  font_id : Int32) : Size
        @measurer.measure(text, font_id, size, max_width)
      end

      # 行高唯一真相（issue #19）：与 font_metrics/measure 同源
      # （FT size metrics）。此前 CoreTextMetrics 不覆盖 line_height，
      # 真实字体永远走 1.25 经验系数，与 measure_text 高度差 8%+。
      def line_height(size : Float32) : Float32
        @measurer.font_metrics(@font_id, size).line_height
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

    # 多 face 度量（issue #29）：包一层 FontStack，按整段文本覆盖选脸并
    # 转发 face 的 font_id——单 face 假设不再泄漏到组件层。粗体宽度用
    # bold face 测量：组件传 font_id 给 measure_text（Context 缓存键含 font_id）。
    class MultiFaceTextMetrics < TextMetrics
      getter stack : Tessell::Text::FontStack

      def initialize(@stack : Tessell::Text::FontStack)
      end

      private def face_for(text : String) : Tessell::Text::FontStack::Face
        @stack.pick(text) || @stack.faces.first
      end

      private def face_for(font_id : Int32) : Tessell::Text::FontStack::Face
        @stack.faces.find { |f| f.font_id == font_id } || @stack.faces.first
      end

      def measure(text : String, size : Float32) : Size
        face = face_for(text)
        face.measurer.measure(text, face.font_id, size, Float32::INFINITY)
      end

      def measure(text : String, size : Float32, max_width : Float32) : Size
        face = face_for(text)
        face.measurer.measure(text, face.font_id, size, max_width)
      end

      def measure(text : String, size : Float32, font_id : Int32) : Size
        face = face_for(font_id)
        face.measurer.measure(text, face.font_id, size, Float32::INFINITY)
      end

      def measure(text : String, size : Float32, max_width : Float32,
                  font_id : Int32) : Size
        face = face_for(font_id)
        face.measurer.measure(text, face.font_id, size, max_width)
      end

      def font_metrics(size : Float32) : Tessell::Text::FontMetrics
        face = @stack.faces.first
        face.measurer.font_metrics(face.font_id, size)
      end

      def line_height(size : Float32) : Float32
        face = @stack.faces.first
        face.measurer.font_metrics(face.font_id, size).line_height
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

      # 文本测量缓存（issue #6/#24/#29）：两代淘汰的有界缓存，
      # 键 (text, font_id, size, max_width)。
      # 正确性不依赖任何人清空——键含文本内容，内容变化天然产生新键；
      # clear_text_cache 是表格/行情这类高频换文本集合应用的内存卫生措施
      # （整体数据快照替换后调用一次即可，不必每帧）。容量有界：cur 代满
      # MEASURE_CACHE_CAP 条时整体换代（old=cur，cur 重建），old 命中会提升回 cur。
      MEASURE_CACHE_CAP = 4096

      @measure_cur : Hash({String, Int32, Float32, Float32}, Size)
      @measure_old : Hash({String, Int32, Float32, Float32}, Size)
      @measure_hits : Int32
      @measure_misses : Int32
      # 多 face 字体栈（issue #29）：nil = 单 face。设置后组件的 FontWeight
      # 经 font_id_for 解析为 face 的 font_id，一路传到 Painter。
      property font_stack : Tessell::Text::FontStack? = nil

      def initialize(theme : Theme = Theme.light,
                     @metrics : TextMetrics = StubTextMetrics.new,
                     @scale : Float32 = 1.0_f32,
                     @now_ms : Int64 = 0_i64)
        @theme = theme
        @render_theme = theme.to_render
        @overlay_host = nil
        @measure_cur = {} of {String, Int32, Float32, Float32} => Size
        @measure_old = {} of {String, Int32, Float32, Float32} => Size
        @measure_hits = 0
        @measure_misses = 0
      end

      def theme=(theme : Theme) : Nil
        @theme = theme
        @render_theme = theme.to_render
      end

      # 逻辑单位契约（issue #14）：以设备字号测量（与 Painter 提交的实际
      # 字形尺寸一致），再除回 scale 返回**逻辑**尺寸。组件在 scale=1 与
      # scale=2 下得到相同逻辑 bounds，宿主无须自写除法适配器。
      def measure_text(text : String, size : Float32) : Size
        measure_text(text, size, Float32::INFINITY, 0)
      end

      # face 维度测量（issue #29）：font_id = 0 表示默认 face。
      def measure_text(text : String, size : Float32, font_id : Int32) : Size
        measure_text(text, size, Float32::INFINITY, font_id)
      end

      def measure_text(text : String, size : Float32, max_width : Float32) : Size
        measure_text(text, size, max_width, 0)
      end

      def measure_text(text : String, size : Float32, max_width : Float32,
                       font_id : Int32) : Size
        # 设备空间整体放大 scale 倍：设备字号 = size*scale，设备 max_width
        # 也必须 = max_width*scale，换行行为才与逻辑空间一致。
        cached_measure({text, font_id, size, max_width}) do
          s = @metrics.measure(text, device_font_size(size), max_width * @scale, font_id)
          Size.new(s.width / @scale, s.height / @scale)
        end
      end

      private def cached_measure(key : {String, Int32, Float32, Float32}, &) : Size
        if (hit = @measure_cur[key]?)
          @measure_hits += 1
          return hit
        end
        if (hit = @measure_old[key]?)
          @measure_hits += 1
          @measure_cur[key] = hit
          return hit
        end
        @measure_misses += 1
        result = yield
        if @measure_cur.size >= MEASURE_CACHE_CAP
          @measure_old = @measure_cur
          @measure_cur = {} of {String, Int32, Float32, Float32} => Size
        end
        @measure_cur[key] = result
        result
      end

      # 缓存观测面（issue #24）：应用据此判断是否需要 clear_text_cache。
      def text_cache_hits : Int32
        @measure_hits
      end

      def text_cache_misses : Int32
        @measure_misses
      end

      def text_cache_size : Int32
        @measure_cur.size
      end

      # 与 CachingMeasurer#stats 同风格的汇总读数。
      def text_cache_stats : NamedTuple(hits: Int32, misses: Int32, size: Int32)
        {hits: @measure_hits, misses: @measure_misses, size: @measure_cur.size}
      end

      # 字体度量（逻辑单位，issue #6）：组件不再猜 baseline（旧 hack 是
      # `0.36 * size`），用 ascent/descent/line_height 做垂直居中。
      def text_metrics(size : Float32) : Tessell::Text::FontMetrics
        m = @metrics.font_metrics(device_font_size(size))
        Tessell::Text::FontMetrics.new(m.ascent / @scale, m.descent / @scale,
          m.line_height / @scale)
      end

      def clear_text_cache : Nil
        @measure_cur.clear
        @measure_old.clear
      end

      # FontWeight → font_id（issue #29）：按栈内字重匹配的覆盖脸；无栈或
      # 无覆盖返回 0（默认 face）。
      def font_id_for(text : String, weight : FontWeight) : Int32
        if stack = @font_stack
          sw = weight == FontWeight::Bold ? Tessell::Text::FontStack::Weight::Bold : Tessell::Text::FontStack::Weight::Regular
          if face = stack.pick(text, sw)
            return face.font_id
          end
        end
        0
      end

      # DPI/缩放变更（issue #30）：scale 与文本测量缓存联动。缓存的测量值
      # 是设备像素口径，对旧 scale 全部失效——改 scale 与清缓存在同一个
      # 入口里完成，避免调用方漏清导致旧值漂移。
      def scale=(value : Float32) : Nil
        return if value == @scale
        @scale = value
        clear_text_cache
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
