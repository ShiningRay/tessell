# Tessell::Layout — 两遍布局内核（纯函数）+ 增量层（issue #34）。
# 设计输入：docs/research/layout-two-pass.md；用例：spec/layout_spec.cr、
# spec/layout_cached_spec.cr。
# 约束：不依赖 widget/UI/FFI；相同输入得到相同输出；无全局状态。
# 热路径若仍需 Array 缓冲，标 TODO(M1-WP5) 复用/零分配，不假装零分配。
# 增量层（文件尾）：CachedNode 每节点双层缓存 + MarkDirty 早停 + 帧间变更
# 上报；纯函数路径是 oracle，两套几何一致性由 spec 锁住。

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
  # ---------- 增量层（issue #34）----------
  #
  # 可变 CachedNode 图 + 每节点双层缓存（final 单槽 + 8 槽测量环形缓冲）
  # + MarkDirty 父链早停 + 帧间变更上报。与纯函数 Layout.solve 并存：
  # 纯函数路径是 oracle（spec 断言两者几何一致），增量路径服务稳态帧——
  # 改一个叶子只重测该叶子并重摆上游盒子，不动的子树连测量都不进。
  #
  # 与 CachingMeasurer（issue #6，内容键控）配合：同内容两节点只测一次。
  # 变更上报返回帧内 rect 真变的节点 id，对接脏矩形/SetFrame 等价物。

  MEASURE_SLOTS = 8

  class CachedNode
    getter id : String
    property source : LayoutNode
    getter children : Array(CachedNode)
    getter parent : CachedNode?
    property dirty : Bool

    # 测量环形缓冲：键=规范化约束（min/max w/h），值=Size。
    @mkeys : StaticArray(Tuple(Float32, Float32, Float32, Float32), 8)
    @mvals : StaticArray(Size, 8)
    @mcount : Int32
    @mcursor : Int32
    # final 单槽（根节点用）：整树 solve 缓存键与上帧输出。
    @final_key : Tuple(Float32, Float32, Float32, Float32, Float32, Float32)?
    @final_box : LayoutBox?
    @frame_rects : Hash(String, Rect)
    @next_rects : Hash(String, Rect)

    def initialize(@id : String, @source : LayoutNode, @parent : CachedNode? = nil)
      # 子树由 CachedNode.build 构造后挂接（避免 initialize 内 self 逃逸）。
      # 默认干净：首帧由 final_key=nil 走全量路径。
      @children = [] of CachedNode
      @dirty = false
      @mkeys = StaticArray(Tuple(Float32, Float32, Float32, Float32), 8).new({0.0_f32, 0.0_f32, 0.0_f32, 0.0_f32})
      @mvals = StaticArray(Size, 8).new(Size.new(0.0_f32, 0.0_f32))
      @mcount = 0
      @mcursor = 0
      @final_key = nil
      @final_box = nil
      @frame_rects = {} of String => Rect
      @next_rects = {} of String => Rect
    end

    # 递归构建：先构造节点（ivars 全就绪），再挂接子树与父链。
    def self.build(node : LayoutNode, parent : CachedNode? = nil) : CachedNode
      n = CachedNode.new(node.id, node, parent)
      node.children.each do |c|
        n.children << CachedNode.build(c, n)
      end
      n
    end

    def dirty? : Bool
      @dirty
    end

    # 结构/内容更新：children id 集合不变 → 原位替换 source（文本变化标脏）；
    # 结构变化 → 重建子树。返回是否发生文本级变化（供计数断言）。
    def update(source : LayoutNode) : Bool
      same_children = @source.children.size == source.children.size &&
                      @source.children.each_with_index.all? { |c, i| c.id == source.children[i].id }
      text_changed = @source.text != source.text
      @source = source
      unless same_children
        @children = source.children.map { |c| CachedNode.build(c, self) }
        mark_dirty
        return true
      end
      # 原位同步子节点的 source（文本/尺寸可能变化）
      @children.each_with_index { |ch, i| ch.update(source.children[i]) }
      if text_changed
        mark_dirty
      end
      text_changed
    end

    def mark! : Nil
      @dirty = true
      @mcount = 0
      @final_key = nil
    end

    # 实例入口：沿父链标脏（早停），返回新标脏节点数。
    def mark_dirty : Int32
      Layout.mark_dirty(self)
    end

    def final_key : Tuple(Float32, Float32, Float32, Float32, Float32, Float32)?
      @final_key
    end

    def final_box : LayoutBox?
      @final_box
    end

    def final_key=(key : Tuple(Float32, Float32, Float32, Float32, Float32, Float32)?) : Nil
      @final_key = key
    end

    def final_box=(box : LayoutBox?) : Nil
      @final_box = box
    end

    def frame_rects : Hash(String, Rect)
      @frame_rects
    end

    def swap_frame_rects(next_rects : Hash(String, Rect)) : Nil
      @frame_rects, @next_rects = @next_rects, @frame_rects
    end

    def next_rects : Hash(String, Rect)
      @next_rects
    end

    def clear_dirty : Nil
      @dirty = false
      @children.each(&.clear_dirty)
    end

    def measure_lookup(key : Tuple(Float32, Float32, Float32, Float32)) : Size?
      i = 0
      while i < @mcount
        k = @mkeys[i]
        if Layout.key_eq(k, key)
          return @mvals[i]
        end
        i += 1
      end
      nil
    end

    def measure_store(key : Tuple(Float32, Float32, Float32, Float32), value : Size) : Nil
      if @mcount < MEASURE_SLOTS
        @mkeys[@mcount] = key
        @mvals[@mcount] = value
        @mcount += 1
      else
        @mkeys[@mcursor] = key
        @mvals[@mcursor] = value
        @mcursor = (@mcursor + 1) % MEASURE_SLOTS
      end
    end
  end

  # 键相等：NaN 视为相等（asuka 口径）；INFINITY == INFINITY 原生成立。
  def self.key_eq(a : Tuple(Float32, Float32, Float32, Float32),
                  b : Tuple(Float32, Float32, Float32, Float32)) : Bool
    Layout.float_eq(a[0], b[0]) && Layout.float_eq(a[1], b[1]) &&
      Layout.float_eq(a[2], b[2]) && Layout.float_eq(a[3], b[3])
  end

  def self.float_eq(a : Float32, b : Float32) : Bool
    (a == b) || (a.nan? && b.nan?)
  end

  # MarkDirty 父链早停：返回本次新标脏的节点数。祖先已脏即止——
  # 第二次标同一叶子返回 0（断言用）。
  def self.mark_dirty(node : CachedNode) : Int32
    count = 0
    current = node
    while current
      break if current.dirty?
      current.mark!
      count += 1
      current = current.parent
    end
    count
  end

  # 增量 measure：环形缓冲命中即返回（零测量）；未命中才下沉计算。
  def self.measure_cached(node : CachedNode, constraints : Constraints,
                          measurer : Text::Measurer? = nil) : Size
    key = {constraints.min_width, constraints.max_width,
           constraints.min_height, constraints.max_height}
    if (hit = node.measure_lookup(key))
      return hit
    end

    src = node.source
    avail_w = constraints.max_width
    avail_h = constraints.max_height
    size = if node.children.empty?
             intrinsic_w_leaf = 0.0_f32
             if measurer && !src.text.empty? && src.width.is_a?(Auto)
               intrinsic_w_leaf = measurer.not_nil!.measure(src.text, src.font_id, src.font_size, avail_w).width
             end
             intrinsic_h_leaf = 0.0_f32
             if measurer && !src.text.empty? && src.height.is_a?(Auto)
               intrinsic_h_leaf = measurer.not_nil!.measure(src.text, src.font_id, src.font_size, avail_w).height
             end
             w = resolve_measure(src.width, avail_w, intrinsic_w_leaf) + src.padding.horizontal
             h = resolve_measure(src.height, avail_h, intrinsic_h_leaf) + src.padding.vertical
             constraints.constrain(Size.new(w, h))
           else
             inner_w = clamp_avail(avail_w - src.padding.horizontal)
             inner_h = clamp_avail(avail_h - src.padding.vertical)
             child_constraints = Constraints.new(0.0_f32, inner_w, 0.0_f32, inner_h)
             sizes = node.children.map { |ch| measure_cached(ch, child_constraints, measurer) }
             intrinsic_w, intrinsic_h = aggregate_intrinsic(src, sizes)
             w = resolve_measure(src.width, avail_w, intrinsic_w) + src.padding.horizontal
             h = resolve_measure(src.height, avail_h, intrinsic_h) + src.padding.vertical
             constraints.constrain(Size.new(w, h))
           end
    node.measure_store(key, size)
    size
  end

  # 增量 arrange：子尺寸全部命中节点缓存，不触发 measurer。
  def self.arrange_cached(node : CachedNode, rect : Rect,
                          measurer : Text::Measurer? = nil) : LayoutBox
    content = Rect.new(
      rect.origin.x + node.source.padding.left,
      rect.origin.y + node.source.padding.top,
      clamp_avail(rect.size.width - node.source.padding.horizontal),
      clamp_avail(rect.size.height - node.source.padding.vertical)
    )

    return LayoutBox.new(rect, [] of LayoutBox) if node.children.empty?

    child_constraints = Constraints.new(0.0_f32, content.size.width, 0.0_f32, content.size.height)
    child_sizes = node.children.map { |ch| measure_cached(ch, child_constraints, measurer) }
    main_sizes = resolve_main(node.source, node.source.children, child_sizes, content)
    child_boxes = [] of LayoutBox
    cursor = node.source.vertical? ? content.origin.y : content.origin.x
    node.children.each_with_index do |ch, i|
      cross = resolve_cross(node.source, ch.source, child_sizes[i],
        node.source.vertical? ? content.size.width : content.size.height)
      ms = main_sizes[i]
      child_rect = if node.source.vertical?
                     Rect.new(content.origin.x, cursor, cross, ms)
                   else
                     Rect.new(cursor, content.origin.y, ms, cross)
                   end
      child_boxes << arrange_cached(ch, child_rect, measurer)
      cursor += ms + node.source.gap
    end
    LayoutBox.new(rect, child_boxes)
  end

  # 增量 solve：根 final 单槽命中（未脏且键相同）时返回上帧 box + 空变更，
  # 一次测量都不进；否则增量 measure/arrange，并对比帧间 per-id rect 上报变更。
  # 返回 NamedTuple(box, changed)：changed 是 rect 真变的节点 id（对接脏矩形）。
  def self.solve_cached(root : CachedNode, constraints : Constraints,
                        origin : Point = Point.new,
                        measurer : Text::Measurer? = nil) : NamedTuple(box: LayoutBox, changed: Array(String))
    key = {constraints.min_width, constraints.max_width,
           constraints.min_height, constraints.max_height,
           origin.x, origin.y}
    if !root.dirty? && root.final_key == key && (last = root.final_box)
      return {box: last, changed: [] of String}
    end

    size = measure_cached(root, constraints, measurer)
    final_size = constraints.constrain(size)
    box = arrange_cached(root, Rect.new(origin.x, origin.y, final_size.width, final_size.height), measurer)

    # 帧间 diff：新旧两份 per-id rect 表（clear 保留容量）。
    changed = [] of String
    next_rects = root.next_rects
    next_rects.clear
    collect_rects(root, box, next_rects)
    frame_rects = root.frame_rects
    next_rects.each do |id, rect|
      old = frame_rects[id]?
      changed << id if old.nil? || old != rect
    end
    root.swap_frame_rects(next_rects)

    root.final_key = key
    root.final_box = box
    root.clear_dirty
    {box: box, changed: changed}
  end

  private def self.collect_rects(node : CachedNode, box : LayoutBox, sink : Hash(String, Rect)) : Nil
    sink[node.id] = box.rect
    box.children.each_with_index { |cb, i| collect_rects(node.children[i], cb, sink) }
  end

  # 从纯函数 LayoutNode 树构建增量树。
  def self.build_cached(node : LayoutNode) : CachedNode
    CachedNode.build(node)
  end
  end
end
