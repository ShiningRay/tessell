require "./spec_helper"

module Tessell
  describe "Text::ColorRasterizer (COLR/CPAL)" do
    it "reports color glyph layers for seguiemj emoji" do
      m = Text::FtMeasurer.open("C:/Windows/Fonts/seguiemj.ttf")
      begin
        cr = Text::ColorRasterizer.new(m)
        g_smile = Text::FT::Lib.get_char_index(m.ft_face_handle, 0x1F600_u32)
        g_thumb = Text::FT::Lib.get_char_index(m.ft_face_handle, 0x1F44D_u32)
        cr.layers(g_smile).should eq 6
        cr.layers(g_thumb).should eq 2
        cr.color?(g_smile).should be_true
        cr.color?(g_thumb).should be_true
        cr.color?(0_u32).should be_false
      ensure
        m.close
      end
    end

    it "msyh has no color layers for emoji codepoints" do
      m = Text::FtMeasurer.open("C:/Windows/Fonts/msyh.ttc", 0)
      begin
        cr = Text::ColorRasterizer.new(m)
        g_smile = Text::FT::Lib.get_char_index(m.ft_face_handle, 0x1F600_u32)
        cr.color?(g_smile).should be_false
      ensure
        m.close
      end
    end

    it "rasterizes 😀 at 32px with reasonable size and buffer" do
      m = Text::FtMeasurer.open("C:/Windows/Fonts/seguiemj.ttf")
      begin
        cr = Text::ColorRasterizer.new(m)
        g_smile = Text::FT::Lib.get_char_index(m.ft_face_handle, 0x1F600_u32)
        bm = cr.rasterize_color(g_smile, 32)
        bm.w.should be >= 25
        bm.w.should be <= 40
        bm.h.should be >= 25
        bm.h.should be <= 40
        bm.pixels.size.should eq bm.w * bm.h * 4
        puts "COLOR_SPEC_32 w=#{bm.w} h=#{bm.h} advance=#{bm.advance_px}"
      ensure
        m.close
      end
    end

    it "keeps premultiplied invariant r<=a g<=a b<=a for all pixels" do
      m = Text::FtMeasurer.open("C:/Windows/Fonts/seguiemj.ttf")
      begin
        cr = Text::ColorRasterizer.new(m)
        g_smile = Text::FT::Lib.get_char_index(m.ft_face_handle, 0x1F600_u32)
        bm = cr.rasterize_color(g_smile, 32)
        bad = 0
        i = 0
        while i < bm.pixels.size
          r = bm.pixels[i]
          g = bm.pixels[i + 1]
          b = bm.pixels[i + 2]
          a = bm.pixels[i + 3]
          bad += 1 if r > a || g > a || b > a
          i += 4
        end
        puts "COLOR_SPEC_PREMUL bad=#{bad} pixels=#{bm.w * bm.h}"
        bad.should eq 0
      ensure
        m.close
      end
    end

    it "produces colorful pixels and reports dominant color for 😀" do
      m = Text::FtMeasurer.open("C:/Windows/Fonts/seguiemj.ttf")
      begin
        cr = Text::ColorRasterizer.new(m)
        g_smile = Text::FT::Lib.get_char_index(m.ft_face_handle, 0x1F600_u32)
        bm = cr.rasterize_color(g_smile, 32)
        colorful = 0
        best_a = -1
        best_r = 0_u8
        best_g = 0_u8
        best_b = 0_u8
        i = 0
        while i < bm.pixels.size
          r = bm.pixels[i].to_i
          g = bm.pixels[i + 1].to_i
          b = bm.pixels[i + 2].to_i
          a = bm.pixels[i + 3].to_i
          mx = r
          mx = g if g > mx
          mx = b if b > mx
          mn = r
          mn = g if g < mn
          mn = b if b < mn
          if (mx - mn) > 30
            colorful += 1
            if a > best_a
              best_a = a
              best_r = bm.pixels[i]
              best_g = bm.pixels[i + 1]
              best_b = bm.pixels[i + 2]
            end
          end
          i += 4
        end
        puts "COLOR_SPEC_COLORFUL colorful=#{colorful} dominant_rgb=(#{best_r},#{best_g},#{best_b}) dominant_a=#{best_a}"
        colorful.should be > 0
      ensure
        m.close
      end
    end

    it "handles boundary cases and 200 calls without leak/crash" do
      m = Text::FtMeasurer.open("C:/Windows/Fonts/seguiemj.ttf")
      begin
        cr = Text::ColorRasterizer.new(m)
        g_smile = Text::FT::Lib.get_char_index(m.ft_face_handle, 0x1F600_u32)
        cr.color?(0_u32).should be_false
        bm128 = cr.rasterize_color(g_smile, 128)
        bm128.w.should be >= 90
        bm128.h.should be >= 90
        bm128.w.should be <= 180
        bm128.h.should be <= 180
        bm128.pixels.size.should eq bm128.w * bm128.h * 4
        ok = true
        i = 0
        while i < bm128.pixels.size
          r = bm128.pixels[i]
          g = bm128.pixels[i + 1]
          b = bm128.pixels[i + 2]
          a = bm128.pixels[i + 3]
          if r > a || g > a || b > a
            ok = false
            break
          end
          i += 4
        end
        ok.should be_true
        before = cr.rasterize_calls
        200.times { cr.rasterize_color(g_smile, 32) }
        after = cr.rasterize_calls
        puts "COLOR_SPEC_200 calls_delta=#{after - before} cache=none(internal)"
        (after - before).should eq 200
      ensure
        m.close
      end
    end
  end
end
