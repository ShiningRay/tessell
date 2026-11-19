require "./spec_helper"
require "../src/tessell/kit"

# issue #61 X1：Platform::Host 契约测试（plan §7：新增宿主先加契约测试）。
# 契约面：clipboard/ime 能力表 + 消费式 resize + 帧循环辅助；
# FakeHost 与可选 SDL2 宿主都必须满足。SDL2 本体不在核心默认依赖里
# （src/tessell.cr 不 require platform/sdl2——编译期由本 spec 的源码断言兜底）。

private class MinimalHost < Tessell::Platform::Host
  def initialize(@clipboard : Tessell::Platform::Clipboard, @ime : Tessell::Platform::ImeSupport)
  end
  def title : String
    "minimal"
  end

  def scale : Float32
    1.0_f32
  end

  def viewport : Tessell::Rect
    Tessell::Rect.new(0.0_f32, 0.0_f32, 10.0_f32, 10.0_f32)
  end

  def poll_events(sink : Array(Tessell::Input::Event)) : Bool
    true
  end

  def present : Nil
  end

  def close : Nil
  end

  def clipboard : Tessell::Platform::Clipboard
    @clipboard
  end

  def ime : Tessell::Platform::ImeSupport
    @ime
  end
end

describe "Platform::Host contract (issue #61 X1)" do
  it "MemoryClipboard roundtrip" do
    clip = Tessell::Platform::MemoryClipboard.new
    clip.get.should be_nil
    clip.set("hello")
    clip.get.should eq("hello")
    clip.set("")
    clip.get.should eq("")
  end

  it "FakeHost satisfies clipboard/ime contract with honest capability report" do
    host = Tessell::Platform::FakeHost.new
    host.clipboard.set("x")
    host.clipboard.get.should eq("x")
    # SDL2 只提供 committed text——FakeHost 同口径，不冒充预编辑能力
    host.ime.should eq(Tessell::Platform::ImeSupport::CommittedText)
    host.close
  end

  it "frame helpers have safe defaults on custom hosts" do
    host = MinimalHost.new(Tessell::Platform::MemoryClipboard.new,
      Tessell::Platform::ImeSupport::Unsupported)
    host.resized?.should be_false
    host.ticks_ms.should eq(0_i64)
    host.delay(0) # no-op，不抛异常
    host.clipboard.get.should be_nil
    host.ime.should eq(Tessell::Platform::ImeSupport::Unsupported)
  end

  it "core entry does not load the optional SDL2 host" do
    # 编译期兜底：src/tessell.cr 不出现 platform/sdl2（X1 硬边界）。
    File.read(File.expand_path("../src/tessell.cr", __DIR__))
      .includes?("platform/sdl2").should be_false
  end

  it "Kit::HostClipboard adapts Platform::Clipboard (Platform ← Kit 依赖方向)" do
    inner = Tessell::Platform::MemoryClipboard.new
    clip = Tessell::Kit::HostClipboard.new(inner)
    inner.set("from host")
    clip.get.should eq("from host")
    clip.set("from kit")
    inner.get.should eq("from kit")
  end
end
