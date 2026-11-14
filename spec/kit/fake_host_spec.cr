require "./spec_helper"

# issue #35：Fake PlatformHost——UI 测试脱离窗口系统进 CI。
# 断言 op 流与计数（不看像素、不 sleep）：一次点击产生的帧命令数、
# measure 调用数、present/frames 对账。命中语义（只命中可见组件、
# modal 拦截）由核心 Router/HitTest 承担，FakeHost 只合成与泵送。

private class ClickProbe < Tessell::Kit::Button
  getter measures = 0

  def measure(ctx : Tessell::Kit::Context, constraints : Tessell::Constraints) : Tessell::Size
    @measures += 1
    super
  end
end

private def drive_frame(host : Tessell::Platform::FakeHost,
                        root : Tessell::Kit::Root, painter : Tessell::Kit::Painter? = nil) : Array(Tessell::Input::Event)
  events = host.pump_frame
  root.advance_time(host.clock_ms)
  events.each { |e| root.handle(e) }
  root.layout(host.viewport.size.width, host.viewport.size.height)
  root.build
  root.paint(painter.not_nil!) if painter
  host.present
  events
end

describe "Platform::FakeHost (issue #35)" do
  it "drives a full UI frame loop without any window system" do
    host = Tessell::Platform::FakeHost.new(200.0_f32, 100.0_f32)
    button = ClickProbe.new(KitSpecHelpers.key.child(1_u64), "Save")
    root = Tessell::Kit::Root.new(
      Tessell::Kit::Column.new(KitSpecHelpers.key, Tessell::Insets.all(0.0_f32), 0.0_f32)
        .tap { |col| col.add(button) })
    painter = Tessell::Kit::PaintListPainter.new

    drive_frame(host, root, painter)
    host.frames.should eq(1)
    host.presents.should eq(1)
    button.measures.should be >= 1 # 容器 arrange 触发子组件 measure
    host.pump_log.first.should eq(0)
  end

  it "tap drives exactly one activation and a bounded command count" do
    host = Tessell::Platform::FakeHost.new(200.0_f32, 100.0_f32)
    clicks = 0
    button = ClickProbe.new(KitSpecHelpers.key, "Save")
    button.on_click = -> { clicks += 1; nil }
    root = Tessell::Kit::Root.new(button)
    painter = Tessell::Kit::PaintListPainter.new

    drive_frame(host, root, painter)
    cmd_count_idle = painter.list.size
    painter.reset

    host.tap(20.0_f32, 10.0_f32)
    events = drive_frame(host, root, painter)
    events.size.should eq(2) # down + up
    clicks.should eq(1)

    painter.reset
    drive_frame(host, root, painter)
    # 点击使组件获焦：帧命令数 = 未聚焦 3 + 焦点环 1 = 4（计数契约，见 #36）
    painter.list.size.should eq(cmd_count_idle + 1)
    cmd_count_idle.should eq(3)
  end

  it "keyboard: Tab focuses, Space activates — driven purely via FakeHost" do
    host = Tessell::Platform::FakeHost.new(200.0_f32, 100.0_f32)
    clicks = 0
    button = Tessell::Kit::Button.new(KitSpecHelpers.key, "Key")
    button.on_click = -> { clicks += 1; nil }
    root = Tessell::Kit::Root.new(button)
    painter = Tessell::Kit::PaintListPainter.new

    drive_frame(host, root, painter)
    host.key(Tessell::Input::KeyCode::Tab)
    drive_frame(host, root, painter)
    root.focused_component.should be(button)

    host.key(Tessell::Input::KeyCode::Space)
    drive_frame(host, root, painter)
    clicks.should eq(1)
  end

  it "hit testing respects visibility: invisible component never receives taps" do
    host = Tessell::Platform::FakeHost.new(200.0_f32, 100.0_f32)
    clicks = 0
    button = Tessell::Kit::Button.new(KitSpecHelpers.key, "Hidden")
    button.on_click = -> { clicks += 1; nil }
    button.visible = false
    root = Tessell::Kit::Root.new(button)
    painter = Tessell::Kit::PaintListPainter.new

    drive_frame(host, root, painter)
    host.tap(20.0_f32, 10.0_f32)
    drive_frame(host, root, painter)
    clicks.should eq(0) # 不可见组件不进命中树
  end

  it "settle never sleeps: 10 frames advance virtual clock deterministically" do
    host = Tessell::Platform::FakeHost.new(200.0_f32, 100.0_f32)
    root = Tessell::Kit::Root.new(Tessell::Kit::Button.new(KitSpecHelpers.key, "x"))
    painter = Tessell::Kit::PaintListPainter.new
    10.times { drive_frame(host, root, painter) }
    host.frames.should eq(10)
    host.presents.should eq(10)
    host.clock_ms.should eq(160_i64) # 16ms × 10，虚拟时钟确定推进
  end

  it "records the op stream: event log and pump log are queryable" do
    host = Tessell::Platform::FakeHost.new(200.0_f32, 100.0_f32)
    root = Tessell::Kit::Root.new(Tessell::Kit::Button.new(KitSpecHelpers.key, "x"))
    painter = Tessell::Kit::PaintListPainter.new
    drive_frame(host, root, painter)
    host.tap(10.0_f32, 10.0_f32)
    drive_frame(host, root, painter)

    host.event_log.size.should eq(2)
    host.event_log[0].kind.should eq(Tessell::Input::Event::Kind::PointerDown)
    host.pump_log.should eq([0, 2])
  end

  it "panics on unsupported capabilities instead of pretending success" do
    host = Tessell::Platform::FakeHost.new
    expect_raises(Exception, "does not support screenshots") do
      host.screenshot("x.png")
    end
    host.close
    expect_raises(Exception, "already closed") do
      host.inject(Tessell::Input::Event.pointer_down(1.0_f32, 1.0_f32))
    end
  end
end
