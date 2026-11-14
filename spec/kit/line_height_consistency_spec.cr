require "./spec_helper"

# issue #19：三套行高口径统一。
# 任一 TextMetrics 实现下：ctx.line_height(fs) == measure_text("x",fs).height
# == text_metrics(fs).line_height；Kit 组件基线用 ascent/descent 推导，
# 不再出现 fs*0.1 / top+fs 经验口径。

private def real_font_path : String?
  candidates = [
    "C:/Windows/Fonts/arial.ttf",
    "/System/Library/Fonts/Supplemental/Arial.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
  ]
  candidates.find { |path| File.exists?(path) }
end

describe "line height consistency (issue #19)" do
  it "unifies the three sources under StubTextMetrics" do
    ctx = Tessell::Kit::Context.new(Tessell::Kit::Theme.light,
      Tessell::Kit::StubTextMetrics.new, 1.0_f32)
    fs = 14.0_f32

    ctx.line_height(fs).should eq(ctx.measure_text("x", fs).height)
    ctx.line_height(fs).should eq(ctx.text_metrics(fs).line_height)
    ctx.text_metrics(fs).line_height.should eq(fs * 1.25_f32) # 桩的显式口径
  end

  it "unifies the three sources under CoreTextMetrics (real font)" do
    path = real_font_path
    unless path
      puts "SKIP line-height real-font check: no platform font found"
      next
    end
    measurer = Tessell::Text::FtMeasurer.open(path, 0)
    core = Tessell::Kit::CoreTextMetrics.new(measurer)
    ctx = Tessell::Kit::Context.new(Tessell::Kit::Theme.light, core, 1.0_f32)
    fs = 14.0_f32

    ctx.line_height(fs).should be_close(ctx.measure_text("x", fs).height, 1e-4_f32)
    ctx.line_height(fs).should be_close(ctx.text_metrics(fs).line_height, 1e-4_f32)
    measurer.close
  end

  it "spaces Text lines exactly by line_height (measure and paint share one number)" do
    text = Tessell::Kit::Text.new(KitSpecHelpers.key, "abcdef",
      size: Tessell::Kit::ControlSize::Medium, wrap: true)
    root = Tessell::Kit::Root.new(text, metrics: Tessell::Kit::StubTextMetrics.new)
    root.layout(20.0_f32, 100.0_f32) # 每行 2 字符 → 3 行
    root.build

    p = Tessell::Kit::PaintListPainter.new
    text.paint(p, root.context)
    baselines = p.list.to_a.select { |c| c.kind == Tessell::Kit::PaintKind::Text }
    baselines.size.should eq(3)

    line_h = root.context.line_height(14.0_f32)
    (baselines[1].y - baselines[0].y).should be_close(line_h, 1e-4_f32)
    (baselines[2].y - baselines[1].y).should be_close(line_h, 1e-4_f32)
    # 首行基线 = top + ascent（不是 top + fs 的第三种口径）
    m = root.context.text_metrics(14.0_f32)
    baselines[0].y.should be_close(text.bounds.origin.y + m.ascent, 1e-4_f32)
  end

  it "centers 14px button text geometrically in a 32px container" do
    button = Tessell::Kit::Button.new(KitSpecHelpers.key, "Save")
    root = Tessell::Kit::Root.new(button, metrics: Tessell::Kit::StubTextMetrics.new)
    root.layout(200.0_f32, 32.0_f32)
    root.build

    p = Tessell::Kit::PaintListPainter.new
    button.paint(p, root.context)
    text_cmds = p.list.to_a.select { |c| c.kind == Tessell::Kit::PaintKind::Text }
    text_cmds.size.should eq(1)

    m = root.context.text_metrics(14.0_f32)
    baseline = text_cmds[0].y
    visual_center = (baseline - m.ascent + baseline + m.descent) / 2.0_f32
    container_center = button.bounds.origin.y + button.bounds.size.height / 2.0_f32
    visual_center.should be_close(container_center, 1e-4_f32)
  end
end
