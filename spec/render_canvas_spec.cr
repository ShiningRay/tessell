require "spec"
require "../src/tessell/render/canvas"

# Issue #2：Render::Canvas 统一绘制门面。命令写入 DrawList，由
# Backend#draw_draw_list 执行；polyline 展开为逐段 Line 命令。
describe "Render::Canvas" do
  it "emits fill/stroke/line commands with clip resolution" do
    canvas = Tessell::Render::Canvas.new
    canvas.fill_rect(Tessell::Rect.new(0, 0, 100, 100), 0xff0000ff_u32)
    canvas.stroke_rect(Tessell::Rect.new(10, 10, 80, 80), 0xff000000_u32, 2.0_f32)
    canvas.line(0.0_f32, 0.0_f32, 50.0_f32, 50.0_f32, 0xff00ff00_u32, 1.5_f32)
    canvas.fill_round_rect(Tessell::Rect.new(0, 0, 40, 40), 6.0_f32, 0xff0000ff_u32)
    canvas.stroke_round_rect(Tessell::Rect.new(0, 0, 40, 40), 6.0_f32, 0xff000000_u32, 1.0_f32)

    canvas.list.size.should eq(5)
    canvas.list[0].kind.should eq(Tessell::Render::CmdKind::Rect)
    canvas.list[1].kind.should eq(Tessell::Render::CmdKind::StrokeRect)
    canvas.list[1].stroke_width.should eq(2.0_f32)
    canvas.list[2].kind.should eq(Tessell::Render::CmdKind::Line)
    canvas.list[2].p1.x.should eq(0.0_f32)
    canvas.list[2].p2.y.should eq(50.0_f32)
    canvas.list[3].kind.should eq(Tessell::Render::CmdKind::RoundRect)
    canvas.list[4].kind.should eq(Tessell::Render::CmdKind::StrokeRoundRect)
    5.times { |i| canvas.list[i].clip.should be_nil }
  end

  it "push_clip/pop_clip applies per command with nested intersection" do
    canvas = Tessell::Render::Canvas.new
    outer = Tessell::Rect.new(0, 0, 200, 100)
    inner = Tessell::Rect.new(50, 50, 100, 100)
    canvas.push_clip(outer)
    canvas.fill_rect(Tessell::Rect.new(0, 0, 300, 50), 0xff0000ff_u32)
    canvas.push_clip(inner)
    canvas.fill_rect(Tessell::Rect.new(0, 0, 300, 50), 0xff0000ff_u32)
    canvas.pop_clip
    canvas.line(0.0_f32, 0.0_f32, 10.0_f32, 10.0_f32, 0xff000000_u32)
    canvas.pop_clip
    canvas.fill_rect(Tessell::Rect.new(0, 0, 10, 10), 0xff000000_u32)

    canvas.list[0].clip.should eq(outer)
    canvas.list[1].clip.should eq(Tessell::Rect.new(50, 50, 100, 50))
    canvas.list[2].clip.should eq(outer)
    canvas.list[3].clip.should be_nil
    canvas.clip_depth.should eq(0)
  end

  it "polyline expands to per-segment Line commands sharing the clip" do
    canvas = Tessell::Render::Canvas.new
    pts = [Tessell::Point.new(0.0_f32, 0.0_f32),
           Tessell::Point.new(10.0_f32, 10.0_f32),
           Tessell::Point.new(20.0_f32, 0.0_f32),
           Tessell::Point.new(30.0_f32, 10.0_f32)]
    clip = Tessell::Rect.new(0, 0, 100, 100)
    canvas.push_clip(clip)
    canvas.polyline(pts, 0xff0000ff_u32, 2.0_f32)
    canvas.pop_clip

    canvas.list.size.should eq(3)
    3.times do |i|
      canvas.list[i].kind.should eq(Tessell::Render::CmdKind::Line)
      canvas.list[i].clip.should eq(clip)
      canvas.list[i].stroke_width.should eq(2.0_f32)
    end
    canvas.list[0].p2.x.should eq(10.0_f32)
    canvas.list[1].p1.x.should eq(10.0_f32)
    canvas.list[2].p2.x.should eq(30.0_f32)
  end

  it "polyline with fewer than 2 points emits nothing" do
    canvas = Tessell::Render::Canvas.new
    canvas.polyline([Tessell::Point.new(1.0_f32, 1.0_f32)], 0xff0000ff_u32)
    canvas.polyline([] of Tessell::Point, 0xff0000ff_u32)
    canvas.list.size.should eq(0)
  end

  it "commands batch contiguously: same clip merges, clip change splits" do
    canvas = Tessell::Render::Canvas.new
    canvas.fill_rect(Tessell::Rect.new(0, 0, 10, 10), 0xff0000ff_u32)
    canvas.fill_rect(Tessell::Rect.new(20, 0, 10, 10), 0xff0000ff_u32)
    canvas.push_clip(Tessell::Rect.new(0, 0, 50, 50))
    canvas.fill_rect(Tessell::Rect.new(40, 0, 10, 10), 0xff0000ff_u32)
    batches = canvas.list.build_batches
    batches.size.should eq(2)
    batches[0].count.should eq(2)
    batches[1].count.should eq(1)
  end

  it "clear resets commands and clips" do
    canvas = Tessell::Render::Canvas.new
    canvas.push_clip(Tessell::Rect.new(0, 0, 10, 10))
    canvas.fill_rect(Tessell::Rect.new(0, 0, 10, 10), 0xff0000ff_u32)
    canvas.clear
    canvas.list.size.should eq(0)
    canvas.clip_depth.should eq(0)
  end
end
