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

def measure_scenario(runner : FrameRunner, frames : Int32, paint1 : Bool) : {Int64, Int64, Int64, Array(Int64)}
  # warmup
  w = 0
  while w < 10
    if paint1
      runner.paint1_frame(w)
    else
      runner.static_frame
    end
    w += 1
  end

  # prime window (diagnostic)
  delta_prime = 0_i64
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
    delta_prime = after.to_i64 - before.to_i64
  ensure
    GC.enable
  end

  # calib window (diagnostic)
  delta_calib = 0_i64
  calib_sink = 0_i64
  GC.collect
  GC.disable
  begin
    before = GC.stats.bytes_since_gc
    i = 0
    while i < frames
      calib_sink &+= i.to_i64
      i += 1
    end
    after = GC.stats.bytes_since_gc
    delta_calib = after.to_i64 - before.to_i64
  ensure
    GC.enable
  end
  _ = calib_sink # keep observable side effect value live

  # 3 work windows
  work = [] of Int64
  3.times do
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
      work << (after.to_i64 - before.to_i64)
    ensure
      GC.enable
    end
  end
  {delta_prime, delta_calib, work.max, work}
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

static_prime, static_calib, static_alloc, static_work = measure_scenario(runner, frames, false)
paint_prime, paint_calib, paint_alloc, paint_work = measure_scenario(runner, frames, true)

static_seq = "[#{static_work[0]},#{static_work[1]},#{static_work[2]}]"
paint_seq = "[#{paint_work[0]},#{paint_work[1]},#{paint_work[2]}]"
static_ok = static_alloc < frames && static_alloc <= 64
paint_ok = paint_alloc < frames && paint_alloc <= 64

if json_out
  puts %({"scenario":"static","frames":#{frames},"nodes":#{node_count},"alloc_bytes":#{static_alloc},"criterion_ok":#{static_ok},"delta_prime":#{static_prime},"delta_calib":#{static_calib},"windows":#{static_seq}})
  puts %({"scenario":"paint1","frames":#{frames},"nodes":#{node_count},"alloc_bytes":#{paint_alloc},"criterion_ok":#{paint_ok},"delta_prime":#{paint_prime},"delta_calib":#{paint_calib},"windows":#{paint_seq}})
else
  puts "scenario=static frames=#{frames} nodes=#{node_count} alloc_bytes=#{static_alloc} criterion_ok=#{static_ok} delta_prime=#{static_prime} delta_calib=#{static_calib} windows=#{static_seq}"
  puts "scenario=paint1 frames=#{frames} nodes=#{node_count} alloc_bytes=#{paint_alloc} criterion_ok=#{paint_ok} delta_prime=#{paint_prime} delta_calib=#{paint_calib} windows=#{paint_seq}"
end

unless static_ok
  puts "alloc_note=static criterion failed: alloc_bytes=#{static_alloc} frames=#{frames} (require <frames and <=64) windows=#{static_seq} prime=#{static_prime} calib=#{static_calib}"
end
unless paint_ok
  puts "alloc_note=paint1 criterion failed: alloc_bytes=#{paint_alloc} frames=#{frames} (require <frames and <=64) windows=#{paint_seq} prime=#{paint_prime} calib=#{paint_calib}"
end
exit 1 unless static_ok && paint_ok
