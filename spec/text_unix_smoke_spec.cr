require "./spec_helper"
require "../src/tessell/text/ft_measurer"
require "../src/tessell/text/glyph_atlas"
require "../src/tessell/text/rasterizer"
require "../src/tessell/render/text_renderer"

# Cross-platform text smoke: macOS/Linux use an installed sans font; Windows
# keeps the existing Windows-font specs. This guards the FreeType LP64 layout
# fix without making Windows CI depend on macOS paths.
private def unix_font_path : String?
  candidates = [
    "/System/Library/Fonts/Supplemental/Arial Unicode.ttf",
    "/System/Library/Fonts/Supplemental/Arial.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
  ]
  candidates.find { |path| File.exists?(path) }
end

describe "Text stack on LP64 (macOS/Linux smoke)" do
  it "measures and rasterizes with the platform font" do
    path = unix_font_path
    if path.nil?
      pending "no Unix test font found"
    else
      measurer = Tessell::Text::FtMeasurer.open(path, 0)
      size = measurer.measure("Hello", 0, 16.0_f32, 1000.0_f32)
      size.width.should be > 0.0_f32
      size.height.should be > 0.0_f32

      atlas = Tessell::Text::GlyphAtlas.new(1024, 4096)
      raster = Tessell::Text::Rasterizer.new(measurer, atlas, 0, 256)
      placements = raster.rasterize("Hello", 16)
      placements.size.should be > 0

      renderer = Tessell::Render::TextRenderer.new(atlas, raster)
      sink = [] of Tessell::Text::GlyphPlacement
      renderer.reset
      renderer.build_text(sink, "Hello", 10.0_f32, 20.0_f32, 16, 400, 200)
      renderer.vertex_count.should be > 0
    end
  end
end
