# Tessell::Render — Dirty：脏矩形合并（M1-WP4）。
#
# 语义（先定后码）：
#   1) 重叠或相接（边贴边）的矩形合并为最小包围盒（保守放大：允许覆盖净区）；
#   2) 输出不得含空矩形（宽或高 ≤ 0）；输入中的退化矩形被忽略；
#   3) 输入空数组 → 输出空数组；
#   4) 超过 max_regions 时，按「合并代价最小」贪心合并（代价 = 合并后包围盒面积
#      减两矩形面积和），直到区域数 ≤ max_regions；
#   5) 合并不保证全局最优（贪心），仅保证：结果 ≤ max_regions 且不产空矩形。

require "../geometry"

module Tessell
  module Render
    module Dirty
      # 重叠/相接矩形合并为包围盒；超过 max_regions 时贪心合并到 ≤ max_regions。
      # 实现委托 merge_into（结果数组一次性分配，非热路径）。
      def self.merge(rects : Array(Rect), max_regions : Int32 = 8) : Array(Rect)
        regions = [] of Rect
        merge_into(rects, regions, max_regions)
        regions
      end

      # M1-WP5 稳态零分配路径：复用调用方缓冲 sink 的合并，语义与 merge 完全一致
      # （重叠/相接合并、超限贪心、不产空矩形、空输入空输出）。
      # 约定：进入时 sink.clear（保留容量）；结果写入 sink。
      # 不新分配：选非退化矩形用 while 索引写 sink（不用 select 生成新数组）；
      # 合并原地 union + delete_at（delete_at 仅移动元素，不新分配数组）。
      # 前提：调用方预分配 sink 容量 ≥ rects.size（合并只减不增）。
      def self.merge_into(rects : Array(Rect), sink : Array(Rect), max_regions : Int32 = 8) : Nil
        sink.clear
        i = 0
        while i < rects.size
          r = rects[i]
          if r.size.width > 0.0_f32 && r.size.height > 0.0_f32
            sink << r
          end
          i += 1
        end

        # 第一遍：把重叠/相接的矩形全部并掉（顺序无关的稳定不动点）。
        changed = true
        while changed
          changed = false
          i = 0
          while i < sink.size
            j = i + 1
            while j < sink.size
              if adjacent?(sink[i], sink[j])
                sink[i] = sink[i].union(sink[j])
                sink.delete_at(j)
                changed = true
              else
                j += 1
              end
            end
            i += 1
          end
        end

        # 第二遍：仍超上限时，贪心合并代价最小的一对（面积增量最小），
        # 直到区域数 ≤ max_regions。
        while sink.size > max_regions
          best_i = -1
          best_j = -1
          best_cost = Float64::INFINITY
          a = 0
          while a < sink.size
            b = a + 1
            while b < sink.size
              cost = area_of(sink[a].union(sink[b])) -
                     area_of(sink[a]) - area_of(sink[b])
              if cost < best_cost
                best_cost = cost
                best_i = a
                best_j = b
              end
              b += 1
            end
            a += 1
          end
          break if best_i < 0
          sink[best_i] = sink[best_i].union(sink[best_j])
          sink.delete_at(best_j)
        end

        Nil
      end

      # 全部矩形面积和（Float64，手算可对照）。
      def self.area(rects : Array(Rect)) : Float64
        total = 0.0_f64
        rects.each do |r|
          total += r.size.width.to_f64 * r.size.height.to_f64
        end
        total
      end

      # 重叠或相接（边贴边）：两轴投影均相交或贴边。
      private def self.adjacent?(a : Rect, b : Rect) : Bool
        a.origin.x <= b.max_x && b.origin.x <= a.max_x &&
          a.origin.y <= b.max_y && b.origin.y <= a.max_y
      end

      private def self.area_of(rect : Rect) : Float64
        rect.size.width.to_f64 * rect.size.height.to_f64
      end
    end
  end
end
