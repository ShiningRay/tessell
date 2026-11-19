# 增量提交的全量重放 oracle（issue #58，机制来源：NSGo core/commit.go 的
# debug 全量重放校验）。
#
# 原理：固定 seed 生成确定性更新序列；每步同时跑
#   a) 增量路径（CachedNode.update + solve_cached，缓存/脏标沿用上一步）
#   b) 从零重建的全量路径（build_cached 重来）
# 逐节点比较快照（id + rect）。任何缓存键遗漏、脏标漏传播、复用缓冲
# 残留都会让 a ≠ b，oracle 失败并输出 seed、步号、节点 id 与首个差异。
#
# 仅限 test/debug：不进 release 热路径，不改计数门禁语义（AGENTS #10）。

require "../spec_helper"
require "../../src/tessell"
require "../../src/tessell/layout"

include Tessell
include Tessell::Layout

# 确定性 PRNG（xorshift64），固定 seed 可复现——失败输出 seed 即可重放。
struct ReplayRandom
  @state : UInt64

  def initialize(@seed : UInt64)
    raise "seed must be nonzero" if @seed == 0
    @state = @seed
  end

  def next_u64 : UInt64
    x = @state
    x ^= x << 13
    x ^= x >> 7
    x ^= x << 17
    @state = x
    x
  end

  def next_int(range : Range(Int32, Int32)) : Int32
    range.begin + (next_u64 % (range.size.to_u64)).to_i32
  end

  def next_f32 : Float32
    (next_u64 & 0xFFFFFF_u64).to_f32 / 16777216.0_f32
  end
end

module ReplayOracle
  extend self

  record SnapshotEntry, id : String, x : Float32, y : Float32,
    w : Float32, h : Float32

  # 更新语义：target_id 节点的某字段改为 value。
  # kind: 0=text 1=width 2=height 3=padding 4=gap
  record Mutation, target_id : String, kind : Int32, value : Float32

  # 固定形状三层树（root→2 容器→各 2 叶），id 可寻址；文本叶让
  # update 的 text 通道与尺寸通道都参与序列。
  def build_mutable_tree : Layout::LayoutNode
    leaf = ->(id : String) {
      Layout::LayoutNode.new(id: id, width: Fixed.new(60.0_f32),
        height: Fixed.new(20.0_f32), text: "leaf-#{id}",
        font_size: 14.0_f32)
    }
    inner = ->(id : String, a : String, b : String) {
      Layout::LayoutNode.new(id: id, width: Auto.new,
        height: Auto.new, direction: Layout::Direction::Vertical,
        gap: 4.0_f32, padding: Insets.new(2.0_f32, 2.0_f32, 2.0_f32, 2.0_f32),
        children: [leaf.call(a), leaf.call(b)])
    }
    Layout::LayoutNode.new(id: "root", width: Fixed.new(200.0_f32),
      height: Fixed.new(120.0_f32),
      direction: Layout::Direction::Horizontal, gap: 6.0_f32,
      children: [inner.call("c1", "a1", "a2"), inner.call("c2", "b1", "b2")])
  end

  MUTABLE_IDS = ["a1", "a2", "b1", "b2", "c1", "c2", "root"]

  # 纯函数重写：命中 target_id 即按 kind 改字段并沿路径重建（LayoutNode
  # 是 struct，必须路径重建携带新子树）。
  def mutate_node(node : Layout::LayoutNode, m : Mutation) : Layout::LayoutNode
    if node.id == m.target_id
      return rebuilt(node, mutation_overrides(node, m))
    end
    return node if node.children.empty?
    changed = false
    children = node.children.map do |c|
      nc = mutate_node(c, m)
      changed ||= !semantically_same?(nc, c)
      nc
    end
    return node unless changed
    rebuilt_with(node, nil, children)
  end

  # 布局语义比较：委托 Layout.semantically_same?（issue #58 单一真相）。
  def semantically_same?(a : Layout::LayoutNode, b : Layout::LayoutNode) : Bool
    Layout.semantically_same?(a, b)
  end

  private def mutation_overrides(node : Layout::LayoutNode, m : Mutation) : Hash(Symbol, Float32 | String)?
    case m.kind
    when 0 then {:text => "leaf-#{node.id}-#{m.value.to_i}"} of Symbol => Float32 | String
    when 1 then {:width => m.value} of Symbol => Float32 | String
    when 2 then {:height => m.value} of Symbol => Float32 | String
    when 3 then {:padding => m.value} of Symbol => Float32 | String
    when 4 then {:gap => m.value} of Symbol => Float32 | String
    else        nil
    end
  end

  private def rebuilt(node : Layout::LayoutNode,
                      overrides : Hash(Symbol, Float32 | String)?) : Layout::LayoutNode
    rebuilt_with(node, overrides, node.children)
  end

  private def rebuilt_with(node : Layout::LayoutNode,
                           overrides : Hash(Symbol, Float32 | String)?,
                           children : Array(Layout::LayoutNode)) : Layout::LayoutNode
    w : Dimension = node.width
    h : Dimension = node.height
    pad : Insets = node.padding
    gap : Float32 = node.gap
    text : String = node.text
    if overrides
      w = Fixed.new(overrides[:width].as(Float32)) if overrides.has_key?(:width)
      h = Fixed.new(overrides[:height].as(Float32)) if overrides.has_key?(:height)
      pv = overrides[:padding]?.as?(Float32)
      pad = Insets.new(pv, pv, pv, pv) if pv
      gap = overrides[:gap].as(Float32) if overrides.has_key?(:gap)
      text = overrides[:text].as(String) if overrides.has_key?(:text)
    end
    Layout::LayoutNode.new(
      id: node.id,
      width: w,
      height: h,
      padding: pad,
      margin: node.margin,
      direction: node.direction,
      gap: gap,
      children: children,
      text: text,
      font_id: node.font_id,
      font_size: node.font_size
    )
  end

  # Layout 序列校验：steps 步随机 mutation；增量树 update+solve_cached，
  # 全量树从零 build_cached。返回 nil=一致；非 nil=首个差异描述。
  def verify_layout(seed : UInt64, steps : Int32 = 40) : String?
    rng = ReplayRandom.new(seed)
    source = build_mutable_tree
    constraints = Constraints.new(0.0_f32, 200.0_f32, 0.0_f32, 200.0_f32)
    cached = Layout.build_cached(source)
    measurer = Tessell::Text::StubMeasurer.new

    step = 0
    while step < steps
      m = Mutation.new(MUTABLE_IDS[rng.next_int(0...MUTABLE_IDS.size)],
        rng.next_int(0...5), (rng.next_f32 * 80.0_f32 + 20.0_f32).round(1))
      source = mutate_node(source, m)

      cached.update(source)
      inc_result = Layout.solve_cached(cached, constraints, measurer: measurer)

      fresh = Layout.build_cached(source)
      full_result = Layout.solve_cached(fresh, constraints, measurer: measurer)

      inc_snap = [] of SnapshotEntry
      full_snap = [] of SnapshotEntry
      snapshot(inc_result[:box], source, inc_snap)
      snapshot(full_result[:box], source, full_snap)
      if diff = first_diff(inc_snap, full_snap)
        return "seed=#{seed} step=#{step} mutation=target=#{m.target_id} kind=#{m.kind} value=#{m.value} → #{diff}"
      end
      step += 1
    end
    nil
  end

  def snapshot(box : Layout::LayoutBox, node : Layout::LayoutNode,
               sink : Array(SnapshotEntry)) : Nil
    sink << SnapshotEntry.new(node.id, box.rect.origin.x, box.rect.origin.y,
      box.rect.size.width, box.rect.size.height)
    box.children.each_with_index do |cb, i|
      snapshot(cb, node.children[i], sink)
    end
  end

  def first_diff(a : Array(SnapshotEntry), b : Array(SnapshotEntry)) : String?
    return "节点数不同 inc=#{a.size} full=#{b.size}" unless a.size == b.size
    a.zip(b).each do |ea, eb|
      unless ea.id == eb.id && ea.x == eb.x && ea.y == eb.y && ea.w == eb.w && ea.h == eb.h
        return "节点 #{ea.id}: inc=(#{ea.x},#{ea.y},#{ea.w}×#{ea.h}) full=(#{eb.x},#{eb.y},#{eb.w}×#{eb.h})"
      end
    end
    nil
  end
end
