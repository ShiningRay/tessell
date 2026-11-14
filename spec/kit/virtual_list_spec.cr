require "./spec_helper"

describe "Tessell::Kit::VirtualList" do
  it "emits only visible rows, not the full logical range" do
    list = Tessell::Kit::VirtualList.new(KitSpecHelpers.key, 1000, 20,
      ->(index : Int32) { "row #{index}" }, name: "rows")
    ctx = KitSpecHelpers.context
    list.arrange(ctx, Tessell::Rect.new(0.0_f32, 0.0_f32, 200.0_f32, 100.0_f32))
    buf = [] of Tessell::UI::Decl
    builder = Tessell::UI::Builder.new(buf, [] of Tessell::UI::UiKey)
    builder.reset(Tessell::UI::UiKey.root)
    list.emit(builder, ctx)

    buf.size.should be < 20
    buf[0].a11y_role.should eq(Tessell::A11y::Role::List)
    buf[0].a11y_name.should eq("rows")
    buf[0].a11y_focusable.should be_true
    row_decls = buf.select { |d| d.a11y_role == Tessell::A11y::Role::ListItem }
    row_decls.size.should eq(list.list.visible_last - list.list.visible_first + 1)
    row_decls.first.text.should eq("row 0")
  end

  it "scrolls and changes visible first row" do
    list = Tessell::Kit::VirtualList.new(KitSpecHelpers.key, 1000, 20,
      ->(index : Int32) { "row #{index}" })
    ctx = KitSpecHelpers.context
    list.arrange(ctx, Tessell::Rect.new(0.0_f32, 0.0_f32, 200.0_f32, 100.0_f32))
    list.handle(Tessell::Kit::Event.wheel(10.0_f32, 10.0_f32, 0.0_f32, -200.0_f32), ctx).should be_true
    list.list.scroll_y.should eq(200)
    list.list.visible_first.should eq(10)
  end

  it "reports logical children_count and scroll offset to a11y" do
    list = Tessell::Kit::VirtualList.new(KitSpecHelpers.key, 1000, 20,
      ->(index : Int32) { "row #{index}" }, name: "rows")
    root = Tessell::Kit::Root.new(list)
    root.layout(200.0_f32, 100.0_f32)
    root.build
    list.handle(Tessell::Kit::Event.wheel(10.0_f32, 10.0_f32, 0.0_f32, -100.0_f32), root.context)

    sink = [] of Tessell::A11y::Node
    root.a11y_emit(sink)
    container = sink.find { |n| n.role == Tessell::A11y::Role::List }.not_nil!
    container.children_count.should eq(1000)
    container.scroll_offset.should eq(100)
    sink.count { |n| n.role == Tessell::A11y::Role::ListItem }.should be < 20
  end

  it "clamps End scroll to max" do
    list = Tessell::Kit::VirtualList.new(KitSpecHelpers.key, 1000, 20,
      ->(index : Int32) { "row #{index}" })
    ctx = KitSpecHelpers.context
    list.arrange(ctx, Tessell::Rect.new(0.0_f32, 0.0_f32, 200.0_f32, 100.0_f32))
    list.on_focus_changed(true)
    list.handle(Tessell::Kit::Event.key_down(Tessell::Kit::Key::End), ctx)
    list.list.scroll_y.should eq(1000 * 20 - 100)
  end
end
