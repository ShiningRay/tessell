require "spec"
require "../src/tessell"

# Issue #5：UI DSL 接入两遍布局内核。vstack/hstack 声明 padding/gap，
# auto_text 按注入 Measurer 测量，UI.apply_auto_layout 求解并写回
# Node.bounds——布局与命中树同源。Auto 容器按内容收缩（内核语义）。
def stub_measurer : Tessell::Text::StubMeasurer
  Tessell::Text::StubMeasurer.new
end

def auto_buf : Tuple(Tessell::UI::Builder, Array(Tessell::UI::Decl), Array(Tessell::UI::UiKey))
  buf = [] of Tessell::UI::Decl
  stack = [] of Tessell::UI::UiKey
  {Tessell::UI::Builder.new(buf, stack), buf, stack}
end

describe "UI auto layout" do
  it "vstack with padding+gap positions measured text children sequentially" do
    builder, buf, _stack = auto_buf
    pool = Tessell::UI::Pool.new
    root = Tessell::Node.new("root", Tessell::Rect.new(0, 0, 400, 300))

    k1 = Tessell::UI::UiKey.root.child(1_u64)
    k2 = Tessell::UI::UiKey.root.child(2_u64)
    Tessell::UI.build(Tessell::UI::UiKey.root, builder) do |x|
      x.vstack(Tessell::UI::UiKey.root.child(10_u64),
        Tessell::Insets.all(10.0_f32), 8.0_f32) do |y|
        y.auto_text(k1, "hello", 20.0_f32)   # w=60  h=24
        y.auto_text(k2, "hi!", 20.0_f32)     # w=36  h=24
      end
    end
    Tessell::UI.apply(buf, root, pool)
    changed = Tessell::UI.apply_auto_layout(buf, pool,
      Tessell::Rect.new(0, 0, 400, 300), stub_measurer)

    cont = pool.map[Tessell::UI::UiKey.root.child(10_u64)]
    n1 = pool.map[k1]
    n2 = pool.map[k2]
    # 容器：内容收缩 = max(child w) + padding*2 = 60 + 20
    cont.bounds.size.width.should eq(80.0_f32)
    # 高 = 10 + 24 + 8(gap) + 24 + 10
    cont.bounds.size.height.should eq(76.0_f32)
    n1.bounds.origin.y.should eq(10.0_f32)
    n1.bounds.size.width.should eq(60.0_f32)
    n2.bounds.origin.y.should eq(10.0_f32 + 24.0_f32 + 8.0_f32)
    changed.should eq(3)
  end

  it "hstack lays children on the x axis with gap" do
    builder, buf, _stack = auto_buf
    pool = Tessell::UI::Pool.new
    root = Tessell::Node.new("root", Tessell::Rect.new(0, 0, 400, 300))

    k1 = Tessell::UI::UiKey.root.child(1_u64)
    k2 = Tessell::UI::UiKey.root.child(2_u64)
    Tessell::UI.build(Tessell::UI::UiKey.root, builder) do |x|
      x.hstack(Tessell::UI::UiKey.root.child(10_u64),
        Tessell::Insets.all(4.0_f32), 12.0_f32) do |y|
        y.auto_text(k1, "ab", 10.0_f32)   # w=12
        y.auto_text(k2, "cd", 10.0_f32)   # w=12
      end
    end
    Tessell::UI.apply(buf, root, pool)
    Tessell::UI.apply_auto_layout(buf, pool,
      Tessell::Rect.new(0, 0, 400, 300), stub_measurer)

    n1 = pool.map[k1]
    n2 = pool.map[k2]
    n1.bounds.origin.x.should eq(4.0_f32)
    n2.bounds.origin.x.should eq(4.0_f32 + 12.0_f32 + 12.0_f32)
    n1.bounds.origin.y.should eq(4.0_f32)
  end

  it "hit tree equals layout result: solved child bounds are hit-testable" do
    builder, buf, _stack = auto_buf
    pool = Tessell::UI::Pool.new
    root = Tessell::Node.new("root", Tessell::Rect.new(0, 0, 400, 300))

    k1 = Tessell::UI::UiKey.root.child(1_u64)
    Tessell::UI.build(Tessell::UI::UiKey.root, builder) do |x|
      x.vstack(Tessell::UI::UiKey.root.child(10_u64)) do |y|
        y.auto_text(k1, "hello world", 20.0_f32)  # w=132 h=24
      end
    end
    Tessell::UI.apply(buf, root, pool)
    Tessell::UI.apply_auto_layout(buf, pool,
      Tessell::Rect.new(0, 0, 400, 300), stub_measurer)

    n1 = pool.map[k1]
    n1.bounds.contains?(Tessell::Point.new(50.0_f32, 12.0_f32)).should be_true
    # Router/HitTest 直接读同一棵树：命中结果就是布局出的节点
    target = Tessell::Input::HitTest.deepest(root,
      Tessell::Point.new(50.0_f32, 12.0_f32))
    target.should eq(n1)
  end

  it "explicit-bounds child inside an auto stack participates as Fixed" do
    builder, buf, _stack = auto_buf
    pool = Tessell::UI::Pool.new
    root = Tessell::Node.new("root", Tessell::Rect.new(0, 0, 400, 300))

    k_fixed = Tessell::UI::UiKey.root.child(1_u64)
    k_auto = Tessell::UI::UiKey.root.child(2_u64)
    Tessell::UI.build(Tessell::UI::UiKey.root, builder) do |x|
      x.vstack(Tessell::UI::UiKey.root.child(10_u64)) do |y|
        y.node(k_fixed, Tessell::Rect.new(0, 0, 120.0_f32, 40.0_f32))
        y.auto_text(k_auto, "ab", 10.0_f32)
      end
    end
    Tessell::UI.apply(buf, root, pool)
    Tessell::UI.apply_auto_layout(buf, pool,
      Tessell::Rect.new(0, 0, 400, 300), stub_measurer)

    nf = pool.map[k_fixed]
    na = pool.map[k_auto]
    nf.bounds.size.width.should eq(120.0_f32)
    nf.bounds.size.height.should eq(40.0_f32)
    nf.bounds.origin.y.should eq(0.0_f32)
    na.bounds.origin.y.should eq(40.0_f32)
  end

  it "gap consumes main-axis space before Fraction grow distribution" do
    tree = Tessell::Layout::LayoutNode.new(
      width: Tessell::Fixed.new(200.0_f32),
      height: Tessell::Fixed.new(100.0_f32),
      direction: Tessell::Layout::Direction::Vertical, gap: 10.0_f32,
      children: [
        Tessell::Layout::LayoutNode.new(width: Tessell::Fixed.new(50.0_f32),
          height: Tessell::Fixed.new(30.0_f32)),
        Tessell::Layout::LayoutNode.new(height: Tessell::Fraction.new(1.0_f32)),
      ])
    box = Tessell::Layout.solve(tree,
      Tessell::Constraints.new(0.0_f32, 200.0_f32, 0.0_f32, 100.0_f32))
    # 100 - 30(fixed) - 10(gap) = 60 给 grow 子项
    box.children[1].rect.size.height.should eq(60.0_f32)
    box.children[1].rect.origin.y.should eq(40.0_f32)
  end

  it "steady state does not rewrite bounds (changed == 0)" do
    builder, buf, _stack = auto_buf
    pool = Tessell::UI::Pool.new
    root = Tessell::Node.new("root", Tessell::Rect.new(0, 0, 400, 300))
    Tessell::UI.build(Tessell::UI::UiKey.root, builder) do |x|
      x.vstack(Tessell::UI::UiKey.root.child(10_u64), gap: 4.0_f32) do |y|
        y.auto_text(Tessell::UI::UiKey.root.child(1_u64), "hi", 14.0_f32)
      end
    end
    Tessell::UI.apply(buf, root, pool)
    viewport = Tessell::Rect.new(0, 0, 400, 300)
    Tessell::UI.apply_auto_layout(buf, pool, viewport, stub_measurer)
    changed2 = Tessell::UI.apply_auto_layout(buf, pool, viewport, stub_measurer)
    changed2.should eq(0)
  end
end
