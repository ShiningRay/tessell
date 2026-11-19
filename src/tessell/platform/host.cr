# Tessell::Platform — 平台宿主契约（issue #35）
#
# 窗口/输入/呈现的最小面：真实宿主（SDL 示例宿主、未来 Win32）实现它；
# FakeHost 是记录式测试替身——UI/Kit 测试不依赖窗口系统、字体文件与 GPU。
# 契约只含平台职责；UI 组合（Root 驱动）在 Kit/应用层完成，本文件不反向
# 依赖 Kit（硬不变量，AGENTS.md #1）。
#
# 线程纪律：poll_events/present 只在 UI 执行上下文调用（architecture §4.2）。

module Tessell
  module Platform
    abstract class Host
      abstract def title : String
      abstract def scale : Float32
      abstract def viewport : Tessell::Rect

      # 泵一批输入事件进 sink（复用调用方缓冲）；返回 false = 宿主要求退出。
      abstract def poll_events(sink : Array(Tessell::Input::Event)) : Bool

      # 呈现当前帧（swap buffers / 位块传输）。
      abstract def present : Nil

      abstract def close : Nil

      # X1 扩展（issue #61 / plan §3.3）：剪贴板与 IME 能力表。
      abstract def clipboard : Clipboard
      abstract def ime : ImeSupport

      # 消费式 resize 通知：宿主在 poll_events 内部处理 size 事件并置位。
      def resized? : Bool
        false
      end

      # 帧循环辅助：平台侧时间源（manual clock 的宿主来源）。
      def ticks_ms : Int64
        0_i64
      end

      def delay(ms : Int32) : Nil
      end
    end
  end
end

module Tessell
  module Platform
    # 剪贴板抽象（plan §3.3）：平台层定义，Kit 只做适配，避免 Platform→Kit
    # 反向依赖。测试用 MemoryClipboard。
    abstract class Clipboard
      abstract def get : String?
      abstract def set(text : String) : Nil
    end

    class MemoryClipboard < Clipboard
      @value : String? = nil

      def get : String?
        @value
      end

      def set(text : String) : Nil
        @value = text
      end
    end

    # IME 能力表：SDL2 只稳定提供 committed text（SDL_TEXTINPUT）。
    # 预编辑/候选窗按平台如实报告 Unsupported（L3 单列，不许冒充）。
    enum ImeSupport
      Unsupported
      CommittedText
    end
  end
end
