# Tessell::Kit::DebugOverlay — 帧调试 overlay（issue #11）
#
# F1 开关（Root#handle 拦截，业务代码零改动）；内容来自宿主每帧塞入的
# DebugInfo：帧耗时/FPS、quad/batch/scissor/culled 数、atlas 页数与
# used_pixels/evicted_total、dirty rect 列表、hover/focus 组件名。
# 绘制为半透明面板 + 等行距文本；text 走 #15 契约（顺序上屏）。

module Tessell
  module Kit
    struct DebugInfo
      getter frame_ms : Float32
      getter quads : Int32
      getter scissor_calls : Int32
      getter culled_quads : Int32
      getter stencil_fills : Int32
      getter atlas_pages : Int32
      getter rgba_pages : Int32
      getter used_pixels : Int32
      getter evicted_total : Int32
      getter dirty_rects : Array(Tessell::Rect)
      getter hover_name : String
      getter focus_name : String

      def initialize(@frame_ms : Float32 = 0.0_f32,
                     @quads : Int32 = 0, @scissor_calls : Int32 = 0,
                     @culled_quads : Int32 = 0, @stencil_fills : Int32 = 0,
                     @atlas_pages : Int32 = 0, @rgba_pages : Int32 = 0,
                     @used_pixels : Int32 = 0, @evicted_total : Int32 = 0,
                     @dirty_rects : Array(Tessell::Rect) = [] of Tessell::Rect,
                     @hover_name : String = "", @focus_name : String = "")
      end

      def fps : Float32
        @frame_ms > 0.0_f32 ? 1000.0_f32 / @frame_ms : 0.0_f32
      end

      # 组装自后端 stats + atlas + Root 状态；宿主只需传 frame_ms 与 dirty。
      def self.collect(backend_stats : Tessell::Render::FrameStats,
                       atlas : Tessell::Text::GlyphAtlas?,
                       root : Root?, frame_ms : Float32,
                       dirty : Array(Tessell::Rect)? = nil) : DebugInfo
        hover_name = root.try(&.hover_component).try(&.a11y_name) || ""
        focus_name = root.try(&.focused_component).try(&.a11y_name) || ""
        DebugInfo.new(
          frame_ms,
          backend_stats.submitted_quads, backend_stats.scissor_calls,
          backend_stats.culled_quads, backend_stats.stencil_fills,
          atlas ? atlas.page_count : 0,
          atlas ? atlas.rgba_page_count : 0,
          atlas ? atlas.used_pixels : 0,
          atlas ? atlas.evicted_total : 0,
          dirty || [] of Tessell::Rect,
          hover_name, focus_name)
      end
    end

    class DebugOverlay
      LINE_HEIGHT = 14.0_f32

      getter visible : Bool
      property font_size : Float32

      def initialize
        @visible = false
        @font_size = 11.0_f32
      end

      def toggle : Bool
        @visible = !@visible
      end

      def visible=(v : Bool) : Nil
        @visible = v
      end

      # 在 viewport 右上角画面板；返回命令数（宿主可断言）。
      def paint(p : Painter, ctx : Context, info : DebugInfo?, viewport : Rect) : Int32
        return 0 unless @visible
        return 0 unless info
        i = info.not_nil!
        lines = [] of String
        lines << "frame=#{i.frame_ms.round(1)}ms fps=#{i.fps.round(0)}"
        lines << "quads=#{i.quads} scissor=#{i.scissor_calls} culled=#{i.culled_quads} stencil=#{i.stencil_fills}"
        lines << "atlas pages=#{i.atlas_pages}+#{i.rgba_pages}rgba used=#{i.used_pixels} evicted=#{i.evicted_total}"
        lines << "dirty=#{i.dirty_rects.size}"
        i.dirty_rects.first(4).each_with_index do |r, idx|
          lines << "  [#{idx}] #{r.origin.x.round(0)},#{r.origin.y.round(0)} #{r.size.width.round(0)}x#{r.size.height.round(0)}"
        end
        lines << "hover=#{i.hover_name.empty? ? "-" : i.hover_name}"
        lines << "focus=#{i.focus_name.empty? ? "-" : i.focus_name}"

        m = ctx.text_metrics(@font_size)
        line_h = Math.max(LINE_HEIGHT, m.line_height)
        width = 240.0_f32
        height = line_h * lines.size + 12.0_f32
        panel = Rect.new(viewport.max_x - width - 8.0_f32, 8.0_f32, width, height)
        p.push_clip(viewport)
        p.fill_round_rect(panel, 6.0_f32, ctx.theme.palette.scrim)
        lines.each_with_index do |line, idx|
          x = panel.origin.x + 10.0_f32
          baseline = panel.origin.y + 8.0_f32 + m.ascent + idx * line_h
          p.text(x, baseline, line, 0xffffffff_u32, @font_size)
        end
        p.pop_clip
        lines.size
      end
    end
  end
end
