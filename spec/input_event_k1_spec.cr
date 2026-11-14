require "spec"
require "../src/tessell/input/event"
require "../src/tessell/input/router"
require "../src/tessell/core/node"

include Tessell
include Tessell::Input

describe "Input event K1 extensions" do
  it "carries modifiers and wheel deltas with backward-compatible factories" do
    mods = Modifiers.new(shift: true, ctrl: true)
    e = Event.key_down(KeyCode::KeyC, mods)
    e.shift?.should be_true
    e.ctrl?.should be_true
    e.alt?.should be_false

    wheel = Event.wheel(10.0_f32, 20.0_f32, 0.0_f32, -120.0_f32)
    wheel.kind.should eq(Event::Kind::Wheel)
    wheel.x.should eq(10.0_f32)
    wheel.y.should eq(20.0_f32)
    wheel.wheel_dy.should eq(-120.0_f32)
  end

  it "supports pointer enter/leave/cancel and navigation keys" do
    Event.pointer_enter(1.0_f32, 2.0_f32).kind.should eq(Event::Kind::PointerEnter)
    Event.pointer_leave(1.0_f32, 2.0_f32).kind.should eq(Event::Kind::PointerLeave)
    Event.pointer_cancel(1.0_f32, 2.0_f32).kind.should eq(Event::Kind::PointerCancel)
    KeyCode::Space.value.should be > KeyCode::Escape.value
    KeyCode::PageDown.value.should be > KeyCode::PageUp.value
  end
end

describe "Router K1 extensions" do
  it "tracks hover on enter/move and clears it on leave" do
    root = Node.new("root", Rect.new(0.0_f32, 0.0_f32, 100.0_f32, 100.0_f32))
    a = Node.new("a", Rect.new(10.0_f32, 10.0_f32, 20.0_f32, 20.0_f32))
    root.add_child(a)
    router = Router.new

    router.handle(Event.pointer_enter(15.0_f32, 15.0_f32), root).should eq(a)
    router.hover.should eq(a)
    router.handle(Event.pointer_leave(15.0_f32, 15.0_f32), root).should be_nil
    router.hover.should be_nil
  end

  it "returns pressed target on cancel and clears pressed" do
    root = Node.new("root", Rect.new(0.0_f32, 0.0_f32, 100.0_f32, 100.0_f32))
    a = Node.new("a", Rect.new(10.0_f32, 10.0_f32, 20.0_f32, 20.0_f32))
    root.add_child(a)
    router = Router.new

    router.handle(Event.pointer_down(15.0_f32, 15.0_f32), root).should eq(a)
    router.handle(Event.pointer_cancel(30.0_f32, 30.0_f32), root).should eq(a)
    router.pressed.should be_nil
  end
end

# issue #4：KeyT/Digit0-9、timestamp、repeat。
describe "Input event model (issue #4)" do
  it " KeyCode has KeyT and digits" do
    Tessell::Input::KeyCode::KeyT.should_not be_nil
    Tessell::Input::KeyCode::Digit0.should_not be_nil
    Tessell::Input::KeyCode::Digit9.should_not be_nil
  end

  it "key events carry timestamp and repeat" do
    e = Tessell::Input::Event.key_down(Tessell::Input::KeyCode::KeyT,
      Tessell::Input::Modifiers.none, 1234_i64, true)
    e.timestamp_ms.should eq(1234_i64)
    e.repeat.should be_true
    e.key.should eq(Tessell::Input::KeyCode::KeyT)

    e2 = Tessell::Input::Event.key_up(Tessell::Input::KeyCode::Space,
      Tessell::Input::Modifiers.none, 5678_i64)
    e2.timestamp_ms.should eq(5678_i64)
    e2.repeat.should be_false
  end

  it "pointer events carry timestamp" do
    e = Tessell::Input::Event.pointer_down(1.0_f32, 2.0_f32, 0,
      Tessell::Input::Modifiers.none, 999_i64)
    e.timestamp_ms.should eq(999_i64)
    e.x.should eq(1.0_f32)

    e2 = Tessell::Input::Event.pointer_up(3.0_f32, 4.0_f32, 0,
      Tessell::Input::Modifiers.none, 1000_i64)
    e2.timestamp_ms.should eq(1000_i64)
  end

  it "wheel keeps dx/dy and gains timestamp via generic path" do
    e = Tessell::Input::Event.wheel(5.0_f32, 6.0_f32, 12.0_f32, -40.0_f32)
    e.wheel_dx.should eq(12.0_f32)
    e.wheel_dy.should eq(-40.0_f32)
    e.timestamp_ms.should eq(0_i64)
  end
end
