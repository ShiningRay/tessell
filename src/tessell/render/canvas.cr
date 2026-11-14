# Tessell::Render::Canvas (issue #2)
#
# 统一绘制门面：应用面向 Canvas 编程，命令写入 DrawList，由
# Backend#draw_draw_list 执行（GLBackend 实现 Rect/RoundRect/Stroke/Line +
# per-command scissor）。文本与图形走同一条提交路径：DrawList 的 Text 命令
# 由宿主在命令序中经 draw_text 交错提交（issue #15 契约）。
#
# draw_polygon 保留为高层路径填充入口（stencil/cover），不是 Canvas 的
# 组成部分；Canvas#polyline 展开为逐段 Line 命令，同一 clip 内天然同批。
#
# 已知边界（K6 复盘 #13.2 同口径）：GLBackend 的 dirty 模式清屏由
# draw_text 承担；draw_draw_list 在 dirty 模式下按命令 clip scissor，但
# 不执行清屏——部分提交混用 Canvas 命令时，宿主需先经 draw_text 完成脏区
# 清除，或使用整帧模式。

require "./draw_list"

module Tessell
  module Render
    class Canvas
      getter list : DrawList

      @clips : Array(Tessell::Rect)

      def initialize(@list : DrawList = DrawList.new)
        @clips = [] of Tessell::Rect
      end

      def fill_rect(rect : Tessell::Rect, color : UInt32) : Nil
        @list.push(DrawCmd.new(CmdKind::Rect, rect, color, clip: current_clip))
      end

      def stroke_rect(rect : Tessell::Rect, color : UInt32, width : Float32 = 1.0_f32) : Nil
        @list.push(DrawCmd.new(CmdKind::StrokeRect, rect, color,
          clip: current_clip, stroke_width: width))
      end

      def fill_round_rect(rect : Tessell::Rect, radius : Float32, color : UInt32) : Nil
        @list.push(DrawCmd.new(CmdKind::RoundRect, rect, color,
          clip: current_clip, radius: radius))
      end

      def stroke_round_rect(rect : Tessell::Rect, radius : Float32, color : UInt32,
                            width : Float32 = 1.0_f32) : Nil
        @list.push(DrawCmd.new(CmdKind::StrokeRoundRect, rect, color,
          clip: current_clip, radius: radius, stroke_width: width))
      end

      def line(x1 : Float32, y1 : Float32, x2 : Float32, y2 : Float32,
               color : UInt32, width : Float32 = 1.0_f32) : Nil
        bounds = Tessell::Rect.new(Math.min(x1, x2), Math.min(y1, y2),
          (x2 - x1).abs, (y2 - y1).abs)
        @list.push(DrawCmd.new(CmdKind::Line, bounds, color,
          clip: current_clip, stroke_width: width,
          p1: Tessell::Point.new(x1, y1), p2: Tessell::Point.new(x2, y2)))
      end

      # 折线：展开为逐段 Line 命令（同一 clip 下 atlas_id/clip 相同 → 同批）。
      # points < 2 时不发任何命令。
      def polyline(points : Array(Tessell::Point), color : UInt32,
                   width : Float32 = 1.0_f32) : Nil
        i = 1
        while i < points.size
          line(points[i - 1].x, points[i - 1].y, points[i].x, points[i].y,
            color, width)
          i += 1
        end
      end

      def push_clip(rect : Tessell::Rect) : Nil
        @clips << current_clip_or(rect)
      end

      def pop_clip : Nil
        @clips.pop unless @clips.empty?
      end

      def clip_depth : Int32
        @clips.size
      end

      def clear : Nil
        @list.clear
        @clips.clear
      end

      private def current_clip : Tessell::Rect?
        @clips.empty? ? nil : @clips.last
      end

      private def current_clip_or(rect : Tessell::Rect) : Tessell::Rect
        return rect if @clips.empty?
        intersect(current_clip.not_nil!, rect)
      end

      private def intersect(a : Tessell::Rect, b : Tessell::Rect) : Tessell::Rect
        x0 = Math.max(a.origin.x, b.origin.x)
        y0 = Math.max(a.origin.y, b.origin.y)
        x1 = Math.min(a.max_x, b.max_x)
        y1 = Math.min(a.max_y, b.max_y)
        Tessell::Rect.new(x0, y0, x1 - x0, y1 - y0)
      end
    end
  end
end
