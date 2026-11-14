# Tessell::Kit — 文本对齐与矩形内绘制助手（issue #6）
#
# 应用不再猜 baseline（旧行为是 `0.36 * size` 之类的经验系数）：用
# Context#text_metrics 的 ascent/descent 计算 top/middle/bottom，
# 用 measure_text 计算 left/center/right。
# 多段不同颜色/字号的文本：Painter#text 按调用顺序逐段发命令即可
# （issue #15 契约保证顺序与合批），无需专门 API。

module Tessell
  module Kit
    enum HAlign
      Left
      Center
      Right
    end

    enum VAlign
      Top
      Middle
      Bottom
    end

    module TextDrawing
      # 单行文本在 rect 内垂直居中的基线（逻辑单位，issue #19）。
      # 与 draw_in_rect 的 VAlign::Middle 同口径：按 ascent/descent 视觉盒
      # 居中，替代组件里 (h + fs)/2 - fs*0.1 一类的经验系数。
      def self.middle_baseline(rect : Rect, m : Tessell::Text::FontMetrics) : Float32
        rect.origin.y + (rect.size.height - (m.ascent + m.descent)) / 2.0_f32 + m.ascent
      end

      # 在 rect 内画单行文本：halign 决定 x，valign 决定 baseline。
      # size 为逻辑字号；坐标全部为逻辑单位（与组件 bounds 同系）。
      def self.draw_in_rect(ctx : Context, p : Painter, rect : Rect,
                            text : String, color : UInt32, size : Float32,
                            halign : HAlign = HAlign::Left,
                            valign : VAlign = VAlign::Middle,
                            max_width : Float32 = Float32::INFINITY) : Nil
        m = ctx.text_metrics(size)
        w = ctx.measure_text(text, size, max_width).width
        x = case halign
            when HAlign::Left   then rect.origin.x
            when HAlign::Center then rect.origin.x + (rect.size.width - w) / 2.0_f32
            else                     rect.max_x - w
            end
        baseline = case valign
                   when VAlign::Top
                     rect.origin.y + m.ascent
                   when VAlign::Middle
                     rect.origin.y + (rect.size.height - (m.ascent + m.descent)) / 2.0_f32 + m.ascent
                   else
                     rect.max_y - m.descent
                   end
        p.text(x, baseline, text, color, size)
      end
    end
  end
end
