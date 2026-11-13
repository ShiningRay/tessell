require "./spec_helper"
require "../src/tessell/geometry"
require "../src/tessell/render/polygon"

describe "Tessell::Render::Polygon (M3-WP4, CPU)" do
  it "contains? works for square and triangle (even-odd)" do
    sq = [
      Tessell::Point.new(10.0_f32, 10.0_f32),
      Tessell::Point.new(30.0_f32, 10.0_f32),
      Tessell::Point.new(30.0_f32, 30.0_f32),
      Tessell::Point.new(10.0_f32, 30.0_f32),
    ] of Tessell::Point
    poly = Tessell::Render::Polygon.new(sq)
    poly.contains?(Tessell::Point.new(20.0_f32, 20.0_f32)).should be_true
    poly.contains?(Tessell::Point.new(5.0_f32, 20.0_f32)).should be_false
    poly.contains?(Tessell::Point.new(35.0_f32, 20.0_f32)).should be_false

    tri = [
      Tessell::Point.new(0.0_f32, 0.0_f32),
      Tessell::Point.new(40.0_f32, 0.0_f32),
      Tessell::Point.new(20.0_f32, 40.0_f32),
    ] of Tessell::Point
    t = Tessell::Render::Polygon.new(tri)
    t.contains?(Tessell::Point.new(20.0_f32, 10.0_f32)).should be_true
    t.contains?(Tessell::Point.new(2.0_f32, 30.0_f32)).should be_false
  end

  it "contains? uses even-odd for five-point star (center not filled)" do
    cx = 50.0_f32
    cy = 50.0_f32
    r = 40.0_f32
    pts = [] of Tessell::Point
    # 5-vertex self-intersecting pentagram in drawing order (skip 144 degrees).
    # Even-odd fill leaves the central pentagon/center empty.
    5.times do |i|
      angle = -Math::PI / 2.0 + i.to_f64 * 4.0 * Math::PI / 5.0
      pts << Tessell::Point.new(cx + r.to_f64 * Math.cos(angle),
        cy + r.to_f64 * Math.sin(angle))
    end
    star = Tessell::Render::Polygon.new(pts)
    star.contains?(Tessell::Point.new(50.0_f32, 50.0_f32)).should be_false
    # point inside top arm (near outer tip, along vertical axis)
    star.contains?(Tessell::Point.new(50.0_f32, 18.0_f32)).should be_true
    # clearly outside
    star.contains?(Tessell::Point.new(5.0_f32, 5.0_f32)).should be_false
  end

  it "computes bounds correctly" do
    pts = [
      Tessell::Point.new(5.0_f32, 7.0_f32),
      Tessell::Point.new(25.0_f32, 3.0_f32),
      Tessell::Point.new(15.0_f32, 30.0_f32),
    ] of Tessell::Point
    poly = Tessell::Render::Polygon.new(pts)
    b = poly.bounds
    b.origin.x.should be_close(5.0_f32, 0.001_f32)
    b.origin.y.should be_close(3.0_f32, 0.001_f32)
    b.size.width.should be_close(20.0_f32, 0.001_f32)
    b.size.height.should be_close(27.0_f32, 0.001_f32)
  end

  it "mask count matches per-pixel contains? sampling" do
    pts = [
      Tessell::Point.new(2.0_f32, 2.0_f32),
      Tessell::Point.new(18.0_f32, 2.0_f32),
      Tessell::Point.new(18.0_f32, 12.0_f32),
      Tessell::Point.new(10.0_f32, 18.0_f32),
      Tessell::Point.new(2.0_f32, 12.0_f32),
    ] of Tessell::Point
    poly = Tessell::Render::Polygon.new(pts)
    bounds = Tessell::Rect.new(0.0_f32, 0.0_f32, 20.0_f32, 20.0_f32)
    sink = Bytes.new(20 * 20)
    covered = Tessell::Render::Polygon.mask(pts, bounds, sink)
    manual = 0
    y = 0
    while y < 20
      x = 0
      while x < 20
        px = x.to_f32 + 0.5_f32
        py = y.to_f32 + 0.5_f32
        inside = poly.contains?(Tessell::Point.new(px, py))
        v = sink[y * 20 + x]
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

  it "mask raises ArgumentError when sink is too small" do
    pts = [
      Tessell::Point.new(0.0_f32, 0.0_f32),
      Tessell::Point.new(10.0_f32, 0.0_f32),
      Tessell::Point.new(10.0_f32, 10.0_f32),
    ] of Tessell::Point
    bounds = Tessell::Rect.new(0.0_f32, 0.0_f32, 10.0_f32, 10.0_f32)
    sink = Bytes.new(10 * 10 - 1)
    expect_raises(ArgumentError) do
      Tessell::Render::Polygon.mask(pts, bounds, sink)
    end
  end

  it "emit_fan returns n-2 triangles and repeats first vertex per triangle" do
    pts = [
      Tessell::Point.new(1.0_f32, 2.0_f32),
      Tessell::Point.new(3.0_f32, 4.0_f32),
      Tessell::Point.new(5.0_f32, 6.0_f32),
      Tessell::Point.new(7.0_f32, 8.0_f32),
      Tessell::Point.new(9.0_f32, 1.0_f32),
    ] of Tessell::Point
    sink = Slice(Float32).new((pts.size - 2) * 6)
    tris = Tessell::Render::Polygon.emit_fan(pts, sink)
    tris.should eq(pts.size - 2)
    # triangles: (p0,p1,p2),(p0,p2,p3),(p0,p3,p4)
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

  it "contains? steady-state zero-alloc (A delta<N, B <=256, 3 windows)" do
    pts = [
      Tessell::Point.new(0.0_f32, 0.0_f32),
      Tessell::Point.new(40.0_f32, 0.0_f32),
      Tessell::Point.new(40.0_f32, 30.0_f32),
      Tessell::Point.new(0.0_f32, 30.0_f32),
    ] of Tessell::Point
    poly = Tessell::Render::Polygon.new(pts)
    p_in = Tessell::Point.new(20.0_f32, 15.0_f32)
    p_out = Tessell::Point.new(50.0_f32, 15.0_f32)
    n = 1000
    sink_b = false

    10.times { sink_b = poly.contains?(p_in); sink_b = poly.contains?(p_out) }

    delta_prime = 0_i64
    GC.collect
    GC.disable
    begin
      before = GC.stats.bytes_since_gc
      n.times { sink_b = poly.contains?(p_in); sink_b = poly.contains?(p_out) }
      delta_prime = GC.stats.bytes_since_gc.to_i64 - before.to_i64
    ensure
      GC.enable
    end

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
    calib_sink.should be >= 0_i64

    retried = false
    attempt = 1
    delta_work = 0_i64
    seq = [0_i64, 0_i64, 0_i64]
    loop do
      seq = [0_i64, 0_i64, 0_i64]
      3.times do |wi|
        GC.collect
        GC.disable
        begin
          before = GC.stats.bytes_since_gc
          n.times { sink_b = poly.contains?(p_in); sink_b = poly.contains?(p_out) }
          seq[wi] = GC.stats.bytes_since_gc.to_i64 - before.to_i64
        ensure
          GC.enable
        end
      end
      delta_work = seq.max
      puts "zero-alloc probe(polygon_contains): delta_prime=#{delta_prime} " \
           "delta_calib=#{delta_calib} delta_work=#{delta_work} N=#{n} " \
           "windows=[#{seq[0]},#{seq[1]},#{seq[2]}] retried=#{retried} attempt=#{attempt}"
      break if delta_work < n && delta_work <= 256
      if attempt >= 2
        fail "zero-alloc probe(polygon_contains): delta_work=#{delta_work} " \
             "delta_calib=#{delta_calib} delta_prime=#{delta_prime} N=#{n} " \
             "windows=[#{seq[0]},#{seq[1]},#{seq[2]}] retried=#{retried} attempt=#{attempt}"
      end
      retried = true
      attempt = 2
    end
    _ = sink_b
    (delta_work < n && delta_work <= 256).should be_true
  end

  it "mask steady-state zero-alloc (A delta<N, B <=256, 3 windows)" do
    pts = [
      Tessell::Point.new(2.0_f32, 2.0_f32),
      Tessell::Point.new(18.0_f32, 2.0_f32),
      Tessell::Point.new(18.0_f32, 18.0_f32),
      Tessell::Point.new(2.0_f32, 18.0_f32),
    ] of Tessell::Point
    bounds = Tessell::Rect.new(0.0_f32, 0.0_f32, 20.0_f32, 20.0_f32)
    sink = Bytes.new(20 * 20)
    n = 1000
    sink_i = 0

    10.times { sink_i = Tessell::Render::Polygon.mask(pts, bounds, sink) }

    delta_prime = 0_i64
    GC.collect
    GC.disable
    begin
      before = GC.stats.bytes_since_gc
      n.times { sink_i = Tessell::Render::Polygon.mask(pts, bounds, sink) }
      delta_prime = GC.stats.bytes_since_gc.to_i64 - before.to_i64
    ensure
      GC.enable
    end

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
    calib_sink.should be >= 0_i64

    retried = false
    attempt = 1
    delta_work = 0_i64
    seq = [0_i64, 0_i64, 0_i64]
    loop do
      seq = [0_i64, 0_i64, 0_i64]
      3.times do |wi|
        GC.collect
        GC.disable
        begin
          before = GC.stats.bytes_since_gc
          n.times { sink_i = Tessell::Render::Polygon.mask(pts, bounds, sink) }
          seq[wi] = GC.stats.bytes_since_gc.to_i64 - before.to_i64
        ensure
          GC.enable
        end
      end
      delta_work = seq.max
      puts "zero-alloc probe(polygon_mask): delta_prime=#{delta_prime} " \
           "delta_calib=#{delta_calib} delta_work=#{delta_work} N=#{n} " \
           "windows=[#{seq[0]},#{seq[1]},#{seq[2]}] retried=#{retried} attempt=#{attempt}"
      break if delta_work < n && delta_work <= 256
      if attempt >= 2
        fail "zero-alloc probe(polygon_mask): delta_work=#{delta_work} " \
             "delta_calib=#{delta_calib} delta_prime=#{delta_prime} N=#{n} " \
             "windows=[#{seq[0]},#{seq[1]},#{seq[2]}] retried=#{retried} attempt=#{attempt}"
      end
      retried = true
      attempt = 2
    end
    _ = sink_i
    (delta_work < n && delta_work <= 256).should be_true
  end

  it "emit_fan steady-state zero-alloc (A delta<N, B <=256, 3 windows)" do
    pts = [
      Tessell::Point.new(1.0_f32, 2.0_f32),
      Tessell::Point.new(3.0_f32, 4.0_f32),
      Tessell::Point.new(5.0_f32, 6.0_f32),
      Tessell::Point.new(7.0_f32, 8.0_f32),
      Tessell::Point.new(9.0_f32, 1.0_f32),
    ] of Tessell::Point
    sink = Slice(Float32).new((pts.size - 2) * 6)
    n = 1000
    sink_i = 0

    10.times { sink_i = Tessell::Render::Polygon.emit_fan(pts, sink) }

    delta_prime = 0_i64
    GC.collect
    GC.disable
    begin
      before = GC.stats.bytes_since_gc
      n.times { sink_i = Tessell::Render::Polygon.emit_fan(pts, sink) }
      delta_prime = GC.stats.bytes_since_gc.to_i64 - before.to_i64
    ensure
      GC.enable
    end

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
    calib_sink.should be >= 0_i64

    retried = false
    attempt = 1
    delta_work = 0_i64
    seq = [0_i64, 0_i64, 0_i64]
    loop do
      seq = [0_i64, 0_i64, 0_i64]
      3.times do |wi|
        GC.collect
        GC.disable
        begin
          before = GC.stats.bytes_since_gc
          n.times { sink_i = Tessell::Render::Polygon.emit_fan(pts, sink) }
          seq[wi] = GC.stats.bytes_since_gc.to_i64 - before.to_i64
        ensure
          GC.enable
        end
      end
      delta_work = seq.max
      puts "zero-alloc probe(polygon_emit_fan): delta_prime=#{delta_prime} " \
           "delta_calib=#{delta_calib} delta_work=#{delta_work} N=#{n} " \
           "windows=[#{seq[0]},#{seq[1]},#{seq[2]}] retried=#{retried} attempt=#{attempt}"
      break if delta_work < n && delta_work <= 256
      if attempt >= 2
        fail "zero-alloc probe(polygon_emit_fan): delta_work=#{delta_work} " \
             "delta_calib=#{delta_calib} delta_prime=#{delta_prime} N=#{n} " \
             "windows=[#{seq[0]},#{seq[1]},#{seq[2]}] retried=#{retried} attempt=#{attempt}"
      end
      retried = true
      attempt = 2
    end
    _ = sink_i
    (delta_work < n && delta_work <= 256).should be_true
  end
end
