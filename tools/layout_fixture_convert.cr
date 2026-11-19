# Taffy XML fixture → Tessell 布局 oracle fixture 转换器（issue #64）。
#
# 输入：fixtures/layout/upstream/taffy/*.xml（手工挑出的受控子集，保留原文件审计）
# 输出：fixtures/layout/taffy/*.json（oracle fixture）+ 转换报告（stdout）
#
# 可复现：同输入同输出；只支持与 Tessell::Layout 语义对应的子集，
# 不支持的特性（border/margin/min-max/align/justify/wrap/%尺寸/text 叶子等）
# 直接跳过并记录原因——不静默转换成错误语义。
#
# 用法：crystal run tools/layout_fixture_convert.cr
#
# 上游来源与许可证见 fixtures/layout/README.md（Taffy MIT，commit 1abd8ee）。

require "xml"
require "json"
require "file_utils"

UPSTREAM_DIR = File.expand_path("#{__DIR__}/../fixtures/layout/upstream/taffy").gsub('\\', "/")
OUT_DIR      = File.expand_path("#{__DIR__}/../fixtures/layout/taffy").gsub('\\', "/")

UPSTREAM_COMMIT = "1abd8ee"

record Skip, name : String, reason : String

class FixNode
  property width : Float32?          # null = Auto
  property height : Float32?         # null = Auto
  property direction : String        # "row" | "column"
  property grow : Float32            # >0 且来自 flex-basis:0%（Fraction 语义）
  property gap : Float32             # 主轴 gap
  property padding : Array(Float32)  # [top, right, bottom, left]
  property children : Array(FixNode)

  def initialize(@width : Float32? = nil, @height : Float32? = nil,
                 @direction : String = "row", @grow : Float32 = 0.0_f32,
                 @gap : Float32 = 0.0_f32,
                 @padding : Array(Float32) = [0.0_f32, 0.0_f32, 0.0_f32, 0.0_f32],
                 @children : Array(FixNode) = [] of FixNode)
  end
end

def parse_px(attr : String) : Float32?
  s = attr
  s = s[0...-2] if s.ends_with?("px")
  s.to_f32?
end

# 特性过滤（与 Tessell::Layout 语义对照）。不支持的组合返回 nil + SKIP 原因。
def convert_tree(xnode : XML::Node, is_root : Bool, name : String,
                 skips : Array(Skip)) : FixNode?
  tag = xnode.name
  if tag == "text"
    skips << Skip.new(name, "text 叶子（期望宽度来自 taffy 测试闭包，非 CSS）")
    return nil
  end
  unless tag == "div"
    skips << Skip.new(name, "未知元素 <#{tag}>")
    return nil
  end

  attrs = {} of String => String
  xnode.attributes.each { |a| attrs[a.name] = a.content }

  if (b = attrs["box-sizing"]?) && b != "content-box"
    skips << Skip.new(name, "box-sizing=#{b}（Tessell 内核只有 content-box 口径）")
    return nil
  end
  if (d = attrs["direction"]?) && d != "ltr"
    skips << Skip.new(name, "direction=#{d}（仅 ltr）")
    return nil
  end
  pos = attrs["position"]? || "relative"
  unless is_root ? (pos == "absolute" || pos == "relative") : (pos == "relative")
    skips << Skip.new(name, "position=#{pos}（根 absolute/其余 relative 之外不支持）")
    return nil
  end
  if (disp = attrs["display"]?) && disp != "flex"
    skips << Skip.new(name, "display=#{disp}（仅 flex）")
    return nil
  end
  if attrs["flex-direction"]?.in?("row-reverse", "column-reverse")
    skips << Skip.new(name, "flex-direction reverse（内核无 reverse）")
    return nil
  end
  if attrs["flex-wrap"]?
    skips << Skip.new(name, "flex-wrap（内核不换行）")
    return nil
  end
  %w(margin margin-left margin-right margin-top margin-bottom
     min-width max-width min-height max-height border-left border-right
     border-top border-bottom aspect-ratio align-self
     justify-content left right top bottom inset).each do |k|
    if attrs[k]?
      skips << Skip.new(name, "#{k}=#{attrs[k]}（内核无此语义）")
      return nil
    end
  end
  # align-items=stretch 是 taffy 默认（等同缺省）；start/center/end 内核无此语义
  if (ai = attrs["align-items"]?) && ai != "stretch"
    skips << Skip.new(name, "align-items=#{ai}（内核交叉轴只按内容/Stretch）")
    return nil
  end
  if (fs = attrs["flex-shrink"]?) && fs.to_f32? != 0.0_f32
    skips << Skip.new(name, "flex-shrink=#{fs}（内核无 shrink，溢出行为不同）")
    return nil
  end

  w : Float32? = nil
  h : Float32? = nil
  %w(width height).each do |k|
    if v = attrs[k]?
      if v.ends_with?("%")
        skips << Skip.new(name, "#{k}=#{v}（% 尺寸不支持）")
        return nil
      end
      p = parse_px(v)
      if p.nil?
        skips << Skip.new(name, "#{k}=#{v}（无法解析为 px）")
        return nil
      end
      if k == "width"
        w = p
      else
        h = p
      end
    end
  end

  # padding（content-box 口径：外层尺寸 = 尺寸 + padding）
  pad = [0.0_f32, 0.0_f32, 0.0_f32, 0.0_f32] # [top, right, bottom, left]
  %w(top right bottom left).each_with_index do |side, i|
    if v = attrs["padding-#{side}"]?
      p = parse_px(v)
      if p.nil?
        skips << Skip.new(name, "padding-#{side}=#{v}（无法解析）")
        return nil
      end
      pad[i] = p
    end
  end

  # 主轴 gap：row 容器取 column-gap，column 容器取 row-gap；
  # 另一轴 gap 必须缺省/0（内核只有主轴 gap）。
  direction = attrs["flex-direction"]? == "column" ? "column" : "row"
  main_gap_attr = direction == "row" ? "column-gap" : "row-gap"
  cross_gap_attr = direction == "row" ? "row-gap" : "column-gap"
  gap = 0.0_f32
  if v = attrs[main_gap_attr]?
    g = parse_px(v)
    if g.nil?
      skips << Skip.new(name, "#{main_gap_attr}=#{v}（无法解析）")
      return nil
    end
    gap = g
  end
  if v = attrs[cross_gap_attr]?
    g = parse_px(v) || 0.0_f32
    if g != 0.0_f32
      skips << Skip.new(name, "#{cross_gap_attr}=#{v}（内核只有主轴 gap）")
      return nil
    end
  end

  # flex-basis 只允许 0%/0px（等价，映射 Fraction）；grow 需要配对零 basis
  basis = attrs["flex-basis"]?
  if basis && basis != "0%" && basis != "0px"
    skips << Skip.new(name, "flex-basis=#{basis}（仅 0%/0px 映射 Fraction）")
    return nil
  end
  grow = attrs["flex-grow"]?.try(&.to_f32?) || 0.0_f32
  if grow > 0.0_f32 && basis.nil?
    skips << Skip.new(name, "flex-grow=#{grow} 无 flex-basis=0%（内核 Fraction 是 basis 0 语义）")
    return nil
  end

  node = FixNode.new
  node.width = w
  node.height = h
  node.direction = direction
  node.grow = basis == "0%" ? grow : 0.0_f32
  node.gap = gap
  node.padding = pad
  node.children = [] of FixNode
  xnode.children.each do |c|
    next unless c.element?
    child = convert_tree(c, false, name, skips)
    return nil unless child
    node.children << child
  end
  node
end

# 收集期望坐标（父级相对 → 绝对），pre-order 与输入树对应。
# use-rounding=true 的 taffy 期望应为整数；非整数说明有 rounding 语义，
# 与 Tessell 纯浮点内核不可比 → 转换失败（调用方过滤）。
def collect_expected(xnode : XML::Node, ox : Float32, oy : Float32,
                     sink : Array(Tuple(Float32, Float32, Float32, Float32))) : Bool
  return false unless xnode.name == "node"
  x = xnode["x"]?.try(&.to_f32?)
  y = xnode["y"]?.try(&.to_f32?)
  w = xnode["width"]?.try(&.to_f32?)
  h = xnode["height"]?.try(&.to_f32?)
  return false if x.nil? || y.nil? || w.nil? || h.nil?
  ax, ay = ox + x, oy + y
  return false unless [{ax, "x"}, {ay, "y"}, {w, "w"}, {h, "h"}].all? { |pair|
    pair[0].trunc == pair[0]
  }
  sink << {ax, ay, w, h}
  xnode.children.select(&.element?).all? do |c|
    collect_expected(c, ax, ay, sink)
  end
end

def count_input_divs(xnode : XML::Node) : Int32
  n = xnode.name == "div" ? 1 : 0
  xnode.children.select(&.element?).sum { |c| count_input_divs(c) } + n
end

def count_expected_nodes(xnode : XML::Node) : Int32
  return 0 unless xnode.name == "node"
  1 + xnode.children.select(&.element?).sum { |c| count_expected_nodes(c) }
end

def write_node(j : JSON::Builder, node : FixNode) : Nil
  j.object do
    j.field "width", node.width
    j.field "height", node.height
    j.field "direction", node.direction
    j.field "grow", node.grow
    j.field "gap", node.gap
    j.field "padding" do
      j.array do
        node.padding.each { |p| j.number(p) }
      end
    end
    j.field "children" do
      j.array do
        node.children.each { |c| write_node(j, c) }
      end
    end
  end
end

FileUtils.mkdir_p(OUT_DIR)
skips = [] of Skip
converted = 0
kept = [] of String

Dir.glob("#{UPSTREAM_DIR}/*.xml").sort.each do |path|
  name = File.basename(path, ".xml").sub(/__content_box_ltr$/, "")
  xml = XML.parse(File.read(path))
  test = xml.root
  raise "bad fixture #{path}" unless test && test.name == "test"

  rounding = test["use-rounding"]? != "false"

  viewport = test.children.find { |c| c.element? && c.name == "viewport" }
  input = test.children.find { |c| c.element? && c.name == "input" }
  expectations = test.children.find { |c| c.element? && c.name == "expectations" }
  if viewport.nil? || input.nil? || expectations.nil?
    skips << Skip.new(name, "缺 viewport/input/expectations 节")
    next
  end

  vnode = viewport.children.find(&.element?)
  vw_attr = vnode.try(&.["width"]?)
  vh_attr = vnode.try(&.["height"]?)
  vw = vw_attr.nil? || vw_attr == "max-content" ? nil : parse_px(vw_attr)
  vh = vh_attr.nil? || vh_attr == "max-content" ? nil : parse_px(vh_attr)
  if (vw_attr && vw_attr != "max-content" && vw.nil?) ||
     (vh_attr && vh_attr != "max-content" && vh.nil?)
    skips << Skip.new(name, "viewport 尺寸无法解析（#{vw_attr}/#{vh_attr}）")
    next
  end

  root_div = input.children.find(&.element?)
  if root_div.nil?
    skips << Skip.new(name, "input 无根 div")
    next
  end

  exp_root = expectations.children.find(&.element?)
  if exp_root.nil?
    skips << Skip.new(name, "expectations 为空")
    next
  end

  tree = convert_tree(root_div, true, name, skips)
  next if tree.nil?

  if count_input_divs(root_div) != count_expected_nodes(exp_root)
    skips << Skip.new(name, "期望节点数与输入树不一致")
    next
  end
  expected = [] of Tuple(Float32, Float32, Float32, Float32)
  unless collect_expected(exp_root, 0.0_f32, 0.0_f32, expected)
    skips << Skip.new(name, "期望含非整数值（use-rounding=#{rounding}，与纯浮点内核不可比）")
    next
  end

  json = JSON.build do |j|
    j.object do
      j.field "name", name
      j.field "source" do
        j.object do
          j.field "repo", "DioxusLabs/taffy"
          j.field "commit", UPSTREAM_COMMIT
          j.field "path", "tests/xml/flex/#{File.basename(path)}"
          j.field "license", "MIT"
        end
      end
      j.field "viewport" do
        j.object do
          j.field "width", vw
          j.field "height", vh
        end
      end
      j.field "tree" { write_node(j, tree) }
      j.field "expected" do
        j.array do
          expected.each do |e|
            j.object do
              j.field "x", e[0]
              j.field "y", e[1]
              j.field "w", e[2]
              j.field "h", e[3]
            end
          end
        end
      end
    end
  end
  File.write("#{OUT_DIR}/#{name}.json", json)
  converted += 1
  kept << name
end

puts "converted=#{converted}"
puts "skipped=#{skips.size}"
reason_counts = Hash(String, Int32).new(0)
skips.each { |s| reason_counts[s.reason.sub(/（.*/, "")] += 1 }
reason_counts.to_a.sort_by { |(_, v)| -v }.each do |(reason, n)|
  puts "  #{n} × #{reason}"
end
skips.each { |s| puts "  SKIP #{s.name}: #{s.reason}" }
puts "kept: #{kept.join(", ")}"
