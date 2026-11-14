require "./spec_helper"

describe "Tessell::Kit::Tooltip" do
  it "measures, paints and exposes Tooltip a11y metadata" do
    tip = Tessell::Kit::Tooltip.new(KitSpecHelpers.key, "Save changes")
    ctx = KitSpecHelpers.context
    size = tip.measure(ctx, Tessell::Constraints.new)
    tip.arrange(ctx, Tessell::Rect.new(10.0_f32, 10.0_f32, size.width, size.height))
    painter = Tessell::Kit::PaintListPainter.new
    tip.paint(painter, ctx)
    painter.list.size.should be >= 3
    tip.a11y_role.should eq(Tessell::A11y::Role::Tooltip)
    tip.a11y_name.should eq("Save changes")
    tip.focusable?.should be_false
  end

  it "opens after hover delay and closes on leave without stealing focus" do
    button = Tessell::Kit::Button.new(KitSpecHelpers.key, "Save")
    button.tooltip_text = "Save changes"
    button.tooltip_delay_ms = 100
    root = Tessell::Kit::Root.new(button)
    root.layout(300.0_f32, 200.0_f32)
    root.build

    center_x = button.bounds.origin.x + button.bounds.size.width / 2.0_f32
    center_y = button.bounds.origin.y + button.bounds.size.height / 2.0_f32
    root.handle(Tessell::Input::Event.pointer_move(center_x, center_y))
    root.advance_time(50)
    root.overlay_host.empty?.should be_true

    root.advance_time(150)
    root.overlay_host.entries.size.should eq(1)
    root.overlay_host.top.not_nil!.kind.should eq(Tessell::Kit::OverlayKind::Tooltip)
    root.focused_component.should be_nil
    root.build

    sink = [] of Tessell::A11y::Node
    root.a11y_emit(sink)
    sink.any? { |n| n.role == Tessell::A11y::Role::Tooltip && n.name == "Save changes" }.should be_true

    root.handle(Tessell::Input::Event.pointer_move(350.0_f32, 250.0_f32))
    root.overlay_host.empty?.should be_true
  end
end
