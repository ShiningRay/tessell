require "spec"
require "../src/tessell/core/node"

include Tessell

describe Tessell::Node do
  it "new node starts fully clean (all three flags false, dirty? nil)" do
    n = Node.new("a")
    n.dirty?.should be_nil
    n.layout_dirty?.should be_false
    n.paint_dirty?.should be_false
    n.composite_dirty?.should be_false
  end

  it "mark Layout dirties self + ancestor Layout chain only; siblings stay clean" do
    root = Node.new("root")
    mid = Node.new("mid")
    leaf = Node.new("leaf")
    sib = Node.new("sib")
    root.add_child(mid)
    mid.add_child(leaf)
    mid.add_child(sib)

    leaf.mark_dirty(Invalidation::Layout)

    leaf.layout_dirty?.should be_true
    mid.layout_dirty?.should be_true
    root.layout_dirty?.should be_true
    sib.layout_dirty?.should be_false
    sib.paint_dirty?.should be_false
    root.paint_dirty?.should be_false
    mid.paint_dirty?.should be_false
    leaf.paint_dirty?.should be_false
  end

  it "mark Paint does not mark ancestors Layout" do
    root = Node.new("root")
    child = Node.new("child")
    root.add_child(child)

    child.mark_dirty(Invalidation::Paint)

    child.paint_dirty?.should be_true
    child.layout_dirty?.should be_false
    root.layout_dirty?.should be_false
    root.paint_dirty?.should be_false
    root.composite_dirty?.should be_false
  end

  it "mark CompositeOnly produces no Layout/Paint dirt and does not propagate" do
    root = Node.new("root")
    child = Node.new("child")
    root.add_child(child)

    child.mark_dirty(Invalidation::CompositeOnly)

    child.composite_dirty?.should be_true
    child.layout_dirty?.should be_false
    child.paint_dirty?.should be_false
    root.dirty?.should be_nil
  end

  it "clean! clears all three levels level by level" do
    root = Node.new("root")
    child = Node.new("child")
    root.add_child(child)

    child.mark_dirty(Invalidation::Layout)
    root.mark_dirty(Invalidation::Paint)

    child.clean!
    child.dirty?.should be_nil
    root.clean!
    root.dirty?.should be_nil
  end

  it "repeated mark is idempotent (dirty_subtree count unchanged)" do
    root = Node.new("root")
    child = Node.new("child")
    root.add_child(child)

    child.mark_dirty(Invalidation::Layout)
    child.mark_dirty(Invalidation::Layout)
    child.mark_dirty(Invalidation::Layout)

    Node.dirty_subtree(root).size.should eq 2
    child.layout_dirty?.should be_true
  end

  it "deep tree (6 levels) propagates Layout to every ancestor only" do
    nodes = (0..5).map { |i| Node.new("n#{i}") }
    (0..4).each { |i| nodes[i].add_child(nodes[i + 1]) }

    nodes[5].mark_dirty(Invalidation::Layout)

    nodes.each do |n|
      n.layout_dirty?.should be_true
      n.paint_dirty?.should be_false
      n.composite_dirty?.should be_false
    end
  end

  it "dirty_subtree contains only dirty nodes" do
    root = Node.new("root")
    a = Node.new("a")
    b = Node.new("b")
    c = Node.new("c")
    root.add_child(a)
    root.add_child(b)
    b.add_child(c)

    a.mark_dirty(Invalidation::Paint)
    c.mark_dirty(Invalidation::CompositeOnly)

    ids = Node.dirty_subtree(root).map(&.id)
    ids.should contain("a")
    ids.should contain("c")
    ids.should_not contain("root")
    ids.should_not contain("b")
    ids.size.should eq 2
  end

  it "dirty? reports highest level Layout > Paint > CompositeOnly" do
    n = Node.new("n")

    n.mark_dirty(Invalidation::CompositeOnly)
    n.dirty?.should eq Invalidation::CompositeOnly

    n.mark_dirty(Invalidation::Paint)
    n.dirty?.should eq Invalidation::Paint

    n.mark_dirty(Invalidation::Layout)
    n.dirty?.should eq Invalidation::Layout
  end

  it "static clean tree yields empty dirty_subtree" do
    root = Node.new("root")
    root.add_child(Node.new("a"))
    root.children[0].add_child(Node.new("b"))

    Node.dirty_subtree(root).should be_empty
  end

  it "mark Layout on parent does not dirty children (upward only)" do
    root = Node.new("root")
    child = Node.new("child")
    root.add_child(child)

    root.mark_dirty(Invalidation::Layout)

    root.layout_dirty?.should be_true
    child.layout_dirty?.should be_false
    child.dirty?.should be_nil
  end

  it "bounds is stored and readable" do
    r = Rect.new(1.0_f32, 2.0_f32, 30.0_f32, 40.0_f32)
    n = Node.new("b", r)
    n.bounds.origin.x.should eq 1.0_f32
    n.bounds.origin.y.should eq 2.0_f32
    n.bounds.size.width.should eq 30.0_f32
    n.bounds.size.height.should eq 40.0_f32
  end

  it "mark Paint on one sibling leaves the other sibling untouched" do
    root = Node.new("root")
    a = Node.new("a")
    b = Node.new("b")
    root.add_child(a)
    root.add_child(b)

    a.mark_dirty(Invalidation::Paint)

    a.paint_dirty?.should be_true
    b.paint_dirty?.should be_false
    b.layout_dirty?.should be_false
    root.layout_dirty?.should be_false
  end
end
