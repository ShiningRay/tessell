require "./spec_helper"
require "spec"
require "../src/tessell/layout"

include Tessell
include Tessell::Layout

EPS = 1.0e-4_f32

def close?(a : Float32, b : Float32) : Bool
  (a - b).abs <= EPS
end

describe Tessell::Layout::LayoutNode do
  it "fixed-size leaf node measures and arranges (use case 1)" do
    node = LayoutNode.new(id: "leaf", width: Fixed.new(100.0_f32), height: Fixed.new(20.0_f32))
    c = Constraints.new(0.0_f32, 200.0_f32, 0.0_f32, 100.0_f32)
    sz = Layout.measure(node, c)
    sz.width.should eq 100.0_f32
    sz.height.should eq 20.0_f32
    box = Layout.solve(node, c, Point.new(5.0_f32, 7.0_f32))
    box.rect.origin.x.should eq 5.0_f32
    box.rect.origin.y.should eq 7.0_f32
    box.rect.size.width.should eq 100.0_f32
    box.rect.size.height.should eq 20.0_f32
  end

  it "auto leaf returns zero size (use case 2)" do
    node = LayoutNode.new(id: "auto-leaf")
    c = Constraints.new(0.0_f32, 100.0_f32, 0.0_f32, 50.0_f32)
    Layout.measure(node, c).width.should eq 0.0_f32
    Layout.measure(node, c).height.should eq 0.0_f32
  end

  it "wrapping under constrained width (use case 3)" do
    node = LayoutNode.new(id: "wrap", children: [LayoutNode.new(id: "a", width: Fixed.new(80.0_f32), height: Fixed.new(10.0_f32))])
    c = Constraints.new(0.0_f32, 50.0_f32, 0.0_f32, 100.0_f32)
    sz = Layout.measure(node, c)
    sz.width.should eq 50.0_f32
  end

  it "fraction sizing depends on parent final rect (use case 4)" do
    node = LayoutNode.new(id: "frac", direction: Direction::Horizontal,
      children: [LayoutNode.new(id: "a", width: Fraction.new(1.0_f32), height: Fixed.new(10.0_f32))])
    c = Constraints.new(0.0_f32, 200.0_f32, 0.0_f32, 50.0_f32)
    box = Layout.solve(node, c, Point.new(0.0_f32, 0.0_f32))
    close?(box.children[0].rect.size.width, 200.0_f32).should be_true
  end

  it "nested padding accumulates insets (use case 5)" do
    inner = LayoutNode.new(id: "inner", width: Fixed.new(10.0_f32), height: Fixed.new(10.0_f32))
    outer = LayoutNode.new(id: "outer", padding: Insets.all(4.0_f32), children: [inner])
    c = Constraints.new(0.0_f32, 100.0_f32, 0.0_f32, 100.0_f32)
    sz = Layout.measure(outer, c)
    sz.width.should eq 18.0_f32
    sz.height.should eq 18.0_f32
    box = Layout.solve(outer, c, Point.new(0.0_f32, 0.0_f32))
    box.children[0].rect.origin.x.should eq 4.0_f32
    box.children[0].rect.origin.y.should eq 4.0_f32
  end

  it "constraint conflict clamps size (use case 6)" do
    node = LayoutNode.new(id: "big", width: Fixed.new(250.0_f32), height: Fixed.new(50.0_f32))
    c = Constraints.new(0.0_f32, 100.0_f32, 0.0_f32, 100.0_f32)
    sz = Layout.measure(node, c)
    sz.width.should eq 100.0_f32
    sz.height.should eq 50.0_f32
  end

  it "zero-size node (use case: zero dimensions)" do
    node = LayoutNode.new(id: "zero", width: Fixed.new(0.0_f32), height: Fixed.new(0.0_f32))
    c = Constraints.new(0.0_f32, 100.0_f32, 0.0_f32, 100.0_f32)
    sz = Layout.measure(node, c)
    sz.width.should eq 0.0_f32
    sz.height.should eq 0.0_f32
    box = Layout.solve(node, c, Point.new(0.0_f32, 0.0_f32))
    box.rect.size.width.should eq 0.0_f32
  end

  it "single child overflow clamps (use case: single child overflow)" do
    node = LayoutNode.new(id: "overflow", children: [LayoutNode.new(id: "a", width: Fixed.new(200.0_f32), height: Fixed.new(10.0_f32))])
    c = Constraints.new(0.0_f32, 100.0_f32, 0.0_f32, 50.0_f32)
    sz = Layout.measure(node, c)
    sz.width.should eq 100.0_f32
  end

  it "fraction allocation error tolerance (use case 9)" do
    node = LayoutNode.new(id: "frac2", direction: Direction::Horizontal,
      children: [
        LayoutNode.new(id: "a", width: Fraction.new(1.0_f32), height: Fixed.new(10.0_f32)),
        LayoutNode.new(id: "b", width: Fraction.new(2.0_f32), height: Fixed.new(10.0_f32)),
      ])
    c = Constraints.new(0.0_f32, 300.0_f32, 0.0_f32, 50.0_f32)
    box = Layout.solve(node, c, Point.new(0.0_f32, 0.0_f32))
    a_w = box.children[0].rect.size.width
    b_w = box.children[1].rect.size.width
    close?(a_w, 100.0_f32).should be_true
    close?(b_w, 200.0_f32).should be_true
    close?(a_w + b_w, 300.0_f32).should be_true
  end

  it "pure function: same input yields same output" do
    node = LayoutNode.new(id: "pure", width: Fixed.new(50.0_f32), height: Fixed.new(25.0_f32))
    c = Constraints.new(0.0_f32, 100.0_f32, 0.0_f32, 100.0_f32)
    r1 = Layout.measure(node, c)
    r2 = Layout.measure(node, c)
    r1.width.should eq r2.width
    r1.height.should eq r2.height
    b1 = Layout.solve(node, c, Point.new(0.0_f32, 0.0_f32))
    b2 = Layout.solve(node, c, Point.new(0.0_f32, 0.0_f32))
    b1.rect.size.width.should eq b2.rect.size.width
  end

  it "vertical stack arranges children along main axis" do
    node = LayoutNode.new(id: "vstack", direction: Direction::Vertical,
      children: [
        LayoutNode.new(id: "a", width: Fixed.new(10.0_f32), height: Fixed.new(10.0_f32)),
        LayoutNode.new(id: "b", width: Fixed.new(10.0_f32), height: Fixed.new(20.0_f32)),
      ])
    c = Constraints.new(0.0_f32, 100.0_f32, 0.0_f32, 100.0_f32)
    box = Layout.solve(node, c, Point.new(0.0_f32, 0.0_f32))
    box.children[0].rect.origin.y.should eq 0.0_f32
    box.children[1].rect.origin.y.should eq 10.0_f32
  end

  it "horizontal row arranges children along main axis" do
    node = LayoutNode.new(id: "hrow", direction: Direction::Horizontal,
      children: [
        LayoutNode.new(id: "a", width: Fixed.new(10.0_f32), height: Fixed.new(10.0_f32)),
        LayoutNode.new(id: "b", width: Fixed.new(20.0_f32), height: Fixed.new(10.0_f32)),
      ])
    c = Constraints.new(0.0_f32, 100.0_f32, 0.0_f32, 100.0_f32)
    box = Layout.solve(node, c, Point.new(0.0_f32, 0.0_f32))
    box.children[0].rect.origin.x.should eq 0.0_f32
    box.children[1].rect.origin.x.should eq 10.0_f32
  end
end