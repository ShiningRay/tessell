# Tessell::Kit::Tooltip — 浮层内容（K3）
#
# 只负责显示文本与尺寸；延迟、锚点、dismiss 由 Root/OverlayHost 管理。
# Tooltip 不抢焦点，不进入焦点环。

module Tessell
  module Kit
    class Tooltip < Component
      property text : String
      property size : ControlSize

      def initialize(@key : UI::UiKey, @text : String,
                     @size : ControlSize = ControlSize::Small)
        super(@key, true, true)
      end

      def measure(ctx : Context, constraints : Constraints) : Size
        fs = ctx.theme.font_size(@size)
        text = ctx.measure_text(@text, fs)
        pad_x = ctx.theme.metrics.spacing_md
        pad_y = ctx.theme.metrics.spacing_sm
        constraints.constrain(Size.new(text.width + pad_x * 2.0_f32,
          text.height + pad_y * 2.0_f32))
      end

      def arrange(ctx : Context, bounds : Rect) : Nil
        @bounds = bounds
      end

      def emit(b : UI::Builder, ctx : Context) : Nil
        b.node(@key, @bounds, paint: paint_token,
          a11y_role: A11y::Role::Tooltip, a11y_name: @text,
          a11y_focusable: false, a11y_enabled: true)
      end

      def paint(p : Painter, ctx : Context) : Nil
        radius = ctx.theme.metrics.radius_md
        p.fill_round_rect(@bounds, radius, ctx.theme.palette.surface_raised)
        p.stroke_round_rect(@bounds, radius, ctx.theme.palette.border,
          ctx.theme.metrics.border_width)
        fs = ctx.theme.font_size(@size)
        pad_x = ctx.theme.metrics.spacing_md
        pad_y = ctx.theme.metrics.spacing_sm
        p.text(@bounds.origin.x + pad_x,
          @bounds.origin.y + pad_y + fs,
          @text, ctx.theme.palette.foreground, fs)
      end

      def a11y_role : A11y::Role
        A11y::Role::Tooltip
      end

      def a11y_name : String
        @text
      end

      def paint_token : UInt32
        @size.value.to_u32
      end
    end
  end
end
