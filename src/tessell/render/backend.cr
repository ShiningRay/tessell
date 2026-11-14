# Tessell::Render::Backend (M3-WP1)
# Abstract render backend interface. Textures are owned by the backend;
# callers never pass texture ids — batches carry atlas page indices and the
# backend resolves them via resolved_texture(page).

require "../geometry"
require "./draw_list"
require "./theme"
require "./text_renderer"
require "../text/glyph_atlas"

module Tessell
  module Render
    struct FrameStats
      getter submitted_quads : Int32
      getter scissor_calls : Int32
      getter culled_quads : Int32
      getter stencil_fills : Int32

      def initialize(@submitted_quads : Int32 = 0, @scissor_calls : Int32 = 0,
                     @culled_quads : Int32 = 0, @stencil_fills : Int32 = 0)
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

      # Draw a command list. Backends that support 2D primitives implement this;
      # base returns 0 = unsupported rather than silently claiming success.
      # Text commands are rendered separately via draw_text; implementations may
      # skip them. Returns number of non-text commands actually submitted.
      def draw_draw_list(list : Tessell::Render::DrawList) : Int32
        0
      end

      # Fill a polygon using stencil/cover when supported (e.g. GLBackend). `points`
      # are in screen space, `color` is premultiplied RGBA8, and `even_odd` selects
      # fill rule (true = even-odd). Base returns false = unsupported; backends that
      # perform the fill must return true and account stencil_fills in stats.
      def draw_polygon(points : Array(Tessell::Point), color : UInt32,
                       even_odd : Bool = true) : Bool
        false
      end
    end
  end
end
