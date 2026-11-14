require "./spec_helper"

# issue #29：字体 face 链路——weight → font_id → Painter → DrawCmd#atlas_id。
# 宿主只建 renderer[font_id] 表，不需要在每次 text() 调用处判断该用哪张脸。

private def two_face_paths : Array({path: String, ttc_index: Int32,
                                    weight: Tessell::Text::FontStack::Weight,
                                    label: String} | {path: String, ttc_index: Int32,
                                                      weight: Tessell::Text::FontStack::Weight,
                                                      label: String})?
  pairs = [
    {reg: "C:/Windows/Fonts/arial.ttf", bold: "C:/Windows/Fonts/arialbd.ttf"},
    {reg: "/System/Library/Fonts/Supplemental/Arial.ttf",
     bold: "/System/Library/Fonts/Supplemental/Arial Bold.ttf"},
    {reg: "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
     bold: "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"},
  ]
  found = pairs.find { |p| File.exists?(p[:reg]) && File.exists?(p[:bold]) }
  return nil unless found
  [
    {path: found[:reg], ttc_index: 0,
     weight: Tessell::Text::FontStack::Weight::Regular, label: "regular"},
    {path: found[:bold], ttc_index: 0,
     weight: Tessell::Text::FontStack::Weight::Bold, label: "bold"},
  ]
end

describe "font face chain (issue #29)" do
  it "passes font_id through both painters" do
    d = Tessell::Kit::DrawListPainter.new
    d.text(1.0_f32, 2.0_f32, "hi", 0xff000000_u32, 14.0_f32, 3)
    d.list[0].atlas_id.should eq(3) # face 选择进 atlas_id（atlas 字体维度）
    d.list[0].font_size.should eq(14.0_f32)

    p = Tessell::Kit::PaintListPainter.new
    p.text(1.0_f32, 2.0_f32, "hi", 0xff000000_u32, 14.0_f32, 3)
    p.list[0].font_id.should eq(3)

    s = Tessell::Kit::SvgPainter.new(200, 50)
    s.text(1.0_f32, 2.0_f32, "hi", 0xff000000_u32, 14.0_f32, 3) # 接受并忽略
    s.svg.includes?("hi").should be_true
  end

  it "defaults font_id to 0 for existing call sites" do
    d = Tessell::Kit::DrawListPainter.new
    d.text(1.0_f32, 2.0_f32, "hi", 0xff000000_u32, 14.0_f32)
    d.list[0].atlas_id.should eq(0)

    p = Tessell::Kit::PaintListPainter.new
    p.text(1.0_f32, 2.0_f32, "hi", 0xff000000_u32, 14.0_f32)
    p.list[0].font_id.should eq(0)
  end

  it "FontStack#pick matches weight with graceful fallback" do
    paths = two_face_paths
    unless paths
      puts "SKIP font-stack weight pick: no regular+bold pair found"
      next
    end
    stack = Tessell::Text::FontStack.open(paths)
    begin
      regular = stack.pick("Total", Tessell::Text::FontStack::Weight::Regular)
      bold = stack.pick("Total", Tessell::Text::FontStack::Weight::Bold)
      regular.should_not be_nil
      bold.should_not be_nil
      regular.not_nil!.font_id.should eq(0)
      bold.not_nil!.font_id.should eq(1)
      bold.not_nil!.weight.should eq(Tessell::Text::FontStack::Weight::Bold)
    ensure
      stack.close
    end
  end

  it "Context#font_id_for resolves weight without a stack and with one" do
    ctx = Tessell::Kit::Context.new
    ctx.font_id_for("Total", Tessell::Kit::FontWeight::Bold).should eq(0)

    paths = two_face_paths
    unless paths
      puts "SKIP font_id_for stack case: no regular+bold pair found"
      next
    end
    stack = Tessell::Text::FontStack.open(paths)
    begin
      ctx.font_stack = stack
      ctx.font_id_for("Total", Tessell::Kit::FontWeight::Normal).should eq(0)
      ctx.font_id_for("Total", Tessell::Kit::FontWeight::Bold).should eq(1)
    ensure
      stack.close
      ctx.font_stack = nil
    end
  end

  it "MultiFaceTextMetrics measures with the requested face" do
    paths = two_face_paths
    unless paths
      puts "SKIP MultiFaceTextMetrics: no regular+bold pair found"
      next
    end
    stack = Tessell::Text::FontStack.open(paths)
    begin
      m = Tessell::Kit::MultiFaceTextMetrics.new(stack)
      regular = m.measure("Total", 28.0_f32, 0)   # 设备字号直接传给底层
      bold = m.measure("Total", 28.0_f32, 1)
      bold.width.should_not eq(regular.width)     # Arial vs Arial Bold 宽度不同
      m.font_metrics(28.0_f32).line_height.should be > 0.0_f32
    ensure
      stack.close
    end
  end

  it "Kit::Text weight:bold measures and paints with the bold face end to end" do
    paths = two_face_paths
    unless paths
      puts "SKIP Text weight end-to-end: no regular+bold pair found"
      next
    end
    stack = Tessell::Text::FontStack.open(paths)
    begin
      metrics = Tessell::Kit::MultiFaceTextMetrics.new(stack)
      base = KitSpecHelpers.key # root.child(1)
      normal_text = Tessell::Kit::Text.new(base.child(1_u64), "Total")
      bold_text = Tessell::Kit::Text.new(base.child(2_u64), "Total",
        weight: Tessell::Kit::FontWeight::Bold)
      root = Tessell::Kit::Root.new(
        Tessell::Kit::Column.new(base, Tessell::Insets.all(0.0_f32), 0.0_f32)
          .tap { |col| col.add(normal_text); col.add(bold_text) },
        metrics: metrics)
      root.context.font_stack = stack
      root.layout(200.0_f32, 100.0_f32)
      root.build

      # measure：粗体与常规宽度不同（真实 face 测量，不是同一张脸）
      cw = root.context.measure_text("Total", 14.0_f32, 0)
      cb = root.context.measure_text("Total", 14.0_f32, 1)
      cw.width.should_not eq(cb.width)

      # paint：粗体命令携带 font_id == 1
      p = Tessell::Kit::PaintListPainter.new
      bold_text.paint(p, root.context)
      cmds = p.list.to_a.select { |c| c.kind == Tessell::Kit::PaintKind::Text }
      cmds.size.should eq(1)
      cmds[0].font_id.should eq(1)
      normal_text.paint(p, root.context)
      cmds = p.list.to_a.select { |c| c.kind == Tessell::Kit::PaintKind::Text }
      cmds[1].font_id.should eq(0)
    ensure
      stack.close
    end
  end

  it "caches per font_id (no cross-face pollution)" do
    ctx = Tessell::Kit::Context.new
    ctx.measure_text("x", 14.0_f32, 0)
    ctx.measure_text("x", 14.0_f32, 1)
    ctx.text_cache_size.should eq(2)
  end
end
