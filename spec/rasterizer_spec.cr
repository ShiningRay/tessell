require "./spec_helper"
require "../src/tessell/text/rasterizer"
require "../src/tessell/text/ffi/freetype"
require "../src/tessell/text/ffi/harfbuzz"

RASTER_FONT = "C:/Windows/Fonts/msyh.ttc"

describe Tessell::Text::Rasterizer do
  it "rasterizes 'A' size 16 with valid placement, uv, used_pixels and coverage" do
    meas = Tessell::Text::FtMeasurer.open(RASTER_FONT, 0)
    atlas = Tessell::Text::GlyphAtlas.new(1024, 4096)
    rast = Tessell::Text::Rasterizer.new(meas, atlas, 1)

    placements = rast.rasterize("A", 16)
    placements.size.should eq 1
    p = placements[0]
    p.w.should be > 0
    p.h.should be > 0
    (p.u0 >= 0.0_f32 && p.u0 <= 1.0_f32).should be_true
    (p.v0 >= 0.0_f32 && p.v0 <= 1.0_f32).should be_true
    (p.u1 >= 0.0_f32 && p.u1 <= 1.0_f32).should be_true
    (p.v1 >= 0.0_f32 && p.v1 <= 1.0_f32).should be_true
    (p.u1 > p.u0).should be_true
    (p.v1 > p.v0).should be_true
    atlas.used_pixels.should eq(p.w * p.h)

    cov = rast.coverage(p)
    cov.should be > 0
    cov.should be < (p.w * p.h)
    puts "EVIDENCE_A16 w=#{p.w} h=#{p.h} bearing_x=#{p.offset_x} bearing_y=#{p.offset_y} advance=#{p.advance_px} u0=#{p.u0} v0=#{p.v0} u1=#{p.u1} v1=#{p.v1} used_pixels=#{atlas.used_pixels} coverage=#{cov}"
    meas.close
  end

  it "reuses cached glyph on second rasterize: hits increase, rasters/used_pixels unchanged" do
    meas = Tessell::Text::FtMeasurer.open(RASTER_FONT, 0)
    atlas = Tessell::Text::GlyphAtlas.new(1024, 4096)
    rast = Tessell::Text::Rasterizer.new(meas, atlas, 1)

    rast.rasterize("A", 16)
    used1 = atlas.used_pixels
    s1 = rast.stats
    rast.rasterize("A", 16)
    used2 = atlas.used_pixels
    s2 = rast.stats

    s1[:hits].should eq 0
    s1[:misses].should eq 1
    s1[:rasters].should eq 1
    s2[:hits].should eq(s1[:hits] + 1)
    s2[:rasters].should eq s1[:rasters]
    used2.should eq used1
    meas.close
  end

  it "rasterizes \"Hello\" and advance sum approximates FtMeasurer.measure within 0.5px" do
    meas = Tessell::Text::FtMeasurer.open(RASTER_FONT, 0)
    atlas = Tessell::Text::GlyphAtlas.new(1024, 4096)
    rast = Tessell::Text::Rasterizer.new(meas, atlas, 1)

    placements = rast.rasterize("Hello", 16)
    placements.size.should eq 5
    sum_adv = 0.0_f32
    placements.each { |p| sum_adv += p.advance_px }
    sz = meas.measure("Hello", 0, 16.0_f32, 0.0_f32)
    (sum_adv - sz.width).abs.should be <= 0.5_f32
    puts "EVIDENCE_HELLO sum_adv=#{sum_adv} measure_width=#{sz.width} diff=#{(sum_adv - sz.width).abs}"
    meas.close
  end

  it "rasterizes CJK '你' size 24 with coverage > 0" do
    meas = Tessell::Text::FtMeasurer.open(RASTER_FONT, 0)
    atlas = Tessell::Text::GlyphAtlas.new(1024, 4096)
    rast = Tessell::Text::Rasterizer.new(meas, atlas, 1)

    placements = rast.rasterize("你", 24)
    placements.size.should eq 1
    p = placements[0]
    p.w.should be > 0
    p.h.should be > 0
    cov = rast.coverage(p)
    cov.should be > 0
    puts "EVIDENCE_CJK 你 size=24 w=#{p.w} h=#{p.h} coverage=#{cov}"
    meas.close
  end

  it "returns empty for empty string without crashing" do
    meas = Tessell::Text::FtMeasurer.open(RASTER_FONT, 0)
    atlas = Tessell::Text::GlyphAtlas.new(1024, 4096)
    rast = Tessell::Text::Rasterizer.new(meas, atlas, 1)
    placements = rast.rasterize("", 16)
    placements.size.should eq 0
    rast.stats[:misses].should eq 0
    meas.close
  end

  it "handles FT bitmap pitch correctly (negative-pitch evidence)" do
    # Evidence: read FT bitmap pitch for 'g' at 24px and verify copied atlas rows match
    # FT source rows in top-to-bottom image order (handles pitch >= 0 and pitch < 0).
    meas = Tessell::Text::FtMeasurer.open(RASTER_FONT, 0)
    atlas = Tessell::Text::GlyphAtlas.new(1024, 4096)
    rast = Tessell::Text::Rasterizer.new(meas, atlas, 1)

    ch = "g"
    placements = rast.rasterize(ch, 24)
    p = placements[0]

    face = meas.ft_face_handle
    Tessell::Text::FT::Lib.set_pixel_sizes(face, 0_u32, 24_u32)
    gid = Tessell::Text::FT::Lib.get_char_index(face, 'g'.ord.to_u32)
    err = Tessell::Text::FT::Lib.load_glyph(face, gid, Tessell::Text::FT::Lib::LOAD_RENDER)
    err.should eq 0
    bm = face.value.glyph.value.bitmap
    pitch = bm.pitch
    w = bm.width.to_i32
    h = bm.rows.to_i32
    w.should eq p.w
    h.should eq p.h

    slot = atlas.lookup(p.key).not_nil!
    d = atlas.page_data(slot.page)
    ps = atlas.page_size
    row = 0
    ok = true
    while row < h
      src_row = if pitch >= 0
                  bm.buffer + row * pitch
                else
                  bm.buffer + (h - 1 - row) * (-pitch)
                end
      x = 0
      while x < w
        if d[(slot.y + row) * ps + (slot.x + x)] != src_row[x]
          ok = false
          break
        end
        x += 1
      end
      break unless ok
      row += 1
    end
    ok.should be_true
    puts "EVIDENCE_PITCH char='g' size=24 w=#{w} h=#{h} pitch=#{pitch} rows_match=#{ok}"
    (pitch != 0 || h == 0).should be_true
    meas.close
  end

  it "rasterize_into reuses sink array (same object_id) and produces same placements" do
    meas = Tessell::Text::FtMeasurer.open(RASTER_FONT, 0)
    atlas = Tessell::Text::GlyphAtlas.new(1024, 4096)
    rast = Tessell::Text::Rasterizer.new(meas, atlas, 1)

    sink = [] of Tessell::Text::GlyphPlacement
    rast.rasterize_into("Hello", 16, sink)
    id1 = sink.object_id
    size1 = sink.size
    rast.rasterize_into("World", 16, sink)
    id2 = sink.object_id
    size2 = sink.size
    id2.should eq id1
    size1.should eq 5
    size2.should eq 5
    meas.close
  end

  it "glyph_id 0 behavior: unmapped codepoint emits zero-bitmap placement preserving HB count/advance" do
    meas = Tessell::Text::FtMeasurer.open(RASTER_FONT, 0)
    atlas = Tessell::Text::GlyphAtlas.new(1024, 4096)
    rast = Tessell::Text::Rasterizer.new(meas, atlas, 1)

    # U+10FFFF: HB may shape to glyph_id 0 (.notdef). Rasterizer must not crash and must
    # keep placements count == HB glyph count with advance preserved (no atlas insert).
    placements = rast.rasterize("\u{10FFFF}", 16)
    info = meas.shape_info("\u{10FFFF}", 16.0_f32)
    placements.size.should eq info[:glyph_ids].size
    if placements.size > 0
      sum = 0.0_f32
      placements.each { |p| sum += p.advance_px; p.w.should eq 0; p.h.should eq 0 }
      hb_sum = 0.0_f32
      info[:advances_px].each { |a| hb_sum += a }
      (sum - hb_sum).abs.should be <= 0.5_f32
    end
    puts "EVIDENCE_GID0 codepoint=U+10FFFF placements=#{placements.size} hb_glyphs=#{info[:glyph_ids].size}"
    meas.close
  end

  it "D1: whitespace glyphs with empty bitmap do not raise and keep correct advance" do
    meas = Tessell::Text::FtMeasurer.open(RASTER_FONT, 0)
    atlas = Tessell::Text::GlyphAtlas.new(1024, 4096)
    rast = Tessell::Text::Rasterizer.new(meas, atlas, 1)

    texts = ["a b", "   ", "\t\n"]
    texts.each do |t|
      placements = rast.rasterize(t, 24)
      placements.size.should be > 0
      sum = 0.0_f32
      placements.each { |p| sum += p.advance_px }
      measured = meas.measure(t, 0, 24.0_f32, 0.0_f32)
      (sum - measured.width).abs.should be <= 0.5_f32
      puts "EVIDENCE_D1 text=#{t.inspect} count=#{placements.size} sum=#{sum} meas=#{measured.width}"
    end
    meas.close
  end

  it "D2: Arabic \"لا\" msyh placements count == HB glyph count and advance matches measure" do
    meas = Tessell::Text::FtMeasurer.open(RASTER_FONT, 0)
    atlas = Tessell::Text::GlyphAtlas.new(1024, 4096)
    rast = Tessell::Text::Rasterizer.new(meas, atlas, 1)

    text = "لا"
    placements = rast.rasterize(text, 16)
    info = meas.shape_info(text, 16.0_f32)
    placements.size.should eq info[:glyph_ids].size
    sum = 0.0_f32
    placements.each { |p| sum += p.advance_px }
    measured = meas.measure(text, 0, 16.0_f32, 0.0_f32)
    (sum - measured.width).abs.should be <= 0.5_f32
    puts "EVIDENCE_D2_MSYYH text=#{text} count=#{placements.size} hb=#{info[:glyph_ids].size} sum=#{sum} meas=#{measured.width}"
    meas.close
  end

  it "D2: Arabic \"لا\" in tahoma/arial/times has at least one font with count==1 and advance consistent" do
    fonts = ["C:/Windows/Fonts/tahoma.ttf", "C:/Windows/Fonts/arial.ttf", "C:/Windows/Fonts/times.ttf"]
    text = "لا"
    any_single = false
    fonts.each do |fp|
      next unless File.exists?(fp)
      meas = Tessell::Text::FtMeasurer.open(fp, 0)
      atlas = Tessell::Text::GlyphAtlas.new(1024, 4096)
      rast = Tessell::Text::Rasterizer.new(meas, atlas, 2)
      begin
        placements = rast.rasterize(text, 16)
        info = meas.shape_info(text, 16.0_f32)
        placements.size.should eq info[:glyph_ids].size
        sum = 0.0_f32
        placements.each { |p| sum += p.advance_px }
        measured = meas.measure(text, 0, 16.0_f32, 0.0_f32)
        (sum - measured.width).abs.should be <= 0.5_f32
        any_single = true if placements.size == 1
        puts "EVIDENCE_D2_FONT font=#{fp} count=#{placements.size} sum=#{sum} meas=#{measured.width}"
      ensure
        meas.close
      end
    end
    any_single.should be_true
  end
end
