# Tessell::Input::FocusManager — 焦点管理（M2-WP1）。
#
# 规则：focus(node) 设置焦点并返回旧焦点；next/prev 为**状态式导航**——
# 按 DFS 前序把焦点移到下一/上一可聚焦节点并返回新焦点，循环回绕。
# 焦点环成员：root 有子节点时为 root 后代中可聚焦节点的前序序列
# （root 仅作容器不入环）；**单节点规则**——root 无子节点且 root 可聚焦
# 时，焦点环仅含 root 自身。detach 节点（parent 链不可达 root）与谓词
# 排除节点不参与；当前焦点不在环中时回绕到端点；无候选返回 nil。
# focusable 谓词可注入（默认所有节点可聚焦），本包不修改 Node 类。
require "../core/node"

module Tessell::Input
  class FocusManager
    @focused : Node?
    @focusable : Proc(Node, Bool)

    def initialize
      @focusable = ->(node : Node) { true }
      @focused = nil
    end

    def initialize(&focusable : Node -> Bool)
      @focusable = focusable
      @focused = nil
    end

    def focus(node : Node) : Node?
      old = @focused
      @focused = node
      old
    end

    def focused : Node?
      @focused
    end

    def focused?(node : Node) : Bool
      @focused == node
    end

    def blur : Nil
      @focused = nil
    end

    def focusable?(node : Node) : Bool
      @focusable.call(node)
    end

    # 移到下一个可聚焦节点（前序+回绕）并返回新焦点；无候选返回 nil。
    def next(root : Node) : Node?
      step(root, 1)
    end

    # 移到上一个可聚焦节点（前序+回绕）并返回新焦点；无候选返回 nil。
    def prev(root : Node) : Node?
      step(root, -1)
    end

    private def step(root : Node, dir : Int32) : Node?
      list = [] of Node
      collect_descendants(root, list)
      # 单节点规则：root 无子节点（环空）且 root 可聚焦时，焦点环仅含 root 自身。
      if list.empty? && focusable?(root)
        list << root
      end
      return nil if list.empty?
      current = @focused
      idx = current.nil? ? nil : list.index(current)
      target =
        if idx.nil?
          # 当前焦点不在环中（nil/detach/谓词变更/外部设定）：回绕到端点。
          dir > 0 ? list[0] : list[list.size - 1]
        else
          list[(idx + dir + list.size) % list.size]
        end
      @focused = target
      target
    end

    # 只收集后代（root 有子节点时仅作容器不入环）；前序 DFS，while 索引无闭包。
    private def collect_descendants(node : Node, sink : Array(Node)) : Nil
      children = node.children
      i = 0
      while i < children.size
        child = children[i]
        sink << child if @focusable.call(child)
        collect_descendants(child, sink)
        i += 1
      end
    end
  end
end
