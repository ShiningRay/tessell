require "./spec_helper"
require "../src/tessell/geometry"
require "../src/tessell/text/measurer"

include Tessell
include Tessell::Text

# issue #56：测量缓存两层化——L1 结果缓存（宽度参与键）+ L2 宽度无关
# shaping 缓存；淘汰从「满即 clear」改为按 font_id 分段 LRU；stats 增加
# shapes/reflows 计数（计数断言口径，issue #36）。

# 确定性 shape 桩：每字符一个 cluster，advance=10px，行高 12px。
# measure 走 shape_run + reflow_run（与 FtMeasurer#measure 同构），
# 保证 L2 reflow 与全量 measure 几何一致可断言。
private class ShapeStubMeasurer < Measurer
  def shape_run(text : String, font_id : Int32, size : Float32) : ShapeRun?
    advances = Array(Float32).new(text.size)
    text.each_char { advances << 10.0_f32 }
    ShapeRun.new(advances, 12.0_f32)
  end

  def measure(text : String, font_id : Int32, size : Float32, max_width : Float32) : Size
    run = shape_run(text, font_id, size)
    return Size.new(0.0_f32, 0.0_f32) unless run
    if max_width > 0.0_f32
      Text.reflow_run(run.advances, run.line_height, max_width)
    else
      total = 0.0_f32
      run.advances.each { |a| total += a }
      Size.new(total, run.line_height)
    end
  end
end

private def msyh_path : String?
  path = "C:/Windows/Fonts/msyh.ttc"
  {% if flag?(:windows) %}
    File.exists?(path) && FtMeasurer.available? ? path : nil
  {% else %}
    nil
  {% end %}
end

MSYH = msyh_path

describe "CachingMeasurer L2 shaping cache + segmented LRU (issue #56)" do
  it "L2: consecutive widths reflow without re-shaping (41 widths, shapes==1)" do
    inner = ShapeStubMeasurer.new
    c = CachingMeasurer.new(inner)
    text = "一二三四五六七八九十甲乙丙丁戊己庚辛壬癸子丑寅卯辰巳午未申酉戌亥" # 32 clusters
    st0 = c.stats
    w = 320.0_f32
    while w <= 360.0_f32
      s = c.measure(text, 0, 16.0_f32, w)
      s.width.should be > 0.0_f32
      w += 1.0_f32
    end
    st1 = c.stats
    st1[:shapes].should eq(st0[:shapes] + 1)          # 只 shape 一次
    st1[:reflows].should eq(st0[:reflows] + 40)       # 其余 40 个宽度只重排断点
    st1[:shapes].should be <= 4 * 32                  # 验收口径：≤ cluster 数常数倍
    # 回到原宽度：L1 命中，shape 增量为 0
    c.measure(text, 0, 16.0_f32, 320.0_f32)
    st2 = c.stats
    st2[:shapes].should eq(st1[:shapes])
    st2[:reflows].should eq(st1[:reflows])
    st2[:hits].should eq(st1[:hits] + 1)
  end

  it "L2 reflow equals full measure geometrically (same width)" do
    inner = ShapeStubMeasurer.new
    c = CachingMeasurer.new(inner)
    text = "宽度变化只重排断点不重 shape"
    w = 40.0_f32
    while w <= 200.0_f32
      a = c.measure(text, 0, 16.0_f32, w)
      b = inner.measure(text, 0, 16.0_f32, w)
      a.width.should eq(b.width)
      a.height.should eq(b.height)
      w += 7.0_f32
    end
  end

  it "measurers without shape_run keep the full-measure path (shapes==0)" do
    inner = StubMeasurer.new
    c = CachingMeasurer.new(inner)
    c.measure("hello", 0, 16.0_f32, 100.0_f32)
    c.measure("hello", 0, 16.0_f32, 120.0_f32)
    st = c.stats
    st[:shapes].should eq(0)
    st[:reflows].should eq(0)
    st[:misses].should eq(2)
    c.shape_cache_size.should eq(0)
  end

  it "segmented LRU: resize storm on one font evicts within its segment only" do
    inner = ShapeStubMeasurer.new
    c = CachingMeasurer.new(inner)
    # font 0 先存一条
    c.measure("keep-me", 0, 16.0_f32, Float32::INFINITY)
    # font 1 风暴：SEGMENT_CAP + 100 条 distinct（max_width=0 走全量路径直塞 L1）
    i = 0
    while i < CachingMeasurer::SEGMENT_CAP + 100
      c.measure("k#{i}", 1, 14.0_f32, 0.0_f32)
      i += 1
    end
    # font 0 的条目仍命中（不被别的字体风暴清掉）
    s = c.measure("keep-me", 0, 16.0_f32, Float32::INFINITY)
    s.width.should be > 0.0_f32
    c.stats[:evictions].should be > 0
  end

  it "global L1 stays bounded at CACHE_CAP" do
    inner = ShapeStubMeasurer.new
    c = CachingMeasurer.new(inner)
    i = 0
    while i < CachingMeasurer::CACHE_CAP + 50
      c.measure("g#{i}", 2, 14.0_f32, 0.0_f32)
      i += 1
    end
    c.l1_size.should be <= CachingMeasurer::CACHE_CAP
  end

  it "invalidate_font and clear drop both layers" do
    inner = ShapeStubMeasurer.new
    c = CachingMeasurer.new(inner)
    c.measure("你好", 7, 16.0_f32, 100.0_f32)
    c.measure("你好", 7, 16.0_f32, 120.0_f32)
    c.shape_cache_size.should eq(1)
    c.invalidate_font(7)
    c.shape_cache_size.should eq(0)
    c.l1_size.should eq(0)
    c.measure("你好", 7, 16.0_f32, 100.0_f32)
    c.stats[:misses].should eq(3)
    c.measure("世界", 9, 16.0_f32, 100.0_f32)
    c.clear
    c.shape_cache_size.should eq(0)
    c.l1_size.should eq(0)
    c.measure("世界", 9, 16.0_f32, 100.0_f32)
    c.stats[:misses].should eq(5)
  end

  it "FtMeasurer: cached reflow equals raw measure across widths; second pass L1-only" do
    unless p = MSYH
      pending "no Windows msyh.ttc on this platform"
      next
    end
    raw = FtMeasurer.open(p, 0)
    cached = CachingMeasurer.new(FtMeasurer.open(p, 0))
    text = "你好世界，测量缓存宽度分键。"
    widths = [40.0_f32, 80.0_f32, 120.0_f32, 200.0_f32, 320.0_f32, 359.5_f32, Float32::INFINITY]
    widths.each do |w|
      a = cached.measure(text, 0, 16.0_f32, w)
      b = raw.measure(text, 0, 16.0_f32, w)
      a.width.should eq(b.width)
      a.height.should eq(b.height)
    end
    st1 = cached.stats
    st1[:shapes].should eq(1)
    st1[:reflows].should eq(widths.size - 1)
    # 第二遍：全部 L1 命中，shape/reflow 增量 0
    widths.each do |w|
      a = cached.measure(text, 0, 16.0_f32, w)
      b = raw.measure(text, 0, 16.0_f32, w)
      a.width.should eq(b.width)
      a.height.should eq(b.height)
    end
    st2 = cached.stats
    st2[:shapes].should eq(st1[:shapes])
    st2[:reflows].should eq(st1[:reflows])
    st2[:hits].should eq(st1[:hits] + widths.size)
    cached.clear
    raw.close
  end
end
