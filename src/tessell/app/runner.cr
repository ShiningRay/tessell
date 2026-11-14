# Tessell::App::Runner — 平台无关帧循环契约（issue #3）
#
# 业务代码只写 on_frame；平台宿主（SDL/Win32）负责窗口、GL 上下文、消息泵
# 与输入映射，通过 advance(now_ms)/should_stop? 驱动 Runner。Runner 管理：
#   - 自动化帧数（frames_limit > 0 时跑满即退出，探针/截图模式）
#   - 虚拟时钟 clock_ms（业务与平台真实时钟解耦；advance 单调推进）
#   - 帧预算 frame_budget_ms（可选；超预算帧记录到 slow_frames 计数）
#   - 干净退出（stop() 置位，平台在下一帧泵循环退出并清理资源）
#
# Win32 平台层（Window/GLContext/MessagePump/InputMapper/Screenshot）仍是
# 独立工作项：拆解清单见 docs/cross-platform-plan.md，真机 gate 待 Windows
# 环境验证后落地（本机 macOS 无法验证 WGL/消息路径，不在此假装实现）。

module Tessell
  module App
    class Runner
      getter frame_count : Int32
      getter clock_ms : Int64
      getter slow_frames : Int32
      property frames_limit : Int32
      property frame_budget_ms : Float32
      getter frame_ms : Float32

      @should_stop : Bool
      @on_frame : Proc(Runner, Nil)?

      def initialize
        @frame_count = 0
        @clock_ms = 0_i64
        @slow_frames = 0
        @frames_limit = 0
        @frame_budget_ms = 0.0_f32
        @frame_ms = 0.0_f32
        @should_stop = false
        @on_frame = nil
      end

      def on_frame(&block : Runner -> Nil) : Nil
        @on_frame = block
      end

      def stop : Nil
        @should_stop = true
      end

      def should_stop? : Bool
        return true if @should_stop
        return true if @frames_limit > 0 && @frame_count >= @frames_limit
        false
      end

      # 平台每帧调用一次：now_ms 为平台单调时钟。返回 should_stop?，
      # 平台据此退出泵循环并清理。
      def advance(now_ms : Int64) : Bool
        return true if should_stop?
        @frame_ms = @last_now ? (now_ms - @last_now.not_nil!).to_f32 : 0.0_f32
        @last_now = now_ms
        @slow_frames += 1 if @frame_budget_ms > 0.0_f32 && @frame_ms > @frame_budget_ms
        @clock_ms += @frame_ms.to_i64
        @frame_count += 1
        @on_frame.try(&.call(self))
        should_stop?
      end

      @last_now : Int64?
    end
  end
end
