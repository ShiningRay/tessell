# M1-WP5 稳态零分配：Node.collect_dirty 复用调用方缓冲（spec）。
#
# 覆盖：
#   1) collect_dirty 与 dirty_subtree 结果集合一致（root 自脏 / 深树混合脏 / 全净空）；
#   2) sink 复用后不残留旧元素；
#   3) 两次调用容量不增长：Crystal 1.22 无公开 Array#capacity，
#      用「先填满预分配槽位再 clear（clear 保留容量）→ 重复调用 size 不超、重复调用不抛」
#      + GC 零分配探针兜底（bytes_since_gc 差值 0），不以 capacity 字段伪造。

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
    # Layout 自 nodes[3] 向上传播 root/n1/n2/n3 共 4 个 + nodes[7] CompositeOnly 1 个 = 5
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
    # 预分配槽位（Array 无公开 reserve/容量字段）：填满后 clear，容量保留。
    201.times { sink << root }
    sink.clear

    5.times do
      Node.collect_dirty(root, sink)
      sink.size.should be <= 201
    end
    sink.should be_empty
  end

  it "allocates zero bytes across repeated calls with a pre-sized buffer (GC probe)" do
    root = Node.new("root")
    200.times do |i|
      root.add_child(Node.new("c#{i}"))
    end

    sink = [] of Node
    201.times { sink << root }
    sink.clear

    10.times { Node.collect_dirty(root, sink) } # warmup
    GC.collect
    GC.disable
    before = GC.stats.bytes_since_gc
    1000.times { Node.collect_dirty(root, sink) }
    after = GC.stats.bytes_since_gc
    GC.enable

    (after - before).should eq 0
  end
end
