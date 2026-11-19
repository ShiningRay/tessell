require "./spec_helper"
require "../src/tessell/text/font_stack"

# issue #55：字体集合（.ttc/.otc）是容器不是单 face——枚举 face 集合数、
# 读 sfnt name 表 family（nameID 16 优先）、集合内按 family 选 face。
#
# 平台门控：真实多字面字体只在有的平台跑。Windows 用 msgothic.ttc
# （MS Gothic / MS UI Gothic / MS PGothic 三字面，等宽 vs 比例）；其他平台
# 用 SystemFonts 发现任何 num_faces>1 且 family 可读的候选。缺前置时
# pending + next 说明原因（顶层 pending，不嵌套）。

private def gothic_path : String?
  candidates = {% begin %}
    {% if flag?(:windows) %}
      ["C:/Windows/Fonts/msgothic.ttc"]
    {% else %}
      [] of String
    {% end %}
  {% end %}
  candidates.find { |path| File.exists?(path) }
end

# 通用：第一个 num_faces>1 且各 face family 可读且不全相同的 .ttc 候选
private def generic_multi_face : Tuple(String, Array(String))?
  return nil unless Tessell::Text::FtMeasurer.available?
  Tessell::Text::SystemFonts.candidates.each do |path|
    next unless path.downcase.ends_with?(".ttc")
    n = Tessell::Text::FtMeasurer.num_faces_of(path)
    next unless n > 1
    fams = Array(String).new(n)
    ok = true
    0.upto(n - 1) do |i|
      f = Tessell::Text::FtMeasurer.face_family(path, i)
      if f
        fams << f.not_nil!
      else
        ok = false
      end
    end
    next unless ok
    return {path, fams} if fams.uniq.size > 1
  end
  nil
end

GENERIC = generic_multi_face
GOTHIC  = gothic_path

describe "Text::FontStack/SystemFonts ttc face enumeration (issue #55)" do
  it "FtMeasurer#num_faces reports face collection size" do
    if p = GOTHIC
      m = Tessell::Text::FtMeasurer.open(p, 0)
      m.num_faces.should eq(3)
      m.close
    else
      pending "no Windows msgothic.ttc on this platform"
    end
    unless GENERIC
      pending "no multi-face .ttc candidate discovered on this platform"
    end
    path, _fams = GENERIC.not_nil!
    n = Tessell::Text::FtMeasurer.num_faces_of(path)
    n.should be > 1
  end

  it "num_faces_of/face_family return safe values for missing files" do
    Tessell::Text::FtMeasurer.num_faces_of("__nope__/missing.ttf").should eq(0)
    Tessell::Text::FtMeasurer.face_family("__nope__/missing.ttf", 0).should be_nil
  end

  it "face_family reads sfnt name table (nameID 1/16), per collection index" do
    if p = GOTHIC
      Tessell::Text::FtMeasurer.face_family(p, 0).should eq("MS Gothic")
      Tessell::Text::FtMeasurer.face_family(p, 1).should eq("MS UI Gothic")
      Tessell::Text::FtMeasurer.face_family(p, 2).should eq("MS PGothic")
      # 实例方法默认读自己绑定的 index
      m1 = Tessell::Text::FtMeasurer.open(p, 1)
      m1.face_family.should eq("MS UI Gothic")
      m1.face_family(0).should eq("MS Gothic")
      m1.close
      # 越界 index 返回 nil，不抛异常
      m2 = Tessell::Text::FtMeasurer.open(p, 0)
      m2.face_family(99).should be_nil
      m2.close
    else
      pending "no Windows msgothic.ttc on this platform"
    end
    unless GENERIC
      pending "no multi-face .ttc candidate discovered on this platform"
    end
    path, fams = GENERIC.not_nil!
    Tessell::Text::FtMeasurer.face_family(path, 0).should eq(fams[0])
  end

  it "SystemFonts.find_face resolves collection-internal face by family" do
    if p = GOTHIC
      hit = Tessell::Text::SystemFonts.find_face(["msgothic"], family: "MS PGothic")
      hit.should_not be_nil
      hit.not_nil![:ttc_index].should eq(2)
      # 大小写不敏感
      hit2 = Tessell::Text::SystemFonts.find_face(["msgothic"], family: "ms ui gothic")
      hit2.not_nil![:ttc_index].should eq(1)
      # 选出的 face 真实覆盖 CJK 码点（不是同 face 复制）
      m = Tessell::Text::FtMeasurer.open(hit.not_nil![:path], hit.not_nil![:ttc_index])
      m.covers?("中文").should be_true
      m.close
      # family：nil 保持旧语义（index 0）
      hit3 = Tessell::Text::SystemFonts.find_face(["msgothic"])
      hit3.not_nil![:ttc_index].should eq(0)
    else
      pending "no Windows msgothic.ttc on this platform"
    end
    unless GENERIC
      pending "no multi-face .ttc candidate discovered on this platform"
    end
    path, fams = GENERIC.not_nil!
    pattern = File.basename(path, File.extname(path)).downcase
    k = 1
    found = false
    while k < fams.size
      next unless fams[k] != fams[0]
      hit = Tessell::Text::SystemFonts.find_face([pattern], family: fams[k])
      if hit
        hit.not_nil![:path].downcase.should eq(path.downcase)
        hit.not_nil![:ttc_index].should eq(k)
        found = true
      end
      k += 1
    end
    found.should be_true
  end

  it "find_face falls back to index 0 (with warning) when family misses" do
    unless p = GOTHIC
      pending "no Windows msgothic.ttc on this platform"
      next
    end
    hit = Tessell::Text::SystemFonts.find_face(["msgothic"], family: "No Such Family")
    hit.should_not be_nil
    hit.not_nil![:ttc_index].should eq(0)
    hit.not_nil![:path].downcase.includes?("msgothic").should be_true
  end

  it "same collection, different indices measure different advances" do
    unless p = GOTHIC
      pending "no Windows msgothic.ttc on this platform"
      next
    end
    m0 = Tessell::Text::FtMeasurer.open(p, 0)
    m2 = Tessell::Text::FtMeasurer.open(p, 2)
    s0 = m0.measure("III", 0, 16.0_f32, Float32::INFINITY)
    s2 = m2.measure("III", 0, 16.0_f32, Float32::INFINITY)
    # MS Gothic 等宽 vs MS PGothic 比例：同一字符串 advance 不同
    s0.width.should_not eq(s2.width)
    m0.close
    m2.close
  end

  it "FontStack.open family channel resolves index; unknown family keeps explicit ttc_index" do
    unless p = GOTHIC
      pending "no Windows msgothic.ttc on this platform"
      next
    end
    stack = Tessell::Text::FontStack.open([
      {path: p, ttc_index: 0, weight: Tessell::Text::FontStack::Weight::Regular, label: "gothic", family: "MS Gothic"},
      {path: p, ttc_index: 0, weight: Tessell::Text::FontStack::Weight::Fallback, label: "pgothic", family: "MS PGothic"},
      {path: p, ttc_index: 2, weight: Tessell::Text::FontStack::Weight::Bold, label: "explicit", family: nil},
    ])
    stack.face_count.should eq(3)
    s0 = stack.faces[0].measurer.measure("III", 0, 16.0_f32, Float32::INFINITY)
    s1 = stack.faces[1].measurer.measure("III", 0, 16.0_f32, Float32::INFINITY)
    # family 解析后确实是两张不同的脸（等宽 vs 比例）
    s0.width.should_not eq(s1.width)
    # family 未命中时保留显式 ttc_index 通道：entry 3 显式 index 2（比例字面）
    s2 = stack.faces[2].measurer.measure("III", 0, 16.0_f32, Float32::INFINITY)
    s2.width.should eq(s1.width)
    stack.close
  end
end
