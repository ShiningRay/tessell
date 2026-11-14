require "spec"
require "../../src/tessell/kit"

# Issue #14：TextMetrics 契约单位是设备像素，Context#measure_text /
# line_height 必须换算回逻辑单位。DPR≠1 时组件逻辑 bounds 不得翻倍。
describe "Kit::Context text metrics under DPR" do
  it "measure_text returns identical logical width at scale=1 and scale=2" do
    c1 = Tessell::Kit::Context.new(Tessell::Kit::Theme.light, Tessell::Kit::StubTextMetrics.new, 1.0_f32)
    c2 = Tessell::Kit::Context.new(Tessell::Kit::Theme.light, Tessell::Kit::StubTextMetrics.new, 2.0_f32)
    ["120000", "TESSEL 行情", "A1:B3"].each do |t|
      s1 = c1.measure_text(t, 14.0_f32)
      s2 = c2.measure_text(t, 14.0_f32)
      s2.width.should eq(s1.width)
      s2.height.should eq(s1.height)
    end
  end

  it "line_height is logical at scale=2" do
    c1 = Tessell::Kit::Context.new(Tessell::Kit::Theme.light, Tessell::Kit::StubTextMetrics.new, 1.0_f32)
    c2 = Tessell::Kit::Context.new(Tessell::Kit::Theme.light, Tessell::Kit::StubTextMetrics.new, 2.0_f32)
    c2.line_height(14.0_f32).should eq(c1.line_height(14.0_f32))
  end

  it "measure_text with max_width wraps the same in logical units at scale=2" do
    c1 = Tessell::Kit::Context.new(Tessell::Kit::Theme.light, Tessell::Kit::StubTextMetrics.new, 1.0_f32)
    c2 = Tessell::Kit::Context.new(Tessell::Kit::Theme.light, Tessell::Kit::StubTextMetrics.new, 2.0_f32)
    text = "aaaa bbbb cccc dddd"
    s1 = c1.measure_text(text, 14.0_f32, 200.0_f32)
    s2 = c2.measure_text(text, 14.0_f32, 200.0_f32)
    s2.width.should eq(s1.width)
    s2.height.should eq(s1.height)
  end

  it "device_font_size still reports the device size used for shaping" do
    c2 = Tessell::Kit::Context.new(Tessell::Kit::Theme.light, Tessell::Kit::StubTextMetrics.new, 2.0_f32)
    c2.device_font_size(14.0_f32).should eq(28.0_f32)
  end
end
