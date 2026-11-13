require "./spec_helper"
# M1-WP5 绋虫€侀浂鍒嗛厤锛歊ender::Dirty.merge_into 澶嶇敤璋冪敤鏂圭紦鍐诧紙spec锛夈€?#
# 瑕嗙洊锛?#   1) merge_into 涓?merge 鍦?6 缁勮緭鍏ヤ笂缁撴灉鐩哥瓑锛堝惈椤哄簭锛夛紱
#   2) sink 棰勫垎閰嶅悗閲嶅璋冪敤涓嶅闀匡紙size 涓嶈秴 max_regions銆侀噸澶嶈皟鐢ㄤ笉鎶涳級锛?#   3) 涓嶄骇绌虹煩褰紱
#   4) GC 闆跺垎閰嶆帰閽堝厹搴曪紙bytes_since_gc 宸€?0锛夈€?
require "spec"
require "../src/tessell/render/dirty"

include Tessell

def r(x, y, w, h)
  Rect.new(x.to_f32, y.to_f32, w.to_f32, h.to_f32)
end

describe "Render::Dirty.merge_into (M1-WP5 zero-alloc path)" do
  cases = {
    "empty"            => [] of Rect,
    "single"           => [r(0, 0, 10, 10)],
    "overlap"          => [r(0, 0, 10, 10), r(5, 5, 10, 10)],
    "adjacent"         => [r(0, 0, 10, 10), r(10, 0, 10, 10)],
    "disjoint"         => [r(0, 0, 10, 10), r(100, 100, 5, 5)],
    "degenerate+valid" => [r(0, 0, 0, 0), r(1, 1, 5, 5), r(2, 2, 0, 3)],
  }

  cases.each do |name, input|
    it "#{name}: merge_into equals merge (order included)" do
      sink = [] of Rect
      Render::Dirty.merge_into(input, sink)
      sink.should eq Render::Dirty.merge(input)
    end
  end

  it "honors max_regions greedily like merge" do
    input = [r(0, 0, 1, 1), r(10, 0, 1, 1), r(20, 0, 1, 1), r(30, 0, 1, 1),
             r(40, 0, 1, 1), r(50, 0, 1, 1), r(60, 0, 1, 1), r(70, 0, 1, 1)] of Rect
    sink = [] of Rect
    Render::Dirty.merge_into(input, sink, 4)
    sink.should eq Render::Dirty.merge(input, 4)
    sink.size.should be <= 4
  end

  it "produces no empty rectangles" do
    input = [r(0, 0, 0, 0), r(1, 1, 5, 5), r(2, 2, 0, 3), r(3, 3, 4, 0)] of Rect
    sink = [] of Rect
    Render::Dirty.merge_into(input, sink)
    sink.each do |rect|
      rect.size.width.should be > 0.0_f32
      rect.size.height.should be > 0.0_f32
    end
  end

  it "repeated calls on a pre-sized sink do not raise and size stays bounded" do
    input = [r(0, 0, 10, 10), r(5, 5, 10, 10)] of Rect
    sink = [] of Rect
    64.times { sink << Rect.new }
    sink.clear

    5.times do
      Render::Dirty.merge_into(input, sink)
      sink.size.should be <= 8
    end
    sink.size.should eq 1
  end

  it "satisfies zero-alloc criterion on repeated calls with a pre-sized sink (GC probe)" do
    input = [r(0, 0, 10, 10), r(5, 5, 10, 10), r(20, 20, 4, 4)] of Rect
    sink = [] of Rect
    64.times { sink << Rect.new }
    sink.clear

    n = 1000
    10.times { Render::Dirty.merge_into(input, sink) } # warmup

    # Prime window (diagnostic)
    delta_prime = 0_i64
    GC.collect
    GC.disable
    begin
      before = GC.stats.bytes_since_gc
      n.times { Render::Dirty.merge_into(input, sink) }
      after = GC.stats.bytes_since_gc
      delta_prime = after.to_i64 - before.to_i64
    ensure
      GC.enable
    end

    # Calib window (diagnostic)
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
      after = GC.stats.bytes_since_gc
      delta_calib = after.to_i64 - before.to_i64
    ensure
      GC.enable
    end
    calib_sink.should be >= 0_i64

    # 3 work windows. First failure: retry whole 3-window set once (GC noise denoising).
    retried = false
    attempt = 1
    loop do
      work = [] of Int64
      3.times do
        GC.collect
        GC.disable
        begin
          before = GC.stats.bytes_since_gc
          n.times { Render::Dirty.merge_into(input, sink) }
          after = GC.stats.bytes_since_gc
          work << (after.to_i64 - before.to_i64)
        ensure
          GC.enable
        end
      end
      delta_work = work.max
      seq = "[#{work[0]},#{work[1]},#{work[2]}]"
      puts "zero-alloc probe(render_dirty): delta_prime=#{delta_prime} delta_calib=#{delta_calib} delta_work=#{delta_work} N=#{n} windows=#{seq} retried=#{retried} attempt=#{attempt}"
      break if delta_work < n && delta_work <= 256
      if attempt >= 2
        fail "zero-alloc probe: delta_work=#{delta_work} delta_calib=#{delta_calib} delta_prime=#{delta_prime} N=#{n} windows=#{seq} retried=#{retried} attempt=#{attempt}"
      end
      retried = true
      attempt = 2
    end
  end
end
