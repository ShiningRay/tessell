require "./spec_helper"
require "../src/tessell/widgets/virtual_list"

describe Tessell::Widgets::VirtualList do
  it "10000 rows x 20px viewport 600: visible 30-31 rows, fetched_count <= 32 (no materialization)" do
    fetch_count = 0
    fetch = ->(i : Int32) { fetch_count += 1; nil }
    vl = Tessell::Widgets::VirtualList.new(10_000, 20, 600, fetch)

    vl.total_height.should eq 200_000
    vr = vl.visible_range
    count = vr[:last] - vr[:first] + 1
    (count == 30 || count == 31).should be_true
    n = vl.bind_visible { |idx, off| }
    n.should be <= 32
    vl.fetched_count.should be <= 32
    vl.fetched_count.should eq count
  end

  it "scroll_by(1000) changes first, fetched_count still <= 32, total_height preserved" do
    fetch = ->(i : Int32) { nil }
    vl = Tessell::Widgets::VirtualList.new(10_000, 20, 600, fetch)
    vl.bind_visible { |idx, off| }
    before = vl.visible_range
    vl.scroll_by(1000)
    after = vl.visible_range
    after[:first].should_not eq before[:first]
    n = vl.bind_visible { |idx, off| }
    n.should be <= 32
    vl.fetched_count.should be <= 32
    vl.total_height.should eq 200_000
  end

  it "scroll_to bottom clamps to max_scroll and last == 9999" do
    fetch = ->(i : Int32) { nil }
    vl = Tessell::Widgets::VirtualList.new(10_000, 20, 600, fetch)
    vl.scroll_to(1_000_000_000)
    vl.scroll_y.should eq vl.total_height - 600
    vr = vl.visible_range
    vr[:last].should eq 9999
  end

  it "empty list returns {0,-1} and safe operations" do
    fetch = ->(i : Int32) { nil }
    vl = Tessell::Widgets::VirtualList.new(0, 20, 600, fetch)
    vl.total_height.should eq 0
    vr = vl.visible_range
    vr[:first].should eq 0
    vr[:last].should eq -1
    vl.scroll_by(100)
    vl.scroll_y.should eq 0
    vl.bind_visible { |idx, off| }.should eq 0
  end

  it "single row list" do
    fetch = ->(i : Int32) { nil }
    vl = Tessell::Widgets::VirtualList.new(1, 20, 600, fetch)
    vr = vl.visible_range
    vr[:first].should eq 0
    vr[:last].should eq 0
    vl.scroll_y.should eq 0
    vl.scroll_to(100)
    vl.scroll_y.should eq 0
  end

  it "row height greater than viewport" do
    fetch = ->(i : Int32) { nil }
    vl = Tessell::Widgets::VirtualList.new(10, 800, 600, fetch)
    vr = vl.visible_range
    vr[:first].should eq 0
    (vr[:last] - vr[:first] + 1).should be >= 1
    (vr[:last] - vr[:first] + 1).should be <= 2
  end

  it "variable row heights (first 100 height 40, rest 20): total_height and node_offset(150) correct" do
    fetch = ->(i : Int32) { nil }
    proc = ->(i : Int32) { i < 100 ? 40 : 20 }
    vl = Tessell::Widgets::VirtualList.new(200, proc, 600, fetch)
    # total = 100*40 + 100*20 = 4000 + 2000 = 6000
    vl.total_height.should eq 6000
    # node_offset(150) at scroll 0 = prefix[150] = 100*40 + 50*20 = 4000 + 1000 = 5000
    vl.node_offset(150).should eq 5000
    vl.scroll_to(1000)
    vl.node_offset(150).should eq 4000
  end

  it "recycler: after 200 scrolls created <= pool_size+1" do
    fetch = ->(i : Int32) { nil }
    vl = Tessell::Widgets::VirtualList.new(10_000, 20, 600, fetch)
    ps = vl.pool_size
    200.times do |t|
      vl.scroll_by((t % 3) + 1)
      vl.bind_visible { |idx, off| }
    end
    stats = vl.recycle_stats
    stats[:created].should be <= ps + 1
    stats[:pool_size].should eq ps
  end

  it "dirty rects: scroll_by(10) => <=2 and area < viewport area" do
    fetch = ->(i : Int32) { nil }
    vl = Tessell::Widgets::VirtualList.new(10_000, 20, 600, fetch, 800)
    vl.dirty_rects # clear initial
    vl.scroll_by(10)
    dr = vl.dirty_rects
    dr[:count].should be <= 2
    dr[:area].should be < (800_i64 * 600_i64)
    dr[:count].should be >= 1
  end

  it "dirty rects: scroll_by(2*viewport_h) => 1 whole-window rect" do
    fetch = ->(i : Int32) { nil }
    vl = Tessell::Widgets::VirtualList.new(10_000, 20, 600, fetch, 800)
    vl.dirty_rects
    vl.scroll_by(1200)
    dr = vl.dirty_rects
    dr[:count].should eq 1
    dr[:area].should eq (800_i64 * 600_i64)
  end

  it "scroll_by within viewport upward produces strips" do
    fetch = ->(i : Int32) { nil }
    vl = Tessell::Widgets::VirtualList.new(10_000, 20, 600, fetch, 800)
    vl.scroll_to(5000)
    vl.dirty_rects
    vl.scroll_by(-20)
    dr = vl.dirty_rects
    dr[:count].should be <= 2
    dr[:count].should be >= 1
    dr[:area].should be < (800_i64 * 600_i64)
  end

  it "steady-state zero-alloc: 1000 scroll_by(1)+dirty_rects (criterion A/B, retry once)" do
    fetch = ->(i : Int32) { nil }
    vl = Tessell::Widgets::VirtualList.new(10_000, 20, 600, fetch, 800)
    n = 1000

    # warmup + steady binding/reuse
    50.times do |i|
      vl.scroll_by(1)
      vl.scroll_to(0) if vl.scroll_y >= vl.total_height - 600
      vl.dirty_rects
    end
    vl.scroll_to(0)
    vl.dirty_rects

    delta_prime = 0_i64
    GC.collect
    GC.disable
    begin
      before = GC.stats.bytes_since_gc
      i = 0
      while i < n
        vl.scroll_by(1)
        vl.scroll_to(0) if vl.scroll_y >= (vl.total_height - 600)
        vl.dirty_rects
        i += 1
      end
      delta_prime = GC.stats.bytes_since_gc.to_i64 - before.to_i64
    ensure
      GC.enable
    end

    delta_calib = 0_i64
    calib_sink = 0_i64
    GC.collect
    GC.disable
    begin
      before = GC.stats.bytes_since_gc
      i = 0
      while i < n
        calib_sink &+= i.to_i64
        i += 1
      end
      delta_calib = GC.stats.bytes_since_gc.to_i64 - before.to_i64
    ensure
      GC.enable
    end
    _ = calib_sink

    retried = false
    attempt = 1
    delta_work = 0_i64
    seq = [] of Int64
    loop do
      seq = [] of Int64
      3.times do
        GC.collect
        GC.disable
        begin
          before = GC.stats.bytes_since_gc
          i = 0
          while i < n
            vl.scroll_by(1)
            vl.scroll_to(0) if vl.scroll_y >= (vl.total_height - 600)
            vl.dirty_rects
            i += 1
          end
          seq << (GC.stats.bytes_since_gc.to_i64 - before.to_i64)
        ensure
          GC.enable
        end
      end
      delta_work = seq.max
      puts "zero-alloc probe(virtual_list): delta_prime=#{delta_prime} delta_calib=#{delta_calib} delta_work=#{delta_work} N=#{n} windows=[#{seq[0]},#{seq[1]},#{seq[2]}] retried=#{retried} attempt=#{attempt}"
      break if delta_work < n && delta_work <= 256
      if attempt >= 2
        fail "zero-alloc probe(virtual_list): delta_work=#{delta_work} delta_calib=#{delta_calib} delta_prime=#{delta_prime} N=#{n} windows=[#{seq[0]},#{seq[1]},#{seq[2]}] retried=#{retried} attempt=#{attempt}"
      end
      retried = true
      attempt = 2
    end
    (delta_work < n && delta_work <= 256).should be_true
  end
end