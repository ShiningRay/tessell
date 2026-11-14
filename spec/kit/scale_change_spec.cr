require "./spec_helper"

# issue #30：DPI/缩放变更不再重建 Root——Root#scale= 联动 Context#scale=
# 清测量缓存并重排，焦点与编辑态跨 DPI 保留。

describe "Root scale change (issue #30)" do
  it "updates scale and invalidates the measure cache atomically" do
    ctx = Tessell::Kit::Context.new(Tessell::Kit::Theme.light,
      Tessell::Kit::StubTextMetrics.new, 1.0_f32)
    a = ctx.measure_text("120000", 14.0_f32)
    ctx.text_cache_size.should eq(1)

    ctx.scale = 2.0_f32

    ctx.scale.should eq(2.0_f32)
    ctx.text_cache_size.should eq(0) # 旧 scale 的设备口径测量全部失效
    b = ctx.measure_text("120000", 14.0_f32)
    b.should eq(a) # 逻辑单位口径：scale=1 与 scale=2 得到相同逻辑宽度
  end

  it "keeps focus and component identity across a scale change" do
    button = Tessell::Kit::Button.new(KitSpecHelpers.key, "Save")
    root = Tessell::Kit::Root.new(button, metrics: Tessell::Kit::StubTextMetrics.new)
    root.layout(200.0_f32, 600.0_f32)
    root.build
    root.focus(button).should be_true
    bounds_before = button.bounds

    root.scale = 1.5_f32

    root.context.scale.should eq(1.5_f32)
    root.focused_component.should be(button) # 同一组件实例，焦点未丢
    button.focused.should be_true
    button.bounds.should eq(bounds_before)   # 逻辑 bounds 不随 DPI 漂移
  end

  it "keeps in-flight editing state across a scale change" do
    input = Tessell::Kit::Input.new(KitSpecHelpers.key, placeholder: "cell")
    root = Tessell::Kit::Root.new(input, metrics: Tessell::Kit::StubTextMetrics.new)
    root.layout(200.0_f32, 600.0_f32)
    root.build
    ctx = root.context
    input.handle(Tessell::Kit::Event.text_input("42"), ctx).should be_true
    root.focus(input).should be_true

    root.scale = 2.0_f32

    root.focused_component.should be(input)
    input.editing.text.should eq("42") # 编辑中内容不丢
    input.editing.text.should_not eq("")
  end

  it "does not clear the cache when the scale is unchanged" do
    ctx = Tessell::Kit::Context.new(Tessell::Kit::Theme.light,
      Tessell::Kit::StubTextMetrics.new, 1.0_f32)
    ctx.measure_text("keep", 14.0_f32)
    ctx.scale = 1.0_f32
    ctx.text_cache_size.should eq(1)
  end
end
