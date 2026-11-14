# Tessell::Input::HitTest — 命中测试（M2-WP1，K1 裁切）。
#
# 规则：从 root 起 DFS；子节点**逆序**遍历（后加的在上面，z-order）；
# 返回包含 p 且未被 clip 排除的最深节点；p 不在 root bounds/clip 内返回 nil。
# 边界点用 Rect#contains?（含边界）；不修改树。
# 前提：bounds/clip 均为 root 坐标系（绝对坐标）。
require "../geometry"
require "../core/node"

module Tessell
  module Input
    module HitTest
      def self.deepest(root : Node, p : Point) : Node?
        return nil unless root.bounds.contains?(p)
        return nil if (clip = root.clip) && !clip.contains?(p)
        deepest_impl(root, p)
      end

      private def self.deepest_impl(node : Node, p : Point) : Node?
        children = node.children
        i = children.size - 1
        while i >= 0
          child = children[i]
          if child.bounds.contains?(p) && (child.clip.nil? || child.clip.not_nil!.contains?(p))
            return deepest_impl(child, p)
          end
          i -= 1
        end
        node
      end
    end
  end
end
