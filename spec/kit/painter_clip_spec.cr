require "./spec_helper"

# issue #25：PaintListPainter 与 DrawListPainter 的 clip 语义必须一致。
# 同一组 push_clip/命令/pop_clip 在两个 Painter 上产生等价的 clip 归属——
# 此前 PaintListPainter 的文本/形状完全不携带 clip，headless 裁切断言误报通过。

private COLOR = 0xff112233_u32

describe "Painter clip contract (issue #25)" do
  it "attaches the active clip to text commands on both painters" do
    clip = Tessell::Rect.new(0.0_f32, 0.0_f32, 10.0_f32, 10.0_f32)

    d = Tessell::Kit::DrawListPainter.new
    d.push_clip(clip)
    d.text(50.0_f32, 50.0_f32, "outside", COLOR, 14.0_f32)
    d.pop_clip

    p = Tessell::Kit::PaintListPainter.new
    p.push_clip(clip)
    p.text(50.0_f32, 50.0_f32, "outside", COLOR, 14.0_f32)
    p.pop_clip

    d.list[0].clip.should eq(clip)
    p.list[1].clip.should eq(clip)
  end

  it "attaches the active clip to shape commands on both painters" do
    clip = Tessell::Rect.new(0.0_f32, 0.0_f32, 10.0_f32, 10.0_f32)

    d = Tessell::Kit::DrawListPainter.new
    p = Tessell::Kit::PaintListPainter.new
    [d, p].each do |painter|
      painter.push_clip(clip)
      painter.fill_rect(Tessell::Rect.new(20.0_f32, 20.0_f32, 5.0_f32, 5.0_f32), COLOR)
      painter.stroke_rect(Tessell::Rect.new(20.0_f32, 20.0_f32, 5.0_f32, 5.0_f32), COLOR)
      painter.fill_round_rect(Tessell::Rect.new(20.0_f32, 20.0_f32, 5.0_f32, 5.0_f32), 2.0_f32, COLOR)
      painter.stroke_round_rect(Tessell::Rect.new(20.0_f32, 20.0_f32, 5.0_f32, 5.0_f32), 2.0_f32, COLOR)
      painter.line(1.0_f32, 1.0_f32, 9.0_f32, 9.0_f32, COLOR)
      painter.pop_clip
    end

    # 两个 Painter 的命令体系不同（PaintList 显式含 PushClip/PopClip 条目，
    # DrawList 把 clip 解析进命令本身），按剔除包装条目后逐一比对 clip。
    d_cmds = (0...d.list.size).map { |i| d.list[i] }
      .select { |c| c.kind != Tessell::Render::CmdKind::Text }
    p_cmds = p.list.to_a.reject { |c| c.kind == Tessell::Kit::PaintKind::PushClip ||
                                     c.kind == Tessell::Kit::PaintKind::PopClip }
    d_cmds.size.should eq(5)
    p_cmds.size.should eq(5)
    d_cmds.each { |c| c.clip.should eq(clip) }
    p_cmds.each { |c| c.clip.should eq(clip) }
  end

  it "intersects nested clips identically on both painters" do
    outer = Tessell::Rect.new(0.0_f32, 0.0_f32, 100.0_f32, 100.0_f32)
    inner = Tessell::Rect.new(50.0_f32, 50.0_f32, 100.0_f32, 100.0_f32)
    expected = Tessell::Rect.new(50.0_f32, 50.0_f32, 50.0_f32, 50.0_f32)

    d = Tessell::Kit::DrawListPainter.new
    d.push_clip(outer)
    d.push_clip(inner)
    d.text(10.0_f32, 10.0_f32, "x", COLOR, 14.0_f32)
    d.pop_clip
    d.text(10.0_f32, 10.0_f32, "y", COLOR, 14.0_f32)
    d.pop_clip

    p = Tessell::Kit::PaintListPainter.new
    p.push_clip(outer)
    p.push_clip(inner)
    p.text(10.0_f32, 10.0_f32, "x", COLOR, 14.0_f32)
    p.pop_clip
    p.text(10.0_f32, 10.0_f32, "y", COLOR, 14.0_f32)
    p.pop_clip

    # DrawList 把 clip 解析进命令（无 PushClip 条目）：list[0]=内层 text、list[1]=外层 text；
    # PaintList 显式含 PushClip/PopClip：list[2]=内层 text、list[4]=外层 text。
    d.list[0].clip.should eq(expected)
    d.list[1].clip.should eq(outer)
    p.list[2].clip.should eq(expected)
    p.list[4].clip.should eq(outer)
  end

  it "leaves clip nil when no push_clip is active" do
    d = Tessell::Kit::DrawListPainter.new
    d.text(1.0_f32, 1.0_f32, "free", COLOR, 14.0_f32)
    d.list[0].clip.should be_nil

    p = Tessell::Kit::PaintListPainter.new
    p.text(1.0_f32, 1.0_f32, "free", COLOR, 14.0_f32)
    p.list[0].clip.should be_nil
    p.list[0].responds_to?(:clip).should be_true
  end

  it "keeps PaintList clip_depth stack-balance reporting and painter reset clean" do
    p = Tessell::Kit::PaintListPainter.new
    p.push_clip(Tessell::Rect.new(0.0_f32, 0.0_f32, 5.0_f32, 5.0_f32))
    p.clip_depth.should eq(1)
    p.pop_clip
    p.clip_depth.should eq(0)

    p.push_clip(Tessell::Rect.new(0.0_f32, 0.0_f32, 5.0_f32, 5.0_f32))
    p.reset
    p.clip_depth.should eq(0)
    p.push_clip(Tessell::Rect.new(0.0_f32, 0.0_f32, 5.0_f32, 5.0_f32))
    p.pop_clip
    p.list[0].clip.should be_nil # reset 后 clip 栈确实清空，无残留
  end
end
