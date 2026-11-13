require "./spec_helper"
require "../src/tessell/text/ffi/freetype"

EMOJI_FONT = "C:/Windows/Fonts/seguiemj.ttf"

describe "Tessell::Text emoji (seguiemj.ttf)" do
  it "measures single emoji 😀 with glyphs>=1, advance>0, |measure-sum(adv)|<=0.5" do
    m = Tessell::Text::FtMeasurer.open(EMOJI_FONT, 0)
    begin
      text = "😀"
      size = 32.0_f32
      sz = m.measure(text, 0, size, 0.0_f32)
      info = m.shape_info(text, size)
      info[:glyph_ids].size.should be >= 1
      sum_adv = 0.0_f32
      info[:advances_px].each { |a| sum_adv += a }
      sz.width.should be > 0.0_f32
      sum_adv.should be > 0.0_f32
      diff = (sz.width - sum_adv).abs
      diff.should be <= 0.5_f32
      puts "EVIDENCE_EMOJI_MEASURE1 text=#{text.inspect} w=#{sz.width} h=#{sz.height} glyphs=#{info[:glyph_ids].size} sum_adv=#{sum_adv} diff=#{diff}"
    ensure
      m.close
    end
  end

  it "measures 😀👍 with glyphs>=1, advance>0, |measure-sum(adv)|<=0.5" do
    m = Tessell::Text::FtMeasurer.open(EMOJI_FONT, 0)
    begin
      text = "😀👍"
      size = 32.0_f32
      sz = m.measure(text, 0, size, 0.0_f32)
      info = m.shape_info(text, size)
      info[:glyph_ids].size.should be >= 1
      sum_adv = 0.0_f32
      info[:advances_px].each { |a| sum_adv += a }
      sz.width.should be > 0.0_f32
      sum_adv.should be > 0.0_f32
      diff = (sz.width - sum_adv).abs
      diff.should be <= 0.5_f32
      puts "EVIDENCE_EMOJI_MEASURE2 text=#{text.inspect} w=#{sz.width} h=#{sz.height} glyphs=#{info[:glyph_ids].size} sum_adv=#{sum_adv} diff=#{diff}"
    ensure
      m.close
    end
  end

  it "rasterizes 😀👍 with at least one placement w>0,h>0 and non-zero coverage (records ratio)" do
    m = Tessell::Text::FtMeasurer.open(EMOJI_FONT, 0)
    atlas = Tessell::Text::GlyphAtlas.new(1024, 4096)
    rast = Tessell::Text::Rasterizer.new(m, atlas, 1)
    begin
      placements = rast.rasterize("😀👍", 32)
      placements.size.should be >= 1
      any_drawable = false
      placements.each_with_index do |p, i|
        next unless p.w > 0 && p.h > 0
        cov = rast.coverage(p)
        cov.should be > 0
        total = p.w * p.h
        ratio = total > 0 ? (cov.to_f64 / total.to_f64) : 0.0
        puts "EVIDENCE_EMOJI_COV i=#{i} gid=#{p.glyph_id} adv=#{p.advance_px} w=#{p.w} h=#{p.h} cov=#{cov} total=#{total} cov_ratio=#{ratio}"
        any_drawable = true
      end
      any_drawable.should be_true
    ensure
      m.close
    end
  end

  it "placements have UV in [0,1] and page>=0 for drawable glyphs" do
    m = Tessell::Text::FtMeasurer.open(EMOJI_FONT, 0)
    atlas = Tessell::Text::GlyphAtlas.new(1024, 4096)
    rast = Tessell::Text::Rasterizer.new(m, atlas, 1)
    begin
      placements = rast.rasterize("😀👍", 32)
      placements.size.should be >= 1
      placements.each do |p|
        (p.u0 >= 0.0_f32 && p.u0 <= 1.0_f32).should be_true
        (p.v0 >= 0.0_f32 && p.v0 <= 1.0_f32).should be_true
        (p.u1 >= 0.0_f32 && p.u1 <= 1.0_f32).should be_true
        (p.v1 >= 0.0_f32 && p.v1 <= 1.0_f32).should be_true
        if p.w > 0 && p.h > 0
          p.page.should be >= 0
          (p.u1 > p.u0).should be_true
          (p.v1 > p.v0).should be_true
        end
      end
      puts "EVIDENCE_EMOJI_UV count=#{placements.size} ok=true"
    ensure
      m.close
    end
  end

  it "asserts seguiemj glyph pixel_mode (2=gray/7=BGRA) and records nonzero bitmap evidence" do
    m = Tessell::Text::FtMeasurer.open(EMOJI_FONT, 0)
    atlas = Tessell::Text::GlyphAtlas.new(1024, 4096)
    rast = Tessell::Text::Rasterizer.new(m, atlas, 1)
    begin
      text = "😀👍"
      size = 32_u32
      info = m.shape_info(text, size.to_f32)
      face = m.ft_face_handle
      Tessell::Text::FT::Lib.set_pixel_sizes(face, 0_u32, size)
      modes = [] of Int32
      any_nonzero_bitmap = false
      info[:glyph_ids].each_with_index do |gid, i|
        err = Tessell::Text::FT::Lib.load_glyph(face, gid, Tessell::Text::FT::Lib::LOAD_RENDER)
        err.should eq 0
        slotg = face.value.glyph
        slotg.null?.should be_false
        bm = slotg.value.bitmap
        pm = bm.pixel_mode.to_i
        modes << pm
        puts "EVIDENCE_EMOJI_PIXELMODE i=#{i} gid=#{gid} pixel_mode=#{pm} bm_w=#{bm.width} bm_h=#{bm.rows} pitch=#{bm.pitch}"
        any_nonzero_bitmap = true if bm.width > 0 && bm.rows > 0
      end
      any_nonzero_bitmap.should be_true
      modes.size.should be > 0
      # All observed glyphs in this path must report a known pixel mode; record value explicitly.
      modes.each do |pm|
        (pm == 2 || pm == 7).should be_true
      end
      puts "EVIDENCE_EMOJI_PIXELMODE_SUMMARY modes=#{modes.inspect} (2=FT_PIXEL_MODE_GRAY,7=FT_PIXEL_MODE_BGRA)"

      placements = rast.rasterize(text, size.to_i)
      drawable_cov = 0
      placements.each do |p|
        next unless p.w > 0 && p.h > 0
        c = rast.coverage(p)
        drawable_cov += c
      end
      if modes.all? { |pm| pm == 7 }
        # BGRA/color: assert nonzero coverage and record P2 limitation (no alpha-correct compositing asserted).
        drawable_cov.should be > 0
        puts "EVIDENCE_EMOJI_COLOR_NOTE pixel_mode=7(BGRA) drawable_cov=#{drawable_cov} status=R8_gray_display_not_applicable P2=color_compositing"
      else
        # Gray path (expected): bitmap coverage must be non-zero.
        drawable_cov.should be > 0
        puts "EVIDENCE_EMOJI_GRAY_NOTE pixel_mode=#{modes.first} drawable_cov=#{drawable_cov} status=R8_gray_path_ok"
      end
    ensure
      m.close
    end
  end
end
