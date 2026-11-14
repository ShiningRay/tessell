require "./spec_helper"

# issue #32：编辑态 Tab 语义在 API 层声明，组件不再手写分支。
#   TextEditing#tabs = Reject（默认，\t 整体拒绝）/ Insert（tab_width 空格）
#   Input#submit_on_tab = true 时 Tab 触发 on_submit 并消费（wants_tab? 随动）
# \t 永不进入编辑文本 → 宽度与光标不依赖字体制表符字形。

describe "Tab semantics (issue #32)" do
  it "rejects \\t insertion by default (v0.2.0 regression guard)" do
    e = Tessell::Kit::TextEditing.new("abc")
    e.insert("\t").should be_false
    e.text.should eq("abc")
    e.insert("a\tb").should be_false
    e.text.should eq("abc")
    e.tabs.should eq(Tessell::Kit::TabBehavior::Reject)
  end

  it "expands \\t to tab_width spaces when tabs = Insert" do
    e = Tessell::Kit::TextEditing.new("abc")
    e.tabs = Tessell::Kit::TabBehavior::Insert
    e.insert("\t").should be_true
    e.text.should eq("abc    ")
    e.cursor.should eq("abc    ".bytesize)

    e.tab_width = 2
    e.insert("x\ty").should be_true
    e.text.should eq("abc    x  y")
    # 文本里永不出现 \t 字形
    e.text.includes?('\t').should be_false
  end

  it "keeps paste consistent with the declared tab behavior" do
    clip = Tessell::Kit::MemoryClipboard.new("a\tb")
    rejected = Tessell::Kit::TextEditing.new("")
    rejected.paste(clip).should be_false
    rejected.text.should eq("")

    accepted = Tessell::Kit::TextEditing.new("")
    accepted.tabs = Tessell::Kit::TabBehavior::Insert
    accepted.paste(clip).should be_true
    accepted.text.should eq("a    b")
  end

  it "Input with submit_on_tab submits and consumes Tab; wants_tab? follows" do
    input = Tessell::Kit::Input.new(KitSpecHelpers.key, "v1", submit_on_tab: true)
    submitted = [] of String
    input.on_submit = ->(value : String) { submitted << value; nil }
    input.wants_tab?.should be_true

    ctx = Tessell::Kit::Context.new
    input.handle(Tessell::Kit::Event.key_down(Tessell::Kit::Key::Tab), ctx).should be_true
    submitted.should eq(["v1"])
    # 编辑内容不被 Tab 破坏
    input.editing.text.should eq("v1")
  end

  it "default Input leaves Tab to the focus ring (no submit)" do
    input = Tessell::Kit::Input.new(KitSpecHelpers.key, "v1")
    submitted = 0
    input.on_submit = ->(value : String) { submitted += 1; nil }
    input.wants_tab?.should be_false

    ctx = Tessell::Kit::Context.new
    input.handle(Tessell::Kit::Event.key_down(Tessell::Kit::Key::Tab), ctx).should be_false
    submitted.should eq(0)
  end

  it "routes Tab through Root: submit_on_tab consumes before the focus ring" do
    input = Tessell::Kit::Input.new(KitSpecHelpers.key, "v1", submit_on_tab: true)
    submitted = [] of String
    input.on_submit = ->(value : String) { submitted << value; nil }
    root = Tessell::Kit::Root.new(input, metrics: Tessell::Kit::StubTextMetrics.new)
    root.layout(200.0_f32, 100.0_f32)
    root.build
    root.focus(input)

    root.handle(Tessell::Input::Event.key_down(Tessell::Input::KeyCode::Tab)).should be_true
    submitted.should eq(["v1"])
    root.focused_component.should be(input) # 消费式提交：焦点留在原地
  end

end
