require "./spec_helper"

# issue #49：Row/Column 弹性布局——子项 grow 权重分享剩余主轴空间
# （紧约束 min=max=share，Flutter Expanded 语义）+ Spacer 占位组件。
# 验收场景：输入框占据剩余宽度 + 固定宽度按钮同排，按钮不再溢出。

private class FixedBox < Tessell::Kit::Component
  def initialize(key : Tessell::UI::UiKey, @w : Float32, @h : Float32)
    super(key)
  end

  def measure(ctx : Tessell::Kit::Context, constraints : Tessell::Constraints) : Tessell::Size
    constraints.constrain(Tessell::Size.new(@w, @h))
  end

  def emit(b : Tessell::UI::Builder, ctx : Tessell::Kit::Context) : Nil
    # 布局数学用例不需要节点
  end
end

describe "Kit Row/Column 弹性布局（issue #49）" do
  it "输入框 grow 填满剩余宽度，按钮不再溢出（issue 报告的验收场景）" do
    row = Tessell::Kit::Row.new(KitSpecHelpers.key)
    input = Tessell::Kit::Input.new(KitSpecHelpers.key.child(1_u64))
    button = Tessell::Kit::Button.new(KitSpecHelpers.key.child(2_u64), "Add")
    row.add(input, grow: 1.0_f32)
    row.add(button)

    root = Tessell::Kit::Root.new(row)
    root.layout(720.0_f32, 100.0_f32)
    root.build

    btn_w = button.bounds.size.width
    btn_w.should be > 0.0_f32
    input.bounds.size.width.should eq(720.0_f32 - btn_w)
    input.bounds.origin.x.should eq(0.0_f32)
    button.bounds.max_x.should be <= 720.0_f32 # 行内，不再溢出到 708+
  end

  it "无 grow 时保持旧行为：有界子项占满行宽，后续子项溢出" do
    row = Tessell::Kit::Row.new(KitSpecHelpers.key)
    input = Tessell::Kit::Input.new(KitSpecHelpers.key.child(1_u64))
    button = Tessell::Kit::Button.new(KitSpecHelpers.key.child(2_u64), "Add")
    row.add(input)
    row.add(button)

    root = Tessell::Kit::Root.new(row)
    root.layout(720.0_f32, 100.0_f32)
    root.build

    input.bounds.size.width.should eq(720.0_f32) # 旧行为：占满行宽
    button.bounds.origin.x.should be >= 720.0_f32
  end

  it "多弹性子项按权重分配剩余空间（1:3）" do
    row = Tessell::Kit::Row.new(KitSpecHelpers.key)
    a = FixedBox.new(KitSpecHelpers.key.child(1_u64), 100.0_f32, 20.0_f32)
    s1 = Tessell::Kit::Spacer.new(KitSpecHelpers.key.child(2_u64))
    b = FixedBox.new(KitSpecHelpers.key.child(3_u64), 100.0_f32, 20.0_f32)
    s2 = Tessell::Kit::Spacer.new(KitSpecHelpers.key.child(4_u64))
    row.add(a)
    row.add(s1, grow: 1.0_f32)
    row.add(b)
    row.add(s2, grow: 3.0_f32)

    root = Tessell::Kit::Root.new(row)
    root.layout(600.0_f32, 50.0_f32)
    root.build

    remaining = 600.0_f32 - 200.0_f32 # inner − 两个 FixedBox
    s1.bounds.size.width.should eq(remaining * 0.25_f32)
    s2.bounds.size.width.should eq(remaining * 0.75_f32)
    # 弹性子项恰好填满剩余空间（浮点余数给最后一个）
    (s1.bounds.size.width + s2.bounds.size.width).should eq(remaining)
    b.bounds.origin.x.should eq(100.0_f32 + remaining * 0.25_f32)
  end

  it "Column 主轴同样适用（垂直方向 grow）" do
    col = Tessell::Kit::Column.new(KitSpecHelpers.key)
    top = FixedBox.new(KitSpecHelpers.key.child(1_u64), 50.0_f32, 30.0_f32)
    flex = FixedBox.new(KitSpecHelpers.key.child(2_u64), 50.0_f32, 10.0_f32)
    bottom = FixedBox.new(KitSpecHelpers.key.child(3_u64), 50.0_f32, 30.0_f32)
    col.add(top)
    col.add(flex, grow: 1.0_f32)
    col.add(bottom)

    root = Tessell::Kit::Root.new(col)
    root.layout(100.0_f32, 200.0_f32)
    root.build

    flex.bounds.size.height.should eq(200.0_f32 - 60.0_f32)
    bottom.bounds.max_y.should eq(200.0_f32)
  end

  it "剩余空间不足时弹性子项塌缩为 0，固定子项优先" do
    row = Tessell::Kit::Row.new(KitSpecHelpers.key)
    a = FixedBox.new(KitSpecHelpers.key.child(1_u64), 400.0_f32, 20.0_f32)
    b = FixedBox.new(KitSpecHelpers.key.child(2_u64), 400.0_f32, 20.0_f32)
    flex = FixedBox.new(KitSpecHelpers.key.child(3_u64), 50.0_f32, 20.0_f32)
    row.add(a)
    row.add(b)
    row.add(flex, grow: 1.0_f32)

    root = Tessell::Kit::Root.new(row)
    root.layout(600.0_f32, 50.0_f32)
    root.build

    flex.bounds.size.width.should eq(0.0_f32)
    a.bounds.size.width.should eq(400.0_f32)
    b.bounds.size.width.should eq(400.0_f32)
  end

  it "无界约束不做弹性分配：容器内在尺寸按内容收缩" do
    row = Tessell::Kit::Row.new(KitSpecHelpers.key)
    a = FixedBox.new(KitSpecHelpers.key.child(1_u64), 100.0_f32, 20.0_f32)
    flex = FixedBox.new(KitSpecHelpers.key.child(2_u64), 40.0_f32, 20.0_f32)
    row.add(a)
    row.add(flex, grow: 1.0_f32)

    sz = row.measure(root_ctx, Tessell::Constraints.new)
    # 主轴无界：弹性子项贡献 0（不参与内在尺寸），固定子项照常
    sz.width.should eq(100.0_f32)
  end

  it "set_grow 权重变更打脏标记，root.build 后重排（无需手动 layout）" do
    row = Tessell::Kit::Row.new(KitSpecHelpers.key)
    input = Tessell::Kit::Input.new(KitSpecHelpers.key.child(1_u64))
    button = Tessell::Kit::Button.new(KitSpecHelpers.key.child(2_u64), "Add")
    row.add(input)
    row.add(button)

    root = Tessell::Kit::Root.new(row)
    root.layout(720.0_f32, 100.0_f32)
    root.build
    input.bounds.size.width.should eq(720.0_f32) # 初始旧行为

    row.set_grow(input, 1.0_f32)
    root.build # 不调用 layout
    input.bounds.size.width.should eq(720.0_f32 - button.bounds.size.width)

    row.set_grow(input, 0.0_f32) # 取消弹性
    root.build
    input.bounds.size.width.should eq(720.0_f32)
    row.grow_of(input).should eq(0.0_f32)
  end

  it "remove 弹性子项后其余子项重排，grow 登记同步清除" do
    row = Tessell::Kit::Row.new(KitSpecHelpers.key)
    a = FixedBox.new(KitSpecHelpers.key.child(1_u64), 100.0_f32, 20.0_f32)
    flex = FixedBox.new(KitSpecHelpers.key.child(2_u64), 40.0_f32, 20.0_f32)
    b = FixedBox.new(KitSpecHelpers.key.child(3_u64), 100.0_f32, 20.0_f32)
    row.add(a)
    row.add(flex, grow: 1.0_f32)
    row.add(b)

    root = Tessell::Kit::Root.new(row)
    root.layout(600.0_f32, 50.0_f32)
    root.build
    flex.bounds.origin.x.should eq(100.0_f32)

    row.remove(flex)
    root.build
    b.bounds.origin.x.should eq(100.0_f32) # flex 移除后 b 紧跟 a
    row.grow_of(flex).should eq(0.0_f32)
  end

  it "Spacer 不进命中树" do
    row = Tessell::Kit::Row.new(KitSpecHelpers.key)
    s = Tessell::Kit::Spacer.new(KitSpecHelpers.key.child(1_u64))
    row.add(s, grow: 1.0_f32)
    root = Tessell::Kit::Root.new(row)
    root.layout(300.0_f32, 50.0_f32)
    root.build

    s.bounds.size.width.should eq(300.0_f32) # 唯一弹性子项吃满
    root.pool.map[s.key]?.should be_nil      # emit 显式跳过，不可命中
  end
end

private def root_ctx : Tessell::Kit::Context
  Tessell::Kit::Context.new(Tessell::Kit::Theme.light, Tessell::Kit::StubTextMetrics.new)
end

describe "保留 key fail-fast（issue #69）" do
  it "content 误用 UiKey.root 在 Root 构造期 raise，不进 build 挂死" do
    col = Tessell::Kit::Column.new(Tessell::UI::UiKey.root)
    expect_raises(ArgumentError, "保留 key") do
      Tessell::Kit::Root.new(col)
    end
    # 正常派生 key 不受影响；孤立组件（不经 Root）仍可用 UiKey.root
    col_ok = Tessell::Kit::Column.new(Tessell::UI::UiKey.root.child(900_u64))
    root_ok = Tessell::Kit::Root.new(col_ok)
    root_ok.layout(100.0_f32, 50.0_f32)
    root_ok.build
    orphan = Tessell::Kit::Column.new(Tessell::UI::UiKey.root) # 孤立用法合法
    orphan.add(Tessell::Kit::Button.new(Tessell::UI::UiKey.root.child(901_u64), "x"))
  end
end
