require "./spec_helper"

# issue #39 第一期：重启式热重载的状态快照/回填。
# 保留的是命名 signal 值，不保留 views（重启后全树 remount）——
# asuka RFC 0003 口径。control socket + fd 继承属平台层后续工作。

describe "signal state snapshot/restore (issue #39 phase 1)" do
  around_each do |example|
    Tessell::Signal.reset_named_registry!
    example.run
    Tessell::Signal.reset_named_registry!
  end

  it "round-trips named signal values across a simulated restart" do
    counter = Tessell::Signal.signal(0, label: "counter")
    name_sig = Tessell::Signal.signal("面板 A", label: "sheet.name")
    Tessell::Signal.signal(999) # 未命名：不参与快照

    counter.set(42)
    name_sig.set("Q3 报表")
    Tessell::Signal.named_count.should eq(2)

    snapshot = Tessell::Signal.snapshot_state
    snapshot.should contain("\"counter\":42")
    snapshot.should contain("Q3 报表")

    # 模拟重启：值归零后回填
    counter.set(0)
    name_sig.set("")
    restored = Tessell::Signal.restore_state(snapshot)
    restored.should eq(2)
    counter.peek.should eq(42)
    name_sig.peek.should eq("Q3 报表")
  end

  it "covers several JSON-mappable types" do
    i = Tessell::Signal.signal(1, label: "t.int")
    f = Tessell::Signal.signal(1.5_f32, label: "t.float")
    b = Tessell::Signal.signal(false, label: "t.bool")
    s = Tessell::Signal.signal("x", label: "t.str")

    f.set(2.5_f32)
    b.set(true)
    s.set("你好")
    text = Tessell::Signal.snapshot_state

    i.set(0)
    f.set(0.0_f32)
    b.set(false)
    s.set("")
    Tessell::Signal.restore_state(text).should eq(4)
    i.peek.should eq(1)
    f.peek.should eq(2.5_f32)
    b.peek.should be_true
    s.peek.should eq("你好")
  end

  it "does not snapshot derived nodes; unknown names are ignored" do
    src = Tessell::Signal.signal(5, label: "src")
    derived = Tessell::Signal.memo { src.get * 2 }
    derived.get

    text = Tessell::Signal.snapshot_state
    text.should contain("src")
    text.should_not contain("derived")

    # 快照里的未知名字（源码已改名）被忽略
    restored = Tessell::Signal.restore_state("{\"gone\":123,\"src\":7}")
    restored.should eq(1)
    src.peek.should eq(7)
    derived.peek.should eq(14) # memo 跟随新值
  end

  it "dispose removes the signal from the registry" do
    owner = Tessell::Signal::Owner.new
    sig = Tessell::Signal.signal(3, label: "temp", owner: owner)
    before = Tessell::Signal.named_count
    owner.dispose
    Tessell::Signal.named_count.should eq(before - 1)
  end

  it "Runner save_state/load_state round-trips through a file" do
    runner = Tessell::App::Runner.new
    counter = Tessell::Signal.signal(0, label: "counter")
    counter.set(7)

    path = ".spike/tessell-state-spec.json"
    begin
      Dir.mkdir_p(".spike") unless Dir.exists?(".spike") # CI 全新 checkout 无该目录（issue #61）
      runner.save_state(path)
      counter.set(0)
      runner.load_state(path).should eq(1)
      counter.peek.should eq(7)

      # 首次启动（无文件）返回 0
      Tessell::App::Runner.new.load_state(path.sub(".json", "-missing.json")).should eq(0)
    ensure
      File.delete?(path)
    end
  end
end
