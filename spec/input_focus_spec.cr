require "./spec_helper"
# M2-WP1 焦点管理 spec：设置/替换返回旧值、next/prev 前序+回绕、单节点自身、
# detach 不参与、可注入 focusable 谓词。
#
# 焦点环规则（与 focus.cr 一致）：
#   - root 有子节点时，焦点环 = root 后代中可聚焦节点的前序序列（root 仅作容器）；
#   - 单节点规则：root 无子节点且 root 可聚焦时，焦点环仅含 root 自身；
#   - detach/谓词排除的节点不在环中；当前焦点不在环中时回绕到端点。

require "spec"
require "../src/tessell/geometry"
require "../src/tessell/core/node"
require "../src/tessell/input/focus"

include Tessell
include Tessell::Input

def build_focus_chain : {Node, Node, Node, Node}
  root = Node.new("root", Rect.new(0.0_f32, 0.0_f32, 100.0_f32, 100.0_f32))
  a = Node.new("a", Rect.new(0.0_f32, 0.0_f32, 10.0_f32, 10.0_f32))
  b = Node.new("b", Rect.new(0.0_f32, 0.0_f32, 10.0_f32, 10.0_f32))
  c = Node.new("c", Rect.new(0.0_f32, 0.0_f32, 10.0_f32, 10.0_f32))
  root.add_child(a)
  root.add_child(b)
  root.add_child(c)
  {root, a, b, c}
end

describe "FocusManager (M2-WP1)" do
  it "focus returns old focus" do
    root, a, b, c = build_focus_chain
    fm = FocusManager.new
    fm.focus(a).should be_nil
    fm.focus(b).should eq a
    fm.focused.should eq b
    fm.focus(c).should eq b
  end

  it "focused? and blur" do
    root, a, b, c = build_focus_chain
    fm = FocusManager.new
    fm.focus(a)
    fm.focused?(a).should be_true
    fm.focused?(b).should be_false
    fm.blur
    fm.focused.should be_nil
    fm.focused?(a).should be_false
  end

  it "next walks preorder and wraps" do
    root, a, b, c = build_focus_chain
    fm = FocusManager.new
    fm.focus(a)
    fm.next(root).should eq b
    fm.next(root).should eq c
    fm.next(root).should eq a
  end

  it "prev walks preorder backwards and wraps" do
    root, a, b, c = build_focus_chain
    fm = FocusManager.new
    fm.focus(a)
    fm.prev(root).should eq c
    fm.prev(root).should eq b
    fm.prev(root).should eq a
  end

  it "single node next/prev returns self" do
    r = Node.new("r", Rect.new(0.0_f32, 0.0_f32, 10.0_f32, 10.0_f32))
    fm = FocusManager.new
    fm.next(r).should eq r
    fm.prev(r).should eq r
    fm.focus(r)
    fm.next(r).should eq r
    fm.prev(r).should eq r
  end

  it "detached node does not participate" do
    root = Node.new("root", Rect.new(0.0_f32, 0.0_f32, 100.0_f32, 100.0_f32))
    a = Node.new("a", Rect.new(0.0_f32, 0.0_f32, 10.0_f32, 10.0_f32))
    b = Node.new("b", Rect.new(0.0_f32, 0.0_f32, 10.0_f32, 10.0_f32))
    root.add_child(a)
    root.add_child(b)
    fm = FocusManager.new
    fm.focus(a)
    a.detach
    # detach 不自动清焦点（语义由调用方负责）
    fm.focused?(a).should be_true
    # a 不在环中：next/prev 均回绕到环内唯一节点 b
    fm.next(root).should eq b
    fm.prev(root).should eq b
  end

  it "injectable focusable predicate excludes nodes" do
    root, a, b, c = build_focus_chain
    fm = FocusManager.new { |node| node.id != "a" }
    fm.focusable?(a).should be_false
    fm.focusable?(b).should be_true
    fm.next(root).should eq b
    fm.focus(b)
    fm.next(root).should eq c
  end

  it "no candidates returns nil" do
    root, a, b, c = build_focus_chain
    fm = FocusManager.new { |node| false }
    fm.next(root).should be_nil
    fm.prev(root).should be_nil
    fm.focus(a)
    fm.next(root).should be_nil
  end
end
