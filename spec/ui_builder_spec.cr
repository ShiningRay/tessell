require "./spec_helper"
require "../src/tessell/ui/key"
require "../src/tessell/ui/builder"
require "spec"

include Tessell
include Tessell::UI

describe "UiKey" do
  it "root is stable" do
    UiKey.root.should eq UiKey.root
  end

  it "derives unique child keys" do
    a = UiKey.root.child(1_u64)
    b = UiKey.root.child(2_u64)
    a.should_not eq b
    UiKey.root.child(1_u64).should eq a
  end

  it "different parents do not collide" do
    k1 = UiKey.root.child(1_u64).child(2_u64)
    k2 = UiKey.root.child(2_u64).child(1_u64)
    k1.should_not eq k2
  end
end

describe "Builder" do
  it "emits decls into caller buffer" do
    buf = [] of Decl
    16.times { buf << Decl.new(UiKey.root, UiKey.root, DeclKind::Node) }
    buf.clear
    stack = [] of UiKey
    8.times { stack << UiKey.root }
    stack.clear
    b = Builder.new(buf, stack)
    UI.build(UiKey.root, b) do |x|
      x.column(UiKey.root.child(1_u64)) do |c|
        c.text(UiKey.root.child(1_u64).child(2_u64), "hi")
      end
    end
    buf.size.should eq 2
    buf[0].key.should eq UiKey.root.child(1_u64)
    buf[1].parent.should eq UiKey.root.child(1_u64)
  end
end

describe "UI.apply reuse" do
  it "idempotent: full frame leaves no dirty after consume (same input)" do
    root = Node.new("root", Rect.new(0.0_f32, 0.0_f32, 100.0_f32, 100.0_f32))
    pool = Pool.new
    k1 = UiKey.root.child(1_u64)
    buf = [] of Decl
    16.times { buf << Decl.new(UiKey.root, UiKey.root, DeclKind::Node) }
    buf.clear
    stack = [] of UiKey
    8.times { stack << UiKey.root }
    stack.clear
    b = Builder.new(buf, stack)
    sink = [] of Node

    UI.build(UiKey.root, b) { |x| x.node(k1, Rect.new(0.0_f32, 0.0_f32, 10.0_f32, 10.0_f32)) }
    UI.apply(buf, root, pool)
    Node.collect_dirty(root, sink)
    UI.consume(sink)

    buf.clear
    UI.build(UiKey.root, b) { |x| x.node(k1, Rect.new(0.0_f32, 0.0_f32, 10.0_f32, 10.0_f32)) }
    UI.apply(buf, root, pool)
    Node.collect_dirty(root, sink)
    sink.should be_empty
  end

  it "changing one leaf dirties only that leaf plus parent chain" do
    root = Node.new("root", Rect.new(0.0_f32, 0.0_f32, 100.0_f32, 100.0_f32))
    pool = Pool.new
    k1 = UiKey.root.child(1_u64)
    kleaf = k1.child(2_u64)
    buf = [] of Decl
    16.times { buf << Decl.new(UiKey.root, UiKey.root, DeclKind::Node) }
    stack = [] of UiKey
    8.times { stack << UiKey.root }
    stack.clear
    b = Builder.new(buf, stack)
    sink = [] of Node

    buf.clear
    UI.build(UiKey.root, b) do |x|
      x.column(k1, Rect.new(0.0_f32, 0.0_f32, 50.0_f32, 50.0_f32)) do |c|
        c.node(kleaf, Rect.new(0.0_f32, 0.0_f32, 10.0_f32, 10.0_f32))
      end
    end
    UI.apply(buf, root, pool)
    Node.collect_dirty(root, sink)
    UI.consume(sink)

    buf.clear
    UI.build(UiKey.root, b) do |x|
      x.column(k1, Rect.new(0.0_f32, 0.0_f32, 50.0_f32, 50.0_f32)) do |c|
        c.node(kleaf, Rect.new(5.0_f32, 5.0_f32, 10.0_f32, 10.0_f32))
      end
    end
    UI.apply(buf, root, pool)
    Node.collect_dirty(root, sink)
    sink.size.should eq 3
  end

  it "node_count stays stable across identical frames" do
    root = Node.new("root", Rect.new(0.0_f32, 0.0_f32, 100.0_f32, 100.0_f32))
    pool = Pool.new
    k1 = UiKey.root.child(1_u64)
    buf = [] of Decl
    16.times { buf << Decl.new(UiKey.root, UiKey.root, DeclKind::Node) }
    stack = [] of UiKey
    8.times { stack << UiKey.root }
    stack.clear
    b = Builder.new(buf, stack)
    sink = [] of Node

    UI.build(UiKey.root, b) { |x| x.node(k1, Rect.new(0.0_f32, 0.0_f32, 10.0_f32, 10.0_f32)) }
    UI.apply(buf, root, pool)
    Node.collect_dirty(root, sink)
    UI.consume(sink)
    before = 1 + root.children.size

    buf.clear
    UI.build(UiKey.root, b) { |x| x.node(k1, Rect.new(0.0_f32, 0.0_f32, 10.0_f32, 10.0_f32)) }
    UI.apply(buf, root, pool)
    Node.collect_dirty(root, sink)
    UI.consume(sink)
    after = 1 + root.children.size
    after.should eq before
  end

  it "recycles and reuses a removed subtree node" do
    root = Node.new("root", Rect.new(0.0_f32, 0.0_f32, 100.0_f32, 100.0_f32))
    pool = Pool.new
    k1 = UiKey.root.child(1_u64)
    kleaf = k1.child(2_u64)
    buf = [] of Decl
    16.times { buf << Decl.new(UiKey.root, UiKey.root, DeclKind::Node) }
    stack = [] of UiKey
    8.times { stack << UiKey.root }
    stack.clear
    b = Builder.new(buf, stack)
    sink = [] of Node

    buf.clear
    UI.build(UiKey.root, b) do |x|
      x.column(k1, Rect.new(0.0_f32, 0.0_f32, 50.0_f32, 50.0_f32)) do |c|
        c.node(kleaf, Rect.new(0.0_f32, 0.0_f32, 10.0_f32, 10.0_f32))
      end
    end
    UI.apply(buf, root, pool)
    Node.collect_dirty(root, sink)
    UI.consume(sink)
    node_before = pool.map[kleaf]

    buf.clear
    UI.build(UiKey.root, b) do |x|
      x.column(k1, Rect.new(0.0_f32, 0.0_f32, 50.0_f32, 50.0_f32))
    end
    UI.apply(buf, root, pool)
    Node.collect_dirty(root, sink)
    UI.consume(sink)

    buf.clear
    UI.build(UiKey.root, b) do |x|
      x.column(k1, Rect.new(0.0_f32, 0.0_f32, 50.0_f32, 50.0_f32)) do |c|
        c.node(kleaf, Rect.new(0.0_f32, 0.0_f32, 10.0_f32, 10.0_f32))
      end
    end
    UI.apply(buf, root, pool)
    Node.collect_dirty(root, sink)
    UI.consume(sink)
    node_after = pool.map[kleaf]
    node_after.should be(node_before)
  end

  it "dirty set is DFS preorder stable" do
    root = Node.new("root", Rect.new(0.0_f32, 0.0_f32, 100.0_f32, 100.0_f32))
    pool = Pool.new
    k1 = UiKey.root.child(1_u64)
    kleaf = k1.child(2_u64)
    buf = [] of Decl
    16.times { buf << Decl.new(UiKey.root, UiKey.root, DeclKind::Node) }
    stack = [] of UiKey
    8.times { stack << UiKey.root }
    stack.clear
    b = Builder.new(buf, stack)
    sink = [] of Node

    buf.clear
    UI.build(UiKey.root, b) do |x|
      x.column(k1, Rect.new(0.0_f32, 0.0_f32, 50.0_f32, 50.0_f32)) do |c|
        c.node(kleaf, Rect.new(0.0_f32, 0.0_f32, 10.0_f32, 10.0_f32))
      end
    end
    UI.apply(buf, root, pool)
    Node.collect_dirty(root, sink)
    UI.consume(sink)

    buf.clear
    UI.build(UiKey.root, b) do |x|
      x.column(k1, Rect.new(0.0_f32, 0.0_f32, 50.0_f32, 50.0_f32)) do |c|
        c.node(kleaf, Rect.new(1.0_f32, 1.0_f32, 10.0_f32, 10.0_f32))
      end
    end
    UI.apply(buf, root, pool)
    Node.collect_dirty(root, sink)
    sink.map(&.id).should eq [root.id, pool.map[k1].id, pool.map[kleaf].id]
  end

  it "preserves external dirty mark across no-change apply" do
    root = Node.new("root", Rect.new(0.0_f32, 0.0_f32, 100.0_f32, 100.0_f32))
    pool = Pool.new
    k1 = UiKey.root.child(1_u64)
    buf = [] of Decl
    16.times { buf << Decl.new(UiKey.root, UiKey.root, DeclKind::Node) }
    stack = [] of UiKey
    8.times { stack << UiKey.root }
    stack.clear
    b = Builder.new(buf, stack)
    sink = [] of Node

    UI.build(UiKey.root, b) { |x| x.node(k1, Rect.new(0.0_f32, 0.0_f32, 10.0_f32, 10.0_f32)) }
    UI.apply(buf, root, pool)
    Node.collect_dirty(root, sink)
    UI.consume(sink)

    leaf = pool.map[k1]
    leaf.mark_dirty(Invalidation::Paint)
    before = leaf.dirty?

    buf.clear
    UI.build(UiKey.root, b) { |x| x.node(k1, Rect.new(0.0_f32, 0.0_f32, 10.0_f32, 10.0_f32)) }
    UI.apply(buf, root, pool)
    after = leaf.dirty?
    puts "P1_EXTERNAL dirty_before_apply=#{before} dirty_after_apply=#{after.inspect} swallowed=#{after.nil?}"
    after.should eq Invalidation::Paint

    Node.collect_dirty(root, sink)
    UI.consume(sink)
    leaf.dirty?.should be_nil
  end

  it "consume clears only passed nodes, others remain dirty" do
    root = Node.new("root", Rect.new(0.0_f32, 0.0_f32, 100.0_f32, 100.0_f32))
    pool = Pool.new
    k1 = UiKey.root.child(1_u64)
    k2 = UiKey.root.child(2_u64)
    buf = [] of Decl
    16.times { buf << Decl.new(UiKey.root, UiKey.root, DeclKind::Node) }
    stack = [] of UiKey
    8.times { stack << UiKey.root }
    stack.clear
    b = Builder.new(buf, stack)
    sink = [] of Node

    buf.clear
    UI.build(UiKey.root, b) do |x|
      x.node(k1, Rect.new(0.0_f32, 0.0_f32, 10.0_f32, 10.0_f32))
      x.node(k2, Rect.new(20.0_f32, 0.0_f32, 10.0_f32, 10.0_f32))
    end
    UI.apply(buf, root, pool)
    Node.collect_dirty(root, sink)
    UI.consume(sink)

    n1 = pool.map[k1]
    n2 = pool.map[k2]
    n1.mark_dirty(Invalidation::Paint)
    n2.mark_dirty(Invalidation::Paint)

    partial = [] of Node
    partial << n1
    UI.consume(partial)

    n1.dirty?.should be_nil
    n2.dirty?.should eq Invalidation::Paint
  end
end

describe "UI.apply zero-alloc" do
  it "satisfies zero-alloc criterion on no-change frames (GC probe)" do
    root = Node.new("root", Rect.new(0.0_f32, 0.0_f32, 100.0_f32, 100.0_f32))
    pool = Pool.new
    k1 = UiKey.root.child(1_u64)
    buf = [] of Decl
    64.times { buf << Decl.new(UiKey.root, UiKey.root, DeclKind::Node) }
    buf.clear
    stack = [] of UiKey
    16.times { stack << UiKey.root }
    stack.clear
    b = Builder.new(buf, stack)
    sink = [] of Node

    UI.build(UiKey.root, b) { |x| x.node(k1, Rect.new(0.0_f32, 0.0_f32, 10.0_f32, 10.0_f32)) }
    UI.apply(buf, root, pool)
    Node.collect_dirty(root, sink)
    UI.consume(sink)

    n = 1000
    10.times do
      buf.clear
      UI.build(UiKey.root, b) { |x| x.node(k1, Rect.new(0.0_f32, 0.0_f32, 10.0_f32, 10.0_f32)) }
      UI.apply(buf, root, pool)
      Node.collect_dirty(root, sink)
      UI.consume(sink)
    end

    delta_prime = 0_i64
    GC.collect
    GC.disable
    begin
      before = GC.stats.bytes_since_gc
      n.times do
        buf.clear
        UI.build(UiKey.root, b) { |x| x.node(k1, Rect.new(0.0_f32, 0.0_f32, 10.0_f32, 10.0_f32)) }
        UI.apply(buf, root, pool)
        Node.collect_dirty(root, sink)
        UI.consume(sink)
      end
      after = GC.stats.bytes_since_gc
      delta_prime = after.to_i64 - before.to_i64
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
      after = GC.stats.bytes_since_gc
      delta_calib = after.to_i64 - before.to_i64
    ensure
      GC.enable
    end
    calib_sink.should be >= 0_i64

    retried = false
    attempt = 1
    loop do
      work = [] of Int64
      3.times do
        GC.collect
        GC.disable
        begin
          before = GC.stats.bytes_since_gc
          n.times do
            buf.clear
            UI.build(UiKey.root, b) { |x| x.node(k1, Rect.new(0.0_f32, 0.0_f32, 10.0_f32, 10.0_f32)) }
            UI.apply(buf, root, pool)
            Node.collect_dirty(root, sink)
            UI.consume(sink)
          end
          after = GC.stats.bytes_since_gc
          work << (after.to_i64 - before.to_i64)
        ensure
          GC.enable
        end
      end
      delta_work = work.max
      seq = "[#{work[0]},#{work[1]},#{work[2]}]"
      puts "zero-alloc probe(ui_apply): delta_prime=#{delta_prime} delta_calib=#{delta_calib} delta_work=#{delta_work} N=#{n} windows=#{seq} retried=#{retried} attempt=#{attempt}"
      break if delta_work < n && delta_work <= 256
      if attempt >= 2
        fail "zero-alloc probe: delta_work=#{delta_work} delta_calib=#{delta_calib} delta_prime=#{delta_prime} N=#{n} windows=#{seq} retried=#{retried} attempt=#{attempt}"
      end
      retried = true
      attempt = 2
    end
  end
end

describe "UI.consume zero-alloc" do
  it "satisfies zero-alloc criterion on repeated consume (GC probe)" do
    root = Node.new("root", Rect.new(0.0_f32, 0.0_f32, 100.0_f32, 100.0_f32))
    pool = Pool.new
    k1 = UiKey.root.child(1_u64)
    buf = [] of Decl
    64.times { buf << Decl.new(UiKey.root, UiKey.root, DeclKind::Node) }
    buf.clear
    stack = [] of UiKey
    16.times { stack << UiKey.root }
    stack.clear
    b = Builder.new(buf, stack)
    sink = [] of Node

    UI.build(UiKey.root, b) { |x| x.node(k1, Rect.new(0.0_f32, 0.0_f32, 10.0_f32, 10.0_f32)) }
    UI.apply(buf, root, pool)
    Node.collect_dirty(root, sink)
    # keep sink populated pattern: mark nodes dirty again each iteration target? 
    # consume clears passed nodes; to measure consume itself we prepare a dirty set each time
    # but preparing (mark_dirty) is cheap and may allocate? mark_dirty is no-alloc.
    nodes_to_consume = [root, pool.map[k1]] of Node

    n = 1000
    10.times do
      nodes_to_consume.each { |nd| nd.mark_dirty(Invalidation::Paint) }
      UI.consume(nodes_to_consume)
    end

    delta_prime = 0_i64
    GC.collect
    GC.disable
    begin
      before = GC.stats.bytes_since_gc
      n.times do
        nodes_to_consume.each { |nd| nd.mark_dirty(Invalidation::Paint) }
        UI.consume(nodes_to_consume)
      end
      after = GC.stats.bytes_since_gc
      delta_prime = after.to_i64 - before.to_i64
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
      after = GC.stats.bytes_since_gc
      delta_calib = after.to_i64 - before.to_i64
    ensure
      GC.enable
    end
    calib_sink.should be >= 0_i64

    retried = false
    attempt = 1
    loop do
      work = [] of Int64
      3.times do
        GC.collect
        GC.disable
        begin
          before = GC.stats.bytes_since_gc
          n.times do
            nodes_to_consume.each { |nd| nd.mark_dirty(Invalidation::Paint) }
            UI.consume(nodes_to_consume)
          end
          after = GC.stats.bytes_since_gc
          work << (after.to_i64 - before.to_i64)
        ensure
          GC.enable
        end
      end
      delta_work = work.max
      seq = "[#{work[0]},#{work[1]},#{work[2]}]"
      puts "zero-alloc probe(ui_consume): delta_prime=#{delta_prime} delta_calib=#{delta_calib} delta_work=#{delta_work} N=#{n} windows=#{seq} retried=#{retried} attempt=#{attempt}"
      break if delta_work < n && delta_work <= 256
      if attempt >= 2
        fail "zero-alloc probe: delta_work=#{delta_work} delta_calib=#{delta_calib} delta_prime=#{delta_prime} N=#{n} windows=#{seq} retried=#{retried} attempt=#{attempt}"
      end
      retried = true
      attempt = 2
    end
  end
end

describe "Builder zero-alloc" do
  it "satisfies zero-alloc criterion on repeated builds (GC probe)" do
    buf = [] of Decl
    64.times { buf << Decl.new(UiKey.root, UiKey.root, DeclKind::Node) }
    buf.clear
    stack = [] of UiKey
    16.times { stack << UiKey.root }
    stack.clear
    b = Builder.new(buf, stack)
    k1 = UiKey.root.child(1_u64)

    n = 1000
    10.times do
      buf.clear
      UI.build(UiKey.root, b) { |x| x.node(k1, Rect.new(0.0_f32, 0.0_f32, 10.0_f32, 10.0_f32)) }
    end

    delta_prime = 0_i64
    GC.collect
    GC.disable
    begin
      before = GC.stats.bytes_since_gc
      n.times do
        buf.clear
        UI.build(UiKey.root, b) { |x| x.node(k1, Rect.new(0.0_f32, 0.0_f32, 10.0_f32, 10.0_f32)) }
      end
      after = GC.stats.bytes_since_gc
      delta_prime = after.to_i64 - before.to_i64
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
      after = GC.stats.bytes_since_gc
      delta_calib = after.to_i64 - before.to_i64
    ensure
      GC.enable
    end
    calib_sink.should be >= 0_i64

    retried = false
    attempt = 1
    loop do
      work = [] of Int64
      3.times do
        GC.collect
        GC.disable
        begin
          before = GC.stats.bytes_since_gc
          n.times do
            buf.clear
            UI.build(UiKey.root, b) { |x| x.node(k1, Rect.new(0.0_f32, 0.0_f32, 10.0_f32, 10.0_f32)) }
          end
          after = GC.stats.bytes_since_gc
          work << (after.to_i64 - before.to_i64)
        ensure
          GC.enable
        end
      end
      delta_work = work.max
      seq = "[#{work[0]},#{work[1]},#{work[2]}]"
      puts "zero-alloc probe(ui_builder): delta_prime=#{delta_prime} delta_calib=#{delta_calib} delta_work=#{delta_work} N=#{n} windows=#{seq} retried=#{retried} attempt=#{attempt}"
      break if delta_work < n && delta_work <= 256
      if attempt >= 2
        fail "zero-alloc probe: delta_work=#{delta_work} delta_calib=#{delta_calib} delta_prime=#{delta_prime} N=#{n} windows=#{seq} retried=#{retried} attempt=#{attempt}"
      end
      retried = true
      attempt = 2
    end
  end
end
