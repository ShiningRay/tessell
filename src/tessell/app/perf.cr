# Tessell::App::PerfCollector — 帧/提交分段观测（issue #60）。
#
# 借 NSGo internal/engine/perf.go 的测量维度（engine commit / frame /
# 分段计数分列），不借其异口径性能阈值。默认关闭：`enabled = false` 时
# record/frame_end 是单 Bool 判断，热路径零改变——测量关闭时不改变现有
# 分配/计数基线（验收口径）。
#
# 分段：Input（事件泵+路由）/ Build（声明 emit + UI.apply）/ Layout
# （arrange）/ Paint（绘制命令产出）/ Present（宿主 swap）。每段记录
# 调用计数与命令/op 数；帧级记录五段 op 数与帧总 ms（宿主钟）。
# 失效→呈现延迟：invalidation → present 的帧跨度（帧粒度近似；跨
# Isolated context 的 hop 单独记 hop 计数，不做时钟差——两钟不同源）。
#
# 口径纪律（AGENTS #10）：p50/p95/p99 只出现在本 collector 的读取面
# （F1 overlay 文本行 / 离线 JSON），供人工定位；不进 CI 门禁——门禁
# 仍只看 op 流/命令数/分配字节。

module Tessell
  module App
    class PerfCollector
      # 有界样本容量：约 4 秒 @60fps 的帧样本，环形覆盖。
      SAMPLE_CAP = 256

      enum Segment
        Input
        Build
        Layout
        Paint
        Present
      end

      SEGMENT_COUNT = 5

      struct FrameSample
        getter frame_ms : Float32
        getter seg_ops : StaticArray(Int32, 5)
        getter seg_calls : StaticArray(Int32, 5)
        getter dirty_nodes : Int32
        getter invalidation_lag_frames : Int32

        def initialize(@frame_ms : Float32,
                       @seg_ops : StaticArray(Int32, 5),
                       @seg_calls : StaticArray(Int32, 5),
                       @dirty_nodes : Int32,
                       @invalidation_lag_frames : Int32)
        end
      end

      getter? enabled : Bool
      getter frame_count : Int32
      getter hop_count : Int32 # engine→UI 跨上下文提交次数（无时钟差）

      def initialize(@enabled : Bool = false)
        @samples = StaticArray(FrameSample?, SAMPLE_CAP).new(nil)
        @sample_cursor = 0
        @sample_size = 0
        @frame_count = 0
        @hop_count = 0
        @cur_ops = StaticArray(Int32, 5).new(0)
        @cur_calls = StaticArray(Int32, 5).new(0)
        @cur_dirty = 0
        @invalidation_pending = false
        @invalidation_age = 0
        @frame_started = false
      end

      def enabled=(v : Bool) : Nil
        @enabled = v
      end

      # 段计时入口（宿主钟毫秒差；由宿主驱动，collector 不取钟）。
      def record(segment : Segment, ops : Int32, start_ms : Int64, end_ms : Int64) : Nil
        return unless @enabled
        idx = segment.value
        @cur_ops[idx] += ops
        @cur_calls[idx] += 1 if end_ms >= start_ms # 负差为钟异常，不记调用
      end

      # 仅计数（无钟）：适合纯 op 流分段。
      def record_ops(segment : Segment, ops : Int32) : Nil
        return unless @enabled
        @cur_ops[segment.value] += ops
        @cur_calls[segment.value] += 1
      end

      # 失效标记：本帧有节点进入 dirty（帧粒度）。
      def mark_invalidated(dirty_nodes : Int32) : Nil
        return unless @enabled
        @invalidation_pending = true
        @cur_dirty += dirty_nodes if dirty_nodes > 0
      end

      # 跨 Isolated context 提交（engine→UI hop；只计数，不做跨钟差）。
      def record_hop : Nil
        return unless @enabled
        @hop_count += 1
      end

      def frame_start : Nil
        return unless @enabled
        @frame_started = true
        @cur_ops = StaticArray(Int32, 5).new(0)
        @cur_calls = StaticArray(Int32, 5).new(0)
        @cur_dirty = 0
      end

      # 帧收口（frame_ms 来自宿主钟差，由宿主传入）。
      # 失效→呈现延迟（帧粒度）：失效帧 lag=0；此后每过一个未 present 的
      # 帧累加 1；present 帧归零并清除 pending。
      def frame_end(frame_ms : Float32) : Nil
        return unless @enabled
        return unless @frame_started
        presented = @cur_ops[Segment::Present.value] > 0
        lag = if presented
                @invalidation_pending = false
                @invalidation_age = 0
                0
              elsif @invalidation_pending
                v = @invalidation_age
                @invalidation_age += 1
                v
              else
                0
              end
        @samples[@sample_cursor] = FrameSample.new(frame_ms, @cur_ops, @cur_calls,
          @cur_dirty, lag)
        @sample_cursor = (@sample_cursor + 1) % SAMPLE_CAP
        @sample_size += 1 if @sample_size < SAMPLE_CAP
        @frame_count += 1
        @frame_started = false
      end

      # 最近样本数（≤ SAMPLE_CAP）。
      def sample_size : Int32
        @sample_size
      end

      def sample(index : Int32) : FrameSample?
        return nil unless index >= 0 && index < @sample_size
        # index 0 = 最旧；环形展开
        base = (@sample_cursor - @sample_size + SAMPLE_CAP) % SAMPLE_CAP
        @samples[(base + index) % SAMPLE_CAP]
      end

      def latest : FrameSample?
        return nil if @sample_size == 0
        @samples[(@sample_cursor - 1 + SAMPLE_CAP) % SAMPLE_CAP]
      end

      # 静止画面判定：最近一帧五段全零 op（无多余提交的验收口径）。
      def idle_last_frame? : Bool
        s = latest
        return true if s.nil?
        total = 0
        5.times { |i| total += s.seg_ops[i] }
        total == 0
      end

      # 分位数：取指定段的帧样本值排序后线性插值。仅人工定位读取面。
      def percentile(segment : Segment, p : Float32) : Float32
        return 0.0_f32 if @sample_size == 0
        values = Array(Float32).new(@sample_size)
        i = 0
        while i < @sample_size
          if s = sample(i)
            values << s.seg_ops[segment.value].to_f32
          end
          i += 1
        end
        values.sort!
        percentile_of(values, p)
      end

      def percentile_frame_ms(p : Float32) : Float32
        return 0.0_f32 if @sample_size == 0
        values = Array(Float32).new(@sample_size)
        i = 0
        while i < @sample_size
          if s = sample(i)
            values << s.frame_ms
          end
          i += 1
        end
        values.sort!
        percentile_of(values, p)
      end

      private def percentile_of(sorted : Array(Float32), p : Float32) : Float32
        return 0.0_f32 if sorted.empty?
        rank = p / 100.0_f32 * (sorted.size - 1).to_f32
        lo = rank.floor.to_i
        hi = rank.ceil.to_i
        return sorted[lo] if lo == hi
        frac = rank - lo.to_f32
        sorted[lo] * (1.0_f32 - frac) + sorted[hi] * frac
      end

      # 离线 JSON（人工 bench 管道读取；不进门禁）。
      def to_json(io : IO) : Nil
        io << "{\"frame_count\":" << @frame_count
        io << ",\"sample_size\":" << @sample_size
        io << ",\"hop_count\":" << @hop_count
        io << ",\"p50_frame_ms\":" << percentile_frame_ms(50.0_f32)
        io << ",\"p95_frame_ms\":" << percentile_frame_ms(95.0_f32)
        io << ",\"p99_frame_ms\":" << percentile_frame_ms(99.0_f32)
        io << ",\"segments\":{"
        first = true
        {Segment::Input, Segment::Build, Segment::Layout, Segment::Paint,
         Segment::Present}.each do |seg|
          io << "," unless first
          first = false
          io << "\"" << seg.to_s.downcase << "\":{\"p50\":" <<
            percentile(seg, 50.0_f32) << ",\"p95\":" <<
            percentile(seg, 95.0_f32) << "}"
        end
        io << "}}"
      end

      def to_json_string : String
        String.build { |sb| to_json(sb) }
      end
    end
  end
end
