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
      # 全量重传 glyph atlas 所有页（冷启动/整体重建用）。动态文本场景禁止
      # 每帧调用——增量路径走 sync_atlas_dirty（issue #22）。
      abstract def sync_atlas(atlas : Text::GlyphAtlas) : Nil
      # Issue #15 contract: text is part of the command order — a host may draw
      # text segments interleaved with draw_draw_list segments. `from_batch`
      # selects the unsubmitted suffix of `batches`; `clip` restricts the text
      # segment to a scissor rect (nil = unclipped).
      abstract def draw_text(vertices : Array(Vertex), batches : Array(TextBatch),
                             batch_count : Int32 = batches.size, from_batch : Int32 = 0,
                             clip : Tessell::Rect? = nil) : Int32
      abstract def end_frame : Nil
      abstract def close : Nil
      abstract def stats : FrameStats
      abstract def resolved_texture(page : Int32) : Int32

      # 增量 glyph atlas 同步（issue #22）：只上传内容 revision 变化的页。
      # 宿主按 Backend 抽象编程即可每帧调用——有增量实现的后端（GL）在
      # atlas 未变化时是 no-op；基类默认退化为全量 sync_atlas，第三方后端
      # 不必强制实现。禁止用 page_count 比较自行判断是否同步（issue #1 口径）。
      def sync_atlas_dirty(atlas : Text::GlyphAtlas) : Nil
        sync_atlas(atlas)
      end

      # Color-page resolution: batches carrying color=true read RGBA atlas pages.
      # Backends without RGBA pages fall back to the R8 resolution (gray semantics).
      def resolved_texture(page : Int32, color : Bool) : Int32
        resolved_texture(page)
      end

      # Draw a command list. Backends that support 2D primitives implement this;
      # base returns 0 = unsupported rather than silently claiming success.
      # Text commands are skipped here (rendered via draw_text) so a host can
      # interleave shape/text segments in command order. `from`/`count` select
      # a sub-range of the list (count < 0 = to the end). Returns number of
      # non-text commands actually submitted.
      def draw_draw_list(list : Tessell::Render::DrawList, from : Int32 = 0,
                         count : Int32 = -1) : Int32
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
