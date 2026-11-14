# Tessell::Kit — 绘制原语（K0）
#
# 组件只通过 Painter 发命令，不直接调 GL/平台 API。
# PaintList 是后端无关的命令缓冲，可用于无窗口断言、headless 光栅化与未来 GL 适配。

module Tessell
  module Kit
    enum PaintKind
      FillRect
      StrokeRect
      FillRoundRect
      StrokeRoundRect
      Line
      Text
      PushClip
      PopClip
    end

    struct PaintCmd
      getter kind : PaintKind
      getter rect : Rect
      getter color : UInt32
      getter width : Float32
      getter radius : Float32
      getter text : String
      getter x : Float32
      getter y : Float32
      getter x2 : Float32
      getter y2 : Float32
      getter font_size : Float32
      # 字体 face 维度（issue #29）：0 = 默认 face；多 face 栈按宿主 renderer
      # 表选取。与 DrawListPainter 写入 DrawCmd#atlas_id 的语义一致。
      getter font_id : Int32
      # 命令生效时的裁切矩形（push_clip/pop_clip 交集结果），与
      # DrawListPainter 的 DrawCmd#clip 同语义（issue #25）。nil = 无裁切。
      getter clip : Rect?

      def initialize(@kind : PaintKind, @rect : Rect = Rect.new,
                     @color : UInt32 = 0_u32, @width : Float32 = 0.0_f32,
                     @radius : Float32 = 0.0_f32, @text : String = "",
                     @x : Float32 = 0.0_f32, @y : Float32 = 0.0_f32,
                     @font_size : Float32 = 0.0_f32,
                     @x2 : Float32 = 0.0_f32, @y2 : Float32 = 0.0_f32,
                     @clip : Rect? = nil, @font_id : Int32 = 0)
      end
    end

    # 复用容量：clear 只重置逻辑计数；push 先覆写物理槽位。
    class PaintList
      def initialize
        @commands = [] of PaintCmd
        @size = 0
      end

      def size : Int32
        @size
      end

      def physical_size : Int32
        @commands.size
      end

      def clear : Nil
        @size = 0
      end

      def push(cmd : PaintCmd) : Nil
        if @size < @commands.size
          @commands[@size] = cmd
        else
          @commands << cmd
        end
        @size += 1
      end

      def [](index : Int) : PaintCmd
        raise IndexError.new if index < 0 || index >= @size
        @commands[index]
      end

      def to_a : Array(PaintCmd)
        result = [] of PaintCmd
        i = 0
        while i < @size
          result << @commands[i]
          i += 1
        end
        result
      end

      def reserve(n : Int32) : Nil
        return if n <= @commands.size
        (n - @commands.size).times do
          @commands << PaintCmd.new(PaintKind::FillRect)
        end
      end

      # 裁切栈深度检查：返回未闭合的 push 数。
      def clip_depth : Int32
        depth = 0
        i = 0
        while i < @size
          case @commands[i].kind
          when PaintKind::PushClip then depth += 1
          when PaintKind::PopClip  then depth -= 1 if depth > 0
          else
          end
          i += 1
        end
        depth
      end
    end

    # 绘制契约（issue #15， Painter 实现与宿主必须共同遵守）：
    #
    # 1. z-order：调用顺序即绘制顺序。text 与形状命令可任意交错，后提交者
    #    覆盖先提交者——「先画文字再画不透明覆盖层」必须能盖住文字。
    #    宿主禁止把文本收集后统一放到形状之后上屏（那会把 z-order 变成
    #    「所有形状 → 所有文本」）。
    # 2. clip：push_clip/pop_clip 同时约束形状与文本；嵌套 clip 取交集。
    #    滚动容器边缘的文本由后端 scissor 裁切，组件不得依赖“只发完全可见
    #    文本”的 workaround。
    # 3. 文本基线：text(x, baseline_y, ...) 的坐标是基线起点（y-down），
    #    与 Render::TextRenderer 的顶点生成约定一致。
    abstract class Painter
      abstract def fill_rect(rect : Rect, color : UInt32) : Nil
      abstract def stroke_rect(rect : Rect, color : UInt32, width : Float32 = 1.0_f32) : Nil
      abstract def fill_round_rect(rect : Rect, radius : Float32, color : UInt32) : Nil
      abstract def stroke_round_rect(rect : Rect, radius : Float32, color : UInt32, width : Float32 = 1.0_f32) : Nil
      abstract def line(x1 : Float32, y1 : Float32, x2 : Float32, y2 : Float32,
                        color : UInt32, width : Float32 = 1.0_f32) : Nil
      abstract def text(x : Float32, baseline_y : Float32, text : String,
                        color : UInt32, size : Float32, font_id : Int32 = 0) : Nil
      abstract def push_clip(rect : Rect) : Nil
      abstract def pop_clip : Nil
    end

    # PaintListPainter 与 DrawListPainter 的 clip 语义一致（issue #25）：
    # push_clip/pop_clip 同时约束形状与文本，命令携带解析后的 clip 矩形。
    # 此前文本/形状完全不看 clip，headless 断言会误报通过。
    class PaintListPainter < Painter
      getter list : PaintList

      @clips : Array(Rect)

      def initialize(@list : PaintList = PaintList.new)
        @clips = [] of Rect
      end

      def fill_rect(rect : Rect, color : UInt32) : Nil
        @list.push(PaintCmd.new(PaintKind::FillRect, rect, color, clip: current_clip))
      end

      def stroke_rect(rect : Rect, color : UInt32, width : Float32 = 1.0_f32) : Nil
        @list.push(PaintCmd.new(PaintKind::StrokeRect, rect, color, width,
          clip: current_clip))
      end

      def fill_round_rect(rect : Rect, radius : Float32, color : UInt32) : Nil
        @list.push(PaintCmd.new(PaintKind::FillRoundRect, rect, color,
          radius: radius, clip: current_clip))
      end

      def stroke_round_rect(rect : Rect, radius : Float32, color : UInt32, width : Float32 = 1.0_f32) : Nil
        @list.push(PaintCmd.new(PaintKind::StrokeRoundRect, rect, color, width, radius,
          clip: current_clip))
      end

      def line(x1 : Float32, y1 : Float32, x2 : Float32, y2 : Float32,
               color : UInt32, width : Float32 = 1.0_f32) : Nil
        @list.push(PaintCmd.new(PaintKind::Line, color: color, width: width,
          x: x1, y: y1, x2: x2, y2: y2, clip: current_clip))
      end

      def text(x : Float32, baseline_y : Float32, text : String,
               color : UInt32, size : Float32, font_id : Int32 = 0) : Nil
        @list.push(PaintCmd.new(PaintKind::Text, Rect.new, color, text: text,
          x: x, y: baseline_y, font_size: size, clip: current_clip,
          font_id: font_id))
      end

      def push_clip(rect : Rect) : Nil
        @clips << current_clip_or(rect)
        @list.push(PaintCmd.new(PaintKind::PushClip, rect))
      end

      def pop_clip : Nil
        @clips.pop unless @clips.empty?
        @list.push(PaintCmd.new(PaintKind::PopClip))
      end

      def clip_depth : Int32
        @clips.size
      end

      def reset : Nil
        @list.clear
        @clips.clear
      end

      private def current_clip : Rect?
        @clips.empty? ? nil : @clips.last
      end

      private def current_clip_or(rect : Rect) : Rect
        return rect if @clips.empty?
        Geometry.intersect(@clips.last, rect)
      end
    end

    # 常用几何工具：Kit 内部使用，不改变核心 Rect 语义。
    module Geometry
      def self.inset(rect : Rect, all : Float32) : Rect
        inset(rect, all, all, all, all)
      end

      def self.inset(rect : Rect, insets : Insets) : Rect
        inset(rect, insets.top, insets.right, insets.bottom, insets.left)
      end

      def self.inset(rect : Rect, top : Float32, right : Float32,
                     bottom : Float32, left : Float32) : Rect
        w = rect.size.width - left - right
        h = rect.size.height - top - bottom
        Rect.new(rect.origin.x + left, rect.origin.y + top,
          w < 0.0_f32 ? 0.0_f32 : w, h < 0.0_f32 ? 0.0_f32 : h)
      end

      def self.center(rect : Rect, child : Size) : Rect
        Rect.new(rect.origin.x + (rect.size.width - child.width) / 2.0_f32,
          rect.origin.y + (rect.size.height - child.height) / 2.0_f32,
          child.width, child.height)
      end

      def self.intersect(a : Rect, b : Rect) : Rect
        x0 = Math.max(a.origin.x, b.origin.x)
        y0 = Math.max(a.origin.y, b.origin.y)
        x1 = Math.min(a.max_x, b.max_x)
        y1 = Math.min(a.max_y, b.max_y)
        w = x1 - x0
        h = y1 - y0
        if w <= 0.0_f32 || h <= 0.0_f32
          Rect.new(x0, y0, 0.0_f32, 0.0_f32)
        else
          Rect.new(x0, y0, w, h)
        end
      end
    end
  end
end
