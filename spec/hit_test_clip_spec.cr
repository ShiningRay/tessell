require "spec"
require "../src/tessell/geometry"
require "../src/tessell/core/node"
require "../src/tessell/input/hit_test"

include Tessell
include Tessell::Input

describe "HitTest clip (K1)" do
  it "rejects points outside a node clip even when bounds contain them" do
    root = Node.new("root", Rect.new(0.0_f32, 0.0_f32, 100.0_f32, 100.0_f32))
    child = Node.new("child", Rect.new(0.0_f32, 0.0_f32, 100.0_f32, 100.0_f32))
    child.clip = Rect.new(0.0_f32, 0.0_f32, 50.0_f32, 100.0_f32)
    root.add_child(child)

    HitTest.deepest(root, Point.new(10.0_f32, 10.0_f32)).should eq(child)
    HitTest.deepest(root, Point.new(60.0_f32, 10.0_f32)).should eq(root)
  end

  it "rejects points outside the root clip" do
    root = Node.new("root", Rect.new(0.0_f32, 0.0_f32, 100.0_f32, 100.0_f32))
    root.clip = Rect.new(10.0_f32, 10.0_f32, 20.0_f32, 20.0_f32)
    HitTest.deepest(root, Point.new(5.0_f32, 5.0_f32)).should be_nil
    HitTest.deepest(root, Point.new(15.0_f32, 15.0_f32)).should eq(root)
  end

  it "nested clipped children do not leak hits outside parent clip" do
    root = Node.new("root", Rect.new(0.0_f32, 0.0_f32, 100.0_f32, 100.0_f32))
    parent = Node.new("parent", Rect.new(0.0_f32, 0.0_f32, 100.0_f32, 100.0_f32))
    parent.clip = Rect.new(0.0_f32, 0.0_f32, 40.0_f32, 40.0_f32)
    child = Node.new("child", Rect.new(0.0_f32, 0.0_f32, 100.0_f32, 100.0_f32))
    parent.add_child(child)
    root.add_child(parent)

    HitTest.deepest(root, Point.new(20.0_f32, 20.0_f32)).should eq(child)
    HitTest.deepest(root, Point.new(60.0_f32, 60.0_f32)).should eq(root)
  end
end
