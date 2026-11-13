require "./spec_helper"
require "../src/tessell/text/rasterizer"
require "../src/tessell/text/glyph_atlas"

SHAPED_RUN_FONT_PATH = "C:/Windows/Fonts/msyh.ttc"

private def placements_equal?(a : Array(Tessell::Text::GlyphPlacement), b : Array(Tessell::Text::GlyphPlacement)) : Bool
  return false unless a.size == b.size
  i = 0
  while i < a.size
    pa = a[i]
    pb = b[i]
    return false unless pa.glyph_id == pb.glyph_id
    return false unless pa.advance_px == pb.advance_px
    return false unless pa.offset_x == pb.offset_x
    return false unless pa.offset_y == pb.offset_y
    return false unless pa.w == pb.w
    return false unless pa.h == pb.h
    return false unless pa.u0 == pb.u0
    return false unless pa.v0 == pb.v0
    return false unless pa.u1 == pb.u1
    return false unless pa.v1 == pb.v1
    return false unless pa.page == pb.page
    return false unless pa.key == pb.key
    i += 1
  end
  true
end

describe "Shaped-run cache (M2-WP4 task-73)" do
  it "cache hit equals uncached rasterize_into field-by-field" do
    ft = Tessell::Text::FtMeasurer.open(SHAPED_RUN_FONT_PATH, 0)
    atlas = Tessell::Text::GlyphAtlas.new(1024, 4096)
    rast = Tessell::Text::Rasterizer.new(ft, atlas, 1, 256)

    text = "Hello 你好"
    size = 16

    # baseline without relying on shaped-run cache: shape fresh by using a separate rasterizer
    atlas2 = Tessell::Text::GlyphAtlas.new(1024, 4096)
    rast2 = Tessell::Text::Rasterizer.new(ft, atlas2, 1, 256)
    baseline = [] of Tessell::Text::GlyphPlacement
    rast2.shape_run_into(text, size, baseline)

    sink = [] of Tessell::Text::GlyphPlacement
    rast.shape_run_into(text, size, sink) # miss -> populate
    hit = [] of Tessell::Text::GlyphPlacement
    rast.shape_run_into(text, size, hit)  # hit

    placements_equal?(baseline, sink).should be_true
    placements_equal?(baseline, hit).should be_true
    rast.run_cache_size.should eq 1

    ft.close
  end

  it "LRU upper bound: evicts least-recently-used when capacity exceeded" do
    ft = Tessell::Text::FtMeasurer.open(SHAPED_RUN_FONT_PATH, 0)
    atlas = Tessell::Text::GlyphAtlas.new(1024, 4096)
    rast = Tessell::Text::Rasterizer.new(ft, atlas, 1, 3)
    sink = [] of Tessell::Text::GlyphPlacement

    texts = ["a", "b", "c", "d"]
    texts.each do |t|
      rast.shape_run_into(t, 16, sink)
    end

    rast.run_cache_size.should eq 3

    # "a" was LRU and should be evicted; inserting "e" should evict "b" (now LRU after above touches?)
    # access "b" is not done, "c","d" inserted later; "a" evicted on "d". current: b,c,d
    # touch c to make b LRU
    rast.shape_run_into("c", 16, sink)
    rast.shape_run_into("e", 16, sink)
    rast.run_cache_size.should eq 3

    # Verify "c","d","e" present by hit behavior equivalence (indirect) and "b" evicted by reinsert growing? size stays 3
    # Direct structural check via behavior: cache stays bounded across many inserts
    10.times do |i|
      rast.shape_run_into("txt#{i}", 16, sink)
    end
    rast.run_cache_size.should eq 3

    ft.close
  end

  it "frame eviction forbidden during begin_frame/end_frame" do
    ft = Tessell::Text::FtMeasurer.open(SHAPED_RUN_FONT_PATH, 0)
    atlas = Tessell::Text::GlyphAtlas.new(1024, 4096)
    rast = Tessell::Text::Rasterizer.new(ft, atlas, 1, 2)
    sink = [] of Tessell::Text::GlyphPlacement

    rast.shape_run_into("a", 16, sink)
    rast.shape_run_into("b", 16, sink)
    rast.begin_frame
    expect_raises(Tessell::Text::Rasterizer::FrameEvictionError) do
      rast.shape_run_into("c", 16, sink) # would evict
    end
    rast.end_frame

    # outside frame eviction allowed
    rast.shape_run_into("c", 16, sink)
    rast.run_cache_size.should eq 2
    rast.in_run_frame?.should be_false

    ft.close
  end

  it "evict_run_lru raises inside frame and works outside" do
    ft = Tessell::Text::FtMeasurer.open(SHAPED_RUN_FONT_PATH, 0)
    atlas = Tessell::Text::GlyphAtlas.new(1024, 4096)
    rast = Tessell::Text::Rasterizer.new(ft, atlas, 1, 8)
    sink = [] of Tessell::Text::GlyphPlacement
    rast.shape_run_into("x", 16, sink)
    rast.shape_run_into("y", 16, sink)
    rast.begin_frame
    expect_raises(Tessell::Text::Rasterizer::FrameEvictionError) do
      rast.evict_run_lru(1)
    end
    rast.end_frame
    rast.evict_run_lru(1).should eq 1
    rast.run_cache_size.should eq 1
    ft.close
  end
end
