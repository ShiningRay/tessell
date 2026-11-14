require "./spec_helper"

# issue #43：重复 UiKey 曾使节点父链成环，Root#build 无限挂死
# （沿 parent 上溯的遍历永不终止）。修复：UI.apply 在任何 pool 变更前
# 预检单帧 decl 缓冲内的重复 key，fail-fast raise（ArgumentError），
# 异常路径不留下半套 pool 状态。

private def dup_tree : Tessell::Kit::Column
  # Column 与其子组件共用同一 key（历史触发场景）
  text = Tessell::Kit::Text.new(KitSpecHelpers.key, "a")
  Tessell::Kit::Column.new(KitSpecHelpers.key, Tessell::Insets.all(0.0_f32), 0.0_f32)
    .tap { |col| col.add(text) }
end

describe "duplicate UiKey fail-fast (issue #43)" do
  it "raises instead of hanging when two components share a key" do
    root = Tessell::Kit::Root.new(dup_tree)
    root.layout(200.0_f32, 100.0_f32)

    expect_raises(ArgumentError, "duplicate UiKey") { root.build }
  end

  it "names the fix (key.child derivation) in the message" do
    root = Tessell::Kit::Root.new(dup_tree)
    root.layout(200.0_f32, 100.0_f32)

    expect_raises(ArgumentError, "key.child") { root.build }
  end

  it "detects duplicates nested deep in the tree (not just direct children)" do
    # 两棵子树各有一个组件共享 child(7) key
    a = Tessell::Kit::Text.new(KitSpecHelpers.key.child(1_u64), "a")
    a2 = Tessell::Kit::Text.new(KitSpecHelpers.key.child(7_u64), "dup")
    left = Tessell::Kit::Column.new(KitSpecHelpers.key.child(1_u64),
      Tessell::Insets.all(0.0_f32), 0.0_f32).tap { |c| c.add(a); c.add(a2) }
    b = Tessell::Kit::Text.new(KitSpecHelpers.key.child(7_u64), "dup")
    right = Tessell::Kit::Column.new(KitSpecHelpers.key.child(2_u64),
      Tessell::Insets.all(0.0_f32), 0.0_f32).tap { |c| c.add(b) }
    top = Tessell::Kit::Column.new(KitSpecHelpers.key,
      Tessell::Insets.all(0.0_f32), 0.0_f32).tap { |c| c.add(left); c.add(right) }

    root = Tessell::Kit::Root.new(top)
    root.layout(200.0_f32, 200.0_f32)
    expect_raises(ArgumentError, "duplicate UiKey") { root.build }
  end

  it "keeps stable identity across frames legal (same key rebuilt every frame)" do
    text = Tessell::Kit::Text.new(KitSpecHelpers.key, "stable")
    root = Tessell::Kit::Root.new(text)
    root.layout(200.0_f32, 100.0_f32)

    root.build
    root.build
    root.build

    root.pool.map[KitSpecHelpers.key]?.should_not be_nil
  end

  it "leaves the pool usable after a caught duplicate (no half-applied state)" do
    text = Tessell::Kit::Text.new(KitSpecHelpers.key, "ok")
    root = Tessell::Kit::Root.new(text)
    root.layout(200.0_f32, 100.0_f32)
    root.build
    calls = 0

    # 同一 pool 上：先触发重复异常，再正常 build 仍可用
    dup_root = Tessell::Kit::Root.new(dup_tree)
    dup_root.layout(100.0_f32, 100.0_f32)
    begin
      dup_root.build
    rescue ArgumentError
      calls += 1
    end
    calls.should eq(1)

    root.build
    root.pool.map[KitSpecHelpers.key]?.should_not be_nil
  end
end
