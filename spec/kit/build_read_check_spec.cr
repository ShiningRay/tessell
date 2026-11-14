require "./spec_helper"

# issue #41 第一期：debug 构建下「建树期读未追踪 signal」可视化告警。
# 阈值纪律（宁漏勿误）：peek 与 untrack 永不报；只在 Root#build 的 emit
# 窗口内生效；消息自带修法与出口。默认关闭，debug 构建或显式开启。

private class BuildReadProbe < Tessell::Kit::Component
  property on_build : Proc(Tessell::Kit::Context, Nil)?

  def measure(ctx : Tessell::Kit::Context, constraints : Tessell::Constraints) : Tessell::Size
    Tessell::Size.new(constraints.max_width, 24.0_f32)
  end

  def emit(b : Tessell::UI::Builder, ctx : Tessell::Kit::Context) : Nil
    b.node(@key, Tessell::Rect.new(0.0_f32, 0.0_f32, 100.0_f32, 24.0_f32))
    @on_build.try(&.call(ctx))
  end
end

describe "build-phase signal read check (issue #41 phase 1)" do
  it "is disabled by default (release-safe)" do
    Tessell::Signal.build_read_check.should be_false

    sig = Tessell::Signal.signal(1)
    probe = BuildReadProbe.new(KitSpecHelpers.key)
    probe.on_build = ->(ctx : Tessell::Kit::Context) { sig.get; nil }
    root = Tessell::Kit::Root.new(probe)
    root.layout(200.0_f32, 100.0_f32)
    root.build
    root.build_warnings.size.should eq(0) # 默认不开：零开销、零噪音
  end

  it "warns on untracked signal read inside the build window" do
    Tessell::Signal.build_read_check = true
    begin
      sig = Tessell::Signal.signal(1)
      probe = BuildReadProbe.new(KitSpecHelpers.key)
      probe.on_build = ->(ctx : Tessell::Kit::Context) { sig.get; nil }
      root = Tessell::Kit::Root.new(probe)
      root.layout(200.0_f32, 100.0_f32)
      root.build

      root.build_warnings.size.should eq(1)
      msg = root.build_warnings.first
      msg.should contain("'Tessell::Signal::Signal(Int32)'")
      msg.should contain("effect")    # 修法
      msg.should contain("peek")      # 出口
    ensure
      Tessell::Signal.build_read_check = false
    end
  end

  it "never reports peek/untrack reads or effect-tracked reads" do
    Tessell::Signal.build_read_check = true
    begin
      sig = Tessell::Signal.signal(1)
      other = Tessell::Signal.signal(2)
      probe = BuildReadProbe.new(KitSpecHelpers.key)
      probe.on_build = ->(ctx : Tessell::Kit::Context) do
        sig.peek                       # 显式一次性读：不报
        Tessell::Signal.untrack { other.get } # 显式退出追踪：不报
        Tessell::Signal.effect { sig.get }    # 追踪读：不报
        nil
      end
      root = Tessell::Kit::Root.new(probe)
      root.layout(200.0_f32, 100.0_f32)
      root.build

      root.build_warnings.size.should eq(0)
    ensure
      Tessell::Signal.build_read_check = false
    end
  end

  it "surfaces warnings through DebugInfo and the overlay (可视化)" do
    Tessell::Signal.build_read_check = true
    begin
      sig = Tessell::Signal.signal(1)
      probe = BuildReadProbe.new(KitSpecHelpers.key)
      probe.on_build = ->(ctx : Tessell::Kit::Context) { sig.get; nil }
      root = Tessell::Kit::Root.new(probe)
      root.layout(200.0_f32, 100.0_f32)
      root.build

      info = Tessell::Kit::DebugInfo.collect(Tessell::Render::FrameStats.new, nil, root, 16.0_f32)
      info.build_warnings.size.should eq(1)

      root.debug_overlay.visible = true
      p = Tessell::Kit::PaintListPainter.new
      cmds = root.debug_overlay.paint(p, root.context, info,
        Tessell::Rect.new(0.0_f32, 0.0_f32, 400.0_f32, 300.0_f32))
      text_cmds = p.list.to_a.select { |c| c.kind == Tessell::Kit::PaintKind::Text }
      text_cmds.any? { |c| c.text.includes?("⚠ signal 建树期读") }.should be_true
      cmds.should be > 0
    ensure
      Tessell::Signal.build_read_check = false
      root.not_nil!.debug_overlay.visible = false
    end
  end
end
