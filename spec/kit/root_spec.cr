require "./spec_helper"

describe "Tessell::Kit::Root" do
  it "builds declarations into retained nodes and emits a11y metadata" do
    button = Tessell::Kit::Button.new(KitSpecHelpers.key, "Save", Tessell::Kit::Variant::Primary)
    root = Tessell::Kit::Root.new(button)
    root.layout(200.0_f32, 100.0_f32)
    root.build

    node = root.pool.map[button.key]?
    node.should_not be_nil
    node.not_nil!.bounds.should eq(Tessell::Rect.new(0.0_f32, 0.0_f32, 200.0_f32, 100.0_f32))

    sink = [] of Tessell::A11y::Node
    root.a11y_emit(sink).should be >= 1
    sink.any? { |n| n.role == Tessell::A11y::Role::Button && n.name == "Save" }.should be_true
  end

  it "routes pointer activation through core Router" do
    clicks = 0
    button = Tessell::Kit::Button.new(KitSpecHelpers.key, "Save")
    button.on_click = -> { clicks += 1; nil }
    root = Tessell::Kit::Root.new(button)
    root.layout(200.0_f32, 100.0_f32)
    root.build

    root.handle(Tessell::Input::Event.pointer_down(20.0_f32, 20.0_f32)).should be_true
    root.handle(Tessell::Input::Event.pointer_up(20.0_f32, 20.0_f32)).should be_true
    clicks.should eq(1)
  end

  it "moves focus with Tab and marks the component focused" do
    button = Tessell::Kit::Button.new(KitSpecHelpers.key, "Save")
    root = Tessell::Kit::Root.new(button)
    root.layout(200.0_f32, 100.0_f32)
    root.build

    root.handle(Tessell::Input::Event.key_down(Tessell::Input::KeyCode::Tab)).should be_true
    root.focused_component.should be(button)
    button.focused.should be_true
  end

  it "skips disabled components in the focus ring" do
    button = Tessell::Kit::Button.new(KitSpecHelpers.key, "Save", enabled: false)
    root = Tessell::Kit::Root.new(button)
    root.layout(200.0_f32, 100.0_f32)
    root.build

    root.handle(Tessell::Input::Event.key_down(Tessell::Input::KeyCode::Tab))
    root.focused_component.should be_nil
  end

  it "routes clicks and Tab focus across a Column of components" do
    col = Tessell::Kit::Column.new(KitSpecHelpers.key, Tessell::Insets.all(8.0_f32), 4.0_f32)
    first = Tessell::Kit::Button.new(KitSpecHelpers.key.child(1_u64), "First")
    second = Tessell::Kit::Button.new(KitSpecHelpers.key.child(2_u64), "Second")
    first_clicks = 0
    second_clicks = 0
    first.on_click = -> { first_clicks += 1; nil }
    second.on_click = -> { second_clicks += 1; nil }
    col.add(first)
    col.add(second)

    root = Tessell::Kit::Root.new(col)
    root.layout(200.0_f32, 200.0_f32)
    root.build

    root.handle(Tessell::Input::Event.key_down(Tessell::Input::KeyCode::Tab)).should be_true
    root.focused_component.should be(first)
    root.handle(Tessell::Input::Event.key_down(Tessell::Input::KeyCode::Tab)).should be_true
    root.focused_component.should be(second)

    center = second.bounds.origin.y + second.bounds.size.height / 2.0_f32
    root.handle(Tessell::Input::Event.pointer_down(100.0_f32, center))
    root.handle(Tessell::Input::Event.pointer_up(100.0_f32, center))
    second_clicks.should eq(1)
    first_clicks.should eq(0)
  end

  it "switches theme through the root context" do
    button = Tessell::Kit::Button.new(KitSpecHelpers.key, "Save")
    root = Tessell::Kit::Root.new(button)
    root.layout(200.0_f32, 100.0_f32)
    root.build
    root.theme = Tessell::Kit::Theme.dark
    root.theme.dark.should be_true
    root.context.theme.dark.should be_true
  end

  it "paints the content through a Painter" do
    button = Tessell::Kit::Button.new(KitSpecHelpers.key, "Save")
    root = Tessell::Kit::Root.new(button)
    root.layout(200.0_f32, 100.0_f32)
    root.build
    painter = Tessell::Kit::PaintListPainter.new
    root.paint(painter)
    painter.list.size.should be > 0
    painter.list.clip_depth.should eq(0)
  end
end
