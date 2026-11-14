# Tessell::Layout — 两遍布局内核（纯函数）。
# 设计输入：docs/research/layout-two-pass.md；用例：spec/layout_spec.cr。
# 约束：不依赖 widget/UI/FFI；相同输入得到相同输出；无全局状态。
# 热路径若仍需 Array 缓冲，标 TODO(M1-WP5) 复用/零分配，不假装零分配。

module Tessell
  module Layout
    enum Direction
      Vertical
      Horizontal
    end

    # 布局节点（纯数据，可嵌套）。children 为 Array 缓冲：
    # TODO(M1-WP5): 复用/零分配——稳态热路径应复用预分配缓冲而非每帧 new。
    struct LayoutNode
      getter id : String
      getter width : Dimension
      getter height : Dimension
      getter padding : Insets
      getter margin : Insets
      getter direction : Direction
      # 主轴子项间距（issue #5）；gap 计入容器 intrinsic 与 arrange 游标推进。
      getter gap : Float32
      getter children : Array(LayoutNode)

      # 可选测量缓存字段（纯函数路径不写入；由外层 retained 树按失效策略填充）。
      getter measured : Size?

      # 文本叶子度量输入（仅当注入 Measurer 时使用；默认空串/0，不改变既有 Auto 叶子行为）。
      getter text : String
      getter font_id : Int32
      getter font_size : Float32

      def initialize(@id : String = "",
                     @width : Dimension = Auto.new,
                     @height : Dimension = Auto.new,
                     @padding : Insets = Insets.new,
                     @margin : Insets = Insets.new,
                     @direction : Direction = Direction::Vertical,
                     @gap : Float32 = 0.0_f32,
                     @children : Array(LayoutNode) = [] of LayoutNode,
                     @measured : Size? = nil,
                     @text : String = "",
                     @font_id : Int32 = 0,
                     @font_size : Float32 = 0.0_f32)
      end

      def vertical? : Bool
        @direction == Direction::Vertical
      end
    end

    # 布局结果（不可变值）。子节点以绝对 Rect 存储；偏移可由子 rect.origin - rect.origin 推导。
    struct LayoutBox
      getter rect : Rect
      getter children : Array(LayoutBox)

      def initialize(@rect : Rect, @children : Array(LayoutBox) = [] of LayoutBox)
      end
    end

    # ---------- Pass A : measure ----------
    def self.measure(node : LayoutNode, constraints : Constraints, measurer : Text::Measurer? = nil) : Size
      avail_w = constraints.max_width
      avail_h = constraints.max_height

      if node.children.empty?
        # 叶子：Dimension 解析 + padding（margin 不计入尺寸，由 arrange 处理间距）。
        # 若注入 Measurer 且节点有文本且对应维度为 Auto，则用测量结果作 intrinsic。
        intrinsic_w_leaf = 0.0_f32
        if measurer && !node.text.empty? && node.width.is_a?(Auto)
          intrinsic_w_leaf = measurer.not_nil!.measure(node.text, node.font_id, node.font_size, avail_w).width
        end
        intrinsic_h_leaf = 0.0_f32
        if measurer && !node.text.empty? && node.height.is_a?(Auto)
          intrinsic_h_leaf = measurer.not_nil!.measure(node.text, node.font_id, node.font_size, avail_w).height
        end
        w = resolve_measure(node.width, avail_w, intrinsic_w_leaf) + node.padding.horizontal
        h = resolve_measure(node.height, avail_h, intrinsic_h_leaf) + node.padding.vertical
        constraints.constrain(Size.new(w, h))
      else
        # 容器：先向子节点分发约束并收集其期望尺寸。
        inner_w = clamp_avail(avail_w - node.padding.horizontal)
        inner_h = clamp_avail(avail_h - node.padding.vertical)
        child_constraints = Constraints.new(0.0_f32, inner_w, 0.0_f32, inner_h)
        child_sizes = node.children.map { |ch| measure(ch, child_constraints, measurer) }

        intrinsic_w, intrinsic_h = aggregate_intrinsic(node, child_sizes)
        w = resolve_measure(node.width, avail_w, intrinsic_w) + node.padding.horizontal
        h = resolve_measure(node.height, avail_h, intrinsic_h) + node.padding.vertical
        constraints.constrain(Size.new(w, h))
      end
    end

    # ---------- Pass B : arrange ----------
    def self.arrange(node : LayoutNode, rect : Rect, measurer : Text::Measurer? = nil) : LayoutBox
      content = Rect.new(
        rect.origin.x + node.padding.left,
        rect.origin.y + node.padding.top,
        clamp_avail(rect.size.width - node.padding.horizontal),
        clamp_avail(rect.size.height - node.padding.vertical)
      )

      if node.children.empty?
        return LayoutBox.new(rect, [] of LayoutBox)
      end

      child_constraints = Constraints.new(0.0_f32, content.size.width, 0.0_f32, content.size.height)
      child_sizes = node.children.map { |ch| measure(ch, child_constraints, measurer) }

      main_sizes = resolve_main(node, node.children, child_sizes, content)
      child_boxes = [] of LayoutBox
      cursor = node.vertical? ? content.origin.y : content.origin.x
      # gap 只加在子项之间；剩余主轴分配（Fraction）在 resolve_main 内扣除。

      node.children.each_with_index do |ch, i|
        cross = resolve_cross(node, ch, child_sizes[i], node.vertical? ? content.size.width : content.size.height)
        ms = main_sizes[i]
        child_rect = if node.vertical?
                       Rect.new(content.origin.x, cursor, cross, ms)
                     else
                       Rect.new(cursor, content.origin.y, ms, cross)
                     end
        child_boxes << arrange(ch, child_rect, measurer)
        cursor += ms + node.gap
      end

      LayoutBox.new(rect, child_boxes)
    end

    # 便捷入口：measure → constrain → arrange。
    def self.solve(node : LayoutNode, constraints : Constraints, origin : Point = Point.new, measurer : Text::Measurer? = nil) : LayoutBox
      size = measure(node, constraints, measurer)
      final_size = constraints.constrain(size)
      arrange(node, Rect.new(origin.x, origin.y, final_size.width, final_size.height), measurer)
    end

    # ---------- helpers ----------
    private def self.resolve_measure(dim : Dimension, avail : Float32, intrinsic : Float32) : Float32
      case dim
      when Fixed
        dim.value
      when Fraction
        avail.finite? ? avail * dim.weight : 0.0_f32
      else # Auto
        intrinsic
      end
    end

    private def self.aggregate_intrinsic(node : LayoutNode, sizes : Array(Size)) : {Float32, Float32}
      gaps = node.gap * (sizes.size > 1 ? sizes.size - 1 : 0)
      if node.vertical?
        w = sizes.empty? ? 0.0_f32 : sizes.map(&.width).max
        h = sizes.map(&.height).sum + gaps
        {w, h}
      else
        w = sizes.map(&.width).sum + gaps
        h = sizes.empty? ? 0.0_f32 : sizes.map(&.height).max
        {w, h}
      end
    end

    private def self.resolve_main(node : LayoutNode, children : Array(LayoutNode), sizes : Array(Size), content : Rect) : Array(Float32)
      avail = node.vertical? ? content.size.height : content.size.width
      fixed_total = 0.0_f32
      weight_total = 0.0_f32
      children.each_with_index do |ch, i|
        dim = node.vertical? ? ch.height : ch.width
        case dim
        when Fixed
          fixed_total += dim.value
        when Fraction
          weight_total += dim.weight
        else # Auto
          fixed_total += node.vertical? ? sizes[i].height : sizes[i].width
        end
      end
      # 子项之间的 gap 占用主轴空间，从可分配余量中扣除（issue #5）。
      gaps = node.gap * (children.size > 1 ? children.size - 1 : 0)
      remaining = avail - fixed_total - gaps
      remaining = 0.0_f32 if remaining < 0.0_f32
      result = Array(Float32).new(children.size, 0.0_f32)
      children.each_with_index do |ch, i|
        dim = node.vertical? ? ch.height : ch.width
        case dim
        when Fixed
          result[i] = dim.value
        when Fraction
          result[i] = weight_total > 0.0_f32 ? remaining * (dim.weight / weight_total) : 0.0_f32
        else # Auto
          result[i] = node.vertical? ? sizes[i].height : sizes[i].width
        end
      end
      result
    end

    private def self.resolve_cross(node : LayoutNode, child : LayoutNode, size : Size, avail : Float32) : Float32
      dim = node.vertical? ? child.width : child.height
      case dim
      when Fixed
        dim.value
      when Fraction
        avail.finite? ? avail * dim.weight : 0.0_f32
      else # Auto
        node.vertical? ? size.width : size.height
      end
    end

    private def self.clamp_avail(v : Float32) : Float32
      v < 0.0_f32 ? 0.0_f32 : v
    end
  end
end
