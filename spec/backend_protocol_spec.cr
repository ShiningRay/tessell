require "./spec_helper"
require "../src/tessell/render/backend"
require "../src/tessell/render/dirty"
require "../src/tessell/text/glyph_atlas"

# RecordingBackend (M3-WP1 spec): records call sequence and implements CPU-side
# dirty-rect culling/scissor stats for protocol verification (no GL).
class RecordingBackend < Tessell::Render::Backend
  getter calls : Array(String)
  getter last_dirty : Array(Tessell::Rect)?
  getter width : Int32
  getter height : Int32
  getter atlas_synced : Bool
  property record_calls : Bool
  @page_tex : Array(Int32)
  @submitted_quads : Int32
  @scissor_calls : Int32
  @culled_quads : Int32

  def initialize
    @calls = [] of String
    @last_dirty = nil
    @width = 0
    @height = 0
    @atlas_synced = false
    @record_calls = true
    @page_tex = [] of Int32
    @submitted_quads = 0
    @scissor_calls = 0
    @culled_quads = 0
  end

  def init(width : Int32, height : Int32) : Nil
    @calls << "init" if @record_calls
    @width = width
    @height = height
  end

  def resize(width : Int32, height : Int32) : Nil
    @calls << "resize" if @record_calls
    @width = width
    @height = height
  end

  def begin_frame(dirty : Array(Tessell::Rect)? = nil) : Nil
    @calls << "begin_frame" if @record_calls
    @last_dirty = dirty
    @submitted_quads = 0
    @scissor_calls = 0
    @culled_quads = 0
  end

  def sync_atlas(atlas : Tessell::Text::GlyphAtlas) : Nil
    @calls << "sync_atlas" if @record_calls
    @atlas_synced = true
    # backend owns texture resolution: synthesize texture ids per page
    while @page_tex.size < atlas.page_count
      @page_tex << (1000 + @page_tex.size)
    end
  end

  def draw_text(vertices : Array(Tessell::Render::Vertex), batches : Array(Tessell::Render::TextBatch), batch_count : Int32 = batches.size) : Int32
    @calls << "draw_text" if @record_calls
    dirty = @last_dirty
    if dirty.nil?
      @scissor_calls = 0
      @culled_quads = 0
      @submitted_quads = total_quads(batches, batch_count)
    else
      rects = dirty.not_nil!
      if rects.empty?
        @scissor_calls = 0
        @culled_quads = total_quads(batches, batch_count)
        @submitted_quads = 0
      else
        @scissor_calls = rects.size
        classify(vertices, batches, batch_count, rects)
      end
    end
    @submitted_quads
  end

  def end_frame : Nil
    @calls << "end_frame" if @record_calls
  end

  def close : Nil
    @calls << "close" if @record_calls
  end

  def stats : Tessell::Render::FrameStats
    Tessell::Render::FrameStats.new(@submitted_quads, @scissor_calls, @culled_quads)
  end

  def resolved_texture(page : Int32) : Int32
    return 0 if page < 0 || page >= @page_tex.size
    @page_tex[page]
  end

  private def total_quads(batches : Array(Tessell::Render::TextBatch), batch_count : Int32) : Int32
    sum = 0
    i = 0
    while i < batch_count
      b = batches[i]
      sum += b.count // 4 if b.count > 0
      i += 1
    end
    sum
  end

  private def classify(vertices : Array(Tessell::Render::Vertex), batches : Array(Tessell::Render::TextBatch), batch_count : Int32, rects : Array(Tessell::Rect)) : Nil
    @submitted_quads = 0
    @culled_quads = 0
    bi = 0
    while bi < batch_count
      b = batches[bi]
      if b.count > 0
        vi = b.start
        vend = b.start + b.count
        while vi < vend
          v0 = vertices[vi]
          v1 = vertices[vi + 1]
          v2 = vertices[vi + 2]
          v3 = vertices[vi + 3]
          ql = min4(v0.x, v1.x, v2.x, v3.x)
          qt = min4(v0.y, v1.y, v2.y, v3.y)
          qr = max4(v0.x, v1.x, v2.x, v3.x)
          qb = max4(v0.y, v1.y, v2.y, v3.y)
          if intersects_any(ql, qt, qr, qb, rects)
            @submitted_quads += 1
          else
            @culled_quads += 1
          end
          vi += 4
        end
      end
      bi += 1
    end
  end

  private def min4(a : Float32, b : Float32, c : Float32, d : Float32) : Float32
    m = a < b ? a : b
    m = c if c < m
    m = d if d < m
    m
  end

  private def max4(a : Float32, b : Float32, c : Float32, d : Float32) : Float32
    m = a > b ? a : b
    m = c if c > m
    m = d if d > m
    m
  end

  private def quad_intersects_rect(ql : Float32, qt : Float32, qr : Float32, qb : Float32, r : Tessell::Rect) : Bool
    rl = r.origin.x
    rt = r.origin.y
    rr = rl + r.size.width
    rb = rt + r.size.height
    !(qr <= rl || ql >= rr || qb <= rt || qt >= rb)
  end

  private def intersects_any(ql : Float32, qt : Float32, qr : Float32, qb : Float32, rects : Array(Tessell::Rect)) : Bool
    i = 0
    while i < rects.size
      return true if quad_intersects_rect(ql, qt, qr, qb, rects[i])
      i += 1
    end
    false
  end
end

def make_quad(vertices : Array(Tessell::Render::Vertex), l : Float32, t : Float32, r : Float32, b : Float32) : Nil
  vertices << Tessell::Render::Vertex.new(l, t, 0.0_f32, 0.0_f32, 0xffffffff_u32)
  vertices << Tessell::Render::Vertex.new(r, t, 1.0_f32, 0.0_f32, 0xffffffff_u32)
  vertices << Tessell::Render::Vertex.new(r, b, 1.0_f32, 1.0_f32, 0xffffffff_u32)
  vertices << Tessell::Render::Vertex.new(l, b, 0.0_f32, 1.0_f32, 0xffffffff_u32)
end

describe "Backend protocol (M3-WP1)" do
  it "records call sequence init->resize->begin_frame->sync_atlas->draw_text->end_frame" do
    backend = RecordingBackend.new
    atlas = Tessell::Text::GlyphAtlas.new(128, 256)
    vertices = [] of Tessell::Render::Vertex
    batches = [] of Tessell::Render::TextBatch
    backend.init(800, 600)
    backend.resize(1024, 768)
    backend.begin_frame(nil)
    backend.sync_atlas(atlas)
    backend.draw_text(vertices, batches, 0)
    backend.end_frame
    backend.calls.should eq ["init", "resize", "begin_frame", "sync_atlas", "draw_text", "end_frame"]
    backend.width.should eq 1024
    backend.height.should eq 768
  end

  it "begin_frame dirty=nil means full frame (no scissor, all submitted)" do
    backend = RecordingBackend.new
    atlas = Tessell::Text::GlyphAtlas.new(128, 256)
    vertices = [] of Tessell::Render::Vertex
    make_quad(vertices, 10.0_f32, 10.0_f32, 30.0_f32, 30.0_f32)
    make_quad(vertices, 200.0_f32, 200.0_f32, 220.0_f32, 220.0_f32)
    batches = [Tessell::Render::TextBatch.new(0, 8, 0)]
    backend.init(800, 600)
    backend.begin_frame(nil)
    backend.sync_atlas(atlas)
    submitted = backend.draw_text(vertices, batches, 1)
    st = backend.stats
    submitted.should eq 2
    st.submitted_quads.should eq 2
    st.scissor_calls.should eq 0
    st.culled_quads.should eq 0
    backend.last_dirty.nil?.should be_true
  end

  it "begin_frame dirty rects: outside rects culled, inside submitted" do
    backend = RecordingBackend.new
    atlas = Tessell::Text::GlyphAtlas.new(128, 256)
    vertices = [] of Tessell::Render::Vertex
    # quad A fully inside dirty, quad B fully outside
    make_quad(vertices, 10.0_f32, 10.0_f32, 30.0_f32, 30.0_f32)
    make_quad(vertices, 500.0_f32, 500.0_f32, 520.0_f32, 520.0_f32)
    batches = [Tessell::Render::TextBatch.new(0, 8, 0)]
    dirty = [Tessell::Rect.new(0.0_f32, 0.0_f32, 100.0_f32, 100.0_f32)]
    backend.init(800, 600)
    backend.begin_frame(dirty)
    backend.sync_atlas(atlas)
    submitted = backend.draw_text(vertices, batches, 1)
    st = backend.stats
    submitted.should eq 1
    st.submitted_quads.should eq 1
    st.culled_quads.should eq 1
    st.scissor_calls.should eq 1
    backend.last_dirty.nil?.should be_false
  end

  it "dirty rects merged via Dirty.merge_into are <= 8" do
    rects = [] of Tessell::Rect
    20.times do |i|
      rects << Tessell::Rect.new((i * 10).to_f32, 0.0_f32, 5.0_f32, 5.0_f32)
    end
    sink = [] of Tessell::Rect
    Tessell::Render::Dirty.merge_into(rects, sink, 8)
    sink.size.should be <= 8
    sink.size.should be > 0
  end

  it "culling arithmetic: fully outside -> 0 submitted, all culled" do
    backend = RecordingBackend.new
    vertices = [] of Tessell::Render::Vertex
    make_quad(vertices, 200.0_f32, 200.0_f32, 220.0_f32, 220.0_f32)
    make_quad(vertices, 300.0_f32, 300.0_f32, 320.0_f32, 320.0_f32)
    batches = [Tessell::Render::TextBatch.new(0, 8, 0)]
    dirty = [Tessell::Rect.new(0.0_f32, 0.0_f32, 50.0_f32, 50.0_f32)]
    backend.init(800, 600)
    backend.begin_frame(dirty)
    backend.draw_text(vertices, batches, 1)
    backend.stats.submitted_quads.should eq 0
    backend.stats.culled_quads.should eq 2
  end

  it "culling arithmetic: partially intersecting -> exact count, fully covered -> all" do
    backend = RecordingBackend.new
    vertices = [] of Tessell::Render::Vertex
    # q0 inside, q1 straddles edge (intersects), q2 outside
    make_quad(vertices, 10.0_f32, 10.0_f32, 20.0_f32, 20.0_f32)
    make_quad(vertices, 40.0_f32, 10.0_f32, 60.0_f32, 20.0_f32) # crosses x=50
    make_quad(vertices, 70.0_f32, 10.0_f32, 80.0_f32, 20.0_f32)
    batches = [Tessell::Render::TextBatch.new(0, 12, 0)]
    dirty = [Tessell::Rect.new(0.0_f32, 0.0_f32, 50.0_f32, 50.0_f32)]
    backend.init(800, 600)
    backend.begin_frame(dirty)
    backend.draw_text(vertices, batches, 1)
    backend.stats.submitted_quads.should eq 2
    backend.stats.culled_quads.should eq 1

    # fully covered by union of rects
    dirty2 = [Tessell::Rect.new(0.0_f32, 0.0_f32, 100.0_f32, 100.0_f32)]
    backend.begin_frame(dirty2)
    backend.draw_text(vertices, batches, 1)
    backend.stats.submitted_quads.should eq 3
    backend.stats.culled_quads.should eq 0
  end

  it "resolved_texture is provided by backend (caller does not pass texture ids)" do
    backend = RecordingBackend.new
    atlas = Tessell::Text::GlyphAtlas.new(128, 256)
    backend.init(800, 600)
    backend.sync_atlas(atlas)
    # page 0 exists (atlas starts with 0 pages until used, but sync_atlas synthesizes by page_count)
    # atlas.page_count is 0 initially; resolved_texture for unknown page returns 0
    backend.resolved_texture(-1).should eq 0
    backend.resolved_texture(99).should eq 0
    # TextBatch carries page, not texture; caller never supplies texture ids
    b = Tessell::Render::TextBatch.new(0, 4, 0)
    b.page.should eq 0
  end

  it "begin_frame+draw_text steady-state zero-alloc (A delta<N, B <=256, 3 windows max, GC in ensure)" do
    backend = RecordingBackend.new
    atlas = Tessell::Text::GlyphAtlas.new(128, 256)
    vertices = [] of Tessell::Render::Vertex
    make_quad(vertices, 10.0_f32, 10.0_f32, 30.0_f32, 30.0_f32)
    make_quad(vertices, 40.0_f32, 10.0_f32, 60.0_f32, 30.0_f32)
    batches = [Tessell::Render::TextBatch.new(0, 8, 0)]
    dirty = [Tessell::Rect.new(0.0_f32, 0.0_f32, 100.0_f32, 100.0_f32)]

    backend.init(800, 600)
    backend.sync_atlas(atlas)
    # Warmup: deterministically absorb first-use/lazy allocations in the measured path.
    # Work sink prevents accidental dead-code elimination; record_calls off to avoid
    # string-append allocations that are outside the steady-state draw contract.
    backend.record_calls = false
    backend.calls.clear
    work_sink = 0
    4096.times do
      backend.begin_frame(dirty)
      work_sink &+= backend.draw_text(vertices, batches, 1)
    end
    _ = work_sink
    GC.collect
    # Extra warmup of the measured window shape to absorb intermittent GC/allocator
    # bookkeeping seen as rare 16B blips in work windows on some runs.
    3.times do
      GC.collect
      GC.disable
      begin
        n = 1000
        n.times { backend.begin_frame(dirty); backend.draw_text(vertices, batches, 1) }
      ensure
        GC.enable
      end
    end
    GC.collect

    n = 1000
    # prime (post-warmup): first measured window; explicit warmup above should absorb
    # any one-time allocations, so prime is expected steady-state (no retry masking).
    delta_prime = 0_i64
    GC.collect
    GC.disable
    begin
      before = GC.stats.bytes_since_gc
      n.times { backend.begin_frame(dirty); backend.draw_text(vertices, batches, 1) }
      delta_prime = GC.stats.bytes_since_gc.to_i64 - before.to_i64
    ensure
      GC.enable
    end

    # calib
    delta_calib = 0_i64
    calib_sink = 0_i64
    GC.collect
    GC.disable
    begin
      before = GC.stats.bytes_since_gc
      i = 0
      while i < n
        calib_sink &+= i.to_i64
        i += 1
      end
      delta_calib = GC.stats.bytes_since_gc.to_i64 - before.to_i64
    ensure
      GC.enable
    end
    _ = calib_sink

    retried = false
    attempt = 1
    delta_work = 0_i64
    seq = [] of Int64
    loop do
      seq = [] of Int64
      3.times do
        GC.collect
        GC.disable
        begin
          before = GC.stats.bytes_since_gc
          n.times { backend.begin_frame(dirty); backend.draw_text(vertices, batches, 1) }
          seq << (GC.stats.bytes_since_gc.to_i64 - before.to_i64)
        ensure
          GC.enable
        end
      end
      delta_work = seq.max
      puts "zero-alloc probe(backend): delta_prime=#{delta_prime} delta_calib=#{delta_calib} delta_work=#{delta_work} N=#{n} windows=[#{seq[0]},#{seq[1]},#{seq[2]}] retried=#{retried} attempt=#{attempt}"
      break if delta_work < n && delta_work <= 256
      if attempt >= 2
        fail "zero-alloc probe(backend): delta_work=#{delta_work} delta_calib=#{delta_calib} delta_prime=#{delta_prime} N=#{n} windows=[#{seq[0]},#{seq[1]},#{seq[2]}] retried=#{retried} attempt=#{attempt}"
      end
      retried = true
      attempt = 2
    end
    (delta_work < n && delta_work <= 256).should be_true
  end
end