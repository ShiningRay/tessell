require "./spec_helper"
require "./support/fonts"
require "../src/tessell/text/rasterizer"
require "../src/tessell/text/glyph_atlas"
require "../src/tessell/render/text_renderer"

# issue #61 X0：COLR 彩色 emoji 路径目前只有 Windows Segoe UI Emoji 是已验证
# 样例（macOS sbix / Linux CBDT 不走 COLR 路径）；TESSELL_TEST_EMOJI 可覆盖。
# 缺前置时每个用例顶层 pending + SKIP 原因，不用 nested pending。

private def emoji_setup
  path = TestFonts.emoji_colr.not_nil!
  m = Tessell::Text::FtMeasurer.open(path, 0)
  atlas = Tessell::Text::GlyphAtlas.new(1024, 4096)
  rast = Tessell::Text::Rasterizer.new(m, atlas, 1, 256, true)
  {m: m, atlas: atlas, rast: rast}
end

describe "text emoji color (COLR/CPAL -> RGBA atlas pages)" do
  it "color path: emoji placement carries color=true with drawable bitmap" do
    unless TestFonts.emoji_colr
      pending_skip "SKIP: 本平台无 COLR 彩色 emoji 字体（Windows seguiemj；TESSELL_TEST_EMOJI 可覆盖）"
      next
    end
    s = emoji_setup
    begin
      ps = s[:rast].rasterize("😀", 32)
      ps.size.should be > 0
      p = ps[0]
      p.color.should be_true
      p.w.should be > 0
      p.h.should be > 0
      p.page.should be >= 0
    ensure
      s[:m].close
    end
  end

  it "gray path stays default-off: color_enabled=false keeps color=false" do
    unless TestFonts.emoji_colr
      pending_skip "SKIP: 本平台无 COLR 彩色 emoji 字体（Windows seguiemj；TESSELL_TEST_EMOJI 可覆盖）"
      next
    end
    s = emoji_setup
    begin
      atlas_g = Tessell::Text::GlyphAtlas.new(1024, 4096)
      rast_g = Tessell::Text::Rasterizer.new(s[:m], atlas_g, 1, 256, false)
      ps = rast_g.rasterize("😀", 32)
      ps.size.should be > 0
      ps[0].color.should be_false
      ps[0].page.should be >= 0
      ps[0].w.should be > 0
    ensure
      s[:m].close
    end
  end

  it "atlas stores emoji in RGBA pages: rgba_page_count grows, page data 4B/px with nonzero alpha" do
    unless TestFonts.emoji_colr
      pending_skip "SKIP: 本平台无 COLR 彩色 emoji 字体（Windows seguiemj；TESSELL_TEST_EMOJI 可覆盖）"
      next
    end
    s = emoji_setup
    begin
      atlas_c = Tessell::Text::GlyphAtlas.new(1024, 4096)
      rast_c = Tessell::Text::Rasterizer.new(s[:m], atlas_c, 1, 256, true)
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
    ensure
      s[:m].close
    end
  end

  it "gray+color mix flushes separate batches in string order (no cross-tint merge)" do
    unless TestFonts.emoji_colr
      pending_skip "SKIP: 本平台无 COLR 彩色 emoji 字体（Windows seguiemj；TESSELL_TEST_EMOJI 可覆盖）"
      next
    end
    s = emoji_setup
    begin
      renderer = Tessell::Render::TextRenderer.new(s[:atlas], s[:rast])
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
    ensure
      s[:m].close
    end
  end

  it "shape_run_into color hit path returns identical placements (cross-frame cache)" do
    unless TestFonts.emoji_colr
      pending_skip "SKIP: 本平台无 COLR 彩色 emoji 字体（Windows seguiemj；TESSELL_TEST_EMOJI 可覆盖）"
      next
    end
    s = emoji_setup
    begin
      sink1 = [] of Tessell::Text::GlyphPlacement
      n1 = s[:rast].shape_run_into("😀", 32, sink1)
      sink2 = [] of Tessell::Text::GlyphPlacement
      n2 = s[:rast].shape_run_into("😀", 32, sink2)
      n1.should eq n2
      sink1.size.should eq sink2.size
      sink1.size.should be > 0
      sink1[0].color.should be_true
      sink1[0].w.should eq sink2[0].w
      sink1[0].h.should eq sink2[0].h
      sink1[0].advance_px.should eq sink2[0].advance_px
      sink1[0].page.should eq sink2[0].page
    ensure
      s[:m].close
    end
  end

  it "repeated color rasterize is stable: 200 calls add no new RGBA pages" do
    unless TestFonts.emoji_colr
      pending_skip "SKIP: 本平台无 COLR 彩色 emoji 字体（Windows seguiemj；TESSELL_TEST_EMOJI 可覆盖）"
      next
    end
    s = emoji_setup
    begin
      s[:rast].rasterize("😀", 32) # 预热：首光栅化建 RGBA 页（原共享 atlas 语义）
      pages_before = s[:atlas].rgba_page_count
      200.times { s[:rast].rasterize("😀", 32) }
      s[:atlas].rgba_page_count.should eq pages_before
    ensure
      s[:m].close
    end
  end

  it "steady color hit loop allocates ~0 per frame (A<1000, B<=256, 3 windows)" do
    unless TestFonts.emoji_colr
      pending_skip "SKIP: 本平台无 COLR 彩色 emoji 字体（Windows seguiemj；TESSELL_TEST_EMOJI 可覆盖）"
      next
    end
    s = emoji_setup
    begin
      renderer = Tessell::Render::TextRenderer.new(s[:atlas], s[:rast])
      sink = [] of Tessell::Text::GlyphPlacement
      40.times do
        s[:rast].shape_run_into("😀👍", 32, sink)
        sink.clear
        renderer.reset
        renderer.build_text(sink, "😀👍", 10.0_f32, 10.0_f32, 32, 800, 600)
        sink.clear
      end
      n = 200
      measure = ->() : UInt64 do
        t0 = GC.stats.bytes_since_gc
        n.times do
          s[:rast].shape_run_into("😀👍", 32, sink)
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
    ensure
      s[:m].close
    end
  end
end
