require "./spec_helper"

private class Spacer < Tessell::Kit::Component
  def initialize(key : Tessell::UI::UiKey, @w : Float32, @h : Float32)
    super(key)
  end

  def measure(ctx : Tessell::Kit::Context, constraints : Tessell::Constraints) : Tessell::Size
    constraints.constrain(Tessell::Size.new(@w, @h))
  end

  def emit(b : Tessell::UI::Builder, ctx : Tessell::Kit::Context) : Nil
    b.node(@key, @bounds)
  end
end

describe "Tessell::Kit::ScrollView" do
  it "measures content and clamps scrolling" do
    content = Spacer.new(KitSpecHelpers.key.child(1_u64), 180.0_f32, 300.0_f32)
    scroll = Tessell::Kit::ScrollView.new(KitSpecHelpers.key, content)
    ctx = KitSpecHelpers.context
    scroll.arrange(ctx, Tessell::Rect.new(0.0_f32, 0.0_f32, 100.0_f32, 100.0_f32))

    scroll.content_size.height.should eq(300.0_f32)
    scroll.max_scroll_y.should eq(200.0_f32)
    scroll.scroll_by(50.0_f32).should eq(50.0_f32)
    scroll.scroll_by(500.0_f32).should eq(200.0_f32)
    scroll.scroll_by(-500.0_f32).should eq(0.0_f32)
  end

  it "scrolls with wheel delta and keyboard End" do
    content = Spacer.new(KitSpecHelpers.key.child(1_u64), 180.0_f32, 300.0_f32)
    scroll = Tessell::Kit::ScrollView.new(KitSpecHelpers.key, content)
    ctx = KitSpecHelpers.context
    scroll.arrange(ctx, Tessell::Rect.new(0.0_f32, 0.0_f32, 100.0_f32, 100.0_f32))

    scroll.handle(Tessell::Kit::Event.wheel(20.0_f32, 20.0_f32, 0.0_f32, -120.0_f32), ctx).should be_true
    scroll.scroll_y.should eq(120.0_f32)

    scroll.on_focus_changed(true)
    scroll.handle(Tessell::Kit::Event.key_down(Tessell::Kit::Key::End), ctx).should be_true
    scroll.scroll_y.should eq(200.0_f32)
  end

  it "clips paint and exposes clip bounds for hit testing" do
    content = Spacer.new(KitSpecHelpers.key.child(1_u64), 180.0_f32, 300.0_f32)
    scroll = Tessell::Kit::ScrollView.new(KitSpecHelpers.key, content)
    ctx = KitSpecHelpers.context
    bounds = Tessell::Rect.new(0.0_f32, 0.0_f32, 100.0_f32, 100.0_f32)
    scroll.arrange(ctx, bounds)
    painter = Tessell::Kit::PaintListPainter.new
    scroll.paint(painter, ctx)
    painter.list.clip_depth.should eq(0)
    painter.list.to_a.map(&.kind).should contain(Tessell::Kit::PaintKind::PushClip)
    scroll.clip_bounds.should eq(bounds)
  end

  it "prevents hits outside the viewport" do
    content = Spacer.new(KitSpecHelpers.key.child(1_u64), 180.0_f32, 300.0_f32)
    scroll = Tessell::Kit::ScrollView.new(KitSpecHelpers.key, content)
    root = Tessell::Kit::Root.new(scroll)
    root.layout(200.0_f32, 200.0_f32)
    scroll.arrange(root.context, Tessell::Rect.new(0.0_f32, 0.0_f32, 100.0_f32, 100.0_f32))
    root.build

    root.handle(Tessell::Input::Event.pointer_down(50.0_f32, 50.0_f32))
    root.focused_component.should be(scroll)
    root.handle(Tessell::Input::Event.pointer_up(50.0_f32, 50.0_f32))
    root.handle(Tessell::Input::Event.pointer_down(50.0_f32, 150.0_f32)).should be_false
  end
end
