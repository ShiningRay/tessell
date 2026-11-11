require "spec"
require "../src/quartz/geometry"

include Quartz

describe Quartz::Rect do
  it "detects containment" do
    r = Rect.new(10.0_f32, 10.0_f32, 100.0_f32, 50.0_f32)
    r.contains?(Point.new(20.0_f32, 20.0_f32)).should be_true
    r.contains?(Point.new(200.0_f32, 20.0_f32)).should be_false
  end

  it "unions dirty rects" do
    a = Rect.new(0.0_f32, 0.0_f32, 10.0_f32, 10.0_f32)
    b = Rect.new(20.0_f32, 20.0_f32, 10.0_f32, 10.0_f32)
    u = a.union(b)
    u.origin.x.should eq 0.0_f32
    u.max_x.should eq 30.0_f32
    u.max_y.should eq 30.0_f32
  end
end

describe Quartz::Constraints do
  it "clamps size" do
    c = Constraints.new(0.0_f32, 100.0_f32, 0.0_f32, 100.0_f32)
    c.constrain(Size.new(250.0_f32, 50.0_f32)).width.should eq 100.0_f32
  end

  it "tight constraints force exact size" do
    c = Constraints.tight(Size.new(40.0_f32, 20.0_f32))
    c.constrain(Size.new(1.0_f32, 1.0_f32)).height.should eq 20.0_f32
  end
end

describe Quartz::Insets do
  it "sums axes" do
    i = Insets.all(4.0_f32)
    i.horizontal.should eq 8.0_f32
    i.vertical.should eq 8.0_f32
  end
end

describe Quartz::Point do
  it "is a value type" do
    a = Point.new(1.0_f32, 2.0_f32)
    b = a
    (a + b).x.should eq 2.0_f32
  end
end
