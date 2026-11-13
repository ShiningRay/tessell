require "./spec_helper"
# M1-WP5 绋虫€侀浂鍒嗛厤锛歂ode.collect_dirty 澶嶇敤璋冪敤鏂圭紦鍐诧紙spec锛夈€?#
# 瑕嗙洊锛?#   1) collect_dirty 涓?dirty_subtree 缁撴灉闆嗗悎涓€鑷达紙root 鑷剰 / 娣辨爲娣峰悎鑴?/ 鍏ㄥ噣绌猴級锛?#   2) sink 澶嶇敤鍚庝笉娈嬬暀鏃у厓绱狅紱
#   3) 涓ゆ璋冪敤瀹归噺涓嶅闀匡細Crystal 1.22 鏃犲叕寮€ Array#capacity锛?#      鐢ㄣ€屽厛濉弧棰勫垎閰嶆Ы浣嶅啀 clear锛坈lear 淇濈暀瀹归噺锛夆啋 閲嶅璋冪敤 size 涓嶈秴銆侀噸澶嶈皟鐢ㄤ笉鎶涖€?#      + GC 闆跺垎閰嶆帰閽堝厹搴曪紙bytes_since_gc 宸€?0锛夛紝涓嶄互 capacity 瀛楁浼€犮€?
require "spec"
require "../src/tessell/core/node"

include Tessell

describe "Node.collect_dirty (M1-WP5 zero-alloc path)" do
  it "matches dirty_subtree when root itself is dirty" do
    root = Node.new("root")
    a = Node.new("a")
    root.add_child(a)
    root.mark_dirty(Invalidation::Paint)

    sink = [] of Node
    Node.collect_dirty(root, sink)

    sink.map(&.id).should eq Node.dirty_subtree(root).map(&.id)
    sink.size.should eq 1
  end

  it "matches dirty_subtree on a deep tree with mixed dirt levels" do
    root = Node.new("root")
    nodes = [root] of Node
    10.times do |i|
      n = Node.new("n#{i}")
      nodes.last.add_child(n)
      nodes << n
    end
    nodes[3].mark_dirty(Invalidation::Layout)
    nodes[7].mark_dirty(Invalidation::CompositeOnly)

    sink = [] of Node
    Node.collect_dirty(root, sink)

    sink.map(&.id).should eq Node.dirty_subtree(root).map(&.id)
    # Layout 鑷?nodes[3] 鍚戜笂浼犳挱 root/n1/n2/n3 鍏?4 涓?+ nodes[7] CompositeOnly 1 涓?= 5
    sink.size.should eq 5
  end

  it "keeps sink empty on a fully clean tree" do
    root = Node.new("root")
    root.add_child(Node.new("a"))
    root.children[0].add_child(Node.new("b"))

    sink = [] of Node
    Node.collect_dirty(root, sink)
    sink.should be_empty
  end

  it "clears stale elements from a reused sink buffer" do
    root = Node.new("root")
    a = Node.new("a")
    root.add_child(a)

    sink = [root, a, root] of Node
    Node.collect_dirty(root, sink)
    sink.should be_empty
  end

  it "repeated calls on a pre-sized buffer do not raise and size stays bounded" do
    root = Node.new("root")
    200.times do |i|
      root.add_child(Node.new("c#{i}"))
    end

    sink = [] of Node
    # 棰勫垎閰嶆Ы浣嶏紙Array 鏃犲叕寮€ reserve/瀹归噺瀛楁锛夛細濉弧鍚?clear锛屽閲忎繚鐣欍€?    201.times { sink << root }
    sink.clear

    5.times do
      Node.collect_dirty(root, sink)
      sink.size.should be <= 201
    end
    sink.should be_empty
  end

  it "satisfies zero-alloc criterion on repeated calls with a pre-sized buffer (GC probe)" do
    root = Node.new("root")
    200.times do |i|
      root.add_child(Node.new("c#{i}"))
    end

    sink = [] of Node
    201.times { sink << root }
    sink.clear

    n = 1000
    10.times { Node.collect_dirty(root, sink) } # warmup

    # Prime window (diagnostic, not asserted)
    delta_prime = 0_i64
    GC.collect
    GC.disable
    begin
      before = GC.stats.bytes_since_gc
      n.times { Node.collect_dirty(root, sink) }
      after = GC.stats.bytes_since_gc
      delta_prime = after.to_i64 - before.to_i64
    ensure
      GC.enable
    end

    # Calib window (diagnostic, not asserted): N empty iterations with observable side effect
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

    # 3 work windows; criterion on worst (max) window. First failure: retry whole
    # 3-window set once (GC noise denoising; per-call alloc still fails A every time).
    retried = false
    attempt = 1
    loop do
      work = [] of Int64
      3.times do
        GC.collect
        GC.disable
        begin
          before = GC.stats.bytes_since_gc
          n.times { Node.collect_dirty(root, sink) }
          after = GC.stats.bytes_since_gc
          work << (after.to_i64 - before.to_i64)
        ensure
          GC.enable
        end
      end
      delta_work = work.max
      seq = "[#{work[0]},#{work[1]},#{work[2]}]"
      puts "zero-alloc probe(core_node): delta_prime=#{delta_prime} delta_calib=#{delta_calib} delta_work=#{delta_work} N=#{n} windows=#{seq} retried=#{retried} attempt=#{attempt}"
      break if delta_work < n && delta_work <= 256
      if attempt >= 2
        fail "zero-alloc probe: delta_work=#{delta_work} delta_calib=#{delta_calib} delta_prime=#{delta_prime} N=#{n} windows=#{seq} retried=#{retried} attempt=#{attempt}"
      end
      retried = true
      attempt = 2
    end
  end
end
