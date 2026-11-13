require "./spec_helper"
require "../src/tessell/input/router"
require "../src/tessell/input/event"
require "spec"

include Tessell
include Tessell::Input

private def build_tree : {Node, Node, Node}
  root = Node.new("root", Rect.new(0.0_f32, 0.0_f32, 100.0_f32, 100.0_f32))
  a = Node.new("a", Rect.new(0.0_f32, 0.0_f32, 50.0_f32, 50.0_f32))
  b = Node.new("b", Rect.new(0.0_f32, 50.0_f32, 50.0_f32, 50.0_f32))
  root.add_child(a)
  root.add_child(b)
  {root, a, b}
end

# D6 (M4-WP1 S3): every event type changes hover/pressed/focus ONLY through
# Input::Router#handle. No second writer exists:
#   grep -n '@hover *=' src/tessell      -> only input/router.cr:24,30,44
#   grep -n '@pressed *=' src/tessell    -> only input/router.cr:25,31,41,48
#   grep -n '@focused *=' src/tessell    -> only input/focus.cr:19,24,29,38,42,76
# FocusManager state is reached from the event path exclusively via Router
# (#handle -> focus_manager.focus / blur / focused). The only non-event writer
# is the app's initial programmatic focus at examples/app_demo.cr init
# (`@router.focus_manager.focus(top)`), which is startup wiring, not an event
# path; this suite asserts the event semantics.
describe "Router single entry (D6)" do
  it "pointer down focuses and presses the deepest hit; up clears pressed" do
    root, a, _b = build_tree
    r = Router.new
    r.handle(Event.pointer_down(10.0_f32, 10.0_f32), root).should eq a
    # down sets pressed + focus; hover is only written by PointerMove
    r.hover.should be_nil
    r.pressed.should eq a
    r.focus_manager.focused.should eq a
    r.handle(Event.pointer_up(10.0_f32, 10.0_f32), root).should eq a
    r.pressed.should be_nil
    # focus survives the gesture
    r.focus_manager.focused.should eq a
  end

  it "pointer move sets hover without touching focus or pressed" do
    root, a, _b = build_tree
    r = Router.new
    r.handle(Event.pointer_move(10.0_f32, 10.0_f32), root).should eq a
    r.hover.should eq a
    r.pressed.should be_nil
    r.focus_manager.focused.should be_nil
    r.handle(Event.pointer_move(10.0_f32, 60.0_f32), root).should eq _b
    r.hover.should eq _b
  end

  it "wheel targets hover first, then focus when there is no hover" do
    root, a, b = build_tree
    r = Router.new
    r.handle(Event.pointer_move(10.0_f32, 10.0_f32), root)
    r.handle(Event.wheel(0.0_f32, 0.0_f32), root).should eq a
    # move outside root bounds clears hover (deepest hit is nil)
    r.handle(Event.pointer_move(200.0_f32, 200.0_f32), root)
    r.hover.should be_nil
    r.focus_manager.focus(b)
    r.handle(Event.wheel(0.0_f32, 0.0_f32), root).should eq b
  end

  it "key/text events go to the focused node; blur clears focus" do
    root, a, _b = build_tree
    r = Router.new
    r.handle(Event.pointer_down(10.0_f32, 10.0_f32), root)
    r.handle(Event.key_down(KeyCode::Tab), root).should eq a
    r.handle(Event.key_up(KeyCode::Tab), root).should eq a
    r.handle(Event.text_input("x"), root).should eq a
    r.handle(Event.blur, root).should be_nil
    r.focus_manager.focused.should be_nil
    r.handle(Event.key_down(KeyCode::Enter), root).should be_nil
  end

  it "resize returns nil and does not move focus" do
    root, a, _b = build_tree
    r = Router.new
    r.handle(Event.pointer_down(10.0_f32, 10.0_f32), root)
    r.handle(Event.resize, root).should be_nil
    r.focus_manager.focused.should eq a
  end
end
