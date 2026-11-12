require "spec"
require "../src/tessell/geometry"
require "../src/tessell/text/measurer"
require "../src/tessell/text/ft_measurer"

include Tessell
include Tessell::Text

FONT_PATH = "C:\\Windows\\Fonts\\msyh.ttc"

describe "Tessell::Text::FtMeasurer" do
  it "⑥1 FtMeasurer.available? true (or fail with reason)" do
    if !FtMeasurer.available?
      reason = FtMeasurer.unavailable_reason
      fail "FtMeasurer not available: #{reason.inspect}"
    end
    FtMeasurer.available?.should be_true
  end

  it "⑥2 Hello size 16 width > 0 and matches HB positions sum (±0.5)" do
    measurer = FtMeasurer.open(FONT_PATH, 0)
    begin
      sz = measurer.measure("Hello", 0, 16.0_f32, 0.0_f32)
      sz.width.should be > 0.0_f32

      info = measurer.shape_info("Hello", 16.0_f32)
      sum_adv = 0.0_f32
      info[:advances_px].each { |a| sum_adv += a }
      (sz.width - sum_adv).abs.should be <= 0.5_f32
    ensure
      measurer.close
    end
  end

  it "⑥3 你好世界 4 chars width ≈ single char advance × 4 (±5%)" do
    measurer = FtMeasurer.open(FONT_PATH, 0)
    begin
      sz4 = measurer.measure("你好世界", 0, 16.0_f32, 0.0_f32)
      sz1 = measurer.measure("你", 0, 16.0_f32, 0.0_f32)
      ratio = sz4.width / sz1.width
      (ratio >= 3.8_f32 && ratio <= 4.2_f32).should be_true
    ensure
      measurer.close
    end
  end

  it "⑥4 max_width forces wrapping height >= 2 lines" do
    measurer = FtMeasurer.open(FONT_PATH, 0)
    begin
      sz = measurer.measure("Hello World Hello World", 0, 16.0_f32, 50.0_f32)
      single = measurer.measure("Hello", 0, 16.0_f32, 0.0_f32)
      (sz.height >= single.height * 1.5_f32).should be_true
    ensure
      measurer.close
    end
  end

  it "⑥5 FT char index for 'A' non-zero and matches HB glyph id" do
    measurer = FtMeasurer.open(FONT_PATH, 0)
    begin
      info = measurer.shape_info("A", 16.0_f32)
      ft_idx = info[:ft_char_index][65_u32] # 'A'.ord
      ft_idx.should be > 0_u32
      if info[:glyph_ids].size > 0
        info[:glyph_ids][0].should eq ft_idx
      end
    ensure
      measurer.close
    end
  end

  it "⑥6 CachingMeasurer wrapping shows hit on second call, inner not called again" do
    inner = FtMeasurer.open(FONT_PATH, 0)
    begin
      inner_calls = 0
      counting = CountingFtMeasurer.new(inner)
      c = CachingMeasurer.new(counting)
      c.measure("Test", 1, 16.0_f32, 0.0_f32)
      c.measure("Test", 1, 16.0_f32, 0.0_f32)
      st = c.stats
      st[:hits].should eq 1
      st[:misses].should eq 1
      counting.calls.should eq 1
    ensure
      inner.close
    end
  end
end

class CountingFtMeasurer < Measurer
  property calls : Int32 = 0

  def initialize(@inner : FtMeasurer)
  end

  def measure(text : String, font_id : Int32, size : Float32, max_width : Float32) : Size
    @calls += 1
    @inner.measure(text, font_id, size, max_width)
  end
end
