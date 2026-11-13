require "./spec_helper"
# M1 观察-1（task-36）：Node remove_child / detach 与重挂载一致性（spec）。
#
# 覆盖：成功/失败、detach 中间节点/根、重挂载双向一致、同父重复 add 幂等、
#      dirty 保留、dirty_subtree 不含已 detach 子树。

require "spec"
require "../src/tessell/core/node"

include Tessell

describe "Node add/remove/detach consistency (M1 observation-1)" do
  it "remove_child succeeds: child removed, parent=nil, children empty" do
    root = Node.new("root")
    a = Node.new("a")
    root.add_child(a)

    root.remove_child(a).should be_true
    a.parent.should be_nil
    root.children.should be_empty
  end

  it "remove_child fails for unattached node and leaves children unchanged" do
    root = Node.new("root")
    a = Node.new("a")
    b = Node.new("b")
    root.add_child(b)

    root.remove_child(a).should be_false
    root.children.size.should eq 1
    root.children[0].should eq b
    a.parent.should be_nil
  end

  it "detach mid node: parent=nil and removed from old parent's children" do
    root = Node.new("root")
    mid = Node.new("mid")
    root.add_child(mid)

    mid.detach

    mid.parent.should be_nil
    root.children.should be_empty
  end

  it "detach root is side-effect free (no parent, no exception)" do
    root = Node.new("root")

    root.detach

    root.parent.should be_nil
    root.children.should be_empty
  end

  it "re-mount is bidirectionally consistent (old parent drops, new parent holds)" do
    root1 = Node.new("root1")
    root2 = Node.new("root2")
    a = Node.new("a")
    root1.add_child(a)

    root2.add_child(a)

    a.parent.should eq root2
    root1.children.should be_empty
    root2.children.size.should eq 1
    root2.children[0].should eq a
  end

  it "add_child same parent twice is idempotent (no duplicate slot)" do
    root = Node.new("root")
    a = Node.new("a")

    root.add_child(a)
    root.add_child(a)

    root.children.size.should eq 1
    root.children[0].should eq a
    a.parent.should eq root
  end

  it "remove_child/detach preserve dirty flags on the detached node" do
    root = Node.new("root")
    a = Node.new("a")
    root.add_child(a)
    a.mark_dirty(Invalidation::Paint)

    removed = root.remove_child(a)

    removed.should be_true
    a.paint_dirty?.should be_true
    a.dirty?.should eq Invalidation::Paint
    root.dirty?.should be_nil
  end

  it "dirty_subtree excludes a detached subtree" do
    root = Node.new("root")
    a = Node.new("a")
    b = Node.new("b")
    root.add_child(a)
    a.add_child(b)
    a.mark_dirty(Invalidation::Paint)
    b.mark_dirty(Invalidation::Paint)

    a.detach

    root_ids = Node.dirty_subtree(root).map(&.id)
    root_ids.should be_empty
    a_ids = Node.dirty_subtree(a).map(&.id)
    a_ids.should contain("a")
    a_ids.should contain("b")
    a_ids.size.should eq 2
  end
end
