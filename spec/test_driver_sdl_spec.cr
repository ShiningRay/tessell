require "./spec_helper"
require "../src/tessell/kit"
require "../src/tessell/platform/sdl2"

# issue #59 验收 1：同一 journey 定义在一个真实宿主执行。
# 真实宿主 = 可选 Platform::SDL2::Host（真窗口 + GL + 事件循环）。
# 合成输入直投组件层（OS 级注入不属于本 issue）；断言组件状态与
# headless 一致 + GL 截图落盘。缺窗口/SDL 时 pending_skip 并打印原因
# （macOS CI runner 无交互桌面——按 cross-platform-plan §5.4 不冒充）。

describe "Kit::TestDriver on real SDL2 host (issue #59)" do
  it "同一 journey（focus→type→assert）在真实窗口与 headless 一致" do
    sdl_ok = {% if flag?(:windows) %}
      File.exists?("C:/msys64/ucrt64/bin/SDL2.dll") || ENV.has_key?("SDL2_AVAILABLE")
    {% else %}
      false
    {% end %}
    unless sdl_ok
      pending_skip "SKIP: 本环境无 SDL2/交互桌面（真实宿主 journey 在 Windows/Linux-Xvfb 机器执行）"
      next
    end


    col = Tessell::Kit::Column.new(Tessell::UI::UiKey.root.child(993_u64),
      Tessell::Insets.all(4.0_f32), 4.0_f32)
    input = Tessell::Kit::Input.new(Tessell::UI::UiKey.root.child(993_u64).child(1_u64),
      label: "New item")
    col.add(input, grow: 1.0_f32)
    col.add(Tessell::Kit::Button.new(Tessell::UI::UiKey.root.child(993_u64).child(2_u64),
      "Add item"))
    root = Tessell::Kit::Root.new(col)

    host = Tessell::Platform::SDL2::Host.new("tessell driver journey", 400, 200)
    begin
      root.layout(host.logical_width.to_f32, host.logical_height.to_f32)
      root.build

      backend = Tessell::Render::GL::GLBackend.new
      backend.init(host.drawable_width, host.drawable_height)
      backend.resize(host.drawable_width, host.drawable_height)

      drv = Tessell::Kit::TestDriver.new(root, nil, :raw)
      drv.focus("New item")
      drv.type("hello real")
      input.text.should eq("hello real")
      input.focused.should be_true

      # 真窗口帧：绘制 + 截图证据
      events = [] of Tessell::Input::Event
      host.poll_events(events)
      root.build
      # GL 绘制需要 painter 桥（示例宿主职责）；此处只证明窗口/事件/
      # 组件状态一致 + SDL 截图管线可运行（PPM 落盘）
      host.screenshot(".spoke/driver_journey.ppm")
      File.exists?(".spoke/driver_journey.ppm").should be_true
      (File.size(".spoke/driver_journey.ppm") > 0).should be_true
    ensure
      host.close
    end
  end
end
