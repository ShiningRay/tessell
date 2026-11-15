require "./spec_helper"

# issue #51：retained-mode 运行期增删子组件后不需要宿主手动 root.layout，
# Root#build 检测到结构脏标记会补一次 arrange，新组件不再停在零 bounds。
describe "Kit 运行期结构变更自动重排（issue #51）" do
  it "新增子组件在 Root#build 后即有非零 bounds 并进入命中树" do
    col = Tessell::Kit::Column.new(KitSpecHelpers.key, Tessell::Insets.all(8.0_f32), 4.0_f32)
    root = Tessell::Kit::Root.new(col)
    root.layout(300.0_f32, 200.0_f32)
    root.build

    button = Tessell::Kit::Button.new(KitSpecHelpers.key.child(9_u64), "New")
    col.add(button)
    button.bounds.size.width.should eq(0.0_f32) # add 后尚未重排

    root.build # 宿主不调用 layout
    button.bounds.size.width.should be > 0.0_f32
    button.bounds.size.height.should be > 0.0_f32

    node = root.pool.map[button.key]?
    node.should_not be_nil
    node.not_nil!.bounds.size.width.should be > 0.0_f32
  end

  it "移除子组件后剩余子项重新排布（前一项上移）" do
    col = Tessell::Kit::Column.new(KitSpecHelpers.key, Tessell::Insets.all(8.0_f32), 4.0_f32)
    first = Tessell::Kit::Button.new(KitSpecHelpers.key.child(1_u64), "First")
    second = Tessell::Kit::Button.new(KitSpecHelpers.key.child(2_u64), "Second")
    col.add(first)
    col.add(second)

    root = Tessell::Kit::Root.new(col)
    root.layout(300.0_f32, 200.0_f32)
    root.build

    before_y = second.bounds.origin.y
    after_y = before_y

    col.remove(first)
    root.build
    after_y = second.bounds.origin.y

    after_y.should eq(8.0_f32) # 顶到 padding，证明重排而不是保留旧位置
    after_y.should be < before_y
  end

  it "结构未变化时 build 不重复 arrange（稳态不付重排成本）" do
    col = Tessell::Kit::Column.new(KitSpecHelpers.key, Tessell::Insets.all(8.0_f32), 4.0_f32)
    button = Tessell::Kit::Button.new(KitSpecHelpers.key.child(1_u64), "Only")
    col.add(button)
    root = Tessell::Kit::Root.new(col)
    root.layout(300.0_f32, 200.0_f32)
    root.build

    # 手动把 bounds 改成哨兵值：若 build 又 arrange 一次就会被覆盖
    button.arrange(root.context, Tessell::Rect.new(1.0_f32, 2.0_f32, 3.0_f32, 4.0_f32))
    root.build
    button.bounds.origin.x.should eq(1.0_f32)
    button.bounds.size.width.should eq(3.0_f32)
  end
end
