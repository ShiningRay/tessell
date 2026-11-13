require "./spec_helper"

private def seguiemj_path : String
  "C:/Windows/Fonts/seguiemj.ttf"
end

describe "text emoji color (COLR/CPAL -> RGBA atlas pages)" do
  measurer = Tessell::Text::FtMeasurer.open(seguiemj_path, 0)
  atlas = Tessell::Text::GlyphAtlas.new(1024, 4096)
  rast = Tessell::Text::Rasterizer.new(measurer, atlas, 1, 256, true)

  it "color path: emoji placement carries color=true with drawable bitmap" do
    ps = rast.rasterize("😀", 32)
    ps.size.should be > 0
    p = ps[0]
    p.color.should be_true
    p.w.should be > 0
    p.h.should be > 0
    p.page.should be >= 0
  end

  it "gray path stays default-off: color_enabled=false keeps color=false" do
    atlas_g = Tessell::Text::GlyphAtlas.new(1024, 4096)
    rast_g = Tessell::Text::Rasterizer.new(measurer, atlas_g, 1, 256, false)
    ps = rast_g.rasterize("😀", 32)
    ps.size.should be > 0
    ps[0].color.should be_false
    ps[0].page.should be >= 0
    ps[0].w.should be > 0
  end

  it "atlas stores emoji in RGBA pages: rgba_page_count grows, page data 4B/px with nonzero alpha" do
    atlas_c = Tessell::Text::GlyphAtlas.new(1024, 4096)
    rast_c = Tessell::Text::Rasterizer.new(measurer, atlas_c, 1, 256, true)
    before = atlas_c.rgba_page_count
    ps = rast_c.rasterize("😀👍", 32)
    ps.size.should be > 0
    atlas_c.rgba_page_count.should be > before
    data = atlas_c.rgba_page_data(ps[0].page)
    data.size.should be > 0
    (data.size % 4).should eq 0
    any_alpha = false
    data.each_with_index do |b, i|
      if i % 4 == 3 && b > 0
        any_alpha = true
        break
      end
    end
    any_alpha.should be_true
  end

  it "gray+color mix flushes separate batches in string order (no cross-tint merge)" do
    renderer = Tessell::Render::TextRenderer.new(atlas, rast)
    sink = [] of Tessell::Text::GlyphPlacement
    renderer.reset
    renderer.build_text(sink, "A😀", 10.0_f32, 10.0_f32, 32, 800, 600)
    batches = renderer.batch_runs
    batches.size.should be >= 2
    gray_seen = false
    color_seen = false
    batches.each do |b|
      if b.color
        color_seen = true
      else
        gray_seen = true
        color_seen.should be_false
      end
    end
    gray_seen.should be_true
    color_seen.should be_true
  end

  it "shape_run_into color hit path returns identical placements (cross-frame cache)" do
    sink1 = [] of Tessell::Text::GlyphPlacement
    n1 = rast.shape_run_into("😀", 32, sink1)
    sink2 = [] of Tessell::Text::GlyphPlacement
    n2 = rast.shape_run_into("😀", 32, sink2)
    n1.should eq n2
    sink1.size.should eq sink2.size
    sink1.size.should be > 0
    sink1[0].color.should be_true
    sink1[0].w.should eq sink2[0].w
    sink1[0].h.should eq sink2[0].h
    sink1[0].advance_px.should eq sink2[0].advance_px
    sink1[0].page.should eq sink2[0].page
  end

  it "repeated color rasterize is stable: 200 calls add no new RGBA pages" do
    pages_before = atlas.rgba_page_count
    200.times { rast.rasterize("😀", 32) }
    atlas.rgba_page_count.should eq pages_before
  end

  it "steady color hit loop allocates ~0 per frame (A<1000, B<=256, 3 windows)" do
    renderer = Tessell::Render::TextRenderer.new(atlas, rast)
    sink = [] of Tessell::Text::GlyphPlacement
    40.times do
      rast.shape_run_into("😀👍", 32, sink)
      sink.clear
      renderer.reset
      renderer.build_text(sink, "😀👍", 10.0_f32, 10.0_f32, 32, 800, 600)
      sink.clear
    end
    n = 200
    measure = ->() : UInt64 do
      t0 = GC.stats.bytes_since_gc
      n.times do
        rast.shape_run_into("😀👍", 32, sink)
        sink.clear
        renderer.reset
        renderer.build_text(sink, "😀👍", 10.0_f32, 10.0_f32, 32, 800, 600)
        sink.clear
      end
      GC.stats.bytes_since_gc - t0
    end
    # prime: absorb first-window lazy-init noise, discard
    2.times do
      GC.collect
      measure.call
    end
    windows = [] of UInt64
    GC.collect
    GC.disable
    begin
      3.times do
        windows << measure.call
        GC.collect
      end
    ensure
      GC.enable
    end
    delta_max = windows.max? || 0_u64
    puts "ZERO_ALLOC_COLOR windows=#{windows.inspect} max=#{delta_max} n=#{n}"
    (delta_max < 1000_u64).should be_true
    (delta_max <= 256_u64).should be_true
  end
end
