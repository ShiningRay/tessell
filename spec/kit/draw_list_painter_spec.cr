require "./spec_helper"

describe "Kit DrawListPainter" do
  it "maps round rect and stroke commands with radius/width" do
    painter = Tessell::Kit::DrawListPainter.new
    painter.fill_round_rect(Tessell::Rect.new(0.0_f32, 0.0_f32, 10.0_f32, 10.0_f32), 4.0_f32, 0xff000000_u32)
    painter.stroke_round_rect(Tessell::Rect.new(0.0_f32, 0.0_f32, 10.0_f32, 10.0_f32), 4.0_f32, 0xffffffff_u32, 2.0_f32)

    painter.list.size.should eq(2)
    painter.list[0].kind.should eq(Tessell::Render::CmdKind::RoundRect)
    painter.list[0].radius.should eq(4.0_f32)
    painter.list[1].kind.should eq(Tessell::Render::CmdKind::StrokeRoundRect)
    painter.list[1].stroke_width.should eq(2.0_f32)
  end

  it "intersects nested clips and restores on pop" do
    painter = Tessell::Kit::DrawListPainter.new
    outer = Tessell::Rect.new(0.0_f32, 0.0_f32, 100.0_f32, 100.0_f32)
    inner = Tessell::Rect.new(50.0_f32, 50.0_f32, 100.0_f32, 100.0_f32)
    painter.push_clip(outer)
    painter.push_clip(inner)
    painter.fill_rect(Tessell::Rect.new(0.0_f32, 0.0_f32, 200.0_f32, 200.0_f32), 0xff000000_u32)
    painter.pop_clip
    painter.fill_rect(Tessell::Rect.new(0.0_f32, 0.0_f32, 200.0_f32, 200.0_f32), 0xff000000_u32)
    painter.pop_clip
    painter.fill_rect(Tessell::Rect.new(0.0_f32, 0.0_f32, 200.0_f32, 200.0_f32), 0xff000000_u32)

    painter.list[0].clip.should eq(Tessell::Rect.new(50.0_f32, 50.0_f32, 50.0_f32, 50.0_f32))
    painter.list[1].clip.should eq(outer)
    painter.list[2].clip.should be_nil
    painter.clip_depth.should eq(0)
  end
end
