require "./spec_helper"
# M2-WP1 路由 spec：down 聚焦+返回目标、move hover、key 到焦点、blur 清焦点、resize nil、up 按压、wheel 回落。

require "spec"
require "../src/tessell/geometry"
require "../src/tessell/core/node"
require "../src/tessell/input/event"
require "../src/tessell/input/hit_test"
require "../src/tessell/input/focus"
require "../src/tessell/input/router"

include Tessell
include Tessell::Input

def build_router_tree : {Node, Node, Node}
  root = Node.new("root", Rect.new(0.0_f32, 0.0_f32, 100.0_f32, 100.0_f32))
  a = Node.new("a", Rect.new(10.0_f32, 10.0_f32, 30.0_f32, 30.0_f32))
  b = Node.new("b", Rect.new(20.0_f32, 20.0_f32, 30.0_f32, 30.0_f32))
  root.add_child(a)
  root.add_child(b)
  {root, a, b}
end

describe "Router (M2-WP1)" do
  it "down hits deepest and focuses it" do
    root, a, b = build_router_tree
    router = Router.new
    target = router.handle(Event.pointer_down(15.0_f32, 15.0_f32), root)
    target.should eq a
    router.focus_manager.focused?(a).should be_true
    router.pressed.should eq a
  end

  it "down on non-focusable returns target without focusing" do
    root, a, b = build_router_tree
    router = Router.new { |node| node.id != "a" }
    target = router.handle(Event.pointer_down(15.0_f32, 15.0_f32), root)
    target.should eq a
    router.focus_manager.focused.should be_nil
  end

  it "move sets hover and returns it" do
    root, a, b = build_router_tree
    router = Router.new
    target = router.handle(Event.pointer_move(25.0_f32, 25.0_f32), root)
    target.should eq b
    router.hover.should eq b
  end

  it "key events go to current focus" do
    root, a, b = build_router_tree
    router = Router.new
    router.handle(Event.pointer_down(15.0_f32, 15.0_f32), root)
    target = router.handle(Event.key_down(KeyCode::Tab), root)
    target.should eq a
    router.handle(Event.text_input("x"), root).should eq a
    router.handle(Event.key_up(KeyCode::Tab), root).should eq a
  end

  it "blur returns nil and clears focus" do
    root, a, b = build_router_tree
    router = Router.new
    router.handle(Event.pointer_down(15.0_f32, 15.0_f32), root)
    router.focus_manager.focused?(a).should be_true
    router.handle(Event.blur, root).should be_nil
    router.focus_manager.focused.should be_nil
  end

  it "resize returns nil and keeps focus" do
    root, a, b = build_router_tree
    router = Router.new
    router.handle(Event.pointer_down(15.0_f32, 15.0_f32), root)
    router.handle(Event.resize, root).should be_nil
    router.focus_manager.focused?(a).should be_true
  end

  it "up returns pressed target then clears it (no re-hit)" do
    root, a, b = build_router_tree
    router = Router.new
    router.handle(Event.pointer_down(15.0_f32, 15.0_f32), root)
    target = router.handle(Event.pointer_up(90.0_f32, 90.0_f32), root)
    target.should eq a
    router.pressed.should be_nil
  end

  it "second up returns nil after press cleared" do
    root, a, b = build_router_tree
    router = Router.new
    router.handle(Event.pointer_down(15.0_f32, 15.0_f32), root)
    router.handle(Event.pointer_up(90.0_f32, 90.0_f32), root).should eq a
    router.handle(Event.pointer_up(90.0_f32, 90.0_f32), root).should be_nil
  end

  it "pressed survives move and up still returns it" do
    root, a, b = build_router_tree
    router = Router.new
    router.handle(Event.pointer_down(15.0_f32, 15.0_f32), root)
    router.handle(Event.pointer_move(25.0_f32, 25.0_f32), root).should eq b
    router.handle(Event.pointer_up(90.0_f32, 90.0_f32), root).should eq a
  end

  it "up on non-focusable node returns that node" do
    root, a, b = build_router_tree
    router = Router.new { |node| node.id != "a" }
    router.handle(Event.pointer_down(15.0_f32, 15.0_f32), root).should eq a
    router.focus_manager.focused.should be_nil
    router.handle(Event.pointer_up(90.0_f32, 90.0_f32), root).should eq a
    router.pressed.should be_nil
  end

  it "wheel prefers hover, falls back to focus" do
    root, a, b = build_router_tree
    router = Router.new
    router.handle(Event.pointer_down(15.0_f32, 15.0_f32), root)
    # 无 hover 时回落到焦点
    router.handle(Event.wheel(15.0_f32, 15.0_f32), root).should eq a
    # 有 hover 时优先 hover
    router.handle(Event.pointer_move(25.0_f32, 25.0_f32), root)
    router.handle(Event.wheel(25.0_f32, 25.0_f32), root).should eq b
  end

  it "pointer event payload struct usable via Event.pointer" do
    root, a, b = build_router_tree
    router = Router.new
    pe = PointerEvent.new(15.0_f32, 15.0_f32, 0)
    target = router.handle(Event.pointer(Event::Kind::PointerDown, pe), root)
    target.should eq a
    pe.button.should eq 0
  end
end
