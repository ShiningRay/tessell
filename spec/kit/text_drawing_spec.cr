require "spec"
require "../../src/tessell/kit"

# Issue #6：TextDrawing.draw_in_rect 用 text_metrics 计算对齐，
# 应用不再猜 baseline；Context#measure_text 带缓存。
def drawing_ctx : Tessell::Kit::Context
  Tessell::Kit::Context.new(Tessell::Kit::Theme.light, Tessell::Kit::StubTextMetrics.new, 1.0_f32)
end

describe "Kit::TextDrawing" do

  it "left/top aligns to rect origin + ascent" do
    c = drawing_ctx
    p = Tessell::Kit::PaintListPainter.new
    rect = Tessell::Rect.new(10.0_f32, 20.0_f32, 200.0_f32, 100.0_f32)
    m = c.text_metrics(20.0_f32)
    Tessell::Kit::TextDrawing.draw_in_rect(c, p, rect, "abc", 0xff0000ff_u32, 20.0_f32,
      Tessell::Kit::HAlign::Left, Tessell::Kit::VAlign::Top)
    cmd = p.list[0]
    cmd.x.should eq(10.0_f32)
    cmd.y.should eq(20.0_f32 + m.ascent)
  end

  it "center/middle centers horizontally and vertically" do
    c = drawing_ctx
    p = Tessell::Kit::PaintListPainter.new
    rect = Tessell::Rect.new(10.0_f32, 20.0_f32, 200.0_f32, 100.0_f32)
    size = 20.0_f32
    m = c.text_metrics(size)
    w = c.measure_text("abc", size).width
    Tessell::Kit::TextDrawing.draw_in_rect(c, p, rect, "abc", 0xff0000ff_u32, size,
      Tessell::Kit::HAlign::Center, Tessell::Kit::VAlign::Middle)
    cmd = p.list[0]
    cmd.x.should eq(10.0_f32 + (200.0_f32 - w) / 2.0_f32)
    expected_baseline = 20.0_f32 + (100.0_f32 - (m.ascent + m.descent)) / 2.0_f32 + m.ascent
    cmd.y.should eq(expected_baseline)
  end

  it "right/bottom aligns to max edges minus width/descent" do
    c = drawing_ctx
    p = Tessell::Kit::PaintListPainter.new
    rect = Tessell::Rect.new(10.0_f32, 20.0_f32, 200.0_f32, 100.0_f32)
    size = 20.0_f32
    m = c.text_metrics(size)
    w = c.measure_text("abc", size).width
    Tessell::Kit::TextDrawing.draw_in_rect(c, p, rect, "abc", 0xff0000ff_u32, size,
      Tessell::Kit::HAlign::Right, Tessell::Kit::VAlign::Bottom)
    cmd = p.list[0]
    cmd.x.should eq(rect.max_x - w)
    cmd.y.should eq(rect.max_y - m.descent)
  end

  it "stub metrics ascent/descent sum to line height proportion" do
    c = drawing_ctx
    m = c.text_metrics(20.0_f32)
    m.ascent.should be > 0.0_f32
    m.descent.should be > 0.0_f32
    (m.ascent + m.descent).should eq(m.line_height)
  end

  it "measure_text cache returns identical results and clear_text_cache resets" do
    c = drawing_ctx
    s1 = c.measure_text("cached-123", 14.0_f32)
    s2 = c.measure_text("cached-123", 14.0_f32)
    s2.width.should eq(s1.width)
    c.clear_text_cache
    s3 = c.measure_text("cached-123", 14.0_f32)
    s3.width.should eq(s1.width)
  end
end
