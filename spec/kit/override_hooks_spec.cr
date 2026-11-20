require "./spec_helper"

# issue #66：内置组件可覆写点契约化——子类覆写单个切面，其余行为
# （焦点环/disabled 分支/命中/激活状态机）由骨架保证，op 流断言锁
# （AGENTS #10：op 流/计数 > 像素）。覆写不新增每帧分配（hook 虚分派）。

# 覆写背景切面的按钮：其余切面走内置实现
private class AccentButton < Tessell::Kit::Button
  getter extra_painted : Int32 = 0

  def draw_background(p : Tessell::Kit::Painter, ctx : Tessell::Kit::Context,
                      colors : Tessell::Kit::ButtonColors, radius : Float32) : Nil
    super
    p.fill_rect(@bounds, 0x2200ff00_u32) # 叠加一层标记（op 流可断言）
    @extra_painted += 1
  end

  # 改命中区域：只认左半边
  def inside?(x : Float32, y : Float32) : Bool
    half = Tessell::Rect.new(@bounds.origin.x, @bounds.origin.y,
      @bounds.size.width / 2.0_f32, @bounds.size.height)
    half.contains?(Tessell::Point.new(x, y))
  end
end

# 覆写内容切面的按钮：记录并委托内置（disabled 分支仍在骨架）
private class LabelProbeButton < Tessell::Kit::Button
  getter content_calls : Int32 = 0

  def draw_content(p : Tessell::Kit::Painter, ctx : Tessell::Kit::Context,
                   colors : Tessell::Kit::ButtonColors, fs : Float32) : Nil
    @content_calls += 1
    super
  end
end

private def paint_ops(component : Tessell::Kit::Component) : Array(Tessell::Kit::PaintKind)
  painter = Tessell::Kit::PaintListPainter.new
  ctx = KitSpecHelpers.context
  component.paint(painter, ctx)
  painter.list.to_a.map(&.kind)
end

describe "内置组件可覆写切面（issue #66）" do
  it "覆写 draw_background：叠加 op 出现，内置背景 op 仍在（super 链）" do
    btn = AccentButton.new(KitSpecHelpers.key, "Hooked")
    ctx = KitSpecHelpers.context
    btn.arrange(ctx, Tessell::Rect.new(0.0_f32, 0.0_f32, 100.0_f32, 32.0_f32))
    kinds = paint_ops(btn)
    kinds.count(Tessell::Kit::PaintKind::FillRect).should eq(1)      # 覆写叠加
    kinds.count(Tessell::Kit::PaintKind::FillRoundRect).should eq(1) # 内置背景（super）
    btn.extra_painted.should eq(1)
  end

  it "焦点环由骨架保留：覆写背景后 focus 环 op 不丢" do
    btn = AccentButton.new(KitSpecHelpers.key, "Hooked")
    ctx = KitSpecHelpers.context
    btn.arrange(ctx, Tessell::Rect.new(0.0_f32, 0.0_f32, 100.0_f32, 32.0_f32))
    btn.on_focus_changed(true)
    kinds = paint_ops(btn)
    # 焦点环 = 第二次 StrokeRoundRect（背景边框 + 焦点环）
    kinds.count(Tessell::Kit::PaintKind::StrokeRoundRect).should eq(2)
  end

  it "disabled 分支不丢：覆写内容计数在 enabled=false 时仍走骨架路径" do
    btn = LabelProbeButton.new(KitSpecHelpers.key, "Hi")
    ctx = KitSpecHelpers.context
    btn.arrange(ctx, Tessell::Rect.new(0.0_f32, 0.0_f32, 100.0_f32, 32.0_f32))
    paint_ops(btn)
    btn.content_calls.should eq(1)
    # disabled：paint_token 的 disabled 位仍由内置口径翻转
    t_on = btn.paint_token
    btn.enabled = false
    t_off = btn.paint_token
    ((t_on ^ t_off) & (1_u32 << 11)).should be > 0
  end

  it "覆写 inside?：命中区域收窄，激活状态机不变（区域外抬起不触发）" do
    btn = AccentButton.new(KitSpecHelpers.key, "Half")
    clicks = 0
    btn.on_click = ->{ clicks += 1 }
    ctx = KitSpecHelpers.context
    btn.arrange(ctx, Tessell::Rect.new(0.0_f32, 0.0_f32, 100.0_f32, 32.0_f32))
    b = btn.bounds
    right = Tessell::Point.new(b.origin.x + b.size.width * 0.75_f32,
      b.origin.y + b.size.height / 2.0_f32)
    btn.handle(Tessell::Kit::Event.pointer(Tessell::Kit::Event::Kind::PointerDown,
      right.x, right.y), ctx).should be_false
    btn.handle(Tessell::Kit::Event.pointer(Tessell::Kit::Event::Kind::PointerUp,
      right.x, right.y), ctx).should be_false
    clicks.should eq(0)
    left = Tessell::Point.new(b.origin.x + b.size.width * 0.25_f32,
      b.origin.y + b.size.height / 2.0_f32)
    btn.handle(Tessell::Kit::Event.pointer(Tessell::Kit::Event::Kind::PointerDown,
      left.x, left.y), ctx).should be_true
    btn.handle(Tessell::Kit::Event.pointer(Tessell::Kit::Event::Kind::PointerUp,
      left.x, left.y), ctx).should be_true
    clicks.should eq(1)
  end

  it "emit 仍由内置实现发自身 key（hook 只改绘制与行为）" do
    col = Tessell::Kit::Column.new(KitSpecHelpers.key)
    btn = LabelProbeButton.new(KitSpecHelpers.key.child(1_u64), "Keyed")
    col.add(btn)
    root = Tessell::Kit::Root.new(col)
    root.layout(300.0_f32, 100.0_f32)
    root.build
    root.build # 第二帧：声明数稳定（覆写不影响 emit 契约）
    root.decl_count.should be >= 1
    root.pool.map[btn.key]?.should_not be_nil
    btn.a11y_role.should eq(Tessell::A11y::Role::Button)
    btn.a11y_name.should eq("Keyed")
  end

  it "Checkbox 覆写 toggle：激活链路完整（checked 翻转 + 覆写计数）" do
    box = HookedCheckbox.new(KitSpecHelpers.key, "Agree")
    ctx = KitSpecHelpers.context
    box.arrange(ctx, Tessell::Rect.new(0.0_f32, 0.0_f32, 140.0_f32, 32.0_f32))
    box.handle(Tessell::Kit::Event.pointer(Tessell::Kit::Event::Kind::PointerDown,
      5.0_f32, 5.0_f32), ctx).should be_true
    box.handle(Tessell::Kit::Event.pointer(Tessell::Kit::Event::Kind::PointerUp,
      5.0_f32, 5.0_f32), ctx).should be_true
    box.checked.should be_true
    box.toggles.should eq(1)
  end
end

private class HookedCheckbox < Tessell::Kit::Checkbox
  getter toggles : Int32 = 0

  def toggle : Nil
    super
    @toggles += 1
  end
end
