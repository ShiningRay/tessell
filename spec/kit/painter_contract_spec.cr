require "spec"
require "../../src/tessell/kit"

# Issue #15：Painter 契约——调用顺序即绘制顺序（文本与形状可交错）、
# clip 同时约束形状与文本、命令列表不得重排。
describe "Kit::Painter contract" do
  it "PaintListPainter preserves command order for interleaved fill/text/fill" do
    p = Tessell::Kit::PaintListPainter.new
    p.fill_rect(Tessell::Rect.new(0, 0, 100, 20), 0xff000000_u32)
    p.text(2.0_f32, 14.0_f32, "hello", 0x00ff00ff_u32, 12.0_f32)
    p.fill_rect(Tessell::Rect.new(0, 0, 100, 20), 0x000000ff_u32)
    kinds = p.list.to_a.map(&.kind)
    kinds.should eq([Tessell::Kit::PaintKind::FillRect,
                     Tessell::Kit::PaintKind::Text,
                     Tessell::Kit::PaintKind::FillRect])
  end

  it "DrawListPainter keeps Text commands inline (no reordering, batching is contiguous)" do
    p = Tessell::Kit::DrawListPainter.new
    p.fill_rect(Tessell::Rect.new(0, 0, 100, 20), 0xff000000_u32)
    p.text(2.0_f32, 14.0_f32, "hello", 0x00ff00ff_u32, 12.0_f32)
    p.fill_rect(Tessell::Rect.new(0, 0, 100, 20), 0x000000ff_u32)
    kinds = [p.list[0].kind, p.list[1].kind, p.list[2].kind]
    kinds.should eq([Tessell::Render::CmdKind::Rect,
                     Tessell::Render::CmdKind::Text,
                     Tessell::Render::CmdKind::Rect])
    # batches are contiguous ranges covering the command array in order:
    # batching never reorders or drops commands
    batches = p.list.build_batches
    covered = batches.sum(&.count)
    covered.should eq(p.list.size)
    first = 0
    batches.each do |b|
      b.start.should eq(first)
      first = b.start + b.count
    end
    first.should eq(p.list.size)
  end

  it "DrawListPainter resolves clip per command and text carries the active clip" do
    p = Tessell::Kit::DrawListPainter.new
    outer = Tessell::Rect.new(0, 0, 200, 100)
    p.push_clip(outer)
    p.fill_rect(Tessell::Rect.new(0, 0, 300, 50), 0xff000000_u32)
    p.text(2.0_f32, 14.0_f32, "row", 0xff00ffff_u32, 12.0_f32)
    inner = Tessell::Rect.new(10, 0, 100, 100)
    p.push_clip(inner)
    p.fill_rect(Tessell::Rect.new(0, 0, 300, 50), 0xff000000_u32)
    p.pop_clip
    p.text(2.0_f32, 40.0_f32, "row2", 0xff00ffff_u32, 12.0_f32)
    p.pop_clip

    p.list[0].clip.should eq(outer)                    # shape under outer clip
    p.list[1].clip.should eq(outer)                    # text under outer clip
    p.list[2].clip.should eq(Tessell::Kit::Geometry.intersect(outer, inner))
    p.list[3].clip.should eq(outer)                    # pop restores outer clip
    p.clip_depth.should eq(0)
  end

  it "PaintList clip_depth counts unclosed push_clip" do
    p = Tessell::Kit::PaintListPainter.new
    p.push_clip(Tessell::Rect.new(0, 0, 10, 10))
    p.push_clip(Tessell::Rect.new(5, 5, 10, 10))
    p.pop_clip
    p.list.clip_depth.should eq(1)
  end

  it "nested push_clip intersects with the active clip (text and shapes share it)" do
    p = Tessell::Kit::DrawListPainter.new
    a = Tessell::Rect.new(0, 0, 100, 100)
    b = Tessell::Rect.new(50, 50, 100, 100)
    p.push_clip(a)
    p.push_clip(b)
    p.text(60.0_f32, 70.0_f32, "cell", 0xff0000ff_u32, 12.0_f32)
    expected = Tessell::Kit::Geometry.intersect(a, b)
    p.list[0].clip.should eq(expected)
  end
end
