# M0-WP5m frame-time/alloc benchmark spike (W2-5 / task-12, updated W2-fix task-19)
# Simulates N frames of layout+draw-record generation.
# Scenarios:
#   default (no flag): per-frame Array(DrawCmd).new + push, measures allocation-heavy path.
#                      Outputs scenario=default; alloc_bytes reflects per-frame allocations.
#                      **MUST NOT** be used as M1-WP5 "zero-allocation steady-state" criterion.
#   --steady: preallocates all buffers, loop body does index writes only (no new/<<).
#             Outputs scenario=steady, alloc_bytes_steady, alloc_delta_zero.
# Protocol (both): warmup -> GC.collect (gc_stable_start) -> GC.disable ->
#   before=GC.stats.bytes_since_gc -> N frames -> after -> GC.enable.
# Usage:
#   crystal run tools/bench_frame_time.cr -- --frames=300 --warmup=30
#   crystal run tools/bench_frame_time.cr -- --frames=300 --warmup=30 --steady
#   crystal run tools/bench_frame_time.cr -- --frames=300 --warmup=30 --steady --json

struct FakeNode
  property x : Float64
  property y : Float64
  property w : Float64
  property h : Float64
  property color : UInt32
  property z : Int32

  def initialize(@x, @y, @w, @h, @color, @z)
  end
end

struct DrawCmd
  property kind : UInt8
  property x : Float64
  property y : Float64
  property w : Float64
  property h : Float64
  property arg : UInt32

  def initialize(@kind, @x, @y, @w, @h, @arg)
  end
end

def percentile(sorted : Array(Float64), p : Float64) : Float64
  return 0.0 if sorted.empty?
  return sorted.first if sorted.size == 1
  rank = (p / 100.0) * (sorted.size - 1)
  lo = rank.floor.to_i
  hi = rank.ceil.to_i
  return sorted[lo] if lo == hi
  w = rank - lo
  sorted[lo] * (1.0 - w) + sorted[hi] * w
end

def fmt1(v : Float64) : String
  # 1 decimal place
  s = ((v * 10.0).round / 10.0).to_s
  if s.includes?('.')
    parts = s.split('.')
    if parts[1].size == 0
      "#{parts[0]}.0"
    elsif parts[1].size == 1
      s
    else
      "#{parts[0]}.#{parts[1][0, 1]}"
    end
  else
    "#{s}.0"
  end
end

frames = 300
warmup = 30
json_out = false
steady = false
i = 0
while i < ARGV.size
  arg = ARGV[i]
  if arg.starts_with?("--frames=")
    frames = arg.split("=", 2)[1].to_i
  elsif arg == "--frames" && i + 1 < ARGV.size
    frames = ARGV[i + 1].to_i
    i += 1
  elsif arg.starts_with?("--warmup=")
    warmup = arg.split("=", 2)[1].to_i
  elsif arg == "--warmup" && i + 1 < ARGV.size
    warmup = ARGV[i + 1].to_i
    i += 1
  elsif arg == "--json"
    json_out = true
  elsif arg == "--steady"
    steady = true
  end
  i += 1
end

if frames <= 0
  STDERR.puts "error=invalid_frames frames=#{frames}"
  exit 1
end
if warmup < 0
  STDERR.puts "error=invalid_warmup warmup=#{warmup}"
  exit 1
end

# Simulate a fixed scene: N nodes, generate layout + draw commands per frame.
node_count = 200
nodes = Array(FakeNode).new(node_count)
node_count.times do |n|
  nodes << FakeNode.new(n.to_f64 * 2.0, n.to_f64 * 1.5, 24.0 + (n % 10), 16.0 + (n % 6), 0xFF203040_u32 + n.to_u32, n)
end

work_sink = 0_u64
scenario = steady ? "steady" : "default"

# Preallocate buffers for steady scenario (and durations buffer reused by index).
cmds_cap = node_count * 2
cmds_buf = Array(DrawCmd).new(cmds_cap) { DrawCmd.new(0_u8, 0.0, 0.0, 0.0, 0.0, 0_u32) }
durations_us = Array(Float64).new(frames, 0.0)

# Warmup (steady: index writes into preallocated buffer; default: per-frame alloc).
warmup.times do |f|
  if steady
    nodes.each_with_index do |nd, idx|
      x = nd.x + (f % 3).to_f64
      y = nd.y + (f % 5).to_f64
      base = idx * 2
      cmds_buf[base] = DrawCmd.new(1_u8, x, y, nd.w, nd.h, nd.color)
      cmds_buf[base + 1] = DrawCmd.new(2_u8, x + 1.0, y + 1.0, nd.w - 2.0, nd.h - 2.0, 0xFFFFFFFF_u32)
      work_sink &+= (x.to_i64 + y.to_i64 + idx).to_u64
    end
    work_sink &+= cmds_buf.size.to_u64
  else
    cmds = Array(DrawCmd).new(cmds_cap)
    nodes.each_with_index do |nd, idx|
      x = nd.x + (f % 3).to_f64
      y = nd.y + (f % 5).to_f64
      cmds << DrawCmd.new(1_u8, x, y, nd.w, nd.h, nd.color)
      cmds << DrawCmd.new(2_u8, x + 1.0, y + 1.0, nd.w - 2.0, nd.h - 2.0, 0xFFFFFFFF_u32)
      work_sink &+= (x.to_i64 + y.to_i64 + idx).to_u64
    end
    work_sink &+= cmds.size.to_u64
  end
end

# Allocation sampling protocol (M1-WP5): warmup -> GC.collect (gc_stable_start) ->
# GC.disable -> before=bytes_since_gc -> N frames -> after -> GC.enable.
GC.collect
gc_stable_start = "collected"
GC.disable
before_bytes = GC.stats.bytes_since_gc

frames.times do |f|
  t0 = Time.instant
  total_w = 0.0
  if steady
    nodes.each_with_index do |nd, idx|
      # simple "layout" update + "draw record" generation into preallocated buffer
      x = nd.x + (f & 1).to_f64
      y = nd.y + ((f + idx) % 7).to_f64 * 0.5
      w = nd.w
      h = nd.h
      base = idx * 2
      cmds_buf[base] = DrawCmd.new(1_u8, x, y, w, h, nd.color ^ (f.to_u32 & 0xFF_u32))
      cmds_buf[base + 1] = DrawCmd.new(2_u8, x + 2.0, y + 2.0, w - 4.0, h - 4.0, 0xFF000000_u32 | (idx.to_u32 * 13_u32))
      total_w += w + h + x + y
    end
    work_sink &+= cmds_buf.size.to_u64 + total_w.to_i64.to_u64
  else
    cmds = Array(DrawCmd).new(cmds_cap)
    nodes.each_with_index do |nd, idx|
      # simple "layout" update + "draw record" generation
      x = nd.x + (f & 1).to_f64
      y = nd.y + ((f + idx) % 7).to_f64 * 0.5
      w = nd.w
      h = nd.h
      cmds << DrawCmd.new(1_u8, x, y, w, h, nd.color ^ (f.to_u32 & 0xFF_u32))
      cmds << DrawCmd.new(2_u8, x + 2.0, y + 2.0, w - 4.0, h - 4.0, 0xFF000000_u32 | (idx.to_u32 * 13_u32))
      total_w += w + h + x + y
    end
    work_sink &+= cmds.size.to_u64 + total_w.to_i64.to_u64
  end
  t1 = Time.instant
  durations_us[f] = (t1 - t0).total_microseconds
end

after_bytes = GC.stats.bytes_since_gc
GC.enable

# Prevent dead-code elimination / keep sink observable
if work_sink == 0xFFFFFFFFFFFFFFFF_u64
  STDERR.puts "sink=#{work_sink}"
end

sorted = durations_us.dup
sorted.sort!

p50 = percentile(sorted, 50.0)
p95 = percentile(sorted, 95.0)
p99 = percentile(sorted, 99.0)
sum = 0.0
sorted.each { |v| sum += v }
mean = sorted.empty? ? 0.0 : (sum / sorted.size)
min_v = sorted.empty? ? 0.0 : sorted.first
max_v = sorted.empty? ? 0.0 : sorted.last
alloc_bytes = after_bytes >= before_bytes ? (after_bytes - before_bytes) : 0_u64
alloc_delta_zero = alloc_bytes == 0_u64

if json_out
  # machine-readable JSON line
  print "{"
  print "\"scenario\":\"#{scenario}\","
  print "\"frames\":#{frames},"
  print "\"warmup\":#{warmup},"
  print "\"p50_us\":#{fmt1(p50)},"
  print "\"p95_us\":#{fmt1(p95)},"
  print "\"p99_us\":#{fmt1(p99)},"
  print "\"mean_us\":#{fmt1(mean)},"
  print "\"min_us\":#{fmt1(min_v)},"
  print "\"max_us\":#{fmt1(max_v)},"
  print "\"alloc_bytes\":#{alloc_bytes},"
  if steady
    print "\"alloc_bytes_steady\":#{alloc_bytes},"
    print "\"alloc_delta_zero\":#{alloc_delta_zero},"
  end
  print "\"gc_disabled\":true,"
  print "\"gc_stable_start\":\"#{gc_stable_start}\""
  puts "}"
end

puts "scenario=#{scenario}"
puts "frames=#{frames}"
puts "warmup=#{warmup}"
puts "p50_us=#{fmt1(p50)}"
puts "p95_us=#{fmt1(p95)}"
puts "p99_us=#{fmt1(p99)}"
puts "mean_us=#{fmt1(mean)}"
puts "min_us=#{fmt1(min_v)}"
puts "max_us=#{fmt1(max_v)}"
puts "alloc_bytes=#{alloc_bytes}"
if steady
  puts "alloc_bytes_steady=#{alloc_bytes}"
  puts "alloc_delta_zero=#{alloc_delta_zero}"
end
puts "gc_disabled=true"
puts "gc_stable_start=#{gc_stable_start}"
exit 0
