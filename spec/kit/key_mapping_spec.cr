require "./spec_helper"

# issue #27：Kit::Key 与 Input::KeyCode 不漂移。
# Kit::Key 是 Input::KeyCode 的 alias（src/tessell/kit/events.cr），本 spec 锁住
# 唯一允许的两个例外：F1（Root 预留给帧调试 overlay）与普通 Tab 走焦点环
# （除非组件声明 wants_tab?）。

private class KeyProbe < Tessell::Kit::Component
  getter received = [] of Tessell::Kit::Key

  def measure(ctx : Tessell::Kit::Context, constraints : Tessell::Constraints) : Tessell::Size
    Tessell::Size.new(constraints.max_width, 24.0_f32)
  end

  def emit(b : Tessell::UI::Builder, ctx : Tessell::Kit::Context) : Nil
    b.node(@key, Tessell::Rect.new(0.0_f32, 0.0_f32, 120.0_f32, 24.0_f32))
  end

  def handle(event : Tessell::Kit::Event, ctx : Tessell::Kit::Context) : Bool
    if event.kind == Tessell::Kit::Event::Kind::KeyDown && (key = event.key)
      @received << key
      return true
    end
    false
  end

  def focusable? : Bool
    true
  end

  def wants_tab? : Bool
    true
  end
end

describe "Tessell::Kit key mapping (issue #27)" do
  it "delivers every core KeyCode to components unchanged (anti-drift loop)" do
    Tessell::Input::KeyCode.values.each do |code|
      probe = KeyProbe.new(KitSpecHelpers.key)
      root = Tessell::Kit::Root.new(probe)
      root.layout(200.0_f32, 100.0_f32)
      root.build
      root.focus(probe).should be_true

      # F1 是 Root 预留的 overlay 开关，见下一个用例；Tab 经 wants_tab? 透传。
      next if code == Tessell::Input::KeyCode::F1

      root.handle(Tessell::Input::Event.key_down(code, timestamp_ms: 100_i64)).should be_true
      probe.received.should eq([code])
    end
  end

  it "keeps F1 reserved for the debug overlay (documented exception)" do
    probe = KeyProbe.new(KitSpecHelpers.key)
    root = Tessell::Kit::Root.new(probe)
    root.layout(200.0_f32, 100.0_f32)
    root.build
    root.focus(probe)

    root.handle(Tessell::Input::Event.key_down(Tessell::Input::KeyCode::F1, timestamp_ms: 100_i64)).should be_true
    probe.received.size.should eq(0)
    root.debug_overlay.visible.should be_true

    root.handle(Tessell::Input::Event.key_down(Tessell::Input::KeyCode::F1, timestamp_ms: 200_i64)).should be_true
    root.debug_overlay.visible.should be_false
  end

  it "delivers Unknown instead of silently dropping unrecognized keys" do
    probe = KeyProbe.new(KitSpecHelpers.key)
    root = Tessell::Kit::Root.new(probe)
    root.layout(200.0_f32, 100.0_f32)
    root.build
    root.focus(probe)

    root.handle(Tessell::Input::Event.key_down(Tessell::Input::KeyCode::Unknown)).should be_true
    probe.received.should eq([Tessell::Kit::Key::Unknown])
  end

  it "passes KeyT/Digit/F-keys that Kit missed before the alias (v0.2.0 regression)" do
    probe = KeyProbe.new(KitSpecHelpers.key)
    root = Tessell::Kit::Root.new(probe)
    root.layout(200.0_f32, 100.0_f32)
    root.build
    root.focus(probe)

    [Tessell::Input::KeyCode::KeyT,
     Tessell::Input::KeyCode::Digit1,
     Tessell::Input::KeyCode::Digit9,
     Tessell::Input::KeyCode::F4].each do |code|
      probe.received.clear
      root.handle(Tessell::Input::Event.key_down(code)).should be_true
      probe.received.should eq([code])
    end
  end
end
