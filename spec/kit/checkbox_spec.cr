require "./spec_helper"

describe "Tessell::Kit::Checkbox" do
  it "emits CheckBox a11y metadata with value" do
    box = Tessell::Kit::Checkbox.new(KitSpecHelpers.key, "Remember me", checked: true)
    ctx = KitSpecHelpers.context
    box.arrange(ctx, Tessell::Rect.new(0.0_f32, 0.0_f32, 160.0_f32, 24.0_f32))
    buf = [] of Tessell::UI::Decl
    builder = Tessell::UI::Builder.new(buf, [] of Tessell::UI::UiKey)
    builder.reset(Tessell::UI::UiKey.root)
    box.emit(builder, ctx)
    buf[0].a11y_role.should eq(Tessell::A11y::Role::CheckBox)
    buf[0].a11y_name.should eq("Remember me")
    buf[0].a11y_value.should eq("checked")
    buf[0].a11y_focusable.should be_true
  end

  it "paints box, check marks and label" do
    box = Tessell::Kit::Checkbox.new(KitSpecHelpers.key, "Remember me", checked: true)
    ctx = KitSpecHelpers.context
    box.arrange(ctx, Tessell::Rect.new(10.0_f32, 10.0_f32, 160.0_f32, 24.0_f32))
    painter = Tessell::Kit::PaintListPainter.new
    box.paint(painter, ctx)
    kinds = painter.list.to_a.map(&.kind)
    kinds.should contain(Tessell::Kit::PaintKind::FillRoundRect)
    kinds.should contain(Tessell::Kit::PaintKind::StrokeRoundRect)
    kinds.count(Tessell::Kit::PaintKind::Line).should eq(2)
    kinds.should contain(Tessell::Kit::PaintKind::Text)
  end

  it "toggles once on pointer click" do
    changes = [] of Bool
    box = Tessell::Kit::Checkbox.new(KitSpecHelpers.key, "Check")
    box.on_change = ->(value : Bool) { changes << value; nil }
    ctx = KitSpecHelpers.context
    box.arrange(ctx, Tessell::Rect.new(0.0_f32, 0.0_f32, 100.0_f32, 24.0_f32))

    box.handle(Tessell::Kit::Event.pointer(Tessell::Kit::Event::Kind::PointerDown, 5.0_f32, 10.0_f32), ctx)
    box.handle(Tessell::Kit::Event.pointer(Tessell::Kit::Event::Kind::PointerUp, 5.0_f32, 10.0_f32), ctx)
    changes.should eq([true])
    box.checked.should be_true
    box.a11y_value.should eq("checked")
  end

  it "clears indeterminate on toggle" do
    changes = [] of Bool
    box = Tessell::Kit::Checkbox.new(KitSpecHelpers.key, "Check", indeterminate: true)
    box.on_change = ->(value : Bool) { changes << value; nil }
    ctx = KitSpecHelpers.context
    box.arrange(ctx, Tessell::Rect.new(0.0_f32, 0.0_f32, 100.0_f32, 24.0_f32))
    box.handle(Tessell::Kit::Event.pointer(Tessell::Kit::Event::Kind::PointerDown, 5.0_f32, 10.0_f32), ctx)
    box.handle(Tessell::Kit::Event.pointer(Tessell::Kit::Event::Kind::PointerUp, 5.0_f32, 10.0_f32), ctx)
    box.indeterminate.should be_false
    box.checked.should be_true
    changes.should eq([true])
  end

  it "toggles with Space only when focused and enabled" do
    box = Tessell::Kit::Checkbox.new(KitSpecHelpers.key, "Check")
    ctx = KitSpecHelpers.context
    box.arrange(ctx, Tessell::Rect.new(0.0_f32, 0.0_f32, 100.0_f32, 24.0_f32))
    box.handle(Tessell::Kit::Event.key_down(Tessell::Kit::Key::Space), ctx)
    box.handle(Tessell::Kit::Event.key_up(Tessell::Kit::Key::Space), ctx)
    box.checked.should be_false

    box.on_focus_changed(true)
    box.handle(Tessell::Kit::Event.key_down(Tessell::Kit::Key::Space), ctx).should be_true
    box.handle(Tessell::Kit::Event.key_up(Tessell::Kit::Key::Space), ctx).should be_true
    box.checked.should be_true
  end

  it "ignores disabled clicks" do
    box = Tessell::Kit::Checkbox.new(KitSpecHelpers.key, "Check", enabled: false)
    ctx = KitSpecHelpers.context
    box.arrange(ctx, Tessell::Rect.new(0.0_f32, 0.0_f32, 100.0_f32, 24.0_f32))
    box.handle(Tessell::Kit::Event.pointer(Tessell::Kit::Event::Kind::PointerDown, 5.0_f32, 10.0_f32), ctx)
    box.handle(Tessell::Kit::Event.pointer(Tessell::Kit::Event::Kind::PointerUp, 5.0_f32, 10.0_f32), ctx)
    box.checked.should be_false
  end
end
