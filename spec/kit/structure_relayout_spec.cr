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

# issue #51 动态列表路径（PR #54 review 补充）：For#items= 直接替换 @children，
# 不经 Container#add/remove——键序变化（增/删/重排）同样要打结构脏标记，
# Root#build 才会补 arrange；键序不变的值更新不打（稳态不重排）。
private class RelayoutRowItem
  include JSON::Serializable
  property id : Int32
  property label : String

  def initialize(@id : Int32, @label : String)
  end
end

private def make_row_for : Tessell::Kit::For(RelayoutRowItem)
  Tessell::Kit::For(RelayoutRowItem).new(KitSpecHelpers.key, ->(it : RelayoutRowItem) { it.id.to_u64 }) do |_item, _is, _xs, k|
    Tessell::Kit::Button.new(k, "row")
  end
end

describe "Kit::For#items= 结构变更自动重排（issue #51 动态列表）" do
  it "运行期增行后 Root#build 补 arrange：新行非零 bounds 并进命中树" do
    list = make_row_for
    list.items = [RelayoutRowItem.new(1, "a"), RelayoutRowItem.new(2, "b")]
    root = Tessell::Kit::Root.new(list)
    root.layout(300.0_f32, 200.0_f32)
    root.build

    list.items = [RelayoutRowItem.new(1, "a"), RelayoutRowItem.new(2, "b"), RelayoutRowItem.new(3, "c")]
    third = list.row_components[2]
    third.bounds.size.width.should eq(0.0_f32) # items= 后尚未重排

    root.build # 宿主不手动 layout
    third.bounds.size.width.should be > 0.0_f32
    third.bounds.size.height.should be > 0.0_f32
    node = root.pool.map[third.key]?
    node.should_not be_nil
    node.not_nil!.bounds.size.width.should be > 0.0_f32
  end

  it "运行期删行后剩余行上移到首位" do
    list = make_row_for
    list.items = [RelayoutRowItem.new(1, "a"), RelayoutRowItem.new(2, "b"), RelayoutRowItem.new(3, "c")]
    root = Tessell::Kit::Root.new(list)
    root.layout(300.0_f32, 200.0_f32)
    root.build

    first_y = list.row_components[0].bounds.origin.y
    second = list.row_components[1]
    before_y = second.bounds.origin.y

    list.items = [RelayoutRowItem.new(2, "b"), RelayoutRowItem.new(3, "c")] # 移除 id=1
    root.build
    list.row_components[0].should eq(second)             # 行实例复用（keyed）
    list.row_components[0].bounds.origin.y.should eq(first_y) # 上移到首位
    before_y.should be > first_y
  end

  it "键序不变的值更新不打结构脏标记：build 不重排（哨兵 bounds 保留）" do
    list = make_row_for
    list.items = [RelayoutRowItem.new(1, "a"), RelayoutRowItem.new(2, "b")]
    root = Tessell::Kit::Root.new(list)
    root.layout(300.0_f32, 200.0_f32)
    root.build

    first = list.row_components[0]
    first.arrange(root.context, Tessell::Rect.new(1.0_f32, 2.0_f32, 3.0_f32, 4.0_f32)) # 哨兵
    list.items = [RelayoutRowItem.new(1, "a2"), RelayoutRowItem.new(2, "b")]           # 只改 label
    root.build
    first.bounds.origin.x.should eq(1.0_f32) # 若又 arrange 就会被覆盖
    first.bounds.size.width.should eq(3.0_f32)
  end
end
