require "spec"
require "../src/tessell/render/draw_list"
require "../src/tessell/render/dirty"

include Tessell

# 确定性桩命令工厂：bounds 固定 (0,0,10,10)，kind/atlas/clip 由参数控制。
def make_cmd(kind : Render::CmdKind = Render::CmdKind::Rect,
             atlas : Int32 = -1,
             clip : Rect? = nil) : Render::DrawCmd
  Render::DrawCmd.new(kind, Rect.new(0.0_f32, 0.0_f32, 10.0_f32, 10.0_f32),
    0xff000000_u32, atlas, clip)
end

describe Tessell::Render::DrawList do
  it "push keeps order and size tracks logical count" do
    list = Render::DrawList.new
    3.times { list.push(make_cmd) }
    list.size.should eq 3
    list[0].kind.should eq Render::CmdKind::Rect
    list[2].kind.should eq Render::CmdKind::Rect
  end

  it "clear resets size to 0 but keeps capacity (buffer reuse)" do
    list = Render::DrawList.new
    list.reserve(32)
    5.times { list.push(make_cmd) }
    cap = list.capacity
    (cap >= 32).should be_true
    list.clear
    list.size.should eq 0
    list.capacity.should eq cap
  end

  it "10_000 push/clear cycles keep capacity stable (no reallocation in steady state)" do
    list = Render::DrawList.new
    list.reserve(64)
    cap0 = list.capacity
    10_000.times do
      list.clear
      64.times { list.push(make_cmd) }
      list.size.should eq 64
    end
    list.capacity.should eq cap0
    stats = list.reuse_stats
    stats[:capacity].should eq cap0
    stats[:size].should eq 64
    stats[:physical].should eq 64
  end

  it "adjacent commands with same atlas and clip form one batch" do
    list = Render::DrawList.new
    3.times { list.push(make_cmd(atlas: 1)) }
    batches = list.build_batches
    batches.size.should eq 1
    batches[0].start.should eq 0
    batches[0].count.should eq 3
    list.batch_count.should eq 1
  end

  it "atlas change splits batches" do
    list = Render::DrawList.new
    list.push(make_cmd(atlas: 1))
    list.push(make_cmd(atlas: 1))
    list.push(make_cmd(atlas: 2))
    batches = list.build_batches
    batches.size.should eq 2
    batches[0].start.should eq 0
    batches[0].count.should eq 2
    batches[1].start.should eq 2
    batches[1].count.should eq 1
  end

  it "clip change splits batches" do
    list = Render::DrawList.new
    list.push(make_cmd(clip: nil))
    list.push(make_cmd(clip: nil))
    list.push(make_cmd(clip: Rect.new(0.0_f32, 0.0_f32, 5.0_f32, 5.0_f32)))
    batches = list.build_batches
    batches.size.should eq 2
    batches[0].start.should eq 0
    batches[0].count.should eq 2
    batches[1].start.should eq 2
    batches[1].count.should eq 1
  end

  it "kind/color differences do not split batches (only atlas+clip are the batch key)" do
    list = Render::DrawList.new
    list.push(make_cmd(kind: Render::CmdKind::Rect, atlas: 7))
    list.push(make_cmd(kind: Render::CmdKind::Text, atlas: 7))
    list.push(make_cmd(kind: Render::CmdKind::Line, atlas: 7))
    list.build_batches.size.should eq 1
  end

  it "empty list yields zero batches" do
    list = Render::DrawList.new
    list.build_batches.should be_empty
    list.batch_count.should eq 0
  end
end

describe Tessell::Render::Dirty do
  it "merge collapses overlapping rects into one bounding box" do
    result = Render::Dirty.merge([Rect.new(0.0_f32, 0.0_f32, 10.0_f32, 10.0_f32),
                                  Rect.new(5.0_f32, 5.0_f32, 10.0_f32, 10.0_f32)])
    result.size.should eq 1
    result[0].should eq Rect.new(0.0_f32, 0.0_f32, 15.0_f32, 15.0_f32)
  end

  it "merge collapses edge-touching rects" do
    result = Render::Dirty.merge([Rect.new(0.0_f32, 0.0_f32, 10.0_f32, 10.0_f32),
                                  Rect.new(10.0_f32, 0.0_f32, 10.0_f32, 10.0_f32)])
    result.size.should eq 1
    result[0].should eq Rect.new(0.0_f32, 0.0_f32, 20.0_f32, 10.0_f32)
  end

  it "disjoint rects are preserved" do
    result = Render::Dirty.merge([Rect.new(0.0_f32, 0.0_f32, 10.0_f32, 10.0_f32),
                                  Rect.new(100.0_f32, 100.0_f32, 5.0_f32, 5.0_f32)])
    result.size.should eq 2
  end

  it "max_regions caps greedy merge: 8 disjoint rects -> <= 4 regions" do
    rects = (0...8).map do |i|
      Rect.new((i * 100).to_f32, 0.0_f32, 10.0_f32, 10.0_f32)
    end
    result = Render::Dirty.merge(rects, 4)
    (result.size <= 4).should be_true
    (result.size > 0).should be_true
    result.each do |r|
      (r.size.width > 0.0_f32).should be_true
      (r.size.height > 0.0_f32).should be_true
    end
  end

  it "empty input yields empty output and zero area" do
    Render::Dirty.merge([] of Rect).should be_empty
    Render::Dirty.area([] of Rect).should eq 0.0
  end

  it "degenerate input rects are ignored; output never contains empty rects" do
    result = Render::Dirty.merge([Rect.new(0.0_f32, 0.0_f32, 0.0_f32, 5.0_f32),
                                  Rect.new(0.0_f32, 0.0_f32, 10.0_f32, 10.0_f32)])
    result.size.should eq 1
    result[0].should eq Rect.new(0.0_f32, 0.0_f32, 10.0_f32, 10.0_f32)
  end

  it "area sums hand-computable rects (100 + 25 = 125)" do
    rects = [Rect.new(0.0_f32, 0.0_f32, 10.0_f32, 10.0_f32),
             Rect.new(20.0_f32, 20.0_f32, 5.0_f32, 5.0_f32)]
    Render::Dirty.area(rects).should eq 125.0
  end
end
