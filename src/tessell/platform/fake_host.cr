# Tessell::Platform::FakeHost — 记录式宿主测试替身（issue #35，对照 asuka
# host/fake）。
#
# 职责：
#   - 记录每帧泵出的事件与 present 次数（断言 op 流，不看像素）；
#   - 事件注入：tap/key/text_input 合成 Input::Event（时间戳走虚拟时钟，
#     settle 绝不 sleep）；
#   - 违规 panic：panic_on_unsupported 开启时，调用未实现能力（截图等）
#     直接 raise，绝不静默成功。
#
# 「按用户所见驱动」的命中语义由核心 Router/HitTest 承担（只命中可见节点、
# Root 的 modal 屏障拦截），FakeHost 只负责合成与泵送。
# 结束泄漏检查：GC 宿主语言下「view 活过 root 即 fail」不可直接观测，
# 以 frames/presents 对账 + 组件树 detach 断言替代（见 spec/kit/fake_host_spec.cr）。

module Tessell
  module Platform
    class FakeHost < Host
      getter presents : Int32
      getter frames : Int32
      getter clock_ms : Int64
      getter event_log : Array(Tessell::Input::Event)
      getter pump_log : Array(Int32) # 每帧泵出的事件数
      property scale : Float32
      property frame_interval_ms : Int64
      property panic_on_unsupported : Bool

      @viewport : Tessell::Rect
      @queue : Array(Tessell::Input::Event)
      @closed : Bool

      def initialize(width : Float32 = 800.0_f32, height : Float32 = 600.0_f32,
                     @scale : Float32 = 1.0_f32)
        @viewport = Tessell::Rect.new(0.0_f32, 0.0_f32, width, height)
        @presents = 0
        @frames = 0
        @clock_ms = 0_i64
        @frame_interval_ms = 16_i64
        @panic_on_unsupported = true
        @queue = [] of Tessell::Input::Event
        @event_log = [] of Tessell::Input::Event
        @pump_log = [] of Int32
        @closed = false
      end

      def title : String
        "fake"
      end

      def viewport : Tessell::Rect
        @viewport
      end

      def inject(event : Tessell::Input::Event) : Nil
        raise "FakeHost already closed" if @closed
        @queue << event
        @event_log << event
      end

      # 按用户所见驱动：tap = 完整按压/抬起对（间隔 30ms 虚拟时钟内）。
      def tap(x : Float32, y : Float32) : Nil
        inject(Tessell::Input::Event.pointer_down(x, y, timestamp_ms: @clock_ms + 1_i64))
        inject(Tessell::Input::Event.pointer_up(x, y, timestamp_ms: @clock_ms + 31_i64))
      end

      def key(code : Tessell::Input::KeyCode, modifiers : Tessell::Input::Modifiers = Tessell::Input::Modifiers.none) : Nil
        inject(Tessell::Input::Event.key_down(code, modifiers, timestamp_ms: @clock_ms + 1_i64))
        inject(Tessell::Input::Event.key_up(code, modifiers, timestamp_ms: @clock_ms + 11_i64))
      end

      def text_input(text : String) : Nil
        inject(Tessell::Input::Event.text_input(text, timestamp_ms: @clock_ms + 1_i64))
      end

      def poll_events(sink : Array(Tessell::Input::Event)) : Bool
        raise "FakeHost already closed" if @closed
        until @queue.empty?
          sink << @queue.shift
        end
        true
      end

      # 泵一帧：推进虚拟时钟并返回本帧事件（合成帧步进，绝不 sleep）。
      def pump_frame : Array(Tessell::Input::Event)
        raise "FakeHost already closed" if @closed
        @frames += 1
        @clock_ms += @frame_interval_ms
        drained = [] of Tessell::Input::Event
        poll_events(drained)
        @pump_log << drained.size
        drained
      end

      def present : Nil
        raise "FakeHost already closed" if @closed
        @presents += 1
      end

      # 未实现能力显式 panic（真实宿主无法应用的 op 不许静默成功）。
      def screenshot(path : String) : Nil
        raise "FakeHost does not support screenshots; use SoftwareBackend pixel() oracle"
      end

      def close : Nil
        @closed = true
      end

      def closed? : Bool
        @closed
      end
    end
  end
end
