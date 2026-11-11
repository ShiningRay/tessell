# Tessell
#
# 顶层入口：只聚合公共 API，不在这里写实现。
# 分层：geometry（值类型）→ layout（纯函数内核）→ tree（retained 树）
#       → render（DrawList 与后端）→ platform（窗口/输入）→ widget / dsl

require "./tessell/version"
require "./tessell/geometry"

module Tessell
  # UI 主循环必须运行在独占系统线程的执行上下文中。
  # 业务代码留在默认 context；跨界只用 Channel 传不可变快照。
  def self.ui_context : Fiber::ExecutionContext::Isolated
    Fiber::ExecutionContext::Isolated.new("tessell-ui")
  end
end
