require "spec"
require "tessell/kit"
require "../src/tessell-badge"

# 第三方组件契约门槛模板（issue #68）：新增组件至少具备
# docs/kit/component-contract.md「测试门槛」六条中的四条——
# 状态与事件、measure/arrange + a11y 元数据、PaintList op、dispose 释放。
# 第三方组件不得读窗口/GPU/平台 API（ Painter 边界）。

private def ctx : Tessell::Kit::Context
  Tessell::Kit::Context.new(Tessell::Kit::Theme.light,
    Tessell::Kit::StubTextMetrics.new)
end

describe TessellBadge::Badge do
  it "measure 按文本宽度收紧且尊重约束" do
    badge = TessellBadge::Badge.new(Tessell::UI::UiKey.root.child(1_u64), "ok")
    s = badge.measure(ctx, Tessell::Constraints.new(0.0_f32, 200.0_f32))
    s.height.should eq(20.0_f32)
    s.width.should be > 0.0_f32
    s.width.should be < 200.0_f32
    # 窄约束钳制
    narrow = badge.measure(ctx, Tessell::Constraints.new(0.0_f32, 10.0_f32))
    narrow.width.should eq(10.0_f32)
  end

  it "emit 携带 a11y 元数据；visible 双守卫（不可见不进命中树）" do
    badge = TessellBadge::Badge.new(Tessell::UI::UiKey.root.child(1_u64), "v1.2")
    badge.arrange(ctx, Tessell::Rect.new(0.0_f32, 0.0_f32, 60.0_f32, 20.0_f32))
    root = Tessell::Kit::Root.new(badge)
    root.layout(100.0_f32, 40.0_f32)
    root.build
    root.pool.map[badge.key]?.should_not be_nil
    badge.a11y_role.should eq(Tessell::A11y::Role::Text)
    badge.a11y_name.should eq("v1.2")

    badge.visible = false
    root.build
    # 用户所见口径：不可见组件不进 a11y 树（emit 即存在）
    sink = [] of Tessell::A11y::Node
    root.a11y_emit(sink)
    sink.any? { |n| n.name == "v1.2" }.should be_false
  end

  it "PaintList op 流：背景圆角 + 文本成对出现（裁切成对由容器保证）" do
    badge = TessellBadge::Badge.new(Tessell::UI::UiKey.root.child(1_u64), "op")
    badge.arrange(ctx, Tessell::Rect.new(0.0_f32, 0.0_f32, 60.0_f32, 20.0_f32))
    painter = Tessell::Kit::PaintListPainter.new
    badge.paint(painter, ctx)
    kinds = painter.list.to_a.map(&.kind)
    kinds.should contain(Tessell::Kit::PaintKind::FillRoundRect)
    kinds.should contain(Tessell::Kit::PaintKind::Text)
  end

  it "dispose 释放契约（AGENTS #9：持有资源必须有释放 spec）" do
    badge = TessellBadge::Badge.new(Tessell::UI::UiKey.root.child(1_u64), "x")
    badge.disposed.should be_false
    badge.dispose
    badge.disposed.should be_true
  end

  it "主题 token：accent 与 muted 两种 tone 产出不同背景色 op" do
    a = TessellBadge::Badge.new(Tessell::UI::UiKey.root.child(1_u64), "a", :accent)
    m = TessellBadge::Badge.new(Tessell::UI::UiKey.root.child(2_u64), "b", :muted)
    c = ctx
    a.arrange(c, Tessell::Rect.new(0.0_f32, 0.0_f32, 60.0_f32, 20.0_f32))
    m.arrange(c, Tessell::Rect.new(0.0_f32, 0.0_f32, 60.0_f32, 20.0_f32))
    pa = Tessell::Kit::PaintListPainter.new
    a.paint(pa, c)
    pm = Tessell::Kit::PaintListPainter.new
    m.paint(pm, c)
    bg_a = pa.list.to_a.find { |cmd| cmd.kind == Tessell::Kit::PaintKind::FillRoundRect }.not_nil!
    bg_m = pm.list.to_a.find { |cmd| cmd.kind == Tessell::Kit::PaintKind::FillRoundRect }.not_nil!
    bg_a.color.should_not eq(bg_m.color)
  end
end
