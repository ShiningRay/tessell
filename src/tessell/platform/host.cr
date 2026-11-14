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
    end
  end
end
