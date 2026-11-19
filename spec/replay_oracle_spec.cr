require "./spec_helper"
require "./support/replay"

# issue #58：增量提交的全量重放 oracle。
# - 负例：绕过失效通道直接换 source（模拟漏标/缓存键遗漏），增量普通
#   solve 不重测、可能通过既有 spec，而全量重放校验必失败——oracle 敏感性。
# - 回归：CachedNode#update 现在比较完整布局语义（text/尺寸/padding/margin/
  # 方向/gap），非文本字段变化同样标脏，增量==全量。
# - seed 序列：8 个 seed × 200 步随机更新，增量与全量逐节点一致。
# - 失败输出 seed/步号/节点 id/首个差异；不使用 wall-clock（AGENTS #10）。

describe "ReplayOracle: incremental vs full-replay (issue #58)" do
  it "负例：漏标脏的增量树被 oracle 抓到（缓存键遗漏可观测）" do
    source0 = ReplayOracle.build_mutable_tree
    constraints = Constraints.new(0.0_f32, 200.0_f32, 0.0_f32, 200.0_f32)
    cached = Layout.build_cached(source0)
    Layout.solve_cached(cached, constraints)

    # 模拟漏标：绕过 update/mark_dirty 直接换根 source（恶意/宿主误用）
    source1 = ReplayOracle.mutate_node(source0,
      ReplayOracle::Mutation.new("a1", 1, 120.0_f32))
    cached.source = source1
    inc = Layout.solve_cached(cached, constraints)

    fresh = Layout.build_cached(source1)
    full = Layout.solve_cached(fresh, constraints)

    inc_snap = [] of ReplayOracle::SnapshotEntry
    full_snap = [] of ReplayOracle::SnapshotEntry
    ReplayOracle.snapshot(inc[:box], source1, inc_snap)
    ReplayOracle.snapshot(full[:box], source1, full_snap)
    diff = ReplayOracle.first_diff(inc_snap, full_snap)
    diff.should_not be_nil # oracle 必抓到：漏标 → 增量复用旧几何
  end

  it "回归：非文本字段（尺寸/padding/gap）变化 update 现在标脏，增量==全量" do
    source0 = ReplayOracle.build_mutable_tree
    constraints = Constraints.new(0.0_f32, 200.0_f32, 0.0_f32, 200.0_f32)
    cached = Layout.build_cached(source0)
    Layout.solve_cached(cached, constraints)

    {"a1" => 1, "root" => 3, "c2" => 4}.each do |target, kind|
      source = ReplayOracle.mutate_node(cached.source,
        ReplayOracle::Mutation.new(target, kind, 77.0_f32))
      dirty_before = cached.dirty?
      cached.update(source)
      cached.dirty?.should be_true,
        "update 后必须标脏（target=#{target} kind=#{kind}，此前 dirty=#{dirty_before}）"
      inc = Layout.solve_cached(cached, constraints)
      fresh = Layout.build_cached(source)
      full = Layout.solve_cached(fresh, constraints)
      inc_snap = [] of ReplayOracle::SnapshotEntry
      full_snap = [] of ReplayOracle::SnapshotEntry
      ReplayOracle.snapshot(inc[:box], source, inc_snap)
      ReplayOracle.snapshot(full[:box], source, full_snap)
      ReplayOracle.first_diff(inc_snap, full_snap).should be_nil,
        "target=#{target} kind=#{kind} 增量与全量不一致"
    end
  end

  it "seed 序列：8 个 seed × 200 步更新增量与全量逐节点一致" do
    (1_u64..8_u64).each do |seed|
      if diff = ReplayOracle.verify_layout(seed, 200)
        fail "replay oracle mismatch: #{diff}"
      end
    end
  end

  it "失败输出可定位：人造不一致返回节点 id 与两侧几何" do
    a = [ReplayOracle::SnapshotEntry.new("n0", 0.0_f32, 0.0_f32, 10.0_f32, 10.0_f32),
         ReplayOracle::SnapshotEntry.new("n1", 0.0_f32, 10.0_f32, 10.0_f32, 5.0_f32)]
    b = [ReplayOracle::SnapshotEntry.new("n0", 0.0_f32, 0.0_f32, 10.0_f32, 10.0_f32),
         ReplayOracle::SnapshotEntry.new("n1", 0.0_f32, 10.0_f32, 99.0_f32, 5.0_f32)]
    diff = ReplayOracle.first_diff(a, b)
    diff.should_not be_nil
    diff.not_nil!.should contain("n1")
    diff.not_nil!.should contain("99.0")
  end
end
