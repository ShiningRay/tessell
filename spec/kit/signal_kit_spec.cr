require "./spec_helper"

# issue #44：Signal 接入 Kit。
# part 1：组件响应式作用域（signal_owner 懒创建、watch、移出树自动 dispose）
# part 2：响应式更新路径（signal 写 → effect → 组件状态 → 下一帧 decl diff
#          产出失效；稳态帧命令计数与直连状态组件一致）
# part 3：For(T) keyed 行复用（只 Set 不重建；移除行 dispose 泄漏契约）

private class WatchProbe < Tessell::Kit::Component
  property label : String = "init"
  property tag : String = "0"
  getter runs = 0
  @external : Tessell::Signal::Signal(Int32)?

  def initialize(key, external : Tessell::Signal::Signal(Int32)? = nil)
    super(key)
    return unless external
    @external = external
    watch do
      @external.not_nil!.get # 追踪读
      @runs += 1
    end
  end

  def runs : Int32
    @runs
  end

  def measure(ctx : Tessell::Kit::Context, constraints : Tessell::Constraints) : Tessell::Size
    Tessell::Size.new(constraints.max_width, 24.0_f32)
  end

  def emit(b : Tessell::UI::Builder, ctx : Tessell::Kit::Context) : Nil
    b.text(@key, @label, Tessell::Rect.new(0.0_f32, 0.0_f32, 100.0_f32, 24.0_f32),
      paint: paint_token, a11y_role: Tessell::A11y::Role::Text, a11y_name: @label)
  end

  def paint(p : Tessell::Kit::Painter, ctx : Tessell::Kit::Context) : Nil
    p.text(0.0_f32, 16.0_f32, @label, 0xff000000_u32, 14.0_f32)
  end
end

describe "Signal → Kit integration (issue #44)" do
  it "watch runs immediately and re-runs on tracked signal writes" do
    sig = Tessell::Signal.signal("a")
    probe = WatchProbe.new(KitSpecHelpers.key)
    probe.watch { probe.label = sig.get }

    probe.label.should eq("a") # Solid 语义：创建即首跑
    sig.set("b")
    probe.label.should eq("b")
    sig.set("b") # 相等写不触发
    probe.label.should eq("b")
  end

  it "component removed from tree is disposed: signal writes stop reaching it" do
    sig = Tessell::Signal.signal(0)
    kept = WatchProbe.new(KitSpecHelpers.key.child(1_u64), sig)
    gone = WatchProbe.new(KitSpecHelpers.key.child(2_u64), sig)
    col = Tessell::Kit::Column.new(KitSpecHelpers.key,
      Tessell::Insets.all(0.0_f32), 0.0_f32).tap { |c| c.add(kept); c.add(gone) }
    root = Tessell::Kit::Root.new(col)
    root.layout(200.0_f32, 100.0_f32)
    root.build

    kept_runs = kept.runs
    gone_runs = gone.runs
    kept_runs.should be > 0

    col.remove(gone)
    root.build # dispose 差分：gone 移出树 → dispose

    sig.set(1)

    gone.runs.should eq(gone_runs)  # 已卸载组件不再收到 signal（泄漏契约）
    kept.runs.should eq(kept_runs + 1)
  end

  it "re-attaching a disposed component allows rebuilding its scope" do
    col = Tessell::Kit::Column.new(KitSpecHelpers.key,
      Tessell::Insets.all(0.0_f32), 0.0_f32)
    root = Tessell::Kit::Root.new(col)
    root.layout(200.0_f32, 100.0_f32)
    root.build

    probe = WatchProbe.new(KitSpecHelpers.key.child(3_u64))
    col.add(probe)
    root.build
    col.remove(probe)
    root.build # 第一轮 dispose：owner 置 nil

    # 重挂后重建 watch（与 Node 生命周期同口径）
    sig = Tessell::Signal.signal("x")
    probe.watch { probe.label = sig.get }
    probe.label.should eq("x")
  end

  it "signal write → effect → decl diff drives the next frame's paint" do
    sig = Tessell::Signal.signal("v1")
    probe = WatchProbe.new(KitSpecHelpers.key)
    probe.watch { probe.label = sig.get }
    root = Tessell::Kit::Root.new(probe)
    root.layout(200.0_f32, 100.0_f32)
    root.build

    painter = Tessell::Kit::PaintListPainter.new
    probe.paint(painter, root.context)
    painter.list[0].text.should eq("v1")

    painter.reset
    sig.set("v2")
    probe.paint(painter, root.context)
    painter.list[0].text.should eq("v2") # 下一帧绘制新内容

    # watch effect 内直接调 root.build：#42 守卫延迟为二段提交，不挂死
    build_probe = WatchProbe.new(KitSpecHelpers.key.child(5_u64))
    build_root = Tessell::Kit::Root.new(build_probe)
    build_root.layout(100.0_f32, 100.0_f32)
    build_probe.watch { build_root.build }
    build_root.build # 不递归爆栈
  end

  it "steady-state frames cost the same as a manual-state component (counting)" do
    sig = Tessell::Signal.signal("a")
    reactive = WatchProbe.new(KitSpecHelpers.key.child(1_u64))
    reactive.watch { reactive.label = sig.get }
    manual = WatchProbe.new(KitSpecHelpers.key.child(2_u64))
    manual.label = "a"

    root = Tessell::Kit::Root.new(
      Tessell::Kit::Column.new(KitSpecHelpers.key, Tessell::Insets.all(0.0_f32), 0.0_f32)
        .tap { |c| c.add(reactive); c.add(manual) })
    root.layout(200.0_f32, 100.0_f32)

    painter = Tessell::Kit::PaintListPainter.new
    root.build
    root.paint(painter)
    idle_cmds = painter.list.size
    misses_idle = root.context.text_cache_stats[:misses]

    # 无 signal 写的帧：零 effect 触发、帧命令数不变、零新增测量
    runs_before = reactive.runs
    painter.reset
    root.build
    root.paint(painter)
    painter.list.size.should eq(idle_cmds)
    reactive.runs.should eq(runs_before)
    root.context.text_cache_stats[:misses].should eq(misses_idle)
  end
end

# Signal(T) 快照契约要求 JSON-mappable（to_json/from_json），用
# JSON::Serializable 而非 record（record 生成的 to_json(io : IO) 与
# Builder 签名不兼容）。
private class Item
  include JSON::Serializable
  property id : Int32
  property label : String

  def initialize(@id : Int32, @label : String)
  end
end

private def make_for(rows : Hash(Int32, WatchProbe), external : Tessell::Signal::Signal(Int32)? = nil) : Tessell::Kit::For(Item)
  Tessell::Kit::For(Item).new(KitSpecHelpers.key, ->(it : Item) { it.id.to_u64 }) do |item, item_sig, idx_sig, k|
    row = WatchProbe.new(k, external)
    row.watch do
      row.label = item_sig.get.label
      row.tag = idx_sig.get.to_s
    end
    rows[item.id] = row
    row
  end
end

describe "Kit::For keyed row reuse (issue #44 part 3)" do
  it "builds one row per item and reuses instances across value updates" do
    rows = {} of Int32 => WatchProbe
    f = make_for(rows)
    f.items = [Item.new(1, "a"), Item.new(2, "b"), Item.new(3, "c")]
    root = Tessell::Kit::Root.new(f)
    root.layout(200.0_f32, 200.0_f32)
    root.build

    f.row_components.size.should eq(3)
    row1 = rows[1]

    # 同 key 值更新（id 不变、label 变）：实例复用（identity），只 Set 不重建
    f.items = [Item.new(1, "a2"), Item.new(2, "b"), Item.new(3, "c")]
    f.row_components.size.should eq(3)
    f.row_components.should contain(row1)      # row1 实例仍在（未重建）
    row1.label.should eq("a2")                 # 经 item signal 更新
    rows[2].label.should eq("b")               # 未变行不受扰动
  end

  it "removed rows are disposed: external signal writes stop reaching them" do
    external = Tessell::Signal.signal(0)
    rows = {} of Int32 => WatchProbe
    f = make_for(rows, external)
    f.items = [Item.new(1, "a"), Item.new(2, "b"), Item.new(3, "c")]
    root = Tessell::Kit::Root.new(f)
    root.layout(200.0_f32, 200.0_f32)
    root.build

    row1 = rows[1]
    row2 = rows[2]
    runs1 = row1.runs
    runs2 = row2.runs

    f.items = [Item.new(2, "b"), Item.new(3, "c")] # 移除 id=1

    external.set(1)

    row1.runs.should eq(runs1)       # 卸载行不再触发（泄漏契约）
    row2.runs.should eq(runs2 + 1)   # 存活行正常
    row2.tag.should eq("0")          # index signal 更新：2 从 1 → 0
  end

  it "raises on duplicate row keys (identity collision, same class as #43)" do
    f = Tessell::Kit::For(Item).new(KitSpecHelpers.key, ->(_it : Item) { 42_u64 }) do |item, _is, _xs, k|
      WatchProbe.new(k)
    end
    expect_raises(ArgumentError, "duplicate row key") do
      f.items = [Item.new(1, "x"), Item.new(2, "y")] # 不同 id 同 key → 身份冲突
    end
  end

  it "empty items disposes all rows and yields no children" do
    rows = {} of Int32 => WatchProbe
    f = make_for(rows)
    f.items = [Item.new(1, "a"), Item.new(2, "b")]
    f.items = [] of Item
    f.row_components.size.should eq(0)
  end
end
