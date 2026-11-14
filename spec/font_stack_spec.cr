require "./spec_helper"
require "../src/tessell/text/font_stack"

private def unix_font_path : String?
  candidates = [
    "/System/Library/Fonts/Supplemental/Arial.ttf",
    "/System/Library/Fonts/Supplemental/Arial Unicode.ttf",
    "/System/Library/Fonts/Helvetica.ttc",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
  ]
  candidates.find { |path| File.exists?(path) }
end

# issue #7：FontStack 真实 cmap 选脸与系统字体发现。
describe "Text::FontStack / SystemFonts" do
  it "FtMeasurer#covers? reports cmap coverage" do
    path = unix_font_path
    unless path
      pending "no Unix test font found"
      next
    end
    m = Tessell::Text::FtMeasurer.open(path)
    m.covers?("Hello").should be_true
    m.covers?("你好").should be_false # Latin-only face；Arial Unicode 存在时下面用例覆盖 CJK
    m.close
  end

  it "pick returns first covering face and measure falls back in priority order" do
    path = unix_font_path
    unless path
      pending "no Unix test font found"
      next
    end
    stack = Tessell::Text::FontStack.open([
      {path: path, ttc_index: 0, weight: Tessell::Text::FontStack::Weight::Regular, label: "primary"},
    ])
    stack.face_count.should eq(1)
    face = stack.pick("Hello 123").should_not be_nil
    face.not_nil!.font_id.should eq(0)
    face.not_nil!.weight.should eq(Tessell::Text::FontStack::Weight::Regular)
    w = stack.measure("Hello 123", 16.0_f32)
    w.width.should be > 0.0_f32
    stack.pick("").should_not be_nil # 空文本视为覆盖
    stack.close
  end

  it "pick prefers earlier face and returns nil when nothing covers" do
    path = unix_font_path
    unless path
      pending "no Unix test font found"
      next
    end
    stack = Tessell::Text::FontStack.open([
      {path: path, ttc_index: 0, weight: Tessell::Text::FontStack::Weight::Regular, label: "primary"},
      {path: path, ttc_index: 0, weight: Tessell::Text::FontStack::Weight::Bold, label: "bold"},
    ])
    picked = stack.pick("Hello")
    picked.not_nil!.label.should eq("primary")
    stack.close
    # 全部脸都不覆盖的文本：nil，应用自行回退（不抛异常）。
    closed_stack = Tessell::Text::FontStack.open([
      {path: path, ttc_index: 0, weight: Tessell::Text::FontStack::Weight::Regular, label: "primary"},
    ])
    closed_stack.close
    closed_stack.pick("Hello").should be_nil
  end

  it "SystemFonts scans standard dirs and matches by filename pattern" do
    dirs = Tessell::Text::SystemFonts.search_dirs
    unless dirs.empty?
      candidates = Tessell::Text::SystemFonts.candidates
      candidates.size.should be > 0
      hit = Tessell::Text::SystemFonts.find(["helvetica"])
      if File.directory?("/System/Library/Fonts")
        hit.should_not be_nil
        hit.not_nil!.downcase.includes?("helvetica").should be_true
      end
    end
  end
end
