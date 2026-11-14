require "./spec_helper"

describe "Tessell::Kit::TextEditing" do
  it "inserts at cursor and replaces selection" do
    editing = Tessell::Kit::TextEditing.new("ac")
    editing.set_cursor(1)
    editing.insert("b").should be_true
    editing.text.should eq("abc")
    editing.cursor.should eq(2)

    editing.set_cursor(0)
    editing.set_cursor(2, extending: true)
    editing.selected_text.should eq("ab")
    editing.insert("X").should be_true
    editing.text.should eq("Xc")
    editing.cursor.should eq(1)
  end

  it "moves and deletes by grapheme cluster" do
    editing = Tessell::Kit::TextEditing.new("a👍🏽")
    editing.backspace.should be_true
    editing.text.should eq("a")
    editing.cursor.should eq(1)

    editing = Tessell::Kit::TextEditing.new("a👍🏽")
    editing.move_left
    editing.cursor.should eq(1)
    editing.backspace.should be_true
    editing.text.should eq("👍🏽")

    editing = Tessell::Kit::TextEditing.new("e\u0301x")
    editing.move_left
    editing.cursor.should eq(3)
    editing.backspace.should be_true
    editing.text.should eq("x")
  end

  it "deletes forward and handles no-op boundaries" do
    editing = Tessell::Kit::TextEditing.new("abc")
    editing.set_cursor(1)
    editing.delete.should be_true
    editing.text.should eq("ac")
    editing.set_cursor(99)
    editing.delete.should be_false
    editing.backspace.should be_true
    editing.text.should eq("a")
  end

  it "extends selection with shift-style movement" do
    editing = Tessell::Kit::TextEditing.new("abcd")
    editing.set_cursor(0)
    editing.move_right(extending: true)
    editing.move_right(extending: true)
    editing.selected_text.should eq("ab")
    editing.move_left
    editing.selection?.should be_false
    editing.cursor.should eq(0)
  end

  it "copies, cuts and pastes through a clipboard" do
    clipboard = Tessell::Kit::MemoryClipboard.new
    editing = Tessell::Kit::TextEditing.new("hello")
    editing.select_all
    editing.copy(clipboard).should be_true
    clipboard.get.should eq("hello")
    editing.cut(clipboard).should be_true
    editing.text.should eq("")
    editing.paste(clipboard).should be_true
    editing.text.should eq("hello")
    editing.cursor.should eq(5)
  end

  it "keeps preedit separate until commit" do
    editing = Tessell::Kit::TextEditing.new("A")
    editing.set_cursor(1)
    editing.set_preedit("ni")
    editing.text.should eq("A")
    editing.preedit?.should be_true
    editing.commit_preedit.should be_true
    editing.text.should eq("Ani")
    editing.preedit?.should be_false
  end

  it "programmatic set_text clamps cursor and clears selection" do
    editing = Tessell::Kit::TextEditing.new("abc")
    editing.select_all
    editing.set_text("xy")
    editing.text.should eq("xy")
    editing.cursor.should eq(2)
    editing.selection?.should be_false
  end
end
