require "./spec_helper"

private class RecordingComponent < Tessell::Kit::Component
  getter events : Array(Tessell::Kit::Event)
  getter wheel_dx : Float32
  getter wheel_dy : Float32
  getter last_modifiers : Tessell::Kit::Modifiers?

  def initialize(key : Tessell::UI::UiKey)
    super(key)
    @events = [] of Tessell::Kit::Event
    @wheel_dx = 0.0_f32
    @wheel_dy = 0.0_f32
    @last_modifiers = nil
  end

  def measure(ctx : Tessell::Kit::Context, constraints : Tessell::Constraints) : Tessell::Size
    constraints.constrain(Tessell::Size.new(100.0_f32, 40.0_f32))
  end

  def emit(b : Tessell::UI::Builder, ctx : Tessell::Kit::Context) : Nil
    b.node(@key, @bounds, a11y_name: "recording")
  end

  def focusable? : Bool
    true
  end

  def handle(event : Tessell::Kit::Event, ctx : Tessell::Kit::Context) : Bool
    @events << event
    @wheel_dx = event.wheel_dx if event.kind == Tessell::Kit::Event::Kind::Wheel
    @wheel_dy = event.wheel_dy if event.kind == Tessell::Kit::Event::Kind::Wheel
    @last_modifiers = event.modifiers
    true
  end
end

describe "Kit input bridge (K1)" do
  it "passes wheel deltas and modifiers from core events" do
    component = RecordingComponent.new(KitSpecHelpers.key)
    root = Tessell::Kit::Root.new(component)
    root.layout(200.0_f32, 100.0_f32)
    root.build

    root.handle(Tessell::Input::Event.pointer_move(20.0_f32, 20.0_f32))
    mods = Tessell::Input::Modifiers.new(ctrl: true)
    root.handle(Tessell::Input::Event.wheel(20.0_f32, 20.0_f32, 0.0_f32, -120.0_f32, mods)).should be_true
    component.wheel_dy.should eq(-120.0_f32)
    component.last_modifiers.not_nil!.ctrl.should be_true
  end

  it "synthesizes enter/leave from core pointer events" do
    component = RecordingComponent.new(KitSpecHelpers.key)
    root = Tessell::Kit::Root.new(component)
    root.layout(200.0_f32, 100.0_f32)
    root.build

    root.handle(Tessell::Input::Event.pointer_enter(20.0_f32, 20.0_f32))
    root.hover_component.should be(component)
    root.handle(Tessell::Input::Event.pointer_leave(20.0_f32, 20.0_f32))
    root.hover_component.should be_nil
    kinds = component.events.map(&.kind)
    kinds.should contain(Tessell::Kit::Event::Kind::PointerEnter)
    kinds.should contain(Tessell::Kit::Event::Kind::PointerLeave)
  end

  it "clamps Tab focus with shift modifier without crashing" do
    component = RecordingComponent.new(KitSpecHelpers.key)
    root = Tessell::Kit::Root.new(component)
    root.layout(200.0_f32, 100.0_f32)
    root.build

    mods = Tessell::Input::Modifiers.new(shift: true)
    root.handle(Tessell::Input::Event.key_down(Tessell::Input::KeyCode::Tab, mods)).should be_true
    root.focused_component.should be(component)
  end
end
