require "./spec_helper"
require "../src/tessell/layout"
require "../src/tessell/text/measurer"
require "json"

include Tessell
include Tessell::Layout

# issue #64：布局外部正确性 oracle——受控 Taffy fixtures 子集 + 本地文本
# 测量 fixtures。纯函数 Layout.solve 对比上游期望；缓存路径（solve_cached）
# 与纯函数路径几何一致。known-failures 清单（fixtures/layout/known_failures.json）
# 记录已知语义缺口；豁免条目一旦开始通过必须清除（spec 强制）。
#
# 不支持特性由 tools/layout_fixture_convert.cr 在转换期过滤并报告
# （通过/豁免/不支持口径见 fixtures/layout/README.md）。
# 本套件不宣称 CSS 全量兼容。

FIXTURE_ROOT = File.expand_path("../fixtures/layout", __DIR__).gsub('\\', "/")

class ORText
  include JSON::Serializable
  property content : String
  property font_size : Float32
  property font_id : Int32
end

class ORNode
  include JSON::Serializable
  property width : Float32?
  property height : Float32?
  property direction : String
  property grow : Float32
  property gap : Float32
  property padding : Array(Float32)
  property text : ORText?
  property children : Array(ORNode)
end

class ORFixture
  property name : String
  property viewport_width : Float32?
  property viewport_height : Float32?
  property tree : ORNode
  property expected : Array(ORRect)

  def initialize(@name : String, @viewport_width : Float32?, @viewport_height : Float32?,
                 @tree : ORNode, @expected : Array(ORRect))
  end
end

class ORRect
  include JSON::Serializable
  property x : Float32
  property y : Float32
  property w : Float32
  property h : Float32

  def initialize(@x : Float32, @y : Float32, @w : Float32, @h : Float32)
  end
end

# 期望/树字段的读取口径与转换器输出对齐：viewport 是嵌套对象。
class ORViewport
  include JSON::Serializable
  property width : Float32?
  property height : Float32?
end

def load_fixtures(dir : String) : Array(ORFixture)
  fixtures = [] of ORFixture
  Dir.glob("#{dir}/*.json").sort.each do |path|
    raw = JSON.parse(File.read(path))
    name = raw["name"].as_s
    vp = ORViewport.from_json(raw["viewport"].to_json)
    tree = ORNode.from_json(raw["tree"].to_json)
    expected = raw["expected"].as_a.map do |e|
      ORRect.new(e["x"].as_f.to_f32, e["y"].as_f.to_f32,
        e["w"].as_f.to_f32, e["h"].as_f.to_f32)
    end
    fixtures << ORFixture.new(name, vp.width, vp.height, tree, expected)
  end
  fixtures.sort_by!(&.name)
  fixtures
end

def build_node(node : ORNode, id : String, row : Bool) : Layout::LayoutNode
  w : Dimension = node.width ? Fixed.new(node.width.not_nil!) : Auto.new
  h : Dimension = node.height ? Fixed.new(node.height.not_nil!) : Auto.new
  # grow（flex-basis:0%）→ 主轴 Fraction；另一轴保持 Auto/Fixed
  if node.grow > 0.0_f32
    if row
      w = Fraction.new(node.grow)
    else
      h = Fraction.new(node.grow)
    end
  end
  direction = row ? Layout::Direction::Horizontal : Layout::Direction::Vertical
  children = node.children.map_with_index do |c, i|
    build_node(c, "#{id}/#{i}", node.direction == "row")
  end
  Layout::LayoutNode.new(
    id: id,
    width: w, height: h,
    padding: Insets.new(node.padding[0], node.padding[1], node.padding[2], node.padding[3]),
    direction: direction,
    gap: node.gap,
    children: children,
    text: node.text ? node.text.not_nil!.content : "",
    font_id: node.text ? node.text.not_nil!.font_id : 0,
    font_size: node.text ? node.text.not_nil!.font_size : 0.0_f32
  )
end

def collect_abs(box : Layout::LayoutBox,
                sink : Array(Tuple(Float32, Float32, Float32, Float32))) : Nil
  sink << {box.rect.origin.x, box.rect.origin.y, box.rect.size.width, box.rect.size.height}
  box.children.each { |c| collect_abs(c, sink) }
end

def rects_match(actual : Array(Tuple(Float32, Float32, Float32, Float32)),
                expected : Array(ORRect), eps : Float32 = 0.01_f32) : Bool
  return false unless actual.size == expected.size
  actual.zip(expected).all? do |(a, e)|
    (a[0] - e.x).abs <= eps && (a[1] - e.y).abs <= eps &&
      (a[2] - e.w).abs <= eps && (a[3] - e.h).abs <= eps
  end
end

def solve_pure(f : ORFixture) : Array(Tuple(Float32, Float32, Float32, Float32))
  node = build_node(f.tree, "n0", f.tree.direction == "row")
  measurer : Tessell::Text::Measurer? = f.tree.tree_has_text? ? Tessell::Text::StubMeasurer.new : nil
  constraints = Tessell::Constraints.new(0.0_f32,
    f.viewport_width || Float32::INFINITY,
    0.0_f32,
    f.viewport_height || Float32::INFINITY)
  box = Layout.solve(node, constraints, measurer: measurer)
  rects = [] of Tuple(Float32, Float32, Float32, Float32)
  collect_abs(box, rects)
  rects
end

def solve_cached(f : ORFixture) : Array(Tuple(Float32, Float32, Float32, Float32))
  node = build_node(f.tree, "n0", f.tree.direction == "row")
  measurer : Tessell::Text::Measurer? = f.tree.tree_has_text? ? Tessell::Text::StubMeasurer.new : nil
  constraints = Tessell::Constraints.new(0.0_f32,
    f.viewport_width || Float32::INFINITY,
    0.0_f32,
    f.viewport_height || Float32::INFINITY)
  cached = Layout.build_cached(node)
  result = Layout.solve_cached(cached, constraints, measurer: measurer)
  rects = [] of Tuple(Float32, Float32, Float32, Float32)
  collect_abs(result[:box], rects)
  rects
end

class ORNode
  def tree_has_text? : Bool
    return true if @text
    @children.any?(&.tree_has_text?)
  end
end

TAFFY_FIXTURES  = load_fixtures("#{FIXTURE_ROOT}/taffy")
LOCAL_FIXTURES  = load_fixtures("#{FIXTURE_ROOT}/local")
KNOWN_FAILURES  = JSON.parse(File.read("#{FIXTURE_ROOT}/known_failures.json")).as_h

describe "layout oracle fixtures (issue #64)" do
  it "supported fixtures match the external oracle; known-failures still fail and never silently pass" do
    passed = 0
    known = 0
    failures = [] of String
    (TAFFY_FIXTURES + LOCAL_FIXTURES).each do |f|
      rects = solve_pure(f)
      ok = rects_match(rects, f.expected)
      kf = KNOWN_FAILURES[f.name]?
      if kf
        # 豁免条目必须仍然失败——开始通过即豁免失效，强制清除（issue #64）
        if ok
          failures << "EXPIRED-KNOWN-FAIL #{f.name}：「#{kf}」现在通过了，请清除该豁免条目"
        else
          known += 1
        end
      elsif ok
        passed += 1
      else
        detail = rects.zip(f.expected).map_with_index do |(a, e), i|
          "  node[#{i}] got (#{a[0]},#{a[1]},#{a[2]}×#{a[3]}) want (#{e.x},#{e.y},#{e.w}×#{e.h})"
        end.join("\n")
        failures << "FAIL #{f.name}:\n#{detail}"
      end
    end
    report = "LAYOUT-ORACLE pass=#{passed} known_fail=#{known} total=#{TAFFY_FIXTURES.size + LOCAL_FIXTURES.size} known_failures_manifest=#{KNOWN_FAILURES.size}"
    puts report
    failures.empty?.should be_true, "oracle mismatch:\n#{failures.join("\n")}\n#{report}"
  end

  it "cached path geometry equals pure oracle on every fixture" do
    mismatches = [] of String
    (TAFFY_FIXTURES + LOCAL_FIXTURES).each do |f|
      pure = solve_pure(f)
      cached = solve_cached(f)
      unless pure.zip(cached).all? { |(a, b)| a == b }
        mismatches << f.name
      end
    end
    mismatches.empty?.should be_true, "缓存路径与纯函数 oracle 不一致: #{mismatches.join(", ")}"
  end
end
