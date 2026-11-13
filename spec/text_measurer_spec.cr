require "./spec_helper"
require "spec"
require "../src/tessell/text/measurer"
require "../src/tessell/geometry"

include Tessell
include Tessell::Text

describe Tessell::Text::MeasureKey do
  it "FNV-1a hash is stable across different String instances" do
    a = "hello".dup
    b = "hello".dup
    MeasureKey.text_hash(a).should eq MeasureKey.text_hash(b)
  end

  it "different text yields different hash (collision unlikely)" do
    MeasureKey.text_hash("abc").should_not eq MeasureKey.text_hash("xyz")
  end
end

describe Tessell::Text::StubMeasurer do
  it "width scales with char count and size" do
    m = StubMeasurer.new
    s1 = m.measure("ab", 1, 10.0_f32, 0.0_f32)
    s2 = m.measure("abcd", 1, 10.0_f32, 0.0_f32)
    (s2.width > s1.width).should be_true
  end

  it "max_width triggers wrapping height" do
    m = StubMeasurer.new
    s = m.measure("abcdefghij", 1, 10.0_f32, 20.0_f32)
    (s.height > 10.0_f32 * 1.2_f32).should be_true
  end
end

describe Tessell::Text::CachingMeasurer do
  it "first call is miss, second hit" do
    inner = StubMeasurer.new
    c = CachingMeasurer.new(inner)
    c.measure("hi", 1, 12.0_f32, 0.0_f32)
    c.measure("hi", 1, 12.0_f32, 0.0_f32)
    st = c.stats
    st[:hits].should eq 1
    st[:misses].should eq 1
    st[:evictions].should eq 0
  end

  it "different font_id is a miss" do
    inner = StubMeasurer.new
    c = CachingMeasurer.new(inner)
    c.measure("hi", 1, 12.0_f32, 0.0_f32)
    c.measure("hi", 2, 12.0_f32, 0.0_f32)
    c.stats[:misses].should eq 2
  end

  it "different size is a miss" do
    inner = StubMeasurer.new
    c = CachingMeasurer.new(inner)
    c.measure("hi", 1, 12.0_f32, 0.0_f32)
    c.measure("hi", 1, 14.0_f32, 0.0_f32)
    c.stats[:misses].should eq 2
  end

  it "different max_width is a miss" do
    inner = StubMeasurer.new
    c = CachingMeasurer.new(inner)
    c.measure("hi", 1, 12.0_f32, 0.0_f32)
    c.measure("hi", 1, 12.0_f32, 50.0_f32)
    c.stats[:misses].should eq 2
  end

  it "different text is a miss" do
    inner = StubMeasurer.new
    c = CachingMeasurer.new(inner)
    c.measure("hi", 1, 12.0_f32, 0.0_f32)
    c.measure("ho", 1, 12.0_f32, 0.0_f32)
    c.stats[:misses].should eq 2
  end

  it "invalidate_font evicts and counts" do
    inner = StubMeasurer.new
    c = CachingMeasurer.new(inner)
    c.measure("hi", 7, 12.0_f32, 0.0_f32)
    c.measure("ho", 7, 12.0_f32, 0.0_f32)
    c.measure("hi", 9, 12.0_f32, 0.0_f32)
    c.invalidate_font(7)
    c.stats[:evictions].should eq 2
    c.measure("hi", 7, 12.0_f32, 0.0_f32)
    c.stats[:misses].should eq 4
  end

  it "clear empties cache" do
    inner = StubMeasurer.new
    c = CachingMeasurer.new(inner)
    c.measure("hi", 1, 12.0_f32, 0.0_f32)
    c.clear
    c.measure("hi", 1, 12.0_f32, 0.0_f32)
    c.stats[:misses].should eq 2
  end

  it "cached value equals inner value" do
    inner = StubMeasurer.new
    c = CachingMeasurer.new(inner)
    a = c.measure("hello", 1, 10.0_f32, 0.0_f32)
    b = inner.measure("hello", 1, 10.0_f32, 0.0_f32)
    a.width.should eq b.width
    a.height.should eq b.height
  end
end
