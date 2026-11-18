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

  it "truncation returns content, not the String::Builder inspect (issue #53)" do
    text = Tessell::Kit::Text.new(KitSpecHelpers.key, "abcdefghij")
    ctx = KitSpecHelpers.context
    # 足够宽放下若干字符 + 省略号（StubTextMetrics：ASCII 0.6*size，省略号 1.0*size）
    text.arrange(ctx, Tessell::Rect.new(0.0_f32, 0.0_f32, 40.0_f32, 20.0_f32))
    painter = Tessell::Kit::PaintListPainter.new
    text.paint(painter, ctx)
    rendered = painter.list[0].text
    rendered.should_not contain("String::Builder")
    rendered.should start_with("a")            # 内容前缀，而不是对象表示
    rendered.should end_with("…")
    "abcdefghij".should start_with(rendered.rchop("…"))
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

  it "truncate/wrap measure with the resolved face and paint carries its font_id (issue #53, PR #54 review)" do
    ctx = BoldFaceContext.new(Tessell::Kit::Theme.light, FaceAwareMetrics.new)
    fs = ctx.theme.font_size(Tessell::Kit::ControlSize::Medium)
    ctx.font_id_for("abcdefghij", Tessell::Kit::FontWeight::Bold).should eq(FaceAwareMetrics::BOLD_FACE)

    # measure 也走 face 7（10 字符 × 0.9*fs = 9*fs；默认 face 是 0.6*10*fs = 6*fs）
    text = Tessell::Kit::Text.new(KitSpecHelpers.key, "abcdefghij",
      weight: Tessell::Kit::FontWeight::Bold)
    text.measure(ctx, Tessell::Constraints.new).width.should be_close(9.0_f32 * fs, 0.01_f32)

    # 截断：face 7（步进 0.9*fs，省略号同价）在 5.0*fs 宽度下放 "abcd…"
    # （4×0.9+0.9=4.5 ≤ 5.0，第 5 个字符 5.4 > 5.0）；若退回默认 face
    # （ASCII 0.6/省略号 1.0）会放 "abcdef…"（6×0.6+1.0=4.6）——前缀区分 face。
    text.arrange(ctx, Tessell::Rect.new(0.0_f32, 0.0_f32, 5.0_f32 * fs, fs * 2.0_f32))
    painter = Tessell::Kit::PaintListPainter.new
    text.paint(painter, ctx)
    painter.list.size.should eq(1)
    painter.list[0].text.should eq("abcd…")
    painter.list[0].font_id.should eq(FaceAwareMetrics::BOLD_FACE)

    # 换行：3.6*fs 宽度下 face 7 每行恰好 4 字符；默认 face 会是 6 字符/行。
    wtext = Tessell::Kit::Text.new(KitSpecHelpers.key.child(2_u64), "abcdefgh",
      wrap: true, weight: Tessell::Kit::FontWeight::Bold)
    wtext.arrange(ctx, Tessell::Rect.new(0.0_f32, 0.0_f32, 3.6_f32 * fs, fs * 4.0_f32))
    wpainter = Tessell::Kit::PaintListPainter.new
    wtext.paint(wpainter, ctx)
    wpainter.list.size.should eq(2)
    wpainter.list[0].text.should eq("abcd")
    wpainter.list[1].text.should eq("efgh")
    wpainter.list[0].font_id.should eq(FaceAwareMetrics::BOLD_FACE)
    wpainter.list[1].font_id.should eq(FaceAwareMetrics::BOLD_FACE)
  end
end

# PR #54 review：StubTextMetrics 的 font_id 重载忽略 font_id，测不出
# truncate/break_lines 退回默认 face 的退化。face 感知桩——face 7 的每个
# 字符（含省略号）步进 0.9*size，与默认 face（ASCII 0.6/非 ASCII 1.0）
# 宽度不同；Context 子类把 Bold 固定解析到 face 7，不依赖 FontStack（FFI）。
private class FaceAwareMetrics < Tessell::Kit::StubTextMetrics
  BOLD_FACE = 7

  def measure(text : String, size : Float32, max_width : Float32,
              font_id : Int32) : Tessell::Size
    return measure(text, size, max_width) unless font_id == BOLD_FACE
    if max_width.infinite? || max_width <= 0.0_f32
      width = 0.0_f32
      text.each_char { |_| width += size * 0.9_f32 }
      return Tessell::Size.new(width, line_height(size))
    end
    # 与桩同型的贪心断行，步进换成 face 7 的统一 0.9*size
    line_width = 0.0_f32
    max_line = 0.0_f32
    lines = 1
    text.each_char do |_|
      w = size * 0.9_f32
      if line_width > 0.0_f32 && line_width + w > max_width
        max_line = line_width if line_width > max_line
        lines += 1
        line_width = w
      else
        line_width += w
      end
    end
    max_line = line_width if line_width > max_line
    Tessell::Size.new(max_line, line_height(size) * lines)
  end
end

private class BoldFaceContext < Tessell::Kit::Context
  def font_id_for(text : String, weight : Tessell::Kit::FontWeight) : Int32
    weight == Tessell::Kit::FontWeight::Bold ? FaceAwareMetrics::BOLD_FACE : 0
  end
end
