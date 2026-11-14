require "./spec_helper"

# issue #42：apply 重入隔离——宿主回调（apply_hook/emit 重入）触发失效时
# 外层批不被触碰，失效延迟为二段提交。对照 asuka ui/root.go apply 的
# spare batch：retained 全树重建等价于「内层批只含自己的命令」，实现为
# pending 通道 + 外层返回后完整重建。

private class ReentryProbe < Tessell::Kit::Component
  property root_ref : Tessell::Kit::Root? = nil
  property reenter_in_apply : Bool = false
  getter emits = 0

  def measure(ctx : Tessell::Kit::Context, constraints : Tessell::Constraints) : Tessell::Size
    Tessell::Size.new(constraints.max_width, 24.0_f32)
  end

  def emit(b : Tessell::UI::Builder, ctx : Tessell::Kit::Context) : Nil
    @emits += 1
    b.node(@key, Tessell::Rect.new(0.0_f32, 0.0_f32, 100.0_f32, 24.0_f32))
    if reenter_in_apply && @emits == 1
      @root_ref.try(&.build) # emit 重入 build（只重入一次，收敛由测试保证）
    end
  end
end

describe "apply reentry isolation (issue #42)" do
  it "host callback during apply defers the rebuild to a second pass" do
    probe = ReentryProbe.new(KitSpecHelpers.key)
    root = Tessell::Kit::Root.new(probe)
    probe.root_ref = root
    root.layout(200.0_f32, 100.0_f32)
    # 本例只测 apply 期宿主回调；emit 期重入在下一个用例
    root.apply_hook = -> do
      root.apply_hook = nil # 一次性回调（持续触发的收敛由应用层负责）
      root.build # 宿主回调中失效：必须被延迟，不许触碰外层批
      nil
    end

    root.build

    # 外层批完整落地 + 内层失效二段提交：emit 恰 2 次（外层 1 + 二段 1）
    probe.emits.should eq(2)
    node = root.pool.map[probe.key]?
    node.should_not be_nil
    node.not_nil!.bounds.should eq(Tessell::Rect.new(0.0_f32, 0.0_f32, 100.0_f32, 24.0_f32))
    root.apply_hook = nil
  end

  it "emit-phase reentry (build inside build) is deferred, not reentrant" do
    probe = ReentryProbe.new(KitSpecHelpers.key)
    root = Tessell::Kit::Root.new(probe)
    probe.root_ref = root
    probe.reenter_in_apply = true
    root.layout(200.0_f32, 100.0_f32)

    root.build

    probe.emits.should eq(2) # 外层 1 + 延迟二段 1；不递归爆栈
    root.pool.map[probe.key]?.should_not be_nil
  end

  it "normal sequential builds are unaffected by the guard" do
    probe = ReentryProbe.new(KitSpecHelpers.key)
    root = Tessell::Kit::Root.new(probe)
    root.layout(200.0_f32, 100.0_f32)

    root.build
    root.build

    probe.emits.should eq(2)
  end
end
