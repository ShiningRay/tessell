require "./spec_helper"

describe "Tessell::Kit::Button" do
  it "measures label + padding and theme control height" do
    button = Tessell::Kit::Button.new(KitSpecHelpers.key, "Save")
    ctx = KitSpecHelpers.context
    size = button.measure(ctx, Tessell::Constraints.new)
    text = ctx.measure_text("Save", ctx.theme.font_size(Tessell::Kit::ControlSize::Medium))
    size.width.should eq(text.width + ctx.theme.padding_x(Tessell::Kit::ControlSize::Medium) * 2.0_f32)
    size.height.should eq(ctx.theme.control_height(Tessell::Kit::ControlSize::Medium))
  end

  it "emits one text declaration with button a11y metadata and focusability" do
    button = Tessell::Kit::Button.new(KitSpecHelpers.key, "Save",
      Tessell::Kit::Variant::Primary, Tessell::Kit::ControlSize::Large)
    button.arrange(KitSpecHelpers.context, Tessell::Rect.new(4.0_f32, 8.0_f32, 120.0_f32, 40.0_f32))
    buf = [] of Tessell::UI::Decl
    builder = Tessell::UI::Builder.new(buf, [] of Tessell::UI::UiKey)
    builder.reset(Tessell::UI::UiKey.root)
    button.emit(builder, KitSpecHelpers.context)

    buf.size.should eq(1)
    d = buf[0]
    d.key.should eq(KitSpecHelpers.key)
    d.kind.should eq(Tessell::UI::DeclKind::Text)
    d.text.should eq("Save")
    d.bounds.should eq(Tessell::Rect.new(4.0_f32, 8.0_f32, 120.0_f32, 40.0_f32))
    d.a11y_role.should eq(Tessell::A11y::Role::Button)
    d.a11y_name.should eq("Save")
    d.a11y_focusable.should be_true
    d.a11y_enabled.should be_true
  end

  it "paints background, border, text and focus ring" do
    button = Tessell::Kit::Button.new(KitSpecHelpers.key, "Save",
      Tessell::Kit::Variant::Secondary)
    ctx = KitSpecHelpers.context
    button.arrange(ctx, Tessell::Rect.new(0.0_f32, 0.0_f32, 100.0_f32, 32.0_f32))
    button.on_focus_changed(true)
    painter = Tessell::Kit::PaintListPainter.new
    button.paint(painter, ctx)

    kinds = painter.list.to_a.map(&.kind)
    kinds.should contain(Tessell::Kit::PaintKind::FillRoundRect)
    kinds.should contain(Tessell::Kit::PaintKind::StrokeRoundRect)
    kinds.should contain(Tessell::Kit::PaintKind::Text)
    text_cmd = painter.list.to_a.find { |cmd| cmd.kind == Tessell::Kit::PaintKind::Text }.not_nil!
    text_cmd.text.should eq("Save")
    text_cmd.font_size.should eq(ctx.theme.font_size(Tessell::Kit::ControlSize::Medium))
  end

  it "activates once on pointer down/up inside" do
    clicks = 0
    button = Tessell::Kit::Button.new(KitSpecHelpers.key, "OK")
    button.on_click = -> { clicks += 1; nil }
    ctx = KitSpecHelpers.context
    button.arrange(ctx, Tessell::Rect.new(10.0_f32, 10.0_f32, 80.0_f32, 32.0_f32))

    button.handle(Tessell::Kit::Event.pointer(Tessell::Kit::Event::Kind::PointerDown, 20.0_f32, 20.0_f32), ctx).should be_true
    button.pressed.should be_true
    button.handle(Tessell::Kit::Event.pointer(Tessell::Kit::Event::Kind::PointerUp, 20.0_f32, 20.0_f32), ctx).should be_true
    clicks.should eq(1)
    button.pressed.should be_false
  end

  it "does not activate when pointer is released outside" do
    clicks = 0
    button = Tessell::Kit::Button.new(KitSpecHelpers.key, "OK")
    button.on_click = -> { clicks += 1; nil }
    ctx = KitSpecHelpers.context
    button.arrange(ctx, Tessell::Rect.new(10.0_f32, 10.0_f32, 80.0_f32, 32.0_f32))

    button.handle(Tessell::Kit::Event.pointer(Tessell::Kit::Event::Kind::PointerDown, 20.0_f32, 20.0_f32), ctx)
    button.handle(Tessell::Kit::Event.pointer(Tessell::Kit::Event::Kind::PointerUp, 200.0_f32, 200.0_f32), ctx)
    clicks.should eq(0)
  end

  it "activates once on Space key down/up" do
    clicks = 0
    button = Tessell::Kit::Button.new(KitSpecHelpers.key, "OK")
    button.on_click = -> { clicks += 1; nil }
    ctx = KitSpecHelpers.context
    button.arrange(ctx, Tessell::Rect.new(0.0_f32, 0.0_f32, 80.0_f32, 32.0_f32))
    button.on_focus_changed(true)

    button.handle(Tessell::Kit::Event.key_down(Tessell::Kit::Key::Space), ctx).should be_true
    button.handle(Tessell::Kit::Event.key_up(Tessell::Kit::Key::Space), ctx).should be_true
    clicks.should eq(1)
  end

  it "ignores pointer and keyboard activation when disabled" do
    clicks = 0
    button = Tessell::Kit::Button.new(KitSpecHelpers.key, "OK", enabled: false)
    button.on_click = -> { clicks += 1; nil }
    ctx = KitSpecHelpers.context
    button.arrange(ctx, Tessell::Rect.new(0.0_f32, 0.0_f32, 80.0_f32, 32.0_f32))
    button.on_focus_changed(true)

    button.focusable?.should be_false
    button.handle(Tessell::Kit::Event.pointer(Tessell::Kit::Event::Kind::PointerDown, 10.0_f32, 10.0_f32), ctx)
    button.handle(Tessell::Kit::Event.pointer(Tessell::Kit::Event::Kind::PointerUp, 10.0_f32, 10.0_f32), ctx)
    button.handle(Tessell::Kit::Event.key_down(Tessell::Kit::Key::Space), ctx)
    button.handle(Tessell::Kit::Event.key_up(Tessell::Kit::Key::Space), ctx)
    clicks.should eq(0)
  end

  it "changes paint token when state changes" do
    button = Tessell::Kit::Button.new(KitSpecHelpers.key, "OK")
    ctx = KitSpecHelpers.context
    button.arrange(ctx, Tessell::Rect.new(0.0_f32, 0.0_f32, 80.0_f32, 32.0_f32))
    base = button.paint_token
    button.handle(Tessell::Kit::Event.pointer(Tessell::Kit::Event::Kind::PointerEnter, 10.0_f32, 10.0_f32), ctx)
    button.paint_token.should_not eq(base)
    button.on_focus_changed(true)
    button.paint_token.should_not eq(base)
  end
end
