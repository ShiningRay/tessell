require "./spec_helper"

private def make_input(text : String = "", label : String = "Name",
                       placeholder : String = "Type here",
                       read_only : Bool = false) : Tessell::Kit::Input
  Tessell::Kit::Input.new(KitSpecHelpers.key, text, placeholder, label,
    read_only: read_only)
end

private def arrange_input(input : Tessell::Kit::Input) : Nil
  ctx = KitSpecHelpers.context
  size = input.measure(ctx, Tessell::Constraints.new(0.0_f32, 240.0_f32, 0.0_f32, 200.0_f32))
  input.arrange(ctx, Tessell::Rect.new(0.0_f32, 0.0_f32, size.width, size.height))
end

describe "Tessell::Kit::Input" do
  it "measures label + field + optional error and emits TextField metadata" do
    input = make_input
    ctx = KitSpecHelpers.context
    size = input.measure(ctx, Tessell::Constraints.new(0.0_f32, 240.0_f32, 0.0_f32, 200.0_f32))
    size.height.should be > ctx.theme.control_height(Tessell::Kit::ControlSize::Medium)
    arrange_input(input)

    buf = [] of Tessell::UI::Decl
    builder = Tessell::UI::Builder.new(buf, [] of Tessell::UI::UiKey)
    builder.reset(Tessell::UI::UiKey.root)
    input.emit(builder, ctx)
    buf[0].a11y_role.should eq(Tessell::A11y::Role::TextField)
    buf[0].a11y_name.should eq("Name")
    buf[0].a11y_focusable.should be_true
  end

  it "inserts text and notifies once per mutation" do
    changes = [] of String
    input = make_input
    input.on_change = ->(value : String) { changes << value; nil }
    arrange_input(input)
    ctx = KitSpecHelpers.context

    input.handle(Tessell::Kit::Event.text_input("a"), ctx).should be_true
    input.handle(Tessell::Kit::Event.text_input("b"), ctx).should be_true
    input.text.should eq("ab")
    changes.should eq(["a", "ab"])
    input.handle(Tessell::Kit::Event.key_down(Tessell::Kit::Key::Backspace), ctx).should be_true
    input.text.should eq("a")
    changes.should eq(["a", "ab", "a"])
  end

  it "moves by grapheme and selects with Shift" do
    input = make_input("a👍🏽b")
    arrange_input(input)
    ctx = KitSpecHelpers.context
    input.on_focus_changed(true)

    input.handle(Tessell::Kit::Event.key_down(Tessell::Kit::Key::Left), ctx)
    input.editing.cursor.should eq(9)
    input.handle(Tessell::Kit::Event.key_down(Tessell::Kit::Key::Left,
      Tessell::Kit::Modifiers.new(shift: true)), ctx)
    input.editing.selected_text.should eq("👍🏽")
    input.handle(Tessell::Kit::Event.key_down(Tessell::Kit::Key::Backspace), ctx)
    input.text.should eq("ab")
  end

  it "copies and pastes through a shared clipboard" do
    clipboard = Tessell::Kit::MemoryClipboard.new
    source = make_input("hello")
    source.clipboard = clipboard
    arrange_input(source)
    ctx = KitSpecHelpers.context
    ctrl = Tessell::Kit::Modifiers.new(ctrl: true)

    source.handle(Tessell::Kit::Event.key_down(Tessell::Kit::Key::KeyA, ctrl), ctx).should be_true
    source.handle(Tessell::Kit::Event.key_down(Tessell::Kit::Key::KeyC, ctrl), ctx).should be_true
    clipboard.get.should eq("hello")

    target = make_input
    target.clipboard = clipboard
    arrange_input(target)
    target.handle(Tessell::Kit::Event.key_down(Tessell::Kit::Key::KeyV, ctrl), ctx).should be_true
    target.text.should eq("hello")
  end

  it "submits on Enter" do
    submitted = [] of String
    input = make_input("ok")
    input.on_submit = ->(value : String) { submitted << value; nil }
    arrange_input(input)
    ctx = KitSpecHelpers.context
    input.handle(Tessell::Kit::Event.key_down(Tessell::Kit::Key::Enter), ctx).should be_true
    submitted.should eq(["ok"])
  end

  it "blocks edits in read-only mode but keeps selection and copy" do
    clipboard = Tessell::Kit::MemoryClipboard.new
    input = make_input("read", read_only: true)
    input.clipboard = clipboard
    arrange_input(input)
    ctx = KitSpecHelpers.context
    input.handle(Tessell::Kit::Event.text_input("x"), ctx).should be_false
    input.text.should eq("read")

    input.handle(Tessell::Kit::Event.key_down(Tessell::Kit::Key::KeyA,
      Tessell::Kit::Modifiers.new(ctrl: true)), ctx)
    input.handle(Tessell::Kit::Event.key_down(Tessell::Kit::Key::KeyC,
      Tessell::Kit::Modifiers.new(ctrl: true)), ctx)
    clipboard.get.should eq("read")
  end

  it "ignores input when disabled and is not focusable" do
    input = Tessell::Kit::Input.new(KitSpecHelpers.key, "", "", "Name", enabled: false)
    input.focusable?.should be_false
    arrange_input(input)
    ctx = KitSpecHelpers.context
    input.handle(Tessell::Kit::Event.text_input("x"), ctx).should be_false
    input.text.should eq("")
  end

  it "sets the caret from a pointer click" do
    input = make_input("abcdef")
    arrange_input(input)
    ctx = KitSpecHelpers.context
    area = input.text_area(ctx)
    click_x = area.origin.x + ctx.measure_text("ab", ctx.theme.font_size(Tessell::Kit::ControlSize::Medium)).width
    input.handle(Tessell::Kit::Event.pointer(Tessell::Kit::Event::Kind::PointerDown, click_x, area.origin.y + 5.0_f32), ctx)
    input.editing.cursor.should be >= 1
    input.editing.cursor.should be <= 3
  end

  it "paints placeholder, selection, caret and invalid error" do
    ctx = KitSpecHelpers.context
    input = make_input("", "Name", "Type here")
    input.invalid = true
    input.error_text = "Required"
    arrange_input(input)
    painter = Tessell::Kit::PaintListPainter.new
    input.paint(painter, ctx)
    texts = painter.list.to_a.select { |cmd| cmd.kind == Tessell::Kit::PaintKind::Text }.map(&.text)
    texts.should contain("Type here")
    texts.should contain("Required")

    input.set_text("abc")
    input.on_focus_changed(true)
    input.editing.set_cursor(0)
    input.editing.set_cursor(2, extending: true)
    painter = Tessell::Kit::PaintListPainter.new
    input.paint(painter, ctx)
    painter.list.to_a.map(&.kind).should contain(Tessell::Kit::PaintKind::Line)
    painter.list.to_a.any? { |cmd| cmd.color == ctx.theme.palette.selection }.should be_true
  end

  it "previews preedit and commits it into the document" do
    changes = [] of String
    input = make_input("A")
    input.on_change = ->(value : String) { changes << value; nil }
    arrange_input(input)
    ctx = KitSpecHelpers.context
    input.set_preedit("ni")
    input.text.should eq("A")
    painter = Tessell::Kit::PaintListPainter.new
    input.paint(painter, ctx)
    painter.list.to_a.any? { |cmd| cmd.kind == Tessell::Kit::PaintKind::Text && cmd.text == "ni" }.should be_true

    input.commit_preedit.should be_true
    input.text.should eq("Ani")
    changes.should eq(["Ani"])
  end

  it "receives text through Root focus routing" do
    input = make_input
    root = Tessell::Kit::Root.new(input)
    root.layout(320.0_f32, 160.0_f32)
    root.build
    root.handle(Tessell::Input::Event.key_down(Tessell::Input::KeyCode::Tab))
    root.focused_component.should be(input)
    root.handle(Tessell::Input::Event.text_input("x")).should be_true
    input.text.should eq("x")
  end
end
