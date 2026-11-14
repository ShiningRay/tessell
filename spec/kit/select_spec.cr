require "./spec_helper"

describe "Tessell::Kit::Select" do
  it "opens a popover, selects with pointer and closes" do
    changes = [] of String
    sel = Tessell::Kit::Select.new(KitSpecHelpers.key, ["Alpha", "Beta", "Gamma"],
      label: "Choice")
    sel.on_change = ->(index : Int32, value : String) { changes << value; nil }
    root = Tessell::Kit::Root.new(sel)
    root.layout(400.0_f32, 300.0_f32)
    root.build

    x = sel.bounds.origin.x + sel.bounds.size.width / 2.0_f32
    y = sel.bounds.origin.y + sel.bounds.size.height / 2.0_f32
    root.handle(Tessell::Input::Event.pointer_down(x, y)).should be_true
    root.handle(Tessell::Input::Event.pointer_up(x, y)).should be_true
    sel.open.should be_true
    root.overlay_host.entries.size.should eq(1)
    root.overlay_host.top.not_nil!.kind.should eq(Tessell::Kit::OverlayKind::Popover)
    root.build
    root.focused_component.should be_a(Tessell::Kit::SelectPopup)

    popup = root.overlay_host.top.not_nil!.component.as(Tessell::Kit::SelectPopup)
    row = popup.row_rect(1)
    cx = row.origin.x + row.size.width / 2.0_f32
    cy = row.origin.y + row.size.height / 2.0_f32
    root.handle(Tessell::Input::Event.pointer_down(cx, cy))
    root.handle(Tessell::Input::Event.pointer_up(cx, cy))

    changes.should eq(["Beta"])
    sel.selected_index.should eq(1)
    sel.selected_text.should eq("Beta")
    sel.open.should be_false
    root.overlay_host.empty?.should be_true
  end

  it "supports keyboard open and selection" do
    changes = [] of String
    sel = Tessell::Kit::Select.new(KitSpecHelpers.key, ["One", "Two", "Three"])
    sel.on_change = ->(index : Int32, value : String) { changes << value; nil }
    root = Tessell::Kit::Root.new(sel)
    root.layout(400.0_f32, 300.0_f32)
    root.build
    root.handle(Tessell::Input::Event.key_down(Tessell::Input::KeyCode::Tab))
    root.focused_component.should be(sel)

    root.handle(Tessell::Input::Event.key_down(Tessell::Input::KeyCode::Enter)).should be_true
    sel.open.should be_true
    root.build
    root.focused_component.should be_a(Tessell::Kit::SelectPopup)
    root.handle(Tessell::Input::Event.key_down(Tessell::Input::KeyCode::Down))
    root.handle(Tessell::Input::Event.key_down(Tessell::Input::KeyCode::Enter)).should be_true

    changes.should eq(["Two"])
    sel.selected_index.should eq(1)
    root.overlay_host.empty?.should be_true
  end

  it "closes on Escape and outside click" do
    sel = Tessell::Kit::Select.new(KitSpecHelpers.key, ["A", "B"])
    root = Tessell::Kit::Root.new(sel)
    root.layout(400.0_f32, 300.0_f32)
    root.build

    root.handle(Tessell::Input::Event.key_down(Tessell::Input::KeyCode::Tab))
    root.handle(Tessell::Input::Event.key_down(Tessell::Input::KeyCode::Enter))
    root.build
    root.handle(Tessell::Input::Event.key_down(Tessell::Input::KeyCode::Escape))
    sel.open.should be_false
    root.overlay_host.empty?.should be_true

    root.handle(Tessell::Input::Event.key_down(Tessell::Input::KeyCode::Enter))
    root.build
    root.handle(Tessell::Input::Event.pointer_down(5.0_f32, 5.0_f32))
    sel.open.should be_false
    root.overlay_host.empty?.should be_true
  end

  it "exposes ComboBox/ListBox/Option a11y metadata" do
    sel = Tessell::Kit::Select.new(KitSpecHelpers.key, ["A", "B"], label: "Choice")
    root = Tessell::Kit::Root.new(sel)
    root.layout(400.0_f32, 300.0_f32)
    root.build
    root.handle(Tessell::Input::Event.key_down(Tessell::Input::KeyCode::Tab))
    root.handle(Tessell::Input::Event.key_down(Tessell::Input::KeyCode::Enter))
    root.build

    sink = [] of Tessell::A11y::Node
    root.a11y_emit(sink)
    sink.any? { |n| n.role == Tessell::A11y::Role::ComboBox && n.name == "Choice" }.should be_true
    sink.any? { |n| n.role == Tessell::A11y::Role::ListBox }.should be_true
    sink.count { |n| n.role == Tessell::A11y::Role::Option }.should eq(2)
  end
end
