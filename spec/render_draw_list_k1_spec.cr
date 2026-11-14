require "spec"
require "../src/tessell/render/draw_list"

include Tessell

describe "DrawList K1 commands" do
  it "carries radius and stroke width with defaults preserved" do
    plain = Render::DrawCmd.new(Render::CmdKind::Rect,
      Rect.new(0.0_f32, 0.0_f32, 10.0_f32, 10.0_f32), 0xff000000_u32)
    plain.radius.should eq(0.0_f32)
    plain.stroke_width.should eq(0.0_f32)

    rounded = Render::DrawCmd.new(Render::CmdKind::RoundRect,
      Rect.new(0.0_f32, 0.0_f32, 10.0_f32, 10.0_f32), 0xff000000_u32,
      radius: 4.0_f32)
    rounded.kind.should eq(Render::CmdKind::RoundRect)
    rounded.radius.should eq(4.0_f32)

    stroke = Render::DrawCmd.new(Render::CmdKind::StrokeRoundRect,
      Rect.new(0.0_f32, 0.0_f32, 10.0_f32, 10.0_f32), 0xff000000_u32,
      radius: 4.0_f32, stroke_width: 2.0_f32)
    stroke.stroke_width.should eq(2.0_f32)
  end

  it "keeps existing batch key semantics (atlas + clip only)" do
    list = Render::DrawList.new
    list.push(Render::DrawCmd.new(Render::CmdKind::RoundRect,
      Rect.new(0.0_f32, 0.0_f32, 10.0_f32, 10.0_f32), 0_u32, atlas_id: 1, radius: 4.0_f32))
    list.push(Render::DrawCmd.new(Render::CmdKind::StrokeRoundRect,
      Rect.new(0.0_f32, 0.0_f32, 10.0_f32, 10.0_f32), 0_u32, atlas_id: 1, radius: 4.0_f32, stroke_width: 2.0_f32))
    list.build_batches.size.should eq(1)
  end
end
