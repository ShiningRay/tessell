require "spec"
require "../tools/lib/png"

# Issue #9：PNG 输出（stored zlib，标准解码器可读）、golden 比较与 diff 图。
describe "TessellPNG" do
  it "write → read round-trips RGBA pixels" do
    w = 7
    h = 5
    rgba = Bytes.new(w * h * 4)
    i = 0
    while i < rgba.size
      rgba[i] = (i % 251).to_u8
      rgba[i + 1] = ((i / 4) % 173).to_u8
      rgba[i + 2] = 64_u8
      rgba[i + 3] = 255_u8
      i += 4
    end
    path = File.tempname("tessell_png", ".png")
    TessellPNG.write(path, w, h, rgba)
    rw, rh, back = TessellPNG.read_rgba(path)
    rw.should eq(w)
    rh.should eq(h)
    back.should eq(rgba)
    File.delete(path)
  end

  it "rejects non-writer PNGs with a clear error" do
    path = File.tempname("tessell_png_bad", ".png")
    # 手工一个 IHDR 合法但 IDAT 为压缩块的文件——读取端明确报错不假装支持
    File.open(path, "wb") do |io|
      io.write("\x89PNG\r\n\x1a\n".to_slice)
    end
    expect_raises(ArgumentError) { TessellPNG.read_rgba(path) }
    File.delete(path)
  end

  it "converts TSRAW to RGBA" do
    tsraw = File.tempname("tessell", ".tsraw")
    File.open(tsraw, "wb") do |io|
      io.print "TSRAW 2 2 RGBA\n"
      io.write(Bytes[10, 20, 30, 255, 40, 50, 60, 255, 70, 80, 90, 255, 1, 2, 3, 4])
    end
    w, h, rgba = TessellPNG.from_tsraw(tsraw)
    w.should eq(2)
    h.should eq(2)
    rgba[0].should eq(10_u8)
    rgba[15].should eq(4_u8)
    File.delete(tsraw)
  end
end

def golden_write_png(path : String, fill : UInt8) : Nil
  rgba = Bytes.new(4 * 4 * 4, fill)
  rgba[3] = 255_u8
  TessellPNG.write(path, 4, 4, rgba)
end

describe "TessellGolden" do

  it "identical images pass with zero diff" do
    a = File.tempname("g_a", ".png")
    b = File.tempname("g_b", ".png")
    golden_write_png(a, 200_u8)
    golden_write_png(b, 200_u8)
    r = TessellGolden.compare(a, b)
    r.diff_pixels.should eq(0)
    r.pass?(0).should be_true
    File.delete(a)
    File.delete(b)
  end

  it "one differing pixel fails at threshold 0 and counts stats" do
    a = File.tempname("g_a", ".png")
    b = File.tempname("g_b", ".png")
    d = File.tempname("g_d", ".png")
    golden_write_png(a, 200_u8)
    golden_write_png(b, 200_u8)
    cur = TessellPNG.read_rgba(b)[2]
    cur[8] = 201_u8 # 一个通道差 1
    TessellPNG.write(b, 4, 4, cur)
    r = TessellGolden.compare(a, b, d)
    r.diff_pixels.should eq(1)
    r.max_channel_diff.should eq(1)
    r.pass?(0).should be_false
    r.pass?(1).should be_true
    _, _, diff_img = TessellPNG.read_rgba(d)
    diff_img[8].should eq(220_u8)   # 差异像素标红
    diff_img[0].should be < 220_u8  # 其余压暗
    File.delete(a)
    File.delete(b)
    File.delete(d)
  end

  it "compares TSRAW against PNG (mixed formats)" do
    png = File.tempname("g_p", ".png")
    tsraw = File.tempname("g_t", ".tsraw")
    rgba = Bytes.new(2 * 2 * 4, 128_u8)
    rgba[3] = 255_u8
    rgba[7] = 255_u8
    rgba[11] = 255_u8
    rgba[15] = 255_u8
    TessellPNG.write(png, 2, 2, rgba)
    File.open(tsraw, "wb") do |io|
      io.print "TSRAW 2 2 RGBA\n"
      io.write(rgba)
    end
    r = TessellGolden.compare(png, tsraw)
    r.diff_pixels.should eq(0)
    File.delete(png)
    File.delete(tsraw)
  end

  it "raises on size mismatch" do
    a = File.tempname("g_a", ".png")
    b = File.tempname("g_b", ".png")
    TessellPNG.write(a, 2, 2, Bytes.new(2 * 2 * 4, 255_u8))
    TessellPNG.write(b, 3, 3, Bytes.new(3 * 3 * 4, 255_u8))
    expect_raises(ArgumentError, "size mismatch") { TessellGolden.compare(a, b) }
    File.delete(a)
    File.delete(b)
  end
end
