# Tessell::Kit::DrawListPainter — 把 Kit 绘制命令映射到核心 Render::DrawList（K1）
#
# 核心 DrawList 只承载命令，不执行光栅化；具体后端按 CmdKind 实现。
# 裁切在 Painter 层解析为每条命令的 clip 矩形（与核心 HitTest 的 Node#clip 同语义）。

require "../render/draw_list"
require "./painter"

module Tessell
  module Kit
    class DrawListPainter < Painter
      getter list : Render::DrawList

      @clips : Array(Rect)

      def initialize(@list : Render::DrawList = Render::DrawList.new)
        @clips = [] of Rect
      end

      def fill_rect(rect : Rect, color : UInt32) : Nil
        @list.push(Render::DrawCmd.new(Render::CmdKind::Rect, rect, color,
          clip: current_clip))
      end

      def stroke_rect(rect : Rect, color : UInt32, width : Float32 = 1.0_f32) : Nil
        @list.push(Render::DrawCmd.new(Render::CmdKind::StrokeRect, rect, color,
          clip: current_clip, stroke_width: width))
      end

      def fill_round_rect(rect : Rect, radius : Float32, color : UInt32) : Nil
        @list.push(Render::DrawCmd.new(Render::CmdKind::RoundRect, rect, color,
          clip: current_clip, radius: radius))
      end

      def stroke_round_rect(rect : Rect, radius : Float32, color : UInt32,
                            width : Float32 = 1.0_f32) : Nil
        @list.push(Render::DrawCmd.new(Render::CmdKind::StrokeRoundRect, rect, color,
          clip: current_clip, radius: radius, stroke_width: width))
      end

      def text(x : Float32, baseline_y : Float32, text : String,
               color : UInt32, size : Float32) : Nil
        @list.push(Render::DrawCmd.new(Render::CmdKind::Text,
          Rect.new(x, baseline_y, 0.0_f32, size), color, clip: current_clip))
      end

      def push_clip(rect : Rect) : Nil
        @clips << current_clip_or(rect)
      end

      def pop_clip : Nil
        @clips.pop unless @clips.empty?
      end

      def clip_depth : Int32
        @clips.size
      end

      private def current_clip : Rect?
        @clips.empty? ? nil : @clips.last
      end

      private def current_clip_or(rect : Rect) : Rect
        return rect if @clips.empty?
        Geometry.intersect(@clips.last, rect)
      end
    end
  end
end
