require "spec"
require "../../examples/apps/text_editor_app"

private def editor_context : Tessell::Kit::Context
  Tessell::Kit::Context.new(Tessell::Kit::Theme.light, Tessell::Kit::StubTextMetrics.new)
end

private def arrange_editor(editor : TessellApps::EditorView) : Tessell::Kit::Context
  ctx = editor_context
  editor.arrange(ctx, Tessell::Rect.new(0.0_f32, 0.0_f32, 480.0_f32, 260.0_f32))
  ctx
end

describe "TessellApps::EditorView" do
  it "inserts text and newlines with change callbacks" do
    changes = [] of String
    editor = TessellApps::EditorView.new(Tessell::UI::UiKey.root.child(1_u64), "ab")
    editor.on_change = ->(text : String) { changes << text; nil }
    ctx = arrange_editor(editor)
    editor.editing.set_cursor(1)

    editor.handle(Tessell::Kit::Event.text_input("X"), ctx).should be_true
    editor.text.should eq("aXb")
    editor.handle(Tessell::Kit::Event.key_down(Tessell::Kit::Key::Enter), ctx).should be_true
    editor.text.should eq("aX\nb")
    changes.size.should eq(2)
  end

  it "moves by line with Home/End and Up/Down" do
    editor = TessellApps::EditorView.new(Tessell::UI::UiKey.root.child(1_u64), "abc\ndef")
    ctx = arrange_editor(editor)
    editor.editing.set_cursor(0)

    editor.handle(Tessell::Kit::Event.key_down(Tessell::Kit::Key::End), ctx)
    editor.editing.cursor.should eq(3)
    editor.handle(Tessell::Kit::Event.key_down(Tessell::Kit::Key::Down), ctx)
    editor.editing.cursor.should eq(7)
    editor.handle(Tessell::Kit::Event.key_down(Tessell::Kit::Key::Home), ctx)
    editor.editing.cursor.should eq(4)
    editor.handle(Tessell::Kit::Event.key_down(Tessell::Kit::Key::End), ctx)
    editor.editing.cursor.should eq(7)
    editor.handle(Tessell::Kit::Event.key_down(Tessell::Kit::Key::Up), ctx)
    editor.editing.cursor.should eq(3)
  end

  it "extends selection with Shift and copies through the clipboard" do
    clipboard = Tessell::Kit::MemoryClipboard.new
    editor = TessellApps::EditorView.new(Tessell::UI::UiKey.root.child(1_u64), "hello\nworld")
    editor.clipboard = clipboard
    ctx = arrange_editor(editor)
    ctrl = Tessell::Kit::Modifiers.new(ctrl: true)

    editor.handle(Tessell::Kit::Event.key_down(Tessell::Kit::Key::KeyA, ctrl), ctx)
    editor.editing.selected_text.should eq("hello\nworld")
    editor.handle(Tessell::Kit::Event.key_down(Tessell::Kit::Key::KeyC, ctrl), ctx)
    clipboard.get.should eq("hello\nworld")

    editor.editing.move_end
    editor.handle(Tessell::Kit::Event.key_down(Tessell::Kit::Key::Left,
      Tessell::Kit::Modifiers.new(shift: true)), ctx)
    editor.editing.selected_text.should eq("d")
  end

  it "deletes newline with Backspace at line start" do
    editor = TessellApps::EditorView.new(Tessell::UI::UiKey.root.child(1_u64), "a\nb")
    ctx = arrange_editor(editor)
    editor.editing.set_cursor(2)
    editor.handle(Tessell::Kit::Event.key_down(Tessell::Kit::Key::Backspace), ctx)
    editor.text.should eq("ab")
    editor.editing.cursor.should eq(1)
  end
end

describe "TessellApps::TextEditorApp" do
  it "saves and reopens a file" do
    path = File.tempname("tessell-editor-spec", ".txt")
    File.delete(path) if File.exists?(path)
    app = TessellApps::TextEditorApp.new(path, initial_text: "")
    app.editor.set_text("hello\nworld")
    app.save_file
    File.exists?(path).should be_true
    app.new_file
    app.editor.text.should eq("")
    app.open_file
    app.editor.text.should eq("hello\nworld")
    File.delete(path)
  end

  it "builds a Root with editor a11y metadata and toolbar buttons" do
    path = File.tempname("tessell-editor-root", ".txt")
    app = TessellApps::TextEditorApp.new(path, initial_text: "hello")
    root = app.build_root(Tessell::Kit::StubTextMetrics.new,
      Tessell::Kit::MemoryClipboard.new)
    root.layout(900.0_f32, 680.0_f32)
    root.build
    sink = [] of Tessell::A11y::Node
    root.a11y_emit(sink)
    editor = sink.find { |n| n.role == Tessell::A11y::Role::TextField }
    editor.should_not be_nil
    editor.not_nil!.name.should eq("Editor")
    editor.not_nil!.value.should eq("hello")
    sink.count { |n| n.role == Tessell::A11y::Role::Button }.should eq(3)
  end
end
