require "./spec_helper"
require "../src/tessell/a11y/tree"

include Tessell

def a11y_rect(x, y, w, h)
  Rect.new(x.to_f32, y.to_f32, w.to_f32, h.to_f32)
end

describe "Tessell::A11y (M2-WP5)" do
  it "J1: empty tree -> sink empty" do
    builder = A11y::Builder.new
    sink = [] of A11y::Node
    # prefill to ensure clear happens
    sink << A11y::Node.new(1_u64, A11y::Role::Group, "x", "", a11y_rect(0, 0, 0, 0), false, false, true, 0, 0)
    builder.build(nil, sink)
    sink.size.should eq 0
  end

  it "J2: single node -> 1 node, index_in_parent==0, children_count==0" do
    root = Node.new("root", a11y_rect(1, 2, 3, 4))
    builder = A11y::Builder.new
    sink = [] of A11y::Node
    builder.build(root, sink)
    sink.size.should eq 1
    n = sink[0]
    n.index_in_parent.should eq 0
    n.children_count.should eq 0
    n.role.should eq A11y::Role::Group
  end

  it "J3: focus source of truth - only focused node true, blur clears all" do
    root = Node.new("root", a11y_rect(0, 0, 100, 100))
    a = Node.new("a", a11y_rect(0, 0, 10, 10))
    b = Node.new("b", a11y_rect(0, 0, 10, 10))
    root.add_child(a)
    root.add_child(b)
    fm = Input::FocusManager.new
    builder = A11y::Builder.new(fm)
    sink = [] of A11y::Node

    fm.focus(a)
    builder.build(root, sink)
    focused_nodes = sink.select(&.focused)
    focused_nodes.size.should eq 1
    focused_nodes[0].id.should eq a.object_id.to_u64
    sink.find { |n| n.id == b.object_id.to_u64 }.not_nil!.focused.should be_false

    fm.blur
    builder.build(root, sink)
    sink.any?(&.focused).should be_false
  end

  it "J4: focused node removed/detached -> rebuild does not crash and has no residual focused" do
    root = Node.new("root", a11y_rect(0, 0, 100, 100))
    a = Node.new("a", a11y_rect(0, 0, 10, 10))
    b = Node.new("b", a11y_rect(0, 0, 10, 10))
    root.add_child(a)
    root.add_child(b)
    fm = Input::FocusManager.new
    fm.focus(a)
    a.detach
    # detach does not auto-clear focus; rebuilt tree must not include a and must not mark it focused
    builder = A11y::Builder.new(fm)
    sink = [] of A11y::Node
    builder.build(root, sink)
    sink.map(&.id).includes?(a.object_id.to_u64).should be_false
    sink.any?(&.focused).should be_false

    # remove_child case
    root2 = Node.new("root2", a11y_rect(0, 0, 100, 100))
    c = Node.new("c", a11y_rect(0, 0, 10, 10))
    root2.add_child(c)
    fm2 = Input::FocusManager.new
    fm2.focus(c)
    root2.remove_child(c)
    sink2 = [] of A11y::Node
    A11y::Builder.new(fm2).build(root2, sink2)
    sink2.map(&.id).includes?(c.object_id.to_u64).should be_false
    sink2.any?(&.focused).should be_false
  end

  it "J5: 10000-row VirtualWindow -> node count <= 32 (hard limit)" do
    fetch = ->(i : Int32) { nil }
    vl = Widgets::VirtualList.new(10_000, 20, 600, fetch, 800)
    sink = [] of A11y::Node
    vw = A11y::VirtualWindow.new
    vw.emit(vl, sink)
    sink.size.should be <= 32
    sink.size.should be >= 1
    container = sink[0]
    container.role.should eq A11y::Role::List
    container.children_count.should eq 10_000
    container.scroll_offset.should eq 0
    # visible items count matches visible range
    vr = vl.visible_range
    visible_count = vr[:last] >= vr[:first] ? (vr[:last] - vr[:first] + 1) : 0
    sink.size.should eq (1 + visible_count)
  end

  it "J5b: VirtualWindow after scroll still <= 32 nodes and exposes scroll_offset/children_count" do
    fetch = ->(i : Int32) { nil }
    vl = Widgets::VirtualList.new(10_000, 20, 600, fetch, 800)
    vl.scroll_to(12_340)
    sink = [] of A11y::Node
    vw = A11y::VirtualWindow.new
    vw.emit(vl, sink)
    sink.size.should be <= 32
    container = sink[0]
    container.children_count.should eq 10_000
    container.scroll_offset.should eq vl.scroll_y
    vr = vl.visible_range
    visible_count = vr[:last] >= vr[:first] ? (vr[:last] - vr[:first] + 1) : 0
    sink.size.should eq (1 + visible_count)
  end

  it "J6: name/value source via set_meta; unset name is empty string not \"(null)\"" do
    root = Node.new("root", a11y_rect(0, 0, 10, 10))
    builder = A11y::Builder.new
    nid = root.object_id.to_u64
    builder.set_meta(nid, A11y::Role::Button, "按钮", "v1", true, true)
    sink = [] of A11y::Node
    builder.build(root, sink)
    sink[0].name.should eq "按钮"
    sink[0].value.should eq "v1"
    sink[0].role.should eq A11y::Role::Button
    sink[0].focusable.should be_true

    root2 = Node.new("root2", a11y_rect(0, 0, 10, 10))
    builder2 = A11y::Builder.new
    sink2 = [] of A11y::Node
    builder2.build(root2, sink2)
    sink2[0].name.should eq ""
    sink2[0].name.should_not eq "(null)"
  end

  it "J7: traversal order stable (DFS preorder), same id sequence on repeated build" do
    root = Node.new("root", a11y_rect(0, 0, 100, 100))
    a = Node.new("a", a11y_rect(0, 0, 10, 10))
    b = Node.new("b", a11y_rect(0, 0, 10, 10))
    c = Node.new("c", a11y_rect(0, 0, 10, 10))
    root.add_child(a)
    a.add_child(b)
    root.add_child(c)
    builder = A11y::Builder.new
    sink1 = [] of A11y::Node
    sink2 = [] of A11y::Node
    builder.build(root, sink1)
    builder.build(root, sink2)
    ids1 = sink1.map(&.id)
    ids2 = sink2.map(&.id)
    ids1.should eq ids2
    expected = [root.object_id.to_u64, a.object_id.to_u64, b.object_id.to_u64, c.object_id.to_u64]
    ids1.should eq expected
  end

  it "J8: bounds fields equal node.bounds" do
    r = a11y_rect(5.5, 6.25, 100.0, 200.5)
    root = Node.new("root", r)
    builder = A11y::Builder.new
    sink = [] of A11y::Node
    builder.build(root, sink)
    b = sink[0].bounds
    b.origin.x.should eq r.origin.x
    b.origin.y.should eq r.origin.y
    b.size.width.should eq r.size.width
    b.size.height.should eq r.size.height
  end

  it "J9: sink reuse - buffer unchanged after 1000 builds and steady-state zero-alloc" do
    root = Node.new("root", a11y_rect(0, 0, 100, 100))
    a = Node.new("a", a11y_rect(0, 0, 10, 10))
    b = Node.new("b", a11y_rect(0, 0, 10, 10))
    c = Node.new("c", a11y_rect(0, 0, 10, 10))
    root.add_child(a)
    root.add_child(b)
    root.add_child(c)
    builder = A11y::Builder.new
    sink = [] of A11y::Node
    # warm to steady capacity/buffer
    10.times { builder.build(root, sink) }
    cap_ptr = sink.to_unsafe
    1000.times { builder.build(root, sink) }
    sink.to_unsafe.should eq cap_ptr

    # steady-state zero-alloc probe (A/B, 3 windows max, retry <= 1)
    n = 1000
    50.times { builder.build(root, sink) }

    delta_prime = 0_i64
    GC.collect
    GC.disable
    begin
      before = GC.stats.bytes_since_gc
      i = 0
      while i < n
        builder.build(root, sink)
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
            builder.build(root, sink)
            i += 1
          end
          seq << (GC.stats.bytes_since_gc.to_i64 - before.to_i64)
        ensure
          GC.enable
        end
      end
      delta_work = seq.max
      puts "zero-alloc probe(a11y_build): delta_prime=#{delta_prime} delta_calib=#{delta_calib} delta_work=#{delta_work} N=#{n} windows=[#{seq[0]},#{seq[1]},#{seq[2]}] retried=#{retried} attempt=#{attempt}"
      break if delta_work < n && delta_work <= 256
      if attempt >= 2
        fail "zero-alloc probe(a11y_build): delta_work=#{delta_work} delta_calib=#{delta_calib} delta_prime=#{delta_prime} N=#{n} windows=[#{seq[0]},#{seq[1]},#{seq[2]}] retried=#{retried} attempt=#{attempt}"
      end
      retried = true
      attempt = 2
    end
    (delta_work < n && delta_work <= 256).should be_true
  end
end