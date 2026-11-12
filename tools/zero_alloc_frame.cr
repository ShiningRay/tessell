# tools/zero_alloc_frame.cr — M1-WP5 稳态零分配探针（static / paint1 两场景）。
#
# 口径（plan.md:167/238）：warmup → GC.collect → 记录 bytes_since_gc → GC.disable → N 帧 → after → GC.enable。
# 热帧路径禁分配：不 new Array、不用 each+block/闭包、不用字符串插值；缓冲全部预分配复用
# （dirty_buf / dirty_rects_in / dirty_rects_out 填满后 clear 保留容量；DrawList.reserve 预付槽位）。
# 场景 A static：全净树 —— collect_dirty + DrawList.clear + 按缓存布局重建全部命令 + merge_into。
# 场景 B paint1：每帧 1 节点 mark_dirty(Paint) → 收集 → 仅该节点命令重建 → clean!。
# 若实测非 0，如实输出实际字节，不用任何手段凑 0。

require "../src/tessell/geometry"
require "../src/tessell/core/node"
require "../src/tessell/render/draw_list"
require "../src/tessell/render/dirty"
require "../src/tessell/text/measurer"

include Tessell
include Tessell::Render

# ≥200 节点 3 层树：root → 4 mid → 每 mid 50 leaves（1+4+200=205）。
class FrameRunner
  def initialize(root : Tessell::Node, nodes : Array(Tessell::Node))
    @root = root
    @nodes = nodes
    @node_count = nodes.size

    @dirty_buf = [] of Tessell::Node
    (@node_count + 1).times { @dirty_buf << @root } # 预填槽位
    @dirty_buf.clear                                # clear 保留容量

    @dirty_rects_in = [] of Tessell::Rect
    (@node_count + 1).times { @dirty_rects_in << Tessell::Rect.new }
    @dirty_rects_in.clear

    @dirty_rects_out = [] of Tessell::Rect
    (@node_count + 1).times { @dirty_rects_out << Tessell::Rect.new }
    @dirty_rects_out.clear

    @draw_list = Tessell::Render::DrawList.new
    @draw_list.reserve(@node_count)
  end

  # 场景 A：全净树，每帧收集（空）+ 重建全部命令（按缓存 bounds）+ 合并脏矩形（空输入）。
  def static_frame : Nil
    Tessell::Node.collect_dirty(@root, @dirty_buf)
    @draw_list.clear
    i = 0
    while i < @node_count
      @draw_list.push(Tessell::Render::DrawCmd.new(Tessell::Render::CmdKind::Rect, @nodes[i].bounds, 0xff000000_u32))
      i += 1
    end
    Tessell::Render::Dirty.merge_into(@dirty_rects_in, @dirty_rects_out)
  end

  # 场景 B：每帧 1 节点 Paint 脏 → 收集 → 仅该节点命令重建 → clean!。
  def paint1_frame(frame : Int32) : Nil
    target = @nodes[frame % @node_count]
    target.mark_dirty(Tessell::Invalidation::Paint)
    Tessell::Node.collect_dirty(@root, @dirty_buf)
    @draw_list.clear
    i = 0
    while i < @dirty_buf.size
      @draw_list.push(Tessell::Render::DrawCmd.new(Tessell::Render::CmdKind::Rect, @dirty_buf[i].bounds, 0xff000000_u32))
      i += 1
    end
    @dirty_rects_in.clear
    @dirty_rects_in << target.bounds
    Tessell::Render::Dirty.merge_into(@dirty_rects_in, @dirty_rects_out)
    target.clean!
  end
end

def measure_scenario(runner : FrameRunner, frames : Int32, paint1 : Bool) : UInt64
  w = 0
  while w < 10
    if paint1
      runner.paint1_frame(w)
    else
      runner.static_frame
    end
    w += 1
  end

  before = 0_u64
  after = 0_u64
  GC.collect
  GC.disable
  begin
    before = GC.stats.bytes_since_gc
    f = 0
    while f < frames
      if paint1
        runner.paint1_frame(f)
      else
        runner.static_frame
      end
      f += 1
    end
    after = GC.stats.bytes_since_gc
  ensure
    GC.enable
  end
  after - before
end

frames = 200
json_out = false
ARGV.each do |a|
  if a.starts_with?("--frames=")
    frames = a[9, a.size - 9].to_i
  elsif a == "--json"
    json_out = true
  end
end

root = Node.new("root")
nodes = [root] of Node
4.times do |i|
  mid = Node.new("mid#{i}")
  root.add_child(mid)
  nodes << mid
  50.times do |j|
    leaf = Node.new("leaf#{i}_#{j}")
    mid.add_child(leaf)
    nodes << leaf
  end
end
node_count = nodes.size

# 固定文本叶子：StubMeasurer 仅在建树期测量一次，结果缓存到 node.bounds（热帧不调用）。
measurer = Text::StubMeasurer.new
i = 0
while i < node_count
  n = nodes[i]
  if n.children.size == 0
    sz = measurer.measure("T", 1, 16.0_f32, 0.0_f32)
    n.bounds = Rect.new((i % 20) * 8.0_f32, (i // 20) * 8.0_f32, sz.width, sz.height)
  else
    n.bounds = Rect.new((i % 8) * 80.0_f32, (i // 8) * 80.0_f32, 64.0_f32, 64.0_f32)
  end
  i += 1
end

runner = FrameRunner.new(root, nodes)

static_alloc = measure_scenario(runner, frames, false)
paint_alloc = measure_scenario(runner, frames, true)

if json_out
  puts %({"scenario":"static","frames":#{frames},"nodes":#{node_count},"alloc_bytes":#{static_alloc},"delta_zero":#{static_alloc == 0}})
  puts %({"scenario":"paint1","frames":#{frames},"nodes":#{node_count},"alloc_bytes":#{paint_alloc},"delta_zero":#{paint_alloc == 0}})
else
  puts "scenario=static frames=#{frames} nodes=#{node_count} alloc_bytes=#{static_alloc} delta_zero=#{(static_alloc == 0) ? "true" : "false"}"
  puts "scenario=paint1 frames=#{frames} nodes=#{node_count} alloc_bytes=#{paint_alloc} delta_zero=#{(paint_alloc == 0) ? "true" : "false"}"
end

# 非 0 如实提示（不凑 0、不臆断来源）：warmup 已跑，非 0 说明仍有隐式分配，需在证据中分析来源。
if static_alloc != 0
  puts "alloc_note=static non-zero: #{static_alloc} bytes in #{frames} measured frames; not forced to 0; source analysis in docs/evidence/M1-WP5-zero-alloc.md"
end
if paint_alloc != 0
  puts "alloc_note=paint1 non-zero: #{paint_alloc} bytes in #{frames} measured frames; not forced to 0; source analysis in docs/evidence/M1-WP5-zero-alloc.md"
end
