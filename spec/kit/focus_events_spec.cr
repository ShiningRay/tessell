require "./spec_helper"

# issue #26：Event::Kind::Focus 曾"存在但永不投递"。
# 契约（Root#sync_focus 注释同步）：
#   组件间转移 A→B：A.on_focus_changed(false) → B.handle(Focus) → B.on_focus_changed(true)
#   窗口级失焦：先 handle(Blur)，再 on_focus_changed(false)
# Blur 事件语义 = 窗口失焦；组件间转移不投递 Blur。

private class FocusProbe < Tessell::Kit::Component
  getter log = [] of String

  def measure(ctx : Tessell::Kit::Context, constraints : Tessell::Constraints) : Tessell::Size
    Tessell::Size.new(constraints.max_width, 24.0_f32)
  end

  def emit(b : Tessell::UI::Builder, ctx : Tessell::Kit::Context) : Nil
    b.node(@key, Tessell::Rect.new(0.0_f32, 0.0_f32, 100.0_f32, 24.0_f32))
  end

  def handle(event : Tessell::Kit::Event, ctx : Tessell::Kit::Context) : Bool
    @log << "event(#{event.kind})"
    true
  end

  def focusable? : Bool
    true
  end

  def on_focus_changed(focused : Bool) : Nil
    super
    @log << "focus_changed(#{focused})"
  end
end

private def probe_root : {Tessell::Kit::Root, FocusProbe}
  probe = FocusProbe.new(KitSpecHelpers.key)
  root = Tessell::Kit::Root.new(probe)
  root.layout(200.0_f32, 100.0_f32)
  root.build
  {root, probe}
end

describe "Tessell::Kit focus event delivery (issue #26)" do
  it "delivers Event.focus exactly once on programmatic gain" do
    root, probe = probe_root
    root.focus(probe).should be_true

    probe.log.should eq(["event(Focus)", "focus_changed(true)"])
  end

  it "keeps transfer order: loser callback first, winner event then callback" do
    a = FocusProbe.new(KitSpecHelpers.key.child(1_u64))
    b = FocusProbe.new(KitSpecHelpers.key.child(2_u64))
    root = Tessell::Kit::Root.new(
      Tessell::Kit::Column.new(KitSpecHelpers.key, Tessell::Insets.all(0.0_f32), 0.0_f32)
        .tap { |col| col.add(a); col.add(b) }
    )
    root.layout(200.0_f32, 100.0_f32)
    root.build
    root.focus(a).should be_true

    root.focus(b).should be_true

    a.log.should eq(["event(Focus)", "focus_changed(true)", "focus_changed(false)"])
    b.log.should eq(["event(Focus)", "focus_changed(true)"])
  end

  it "does not re-deliver when focusing the already-focused component" do
    root, probe = probe_root
    root.focus(probe)
    probe.log.clear

    root.focus(probe).should be_true
    probe.log.size.should eq(0)
  end

  it "delivers Blur event before on_focus_changed(false) on window blur" do
    root, probe = probe_root
    root.focus(probe)
    probe.log.clear

    root.handle(Tessell::Input::Event.blur).should be_true

    probe.log.should eq(["event(Blur)", "focus_changed(false)"])
  end

  it "delivers Focus after Tab focus-ring movement (same path as programmatic)" do
    probe = FocusProbe.new(KitSpecHelpers.key)
    root = Tessell::Kit::Root.new(probe)
    root.layout(200.0_f32, 100.0_f32)
    root.build

    root.handle(Tessell::Input::Event.key_down(Tessell::Input::KeyCode::Tab)).should be_true

    probe.log.should eq(["event(Focus)", "focus_changed(true)"])
  end
end
