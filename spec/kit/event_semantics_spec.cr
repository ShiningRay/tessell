require "./spec_helper"

# issue #20：Kit 组件只看 Event 就能区分单击/双击与按住重复——
# click_count/timestamp_ms/repeat/drag_distance 由 Root 透传，组件无需
# 自存时间戳或反向依赖 Root/Router。

private class ClickProbe < Tessell::Kit::Component
  getter ups = [] of Tessell::Kit::Event
  getter downs = [] of Tessell::Kit::Event
  getter keys = [] of Tessell::Kit::Event

  def measure(ctx : Tessell::Kit::Context, constraints : Tessell::Constraints) : Tessell::Size
    Tessell::Size.new(constraints.max_width, 24.0_f32)
  end

  def emit(b : Tessell::UI::Builder, ctx : Tessell::Kit::Context) : Nil
    b.node(@key, Tessell::Rect.new(0.0_f32, 0.0_f32, 100.0_f32, 24.0_f32))
  end

  def handle(event : Tessell::Kit::Event, ctx : Tessell::Kit::Context) : Bool
    case event.kind
    when Tessell::Kit::Event::Kind::PointerUp   then @ups << event
    when Tessell::Kit::Event::Kind::PointerDown then @downs << event
    when Tessell::Kit::Event::Kind::KeyDown     then @keys << event
    end
    true
  end

  def focusable? : Bool
    true
  end
end

private def probe_root
  probe = ClickProbe.new(KitSpecHelpers.key)
  root = Tessell::Kit::Root.new(probe)
  root.layout(200.0_f32, 100.0_f32)
  root.build
  {root, probe}
end

describe "Kit::Event input semantics passthrough (issue #20)" do
  it "reports click_count == 2 for two fast clicks on the same target" do
    root, probe = probe_root

    root.handle(Tessell::Input::Event.pointer_down(20.0_f32, 10.0_f32, timestamp_ms: 100_i64)).should be_true
    root.handle(Tessell::Input::Event.pointer_up(20.0_f32, 10.0_f32, timestamp_ms: 120_i64)).should be_true
    probe.ups.last.click_count.should eq(1)

    root.handle(Tessell::Input::Event.pointer_down(20.0_f32, 10.0_f32, timestamp_ms: 180_i64)).should be_true
    root.handle(Tessell::Input::Event.pointer_up(20.0_f32, 10.0_f32, timestamp_ms: 200_i64)).should be_true
    probe.ups.last.click_count.should eq(2)
  end

  it "reports click_count == 1 when the window elapses" do
    root, probe = probe_root
    root.handle(Tessell::Input::Event.pointer_down(20.0_f32, 10.0_f32, timestamp_ms: 100_i64))
    root.handle(Tessell::Input::Event.pointer_up(20.0_f32, 10.0_f32, timestamp_ms: 120_i64))
    root.handle(Tessell::Input::Event.pointer_down(20.0_f32, 10.0_f32, timestamp_ms: 900_i64))
    root.handle(Tessell::Input::Event.pointer_up(20.0_f32, 10.0_f32, timestamp_ms: 920_i64))
    probe.ups.last.click_count.should eq(1)
  end

  it "keeps click_count == 1 when modifiers change between clicks" do
    root, probe = probe_root
    mods = Tessell::Input::Modifiers.new(shift: true)
    root.handle(Tessell::Input::Event.pointer_down(20.0_f32, 10.0_f32, timestamp_ms: 100_i64))
    root.handle(Tessell::Input::Event.pointer_up(20.0_f32, 10.0_f32, timestamp_ms: 120_i64))
    root.handle(Tessell::Input::Event.pointer_down(20.0_f32, 10.0_f32, 0, mods, 180_i64))
    root.handle(Tessell::Input::Event.pointer_up(20.0_f32, 10.0_f32, 0, mods, 200_i64))
    probe.ups.last.click_count.should eq(1)
  end

  it "reports drag_distance on PointerUp and keeps other kinds at default 1" do
    root, probe = probe_root
    root.handle(Tessell::Input::Event.pointer_down(20.0_f32, 10.0_f32, timestamp_ms: 100_i64))
    root.handle(Tessell::Input::Event.pointer_up(50.0_f32, 10.0_f32, timestamp_ms: 120_i64))
    probe.ups.last.drag_distance.should eq(30.0_f32)

    probe.ups.last.timestamp_ms.should eq(120_i64)
    probe.downs.last.timestamp_ms.should eq(100_i64)
    probe.downs.last.click_count.should eq(1)

    root.handle(Tessell::Input::Event.key_down(Tessell::Input::KeyCode::KeyT,
      timestamp_ms: 300_i64, repeat: true))
    probe.keys.last.repeat.should be_true
    probe.keys.last.timestamp_ms.should eq(300_i64)
    probe.keys.last.click_count.should eq(1)
  end
end
