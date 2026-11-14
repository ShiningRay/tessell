require "./spec_helper"
require "../src/tessell/layout"
require "../src/tessell/text/measurer"

# issue #34：布局增量缓存——每节点双层缓存 + MarkDirty 父链早停 + 变更上报。
# 计数断言（不依赖 wall-clock）：改一个文本 → measurer 调用 ==1、上游重摆
# 不重测；稳态 solve 零测量；同内容两节点经 CachingMeasurer 只测一次。

private class CountingMeasurer < Tessell::Text::Measurer
  getter calls = 0
  property next_width : Float32 = 10.0_f32

  def measure(text : String, font_id : Int32, size : Float32, max_width : Float32) : Tessell::Size
    @calls += 1
    Tessell::Size.new(@next_width * text.size, size * 1.2_f32)
  end
end

private def leaf(id : String, text : String) : Tessell::Layout::LayoutNode
  # 高度 Fixed：measure/arrange 两遍的约束键稳定（Auto 高会让 arrange 的
  # 紧约束键随内容漂移，导致重测——那属于换键重算，不是增量失效）
  Tessell::Layout::LayoutNode.new(id: id, width: Tessell::Auto.new,
    height: Tessell::Fixed.new(20.0_f32),
    text: text, font_id: 0, font_size: 14.0_f32)
end

private def build_tree : Tessell::Layout::LayoutNode
  # 根/行宽 Fixed：arrange 子约束的 max_width 与 measure 遍一致（键稳定）
  row = Tessell::Layout::LayoutNode.new(id: "row", width: Tessell::Fixed.new(400.0_f32),
    direction: Tessell::Layout::Direction::Horizontal,
    children: [leaf("a", "hello"), leaf("b", "world")])
  Tessell::Layout::LayoutNode.new(id: "root", width: Tessell::Fixed.new(400.0_f32),
    direction: Tessell::Layout::Direction::Vertical,
    children: [row])
end

describe "Layout incremental cache (issue #34)" do
  it "matches the pure-function oracle geometrically" do
    tree = build_tree
    constraints = Tessell::Constraints.new(0.0_f32, 400.0_f32, 0.0_f32, 400.0_f32)

    oracle = Tessell::Layout.solve(tree, constraints, Tessell::Point.new(0.0_f32, 0.0_f32))
    cached_root = Tessell::Layout.build_cached(tree)
    result = Tessell::Layout.solve_cached(cached_root, constraints)

    # 逐 id 比对 rect（oracle vs 增量）
    expected = {} of String => Tessell::Rect
    collect_rects(tree, oracle, expected)
    expected.keys.each do |id|
      got = find_box(result[:box], tree, id)
      got.should_not be_nil
      got.not_nil!.should eq(expected[id])
    end
  end

  it "re-measures only the changed leaf: text update → exactly 1 measurer call" do
    tree = build_tree
    # w/h 两遍用同一键（宽度传入一致），CachingMeasurer 去重后底层恰 1 次
    measurer = CountingMeasurer.new
    caching = Tessell::Text::CachingMeasurer.new(measurer)
    cached_root = Tessell::Layout.build_cached(tree)
    constraints = Tessell::Constraints.new(0.0_f32, 400.0_f32, 0.0_f32, 400.0_f32)
    Tessell::Layout.solve_cached(cached_root, constraints, measurer: caching)
    after_initial = measurer.calls

    # 改 leaf a 的文本
    row = tree.children[0]
    new_row = Tessell::Layout::LayoutNode.new(id: "row",
      width: Tessell::Fixed.new(400.0_f32),
      direction: Tessell::Layout::Direction::Horizontal,
      children: [leaf("a", "hello!!!"), leaf("b", "world")])
    new_root = Tessell::Layout::LayoutNode.new(id: "root",
      width: Tessell::Fixed.new(400.0_f32),
      direction: Tessell::Layout::Direction::Vertical, children: [new_row])
    cached_root.update(new_root)
    Tessell::Layout.mark_dirty(cached_root)

    Tessell::Layout.solve_cached(cached_root, constraints, measurer: caching)

    (measurer.calls - after_initial).should eq(1) # 只有 leaf a 重测
  end

  it "steady-state solve is measurement-free (final single-slot hit)" do
    tree = build_tree
    measurer = CountingMeasurer.new
    cached_root = Tessell::Layout.build_cached(tree)
    constraints = Tessell::Constraints.new(0.0_f32, 400.0_f32, 0.0_f32, 400.0_f32)
    first = Tessell::Layout.solve_cached(cached_root, constraints, measurer: measurer)
    after_first = measurer.calls

    second = Tessell::Layout.solve_cached(cached_root, constraints, measurer: measurer)

    measurer.calls.should eq(after_first)      # 零测量
    second[:box].rect.should eq(first[:box].rect)
    second[:changed].size.should eq(0)          # 无变更上报
  end

  it "reports only changed node ids across frames" do
    tree = build_tree
    cached_root = Tessell::Layout.build_cached(tree)
    constraints = Tessell::Constraints.new(0.0_f32, 400.0_f32, 0.0_f32, 400.0_f32)
    # Auto 宽叶子的 intrinsic 来自 measurer——无 measurer 时宽度恒 0，diff 无从变化
    measurer = CountingMeasurer.new
    Tessell::Layout.solve_cached(cached_root, constraints, measurer: measurer)

    new_row = Tessell::Layout::LayoutNode.new(id: "row",
      width: Tessell::Fixed.new(400.0_f32),
      direction: Tessell::Layout::Direction::Horizontal,
      children: [leaf("a", "hi"), leaf("b", "world")])
    cached_root.update(Tessell::Layout::LayoutNode.new(id: "root",
      width: Tessell::Fixed.new(400.0_f32),
      direction: Tessell::Layout::Direction::Vertical, children: [new_row]))
    Tessell::Layout.mark_dirty(cached_root)
    result = Tessell::Layout.solve_cached(cached_root, constraints, measurer: measurer)

    result[:changed].should contain("a")
    # 行宽 Fixed → row/root rect 不变，不算变更；b 因 x 位移（a 变窄）而变
    result[:changed].should contain("b")
    result[:changed].should_not contain("row")
    result[:changed].should_not contain("root")
  end

  it "MarkDirty stops early along an already-dirty parent chain" do
    tree = build_tree
    cached_root = Tessell::Layout.build_cached(tree)
    leaf_a = cached_root.children[0].children[0]

    first = Tessell::Layout.mark_dirty(leaf_a)
    first.should eq(3) # leaf → row → root

    again = Tessell::Layout.mark_dirty(leaf_a)
    again.should eq(0) # 链上已脏：早停

    row = cached_root.children[0]
    row.mark!
    up = Tessell::Layout.mark_dirty(row)
    up.should eq(0) # 自身已脏：不再上溯
  end

  it "measures same-content nodes once through the content-keyed CachingMeasurer" do
    calls = CountingMeasurer.new
    caching = Tessell::Text::CachingMeasurer.new(calls)
    tree = Tessell::Layout::LayoutNode.new(id: "root",
      width: Tessell::Fixed.new(400.0_f32),
      direction: Tessell::Layout::Direction::Vertical,
      children: [leaf("x", "same"), leaf("y", "same")])
    cached_root = Tessell::Layout.build_cached(tree)
    constraints = Tessell::Constraints.new(0.0_f32, 400.0_f32, 0.0_f32, 400.0_f32)
    Tessell::Layout.solve_cached(cached_root, constraints, measurer: caching)

    calls.calls.should eq(1) # 内容键控：两个节点同文本只测一次
  end

  it "CachingMeasurer stays bounded at CACHE_CAP" do
    calls = CountingMeasurer.new
    caching = Tessell::Text::CachingMeasurer.new(calls)
    i = 0
    while i < Tessell::Text::CachingMeasurer::CACHE_CAP + 10
      caching.measure("key-#{i}", 0, 14.0_f32, Float32::INFINITY)
      i += 1
    end
    # 换代后仍在运行且计数正确（清空全有全无口径）
    caching.measure("after-cap", 0, 14.0_f32, Float32::INFINITY)
    caching.stats[:misses].should be > Tessell::Text::CachingMeasurer::CACHE_CAP
  end
end

private def collect_rects(node : Tessell::Layout::LayoutNode, box : Tessell::Layout::LayoutBox,
                          sink : Hash(String, Tessell::Rect)) : Nil
  sink[node.id] = box.rect
  box.children.each_with_index { |cb, i| collect_rects(node.children[i], cb, sink) }
end

private def find_box(box : Tessell::Layout::LayoutBox, node : Tessell::Layout::LayoutNode,
                     id : String) : Tessell::Rect?
  return box.rect if node.id == id
  box.children.each_with_index do |cb, i|
    if (found = find_box(cb, node.children[i], id))
      return found
    end
  end
  nil
end
