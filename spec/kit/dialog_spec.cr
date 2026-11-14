require "./spec_helper"

describe "Tessell::Kit::Dialog" do
  it "opens as a modal overlay, focuses first action and restores focus on Escape" do
    background = Tessell::Kit::Button.new(KitSpecHelpers.key.child(1_u64), "Background")
    content = Tessell::Kit::Text.new(KitSpecHelpers.key.child(2_u64), "This cannot be undone.")
    cancel = Tessell::Kit::Button.new(KitSpecHelpers.key.child(3_u64), "Cancel")
    confirm = Tessell::Kit::Button.new(KitSpecHelpers.key.child(4_u64), "Delete",
      Tessell::Kit::Variant::Danger)
    dialog = Tessell::Kit::Dialog.new(KitSpecHelpers.key.child(5_u64),
      "Delete item?", content, [cancel, confirm])

    root = Tessell::Kit::Root.new(background)
    root.layout(800.0_f32, 600.0_f32)
    root.build
    root.handle(Tessell::Input::Event.key_down(Tessell::Input::KeyCode::Tab))
    root.focused_component.should be(background)

    entry = root.open_dialog(dialog)
    entry.modal.should be_true
    entry.barrier.should_not be_nil
    root.build
    root.focused_component.should be(cancel)

    root.handle(Tessell::Input::Event.key_down(Tessell::Input::KeyCode::Escape)).should be_true
    root.overlay_host.empty?.should be_true
    root.focused_component.should be(background)
    dialog.on_close.should be_nil
  end

  it "calls on_close when the barrier is clicked and blocks background clicks" do
    clicks = 0
    background = Tessell::Kit::Button.new(KitSpecHelpers.key.child(1_u64), "Background")
    background.on_click = -> { clicks += 1; nil }
    content = Tessell::Kit::Text.new(KitSpecHelpers.key.child(2_u64), "Body")
    dialog = Tessell::Kit::Dialog.new(KitSpecHelpers.key.child(3_u64), "Title", content)
    closed = 0
    dialog.on_close = -> { closed += 1; nil }

    root = Tessell::Kit::Root.new(background)
    root.layout(800.0_f32, 600.0_f32)
    root.build
    root.open_dialog(dialog)
    root.build

    root.handle(Tessell::Input::Event.pointer_down(5.0_f32, 5.0_f32))
    root.handle(Tessell::Input::Event.pointer_up(5.0_f32, 5.0_f32))
    clicks.should eq(0)
    closed.should eq(1)
    root.overlay_host.empty?.should be_true
  end

  it "traps Tab inside the modal and never reaches background controls" do
    background = Tessell::Kit::Button.new(KitSpecHelpers.key.child(1_u64), "Background")
    content = Tessell::Kit::Text.new(KitSpecHelpers.key.child(2_u64), "Body")
    cancel = Tessell::Kit::Button.new(KitSpecHelpers.key.child(3_u64), "Cancel")
    confirm = Tessell::Kit::Button.new(KitSpecHelpers.key.child(4_u64), "Confirm")
    dialog = Tessell::Kit::Dialog.new(KitSpecHelpers.key.child(5_u64), "Title", content, [cancel, confirm])
    root = Tessell::Kit::Root.new(background)
    root.layout(800.0_f32, 600.0_f32)
    root.build
    root.open_dialog(dialog)
    root.build
    root.focused_component.should be(cancel)

    root.handle(Tessell::Input::Event.key_down(Tessell::Input::KeyCode::Tab))
    root.focused_component.should be(confirm)
    root.handle(Tessell::Input::Event.key_down(Tessell::Input::KeyCode::Tab))
    root.focused_component.should be(cancel)
    root.focused_component.should_not be(background)
  end
end
