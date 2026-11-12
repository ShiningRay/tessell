# M2-WP1 命中测试 spec：嵌套命中、重叠 z-order（后加子节点优先）、边界点、miss。

require "spec"
require "../src/tessell/geometry"
require "../src/tessell/core/node"
require "../src/tessell/input/hit_test"

include Tessell

def build_hit_tree : {Node, Node, Node, Node}
  root = Node.new("root", Rect.new(0.0_f32, 0.0_f32, 100.0_f32, 100.0_f32))
  mid = Node.new("mid", Rect.new(10.0_f32, 10.0_f32, 80.0_f32, 80.0_f32))
  leaf = Node.new("leaf", Rect.new(20.0_f32, 20.0_f32, 30.0_f32, 30.0_f32))
  sib = Node.new("sib", Rect.new(60.0_f32, 60.0_f32, 30.0_f32, 30.0_f32))
  root.add_child(mid)
  mid.add_child(leaf)
  mid.add_child(sib)
  {root, mid, leaf, sib}
end

describe "HitTest.deepest (M2-WP1)" do
  it "nested hit returns deepest leaf" do
    root, mid, leaf, sib = build_hit_tree
    HitTest.deepest(root, Point.new(25.0_f32, 25.0_f32)).should eq leaf
  end

  it "sibling hit by own bounds" do
    root, mid, leaf, sib = build_hit_tree
    HitTest.deepest(root, Point.new(70.0_f32, 70.0_f32)).should eq sib
  end

  it "later-added child wins on overlap (reverse z-order)" do
    root = Node.new("root", Rect.new(0.0_f32, 0.0_f32, 100.0_f32, 100.0_f32))
    a = Node.new("a", Rect.new(10.0_f32, 10.0_f32, 40.0_f32, 40.0_f32))
    b = Node.new("b", Rect.new(10.0_f32, 10.0_f32, 40.0_f32, 40.0_f32))
    root.add_child(a)
    root.add_child(b)
    HitTest.deepest(root, Point.new(20.0_f32, 20.0_f32)).should eq b
  end

  it "earlier child returned when point only inside it" do
    root = Node.new("root", Rect.new(0.0_f32, 0.0_f32, 100.0_f32, 100.0_f32))
    a = Node.new("a", Rect.new(10.0_f32, 10.0_f32, 40.0_f32, 40.0_f32))
    b = Node.new("b", Rect.new(50.0_f32, 50.0_f32, 40.0_f32, 40.0_f32))
    root.add_child(a)
    root.add_child(b)
    HitTest.deepest(root, Point.new(15.0_f32, 15.0_f32)).should eq a
  end

  it "boundary point is inclusive (Rect#contains?)" do
    root = Node.new("root", Rect.new(0.0_f32, 0.0_f32, 100.0_f32, 100.0_f32))
    a = Node.new("a", Rect.new(10.0_f32, 10.0_f32, 40.0_f32, 40.0_f32))
    root.add_child(a)
    HitTest.deepest(root, Point.new(0.0_f32, 0.0_f32)).should eq root
    HitTest.deepest(root, Point.new(10.0_f32, 10.0_f32)).should eq a
    HitTest.deepest(root, Point.new(50.0_f32, 50.0_f32)).should eq a
  end

  it "miss outside root returns nil" do
    root, mid, leaf, sib = build_hit_tree
    HitTest.deepest(root, Point.new(150.0_f32, 150.0_f32)).should be_nil
    HitTest.deepest(root, Point.new(-1.0_f32, 50.0_f32)).should be_nil
  end

  it "point inside root but no child returns root" do
    root, mid, leaf, sib = build_hit_tree
    HitTest.deepest(root, Point.new(5.0_f32, 5.0_f32)).should eq root
  end

  it "deeper nesting returns deepest node" do
    root = Node.new("root", Rect.new(0.0_f32, 0.0_f32, 100.0_f32, 100.0_f32))
    n1 = Node.new("n1", Rect.new(0.0_f32, 0.0_f32, 90.0_f32, 90.0_f32))
    n2 = Node.new("n2", Rect.new(0.0_f32, 0.0_f32, 80.0_f32, 80.0_f32))
    n3 = Node.new("n3", Rect.new(0.0_f32, 0.0_f32, 70.0_f32, 70.0_f32))
    root.add_child(n1)
    n1.add_child(n2)
    n2.add_child(n3)
    HitTest.deepest(root, Point.new(5.0_f32, 5.0_f32)).should eq n3
  end
end
