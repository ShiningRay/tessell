# Tessell::Render::Backend (M3-WP1)
# Abstract render backend interface. Textures are owned by the backend;
# callers never pass texture ids — batches carry atlas page indices and the
# backend resolves them via resolved_texture(page).

require "../geometry"
require "./theme"
require "./text_renderer"
require "../text/glyph_atlas"

module Tessell
  module Render
    struct FrameStats
      getter submitted_quads : Int32
      getter scissor_calls : Int32
      getter culled_quads : Int32

      def initialize(@submitted_quads : Int32 = 0, @scissor_calls : Int32 = 0, @culled_quads : Int32 = 0)
      end
    end

    abstract class Backend
      abstract def init(width : Int32, height : Int32) : Nil
      abstract def resize(width : Int32, height : Int32) : Nil
      abstract def begin_frame(dirty : Array(Tessell::Rect)? = nil, theme : Tessell::Render::Theme = Tessell::Render::Theme.light) : Nil
      abstract def sync_atlas(atlas : Text::GlyphAtlas) : Nil
      abstract def draw_text(vertices : Array(Vertex), batches : Array(TextBatch), batch_count : Int32 = batches.size) : Int32
      abstract def end_frame : Nil
      abstract def close : Nil
      abstract def stats : FrameStats
      abstract def resolved_texture(page : Int32) : Int32

      # Color-page resolution: batches carrying color=true read RGBA atlas pages.
      # Backends without RGBA pages fall back to the R8 resolution (gray semantics).
      def resolved_texture(page : Int32, color : Bool) : Int32
        resolved_texture(page)
      end
    end
  end
end