require "./spec_helper"
require "../src/tessell/geometry"
require "../src/tessell/render/polygon"
require "../src/tessell/render/backend"
require "../src/tessell/text/glyph_atlas"

# M3-WP4 stage B: CPU/RecordingBackend protocol coverage (no window).
# GL stencil/cover visual correctness and stencil_bits query are exercised by
# examples/m3_path_window.cr (--verify / --no-stencil), not by this spec.

# RecordingBackend local copy (mirrors backend_protocol_spec) to avoid coupling.
private class PWRecordingBackend < Tessell::Render::Backend
  getter calls : Array(String)
  getter last_dirty : Array(Tessell::Rect)?
  @page_tex : Array(Int32)
  @submitted_quads : Int32
  @scissor_calls : Int32
  @culled_quads : Int32
  @stencil_fills : Int32

  def initialize
    @calls = [] of String
    @last_dirty = nil
    @page_tex = [] of Int32
    @submitted_quads = 0
    @scissor_calls = 0
    @culled_quads = 0
    @stencil_fills = 0
  end

  def init(width : Int32, height : Int32) : Nil
    @calls << "init"
  end

  def resize(width : Int32, height : Int32) : Nil
    @calls << "resize"
  end

  def begin_frame(dirty : Array(Tessell::Rect)? = nil,
                  theme : Tessell::Render::Theme = Tessell::Render::Theme.light) : Nil
    @calls << "begin_frame"
    @last_dirty = dirty
    @submitted_quads = 0
    @scissor_calls = 0
    @culled_quads = 0
    @stencil_fills = 0
  end

  def sync_atlas(atlas : Tessell::Text::GlyphAtlas) : Nil
    @calls << "sync_atlas"
  end

  def draw_text(vertices : Array(Tessell::Render::Vertex),
                batches : Array(Tessell::Render::TextBatch),
                batch_count : Int32 = batches.size) : Int32
    @calls << "draw_text"
    @submitted_quads
  end

  def end_frame : Nil
    @calls << "end_frame"
  end

  def close : Nil
    @calls << "close"
  end

  def stats : Tessell::Render::FrameStats
    Tessell::Render::FrameStats.new(@submitted_quads, @scissor_calls,
      @culled_quads, @stencil_fills)
  end

  def draw_polygon(points : Array(Tessell::Point), color : UInt32,
                   even_odd : Bool = true) : Bool
    @calls << "draw_polygon"
    @stencil_fills += 1
    true
  end

  def resolved_texture(page : Int32) : Int32
    0
  end
end

private class PWNoPolyBackend < Tessell::Render::Backend
  def init(width : Int32, height : Int32) : Nil; end
  def resize(width : Int32, height : Int32) : Nil; end
  def begin_frame(dirty : Array(Tessell::Rect)? = nil,
                  theme : Tessell::Render::Theme = Tessell::Render::Theme.light) : Nil; end
  def sync_atlas(atlas : Tessell::Text::GlyphAtlas) : Nil; end
  def draw_text(vertices : Array(Tessell::Render::Vertex),
                batches : Array(Tessell::Render::TextBatch),
                batch_count : Int32 = batches.size) : Int32
    0
  end
  def end_frame : Nil; end
  def close : Nil; end
  def stats : Tessell::Render::FrameStats
    Tessell::Render::FrameStats.new
  end
  def resolved_texture(page : Int32) : Int32
    0
  end
end

private def pentagram_star(cx : Float32, cy : Float32, r : Float32)
  pts = [] of Tessell::Point
  5.times do |i|
    angle = -Math::PI / 2.0 + i.to_f64 * 4.0 * Math::PI / 5.0
    pts << Tessell::Point.new(cx + r.to_f64 * Math.cos(angle),
      cy + r.to_f64 * Math.sin(angle))
  end
  pts
end

describe "M3-WP4 path (CPU + backend protocol, no window)" do
  it "base backend draw_polygon returns false (unsupported)" do
    b = PWNoPolyBackend.new
    pts = pentagram_star(0.0_f32, 0.0_f32, 10.0_f32)
    b.draw_polygon(pts, 0xFF0000FF_u32).should be_false
    b.stats.stencil_fills.should eq(0)
  end

  it "recording backend draw_polygon records call and increments stencil_fills" do
    b = PWRecordingBackend.new
    pts = pentagram_star(0.0_f32, 0.0_f32, 10.0_f32)
    b.draw_polygon(pts, 0xFF0000FF_u32).should be_true
    b.calls.includes?("draw_polygon").should be_true
    b.stats.stencil_fills.should eq(1)
    b.draw_polygon(pts, 0xFF00FF00_u32).should be_true
    b.stats.stencil_fills.should eq(2)
  end

  it "even-odd pentagram: center outside, top arm inside, far outside false" do
    # Same vertex order/geometry as polygon_spec and m3_path_window example.
    cx = 400.37_f32
    cy = 300.61_f32
    pts = pentagram_star(cx, cy, 100.0_f32)
    poly = Tessell::Render::Polygon.new(pts)
    # center falls in the central pentagon -> even-odd parity 0 (outside)
    poly.contains?(Tessell::Point.new(cx, cy)).should be_false
    # point inside top arm (toward outer tip, along vertical axis)
    poly.contains?(Tessell::Point.new(cx, cy - 80.0_f32)).should be_true
    # clearly outside
    poly.contains?(Tessell::Point.new(cx - 200.0_f32, cy - 200.0_f32)).should be_false
  end

  it "mask pixel-center sampling matches contains? (bounds-aligned)" do
    cx = 400.37_f32
    cy = 300.61_f32
    pts = pentagram_star(cx, cy, 100.0_f32)
    poly = Tessell::Render::Polygon.new(pts)
    b = poly.bounds
    bx0 = b.origin.x.floor.to_i
    by0 = b.origin.y.floor.to_i
    w = b.max_x.ceil.to_i - bx0
    h = b.max_y.ceil.to_i - by0
    sink = Bytes.new(w * h)
    covered = Tessell::Render::Polygon.mask(pts,
      Tessell::Rect.new(bx0.to_f32, by0.to_f32, w.to_f32, h.to_f32), sink)
    manual = 0
    y = 0
    while y < h
      x = 0
      while x < w
        inside = poly.contains?(Tessell::Point.new(bx0 + x + 0.5_f32, by0 + y + 0.5_f32))
        v = sink[y * w + x]
        if inside
          v.should eq(1_u8)
          manual += 1
        else
          v.should eq(0_u8)
        end
        x += 1
      end
      y += 1
    end
    covered.should eq(manual)
    covered.should be > 0
  end

  it "emit_fan returns n-2 triangles and reuses first vertex" do
    pts = pentagram_star(400.37_f32, 300.61_f32, 100.0_f32)
    sink = Slice(Float32).new((pts.size - 2) * 6)
    tris = Tessell::Render::Polygon.emit_fan(pts, sink)
    tris.should eq(pts.size - 2)
    3.times do |i|
      base = i * 6
      sink[base].should be_close(pts[0].x, 0.0001_f32)
      sink[base + 1].should be_close(pts[0].y, 0.0001_f32)
      sink[base + 2].should be_close(pts[i + 1].x, 0.0001_f32)
      sink[base + 3].should be_close(pts[i + 1].y, 0.0001_f32)
      sink[base + 4].should be_close(pts[i + 2].x, 0.0001_f32)
      sink[base + 5].should be_close(pts[i + 2].y, 0.0001_f32)
    end
  end

  it "bounds encloses translated star and has positive area" do
    pts = pentagram_star(400.37_f32, 300.61_f32, 100.0_f32)
    poly = Tessell::Render::Polygon.new(pts)
    b = poly.bounds
    b.origin.x.should be < 400.37_f32
    b.origin.y.should be < 300.61_f32
    b.max_x.should be > 400.37_f32
    b.max_y.should be > 300.61_f32
    b.size.width.should be > 0.0_f32
    b.size.height.should be > 0.0_f32
  end
end
