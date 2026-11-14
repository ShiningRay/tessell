require "./spec_helper"

describe "Tessell::Kit::Text" do
  it "measures and emits a11y name" do
    text = Tessell::Kit::Text.new(KitSpecHelpers.key, "Hello")
    ctx = KitSpecHelpers.context
    size = text.measure(ctx, Tessell::Constraints.new)
    size.width.should be > 0.0_f32
    text.arrange(ctx, Tessell::Rect.new(0.0_f32, 0.0_f32, size.width, size.height))

    buf = [] of Tessell::UI::Decl
    builder = Tessell::UI::Builder.new(buf, [] of Tessell::UI::UiKey)
    builder.reset(Tessell::UI::UiKey.root)
    text.emit(builder, ctx)
    buf.size.should eq(1)
    buf[0].a11y_role.should eq(Tessell::A11y::Role::Text)
    buf[0].a11y_name.should eq("Hello")
  end

  it "truncates a single line with ellipsis when bounds are narrow" do
    text = Tessell::Kit::Text.new(KitSpecHelpers.key, "abcdefghij")
    ctx = KitSpecHelpers.context
    text.arrange(ctx, Tessell::Rect.new(0.0_f32, 0.0_f32, 20.0_f32, 20.0_f32))
    painter = Tessell::Kit::PaintListPainter.new
    text.paint(painter, ctx)
    painter.list.size.should eq(1)
    painter.list[0].text.should end_with("…")
  end

  it "wraps into multiple lines when wrap is enabled" do
    text = Tessell::Kit::Text.new(KitSpecHelpers.key, "abcdefgh", wrap: true,
      size: Tessell::Kit::ControlSize::Medium)
    ctx = KitSpecHelpers.context
    text.arrange(ctx, Tessell::Rect.new(0.0_f32, 0.0_f32, 30.0_f32, 60.0_f32))
    painter = Tessell::Kit::PaintListPainter.new
    text.paint(painter, ctx)
    painter.list.size.should be > 1
  end

  it "respects max_lines" do
    text = Tessell::Kit::Text.new(KitSpecHelpers.key, "abcdefghijklmnop", wrap: true,
      max_lines: 2)
    ctx = KitSpecHelpers.context
    text.arrange(ctx, Tessell::Rect.new(0.0_f32, 0.0_f32, 30.0_f32, 60.0_f32))
    painter = Tessell::Kit::PaintListPainter.new
    text.paint(painter, ctx)
    painter.list.size.should eq(2)
  end

  it "uses muted color when disabled" do
    text = Tessell::Kit::Text.new(KitSpecHelpers.key, "Hello", enabled: false)
    ctx = KitSpecHelpers.context
    text.arrange(ctx, Tessell::Rect.new(0.0_f32, 0.0_f32, 100.0_f32, 20.0_f32))
    painter = Tessell::Kit::PaintListPainter.new
    text.paint(painter, ctx)
    painter.list[0].color.should eq(ctx.theme.palette.muted)
  end
end
