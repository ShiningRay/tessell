# Tessell::Input::HitTest — 命中测试（M2-WP1，K1/K2 裁切）。
#
# 规则：从 root 起 DFS；子节点**逆序**遍历（后加的在上面，z-order）；
# 返回包含 p 且未被祖先/自身 clip 排除的最深节点；p 不在 root bounds/clip 内返回 nil。
# 边界点用 Rect#contains?（含边界）；不修改树。
# 前提：bounds/clip 均为 root 坐标系（绝对坐标）。
require "../geometry"
require "../core/node"

module Tessell
  module Input
    module HitTest
      def self.deepest(root : Node, p : Point) : Node?
        return nil unless root.bounds.contains?(p)
        clip = root.clip
        return nil if clip && !clip.contains?(p)
        deepest_impl(root, p, clip)
      end

      private def self.deepest_impl(node : Node, p : Point, inherited : Rect?) : Node?
        children = node.children
        i = children.size - 1
        while i >= 0
          child = children[i]
          if child.bounds.contains?(p)
            effective = intersect(inherited, child.clip)
            if effective.nil? || effective.not_nil!.contains?(p)
              return deepest_impl(child, p, effective)
            end
          end
          i -= 1
        end
        node
      end

      private def self.intersect(a : Rect?, b : Rect?) : Rect?
        return b unless a
        return a unless b
        x0 = Math.max(a.origin.x, b.origin.x)
        y0 = Math.max(a.origin.y, b.origin.y)
        x1 = Math.min(a.max_x, b.max_x)
        y1 = Math.min(a.max_y, b.max_y)
        w = x1 - x0
        h = y1 - y0
        if w <= 0.0_f32 || h <= 0.0_f32
          Rect.new(x0, y0, 0.0_f32, 0.0_f32)
        else
          Rect.new(x0, y0, w, h)
        end
      end
    end
  end
end
