require "./spec_helper"

describe "Tessell::Kit::Container" do
  it "measures Column with padding and spacing" do
    col = Tessell::Kit::Column.new(KitSpecHelpers.key, Tessell::Insets.all(8.0_f32), 4.0_f32)
    a = Tessell::Kit::Button.new(KitSpecHelpers.key.child(1_u64), "A")
    b = Tessell::Kit::Button.new(KitSpecHelpers.key.child(2_u64), "B")
    col.add(a)
    col.add(b)
    ctx = KitSpecHelpers.context
    size = col.measure(ctx, Tessell::Constraints.new)
    a_size = a.measure(ctx, Tessell::Constraints.new)
    b_size = b.measure(ctx, Tessell::Constraints.new)
    size.width.should eq(Math.max(a_size.width, b_size.width) + 16.0_f32)
    size.height.should eq(a_size.height + b_size.height + 4.0_f32 + 16.0_f32)
  end

  it "arranges children vertically and stretches width" do
    col = Tessell::Kit::Column.new(KitSpecHelpers.key, Tessell::Insets.all(10.0_f32), 6.0_f32)
    a = Tessell::Kit::Button.new(KitSpecHelpers.key.child(1_u64), "A")
    b = Tessell::Kit::Button.new(KitSpecHelpers.key.child(2_u64), "B")
    col.add(a)
    col.add(b)
    ctx = KitSpecHelpers.context
    col.arrange(ctx, Tessell::Rect.new(0.0_f32, 0.0_f32, 200.0_f32, 100.0_f32))
    a.bounds.origin.x.should eq(10.0_f32)
    a.bounds.size.width.should eq(180.0_f32)
    b.bounds.origin.y.should eq(a.bounds.max_y + 6.0_f32)
  end

  it "collects nested components in preorder" do
    outer = Tessell::Kit::Column.new(KitSpecHelpers.key)
    inner = Tessell::Kit::Row.new(KitSpecHelpers.key.child(1_u64))
    button = Tessell::Kit::Button.new(KitSpecHelpers.key.child(2_u64), "A")
    inner.add(button)
    outer.add(inner)
    sink = [] of Tessell::Kit::Component
    outer.collect_components(sink)
    sink.should eq([outer, inner, button])
  end
end
