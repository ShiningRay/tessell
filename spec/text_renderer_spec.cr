require "./spec_helper"
require "../src/tessell/render/text_renderer"

TEXT_RENDERER_FONT_PATH = "C:/Windows/Fonts/msyh.ttc"

describe Tessell::Render::TextRenderer do
  it "\"Hello\" 24px produces quads == drawable glyph count" do
    ft = Tessell::Text::FtMeasurer.open(TEXT_RENDERER_FONT_PATH, 0)
    atlas = Tessell::Text::GlyphAtlas.new(1024, 4096)
    rast = Tessell::Text::Rasterizer.new(ft, atlas, 1)
    tr = Tessell::Render::TextRenderer.new(atlas, rast)
    sink = [] of Tessell::Text::GlyphPlacement
    page_tex = [1]

    tr.build_text(sink, "Hello", 10.0_f32, 50.0_f32, 24, 800, 600, page_tex)
    drawable = sink.count { |p| p.w > 0 && p.h > 0 }
    tr.stats[:quads].should eq drawable
    tr.vertex_count.should eq drawable * 4
    tr.stats[:batches].should be >= 1
    ft.close
  end

  it "space produces no quad but pen advances" do
    ft = Tessell::Text::FtMeasurer.open(TEXT_RENDERER_FONT_PATH, 0)
    atlas = Tessell::Text::GlyphAtlas.new(1024, 4096)
    rast = Tessell::Text::Rasterizer.new(ft, atlas, 1)
    tr = Tessell::Render::TextRenderer.new(atlas, rast)
    sink = [] of Tessell::Text::GlyphPlacement
    page_tex = [1]

    pen_end = tr.build_text(sink, " ", 10.0_f32, 50.0_f32, 24, 800, 600, page_tex)
    tr.stats[:quads].should eq 0
    pen_end.should be > 10.0_f32
    sink.size.should be > 0
    ft.close
  end

  it "UVs are within [0,1] for all vertices" do
    ft = Tessell::Text::FtMeasurer.open(TEXT_RENDERER_FONT_PATH, 0)
    atlas = Tessell::Text::GlyphAtlas.new(1024, 4096)
    rast = Tessell::Text::Rasterizer.new(ft, atlas, 1)
    tr = Tessell::Render::TextRenderer.new(atlas, rast)
    sink = [] of Tessell::Text::GlyphPlacement
    page_tex = [1]

    tr.build_text(sink, "你好Hello", 0.0_f32, 40.0_f32, 24, 800, 600, page_tex)
    tr.vertex_count.should be > 0
    i = 0
    while i < tr.vertex_count
      v = tr.vertices[i]
      (v.u >= 0.0_f32 && v.u <= 1.0_f32).should be_true
      (v.v >= 0.0_f32 && v.v <= 1.0_f32).should be_true
      i += 1
    end
    ft.close
  end

  it "same page produces a single batch run" do
    ft = Tessell::Text::FtMeasurer.open(TEXT_RENDERER_FONT_PATH, 0)
    atlas = Tessell::Text::GlyphAtlas.new(1024, 4096)
    rast = Tessell::Text::Rasterizer.new(ft, atlas, 1)
    tr = Tessell::Render::TextRenderer.new(atlas, rast)
    sink = [] of Tessell::Text::GlyphPlacement
    page_tex = [7, 8, 9]

    tr.build_text(sink, "Hello", 0.0_f32, 40.0_f32, 24, 800, 600, page_tex)
    atlas.page_count.should eq 1
    tr.batch_count.should eq 1
    b = tr.batch_runs[0]
    b.page.should eq 0
    page_tex[b.page].should eq 7
    b.start.should eq 0
    b.count.should eq tr.vertex_count
    ft.close
  end

  it "cross-page placements produce multiple batches with correct page indices" do
    # Force 2 pages: 64x64 atlas. 48px CJK glyphs (~48x48) fill a page quickly;
    # pre-place "你" on page 0, then "好" (miss, cached "你" stays on page 0) won't fit -> page 1.
    ft = Tessell::Text::FtMeasurer.open(TEXT_RENDERER_FONT_PATH, 0)
    atlas = Tessell::Text::GlyphAtlas.new(64, 4096)
    rast = Tessell::Text::Rasterizer.new(ft, atlas, 1)
    tr = Tessell::Render::TextRenderer.new(atlas, rast)
    sink = [] of Tessell::Text::GlyphPlacement
    page_tex = [101, 202, 303, 404]

    rast.rasterize("你", 48)
    atlas.page_count.should eq 1

    tr.build_text(sink, "你好", 0.0_f32, 80.0_f32, 48, 800, 600, page_tex)
    atlas.page_count.should eq 2
    tr.batch_count.should eq 2

    b0 = tr.batch_runs[0]
    b1 = tr.batch_runs[1]
    b0.page.should eq 0
    b1.page.should eq 1
    page_tex[b0.page].should eq 101
    page_tex[b1.page].should eq 202
    b0.start.should eq 0
    b0.count.should be > 0
    b1.start.should eq b0.count
    (b0.count + b1.count).should eq tr.vertex_count
    (page_tex.size > b0.page).should be_true
    (page_tex.size > b1.page).should be_true
    ft.close
  end

  it "quad rectangle sizes equal glyph slot w/h" do
    ft = Tessell::Text::FtMeasurer.open(TEXT_RENDERER_FONT_PATH, 0)
    atlas = Tessell::Text::GlyphAtlas.new(1024, 4096)
    rast = Tessell::Text::Rasterizer.new(ft, atlas, 1)
    tr = Tessell::Render::TextRenderer.new(atlas, rast)
    sink = [] of Tessell::Text::GlyphPlacement
    page_tex = [1]

    tr.build_text(sink, "Hello", 10.0_f32, 60.0_f32, 24, 800, 600, page_tex)
    # iterate placements in order and match emitted quads
    vi = 0
    pi = 0
    while pi < sink.size
      p = sink[pi]
      if p.w > 0 && p.h > 0
        vlt = tr.vertices[vi]
        vrt = tr.vertices[vi + 1]
        vrb = tr.vertices[vi + 2]
        vlb = tr.vertices[vi + 3]
        qw = (vrt.x - vlt.x).abs
        qh = (vlb.y - vlt.y).abs
        (qw - p.w.to_f32).abs.should be < 0.001_f32
        (qh - p.h.to_f32).abs.should be < 0.001_f32
        vi += 4
      end
      pi += 1
    end
    vi.should eq tr.vertex_count
    ft.close
  end

  it "viewport 800x600 baseline/edge positions produce no NaN/Inf" do
    ft = Tessell::Text::FtMeasurer.open(TEXT_RENDERER_FONT_PATH, 0)
    atlas = Tessell::Text::GlyphAtlas.new(1024, 4096)
    rast = Tessell::Text::Rasterizer.new(ft, atlas, 1)
    tr = Tessell::Render::TextRenderer.new(atlas, rast)
    sink = [] of Tessell::Text::GlyphPlacement
    page_tex = [1]

    tr.build_text(sink, "Hello 你好", 0.0_f32, 0.0_f32, 24, 800, 600, page_tex)
    tr.build_text(sink, "Edge", 799.0_f32, 599.0_f32, 24, 800, 600, page_tex)
    i = 0
    while i < tr.vertex_count
      v = tr.vertices[i]
      v.x.finite?.should be_true
      v.y.finite?.should be_true
      v.u.finite?.should be_true
      v.v.finite?.should be_true
      i += 1
    end
    ft.close
  end

  it "steady-state zero-alloc: 1000 build_text reuses sink/buffer (criterion A/B)" do
    ft = Tessell::Text::FtMeasurer.open(TEXT_RENDERER_FONT_PATH, 0)
    atlas = Tessell::Text::GlyphAtlas.new(1024, 4096)
    rast = Tessell::Text::Rasterizer.new(ft, atlas, 1)
    tr = Tessell::Render::TextRenderer.new(atlas, rast)
    sink = [] of Tessell::Text::GlyphPlacement
    page_tex = [1, 2, 3, 4]
    text = "Hello World"
    n = 1000

    # warmup + capacity prepay
    tr.build_text(sink, text, 10.0_f32, 40.0_f32, 16, 800, 600, page_tex)
    tr.reserve_quads(tr.stats[:quads])
    tr.reserve_batches(tr.stats[:batches])
    # ensure placement sink capacity stable and raster cache warm
    tr.build_text(sink, text, 10.0_f32, 40.0_f32, 16, 800, 600, page_tex)

    # prime (diagnostic)
    delta_prime = 0_i64
    GC.collect
    GC.disable
    begin
      before = GC.stats.bytes_since_gc
      n.times { tr.build_text(sink, text, 10.0_f32, 40.0_f32, 16, 800, 600, page_tex) }
      delta_prime = GC.stats.bytes_since_gc.to_i64 - before.to_i64
    ensure
      GC.enable
    end

    # calib (diagnostic, empty loop)
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

    # 3 work windows, take max. First failure: retry whole 3-window set once (GC noise denoising).
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
          n.times { tr.build_text(sink, text, 10.0_f32, 40.0_f32, 16, 800, 600, page_tex) }
          seq << (GC.stats.bytes_since_gc.to_i64 - before.to_i64)
        ensure
          GC.enable
        end
      end
      delta_work = seq.max
      puts "zero-alloc probe(text_renderer): delta_prime=#{delta_prime} delta_calib=#{delta_calib} delta_work=#{delta_work} N=#{n} windows=[#{seq[0]},#{seq[1]},#{seq[2]}] retried=#{retried} attempt=#{attempt}"
      break if delta_work < n && delta_work <= 256
      if attempt >= 2
        fail "zero-alloc probe(text_renderer): delta_work=#{delta_work} delta_calib=#{delta_calib} delta_prime=#{delta_prime} N=#{n} windows=[#{seq[0]},#{seq[1]},#{seq[2]}] retried=#{retried} attempt=#{attempt}"
      end
      retried = true
      attempt = 2
    end
    (delta_work < n && delta_work <= 256).should be_true
    ft.close
  end
end
