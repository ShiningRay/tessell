require "./spec_helper"
require "../src/tessell/ui/key"
require "../src/tessell/ui/builder"
require "../src/tessell/a11y/tree"
require "spec"

include Tessell
include Tessell::UI

# D5 (M4-WP1 S3): the a11y mirror stays in sync with the retained Node tree.
# UI.apply writes A11y::Builder meta for new/changed declarations and drops it
# for removed ones; UI.a11y_emit renders the mirror into a caller-provided sink
# without materializing virtual rows.
describe "UI a11y sync" do
  it "apply writes meta matching the Decl a11y fields" do
    root = Node.new("root", Rect.new(0.0_f32, 0.0_f32, 100.0_f32, 100.0_f32))
    pool = Pool.new
    a11y = A11y::Builder.new
    k = UiKey.root.child(1_u64)
    buf = [] of Decl
    16.times { buf << Decl.new(UiKey.root, UiKey.root, DeclKind::Node) }
    buf.clear
    stack = [] of UiKey
    8.times { stack << UiKey.root }
    stack.clear
    b = Builder.new(buf, stack)
    UI.build(UiKey.root, b) do |x|
      x.text(k, "hi", Rect.new(0.0_f32, 0.0_f32, 40.0_f32, 20.0_f32),
        a11y_role: A11y::Role::Text, a11y_name: "greeting",
        a11y_value: "hi", a11y_focusable: true, a11y_enabled: false)
    end
    UI.apply(buf, root, pool, a11y)
    node = pool.map[k].not_nil!
    m = a11y.meta_for(node.object_id.to_u64).not_nil!
    m.role.should eq A11y::Role::Text
    m.name.should eq "greeting"
    m.value.should eq "hi"
    m.focusable.should be_true
    m.enabled.should be_false
  end

  it "text change updates the a11y value" do
    root = Node.new("root", Rect.new(0.0_f32, 0.0_f32, 100.0_f32, 100.0_f32))
    pool = Pool.new
    a11y = A11y::Builder.new
    k = UiKey.root.child(1_u64)
    buf = [] of Decl
    stack = [] of UiKey
    b = Builder.new(buf, stack)
    rect = Rect.new(0.0_f32, 0.0_f32, 40.0_f32, 20.0_f32)
    UI.build(UiKey.root, b) do |x|
      x.text(k, "v1", rect, a11y_role: A11y::Role::Text, a11y_value: "v1")
    end
    UI.apply(buf, root, pool, a11y)
    UI.build(UiKey.root, b) do |x|
      x.text(k, "v2", rect, a11y_role: A11y::Role::Text, a11y_value: "v2")
    end
    UI.apply(buf, root, pool, a11y)
    m = a11y.meta_for(pool.map[k].not_nil!.object_id.to_u64).not_nil!
    m.value.should eq "v2"
  end

  it "removed node has its a11y meta deleted" do
    root = Node.new("root", Rect.new(0.0_f32, 0.0_f32, 100.0_f32, 100.0_f32))
    pool = Pool.new
    a11y = A11y::Builder.new
    k = UiKey.root.child(1_u64)
    buf = [] of Decl
    stack = [] of UiKey
    b = Builder.new(buf, stack)
    rect = Rect.new(0.0_f32, 0.0_f32, 40.0_f32, 20.0_f32)
    UI.build(UiKey.root, b) do |x|
      x.node(k, rect, a11y_role: A11y::Role::Button, a11y_name: "btn")
    end
    UI.apply(buf, root, pool, a11y)
    id = pool.map[k].not_nil!.object_id.to_u64
    a11y.meta_for(id).should_not be_nil
    UI.build(UiKey.root, b) { |x| }
    UI.apply(buf, root, pool, a11y)
    a11y.meta_for(id).should be_nil
  end

  it "a11y_emit count and bounds match the Node tree" do
    root = Node.new("root", Rect.new(0.0_f32, 0.0_f32, 100.0_f32, 100.0_f32))
    pool = Pool.new
    a11y = A11y::Builder.new
    k1 = UiKey.root.child(1_u64)
    k2 = UiKey.root.child(2_u64)
    buf = [] of Decl
    stack = [] of UiKey
    b = Builder.new(buf, stack)
    r1 = Rect.new(0.0_f32, 0.0_f32, 10.0_f32, 10.0_f32)
    r2 = Rect.new(0.0_f32, 10.0_f32, 10.0_f32, 10.0_f32)
    UI.build(UiKey.root, b) do |x|
      x.node(k1, r1)
      x.node(k2, r2)
    end
    UI.apply(buf, root, pool, a11y)
    sink = [] of A11y::Node
    n = UI.a11y_emit(root, a11y, sink)
    n.should eq 3
    sink.size.should eq 3
    sink[0].bounds.should eq root.bounds
    sink[0].children_count.should eq 2
    sink[1].bounds.should eq pool.map[k1].not_nil!.bounds
    sink[1].index_in_parent.should eq 0
    sink[2].bounds.should eq pool.map[k2].not_nil!.bounds
    sink[2].index_in_parent.should eq 1
  end

  it "focus change is reflected live in the emitted focused flag" do
    root = Node.new("root", Rect.new(0.0_f32, 0.0_f32, 100.0_f32, 100.0_f32))
    pool = Pool.new
    fm = Input::FocusManager.new
    a11y = A11y::Builder.new(fm)
    k = UiKey.root.child(1_u64)
    buf = [] of Decl
    stack = [] of UiKey
    b = Builder.new(buf, stack)
    UI.build(UiKey.root, b) do |x|
      x.node(k, Rect.new(0.0_f32, 0.0_f32, 10.0_f32, 10.0_f32),
        a11y_role: A11y::Role::Button, a11y_name: "btn", a11y_focusable: true)
    end
    UI.apply(buf, root, pool, a11y)
    node = pool.map[k].not_nil!
    sink = [] of A11y::Node
    UI.a11y_emit(root, a11y, sink)
    sink[1].focused.should be_false
    fm.focus(node)
    UI.a11y_emit(root, a11y, sink)
    sink[1].focused.should be_true
    fm.blur
    UI.a11y_emit(root, a11y, sink)
    sink[1].focused.should be_false
  end

  it "virtual list emits only the visible window (10k rows never materialized)" do
    rows = 10_000
    fetch = ->(_i : Int32) { nil }
    vl = Widgets::VirtualList.new(rows, 20, 600, fetch, 800)
    root = Node.new("root", Rect.new(0.0_f32, 0.0_f32, 100.0_f32, 100.0_f32))
    container = Node.new("list", Rect.new(0.0_f32, 0.0_f32, 800.0_f32, 600.0_f32))
    root.add_child(container)
    a11y = A11y::Builder.new
    a11y.set_meta(container.object_id.to_u64, A11y::Role::List, "rows")
    sink = [] of A11y::Node
    n = UI.a11y_emit(root, a11y, sink, vl, container)
    # root + container + visible items only (10k rows never materialized)
    n.should eq 2 + (vl.visible_last - vl.visible_first + 1)
    sink[0].role.should eq A11y::Role::Group
    sink[1].role.should eq A11y::Role::List
    sink[1].children_count.should eq rows
    sink[1].scroll_offset.should eq vl.scroll_y
    sink[2].role.should eq A11y::Role::ListItem
    n.should be < 100
  end

  it "steady state is zero-alloc (A delta<N, B <=256, 3 windows max)" do
    root = Node.new("root", Rect.new(0.0_f32, 0.0_f32, 100.0_f32, 100.0_f32))
    pool = Pool.new
    a11y = A11y::Builder.new
    k1 = UiKey.root.child(1_u64)
    rect = Rect.new(0.0_f32, 0.0_f32, 10.0_f32, 10.0_f32)
    buf = [] of Decl
    16.times { buf << Decl.new(UiKey.root, UiKey.root, DeclKind::Node) }
    buf.clear
    stack = [] of UiKey
    8.times { stack << UiKey.root }
    stack.clear
    b = Builder.new(buf, stack)
    sink = [] of A11y::Node
    dsink = [] of Node

    UI.build(UiKey.root, b) do |x|
      x.text(k1, "hi", rect, a11y_role: A11y::Role::Text,
        a11y_name: "g", a11y_value: "hi", a11y_focusable: true)
    end
    UI.apply(buf, root, pool, a11y)
    Node.collect_dirty(root, dsink)
    UI.consume(dsink)
    UI.a11y_emit(root, a11y, sink)

    n = 1000
    10.times do
      buf.clear
      UI.build(UiKey.root, b) do |x|
        x.text(k1, "hi", rect, a11y_role: A11y::Role::Text,
          a11y_name: "g", a11y_value: "hi", a11y_focusable: true)
      end
      UI.apply(buf, root, pool, a11y)
      Node.collect_dirty(root, dsink)
      UI.consume(dsink)
      UI.a11y_emit(root, a11y, sink)
    end

    delta_prime = 0_i64
    GC.collect
    GC.disable
    begin
      before = GC.stats.bytes_since_gc
      n.times do
        buf.clear
        UI.build(UiKey.root, b) do |x|
          x.text(k1, "hi", rect, a11y_role: A11y::Role::Text,
            a11y_name: "g", a11y_value: "hi", a11y_focusable: true)
        end
        UI.apply(buf, root, pool, a11y)
        Node.collect_dirty(root, dsink)
        UI.consume(dsink)
        UI.a11y_emit(root, a11y, sink)
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
            UI.build(UiKey.root, b) do |x|
              x.text(k1, "hi", rect, a11y_role: A11y::Role::Text,
                a11y_name: "g", a11y_value: "hi", a11y_focusable: true)
            end
            UI.apply(buf, root, pool, a11y)
            UI.a11y_emit(root, a11y, sink)
            Node.collect_dirty(root, dsink)
            UI.consume(dsink)
          end
          after = GC.stats.bytes_since_gc
          work << (after.to_i64 - before.to_i64)
        ensure
          GC.enable
        end
      end
      delta_work = work.max
      seq = "[#{work[0]},#{work[1]},#{work[2]}]"
      puts "zero-alloc probe(ui_a11y): delta_prime=#{delta_prime} delta_calib=#{delta_calib} delta_work=#{delta_work} N=#{n} windows=#{seq} retried=#{retried} attempt=#{attempt}"
      break if delta_work < n && delta_work <= 256
      if attempt >= 2
        fail "zero-alloc probe: delta_work=#{delta_work} delta_calib=#{delta_calib} delta_prime=#{delta_prime} N=#{n} windows=#{seq} retried=#{retried} attempt=#{attempt}"
      end
      retried = true
      attempt = 2
    end
  end
end
