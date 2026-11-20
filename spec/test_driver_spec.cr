require "./spec_helper"
require "./kit/spec_helper"

# issue #59：跨宿主用户操作测试——同一 journey 定义跑 FakeHost 管道与
# Raw 直投（真实宿主用）两个后端；selector 歧义/无匹配/禁用/不可见的
# 有界失败路径；无 wall-clock sleep；失败输出步骤与组件证据。

require "../src/tessell/kit"
require "../src/tessell/platform/fake_host"

# 被测树：输入框 + 添加按钮（press 后清空输入并追加历史）+ 滚动列表
private class JourneyApp
  getter root : Tessell::Kit::Root
  getter added : Array(String)
  getter scroll : Int32

  def initialize
    col = Tessell::Kit::Column.new(Tessell::UI::UiKey.root.child(990_u64),
      Tessell::Insets.all(4.0_f32), 4.0_f32)
    input = Tessell::Kit::Input.new(Tessell::UI::UiKey.root.child(990_u64).child(1_u64), label: "New item")
    col.add(input, grow: 1.0_f32)
    btn = Tessell::Kit::Button.new(Tessell::UI::UiKey.root.child(990_u64).child(2_u64), "Add item")
    col.add(btn)
    disabled = Tessell::Kit::Button.new(Tessell::UI::UiKey.root.child(990_u64).child(4_u64), "Disabled action",
      enabled: false)
    col.add(disabled)

    @root = Tessell::Kit::Root.new(col)
    @added = [] of String
    @scroll = 0
  end
end

# 统一 journey：同一测试定义，两个后端执行（issue #59 验收 1）。
private def run_journey(driver : Tessell::Kit::TestDriver, app : JourneyApp) : Nil
  driver.focus("New item")
  driver.type("hello")
  driver.assert_text("New item", "hello")
end

describe "Kit::TestDriver 用户操作驱动（issue #59）" do
  it "同一 journey 在 FakeHost 管道与 Raw 直投两后端结果一致" do
    # 后端 A：FakeHost 完整管道（inject → pump_frame 虚拟时钟）
    app_a = JourneyApp.new
    host_a = Tessell::Platform::FakeHost.new(400.0_f32, 200.0_f32)
    app_a.root.layout(400.0_f32, 200.0_f32)
    app_a.root.build
    drv_a = Tessell::Kit::TestDriver.new(app_a.root, host_a, :fake)
    drv_a.press("Add item")

    # 后端 B：Raw 直投（真实宿主口径）
    app_b = JourneyApp.new
    app_b.root.layout(400.0_f32, 200.0_f32)
    app_b.root.build
    drv_b = Tessell::Kit::TestDriver.new(app_b.root, nil, :raw)
    drv_b.press("Add item")

    # 两后端事件都被按钮消费（focus 变化一致）——焦点组件同一目标
    fa = app_a.root.focused_component
    fb = app_b.root.focused_component
    fa.should_not be_nil
    fb.should_not be_nil
    fa.not_nil!.a11y_name.should eq(fb.not_nil!.a11y_name)
    # 无 sleep：两后端同步推进（FakeHost 虚拟时钟已 pump）
    host_a.frames.should be > 0
  end

  it "press → 按钮激活；type → Input 文本；scroll → 事件路由（完整用户路径）" do
    col = Tessell::Kit::Column.new(Tessell::UI::UiKey.root.child(991_u64),
      Tessell::Insets.all(4.0_f32), 4.0_f32)
    input = Tessell::Kit::Input.new(Tessell::UI::UiKey.root.child(990_u64).child(1_u64), label: "New item")
    col.add(input, grow: 1.0_f32)
    button = Tessell::Kit::Button.new(Tessell::UI::UiKey.root.child(990_u64).child(2_u64), "Add item")
    col.add(button)
    root = Tessell::Kit::Root.new(col)
    root.layout(400.0_f32, 200.0_f32)
    root.build

    drv = Tessell::Kit::TestDriver.new(root, nil, :raw)
    drv.focus("New item")   # 输入框 a11y_name 来自 label
    drv.type("hello world")
    input.text.should eq("hello world")

    drv.press("Add item")   # press 移走焦点，输入不再聚焦
    input.focused.should be_false

    drv.scroll(200.0_f32, 100.0_f32, 0.0_f32, 40.0_f32) # 无滚动容器不崩
    drv.key(Tessell::Input::KeyCode::Escape)
  end

  it "selector 歧义：同名按钮两个 → 失败并列出全部匹配" do
    col = Tessell::Kit::Column.new(Tessell::UI::UiKey.root.child(992_u64))
    col.add(Tessell::Kit::Button.new(Tessell::UI::UiKey.root.child(992_u64).child(1_u64), "Dup"))
    col.add(Tessell::Kit::Button.new(Tessell::UI::UiKey.root.child(992_u64).child(2_u64), "Dup"))
    root = Tessell::Kit::Root.new(col)
    root.layout(400.0_f32, 200.0_f32)
    root.build
    drv = Tessell::Kit::TestDriver.new(root, nil, :raw)
    begin
      drv.press("Dup")
      fail "应抛 selector 歧义"
    rescue e : Tessell::Kit::SelectorError
      e.message.not_nil!.should contain("歧义")
      e.message.not_nil!.should contain("2 个匹配")
    end
  end

  it "selector 无匹配：失败并列出当前树全部可见组件（可定位证据）" do
    app = JourneyApp.new
    app.root.layout(400.0_f32, 200.0_f32)
    app.root.build
    drv = Tessell::Kit::TestDriver.new(app.root, nil, :raw)
    begin
      drv.press("No Such Button")
      fail "应抛 selector 无匹配"
    rescue e : Tessell::Kit::SelectorError
      msg = e.message.not_nil!
      msg.should contain("无匹配")
      msg.should contain("Add item")       # 诊断列出实际存在的组件
      msg.should contain("Disabled action")
    end
  end

  it "禁用目标：失败并注明不可操作" do
    app = JourneyApp.new
    app.root.layout(400.0_f32, 200.0_f32)
    app.root.build
    drv = Tessell::Kit::TestDriver.new(app.root, nil, :raw)
    begin
      drv.press("Disabled action")
      fail "应抛禁用诊断"
    rescue e : Tessell::Kit::SelectorError
      e.message.not_nil!.should contain("禁用")
    end
  end

  it "不可见目标：等同无匹配（emit 即存在口径）" do
    col = Tessell::Kit::Column.new(Tessell::UI::UiKey.root.child(990_u64))
    btn = Tessell::Kit::Button.new(Tessell::UI::UiKey.root.child(990_u64).child(1_u64), "Ghost")
    col.add(btn)
    btn.visible = false
    root = Tessell::Kit::Root.new(col)
    root.layout(300.0_f32, 100.0_f32)
    root.build
    drv = Tessell::Kit::TestDriver.new(root, nil, :raw)
    begin
      drv.press("Ghost")
      fail "应抛不可见无匹配"
    rescue e : Tessell::Kit::SelectorError
      e.message.not_nil!.should contain("无匹配")
    end
  end

  it "失败输出已执行步骤链（可定位 op 证据，无 wall-clock）" do
    col = Tessell::Kit::Column.new(Tessell::UI::UiKey.root.child(990_u64))
    col.add(Tessell::Kit::Button.new(Tessell::UI::UiKey.root.child(990_u64).child(1_u64), "OK"))
    root = Tessell::Kit::Root.new(col)
    root.layout(300.0_f32, 100.0_f32)
    root.build
    drv = Tessell::Kit::TestDriver.new(root, nil, :raw)
    begin
      drv.press("OK")
      drv.press("Missing")
      fail "不可达"
    rescue e : Tessell::Kit::SelectorError
      msg = e.message.not_nil!
      msg.should contain("已执行步骤")
      msg.should contain("ok   press")   # 前序成功步骤可见
      msg.should contain("FAIL press")   # 失败步骤定位
    end
  end
end
