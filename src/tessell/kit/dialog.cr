# Tessell::Kit::Dialog — 模态对话框内容（K3）
#
# 只构建标题/内容/动作区；模态屏障、焦点圈定、Escape 与关闭由 Root/OverlayHost 管。
# 对话框本身不抢焦点，焦点落在第一个可聚焦子组件。

module Tessell
  module Kit
    class Dialog < Component
      getter title : String
      getter content : Component
      getter actions : Array(Button)
      property on_close : Proc(Nil)?
      property width : Float32

      @actions_row : Row

      def initialize(@key : UI::UiKey, @title : String, @content : Component,
                     @actions : Array(Button) = [] of Button,
                     @width : Float32 = 420.0_f32)
        super(@key, true, true)
        @on_close = nil
        @actions_row = Row.new(@key.child(2_u64), Insets.new, 8.0_f32,
          Alignment::End)
        @actions.each { |button| @actions_row.add(button) }
        attach(@content)
      end

      def measure(ctx : Context, constraints : Constraints) : Size
        pad = ctx.theme.metrics.spacing_lg
        inner_w = @width - pad * 2.0_f32
        title_fs = ctx.theme.font_size(ControlSize::Large)
        title_h = ctx.line_height(title_fs)
        content_size = @content.measure(ctx, Constraints.new(0.0_f32, inner_w,
          0.0_f32, Float32::INFINITY))
        actions_size = @actions_row.measure(ctx, Constraints.new(0.0_f32, inner_w,
          0.0_f32, Float32::INFINITY))
        gap = ctx.theme.metrics.spacing_md
        height = pad * 2.0_f32 + title_h + gap + content_size.height +
                 (actions_size.height > 0.0_f32 ? gap + actions_size.height : 0.0_f32)
        constraints.constrain(Size.new(@width, height))
      end

      def arrange(ctx : Context, bounds : Rect) : Nil
        @bounds = bounds
        pad = ctx.theme.metrics.spacing_lg
        inner = Geometry.inset(bounds, pad)
        title_fs = ctx.theme.font_size(ControlSize::Large)
        title_h = ctx.line_height(title_fs)
        gap = ctx.theme.metrics.spacing_md
        actions_size = @actions_row.measure(ctx, Constraints.new(0.0_f32, inner.size.width,
          0.0_f32, Float32::INFINITY))
        actions_h = actions_size.height
        content_top = inner.origin.y + title_h + gap
        content_bottom = inner.max_y - (actions_h > 0.0_f32 ? actions_h + gap : 0.0_f32)
        @content.arrange(ctx, Rect.new(inner.origin.x, content_top,
          inner.size.width, Math.max(0.0_f32, content_bottom - content_top)))
        if actions_h > 0.0_f32
          @actions_row.arrange(ctx, Rect.new(inner.origin.x, inner.max_y - actions_h,
            inner.size.width, actions_h))
        end
      end

      def emit(b : UI::Builder, ctx : Context) : Nil
        b.group(@key, @bounds, paint: paint_token,
          a11y_role: A11y::Role::Dialog, a11y_name: @title,
          a11y_focusable: false, a11y_enabled: @enabled) do
          @content.emit(b, ctx)
          @actions_row.emit(b, ctx) if @actions.size > 0
        end
      end

      def paint(p : Painter, ctx : Context) : Nil
        radius = ctx.theme.metrics.radius_lg
        p.fill_round_rect(@bounds, radius, ctx.theme.palette.surface)
        p.stroke_round_rect(@bounds, radius, ctx.theme.palette.border,
          ctx.theme.metrics.border_width)
        pad = ctx.theme.metrics.spacing_lg
        fs = ctx.theme.font_size(ControlSize::Large)
        p.text(@bounds.origin.x + pad, @bounds.origin.y + pad + fs,
          @title, ctx.theme.palette.foreground, fs)
        @content.paint(p, ctx)
        @actions_row.paint(p, ctx) if @actions.size > 0
      end

      def collect_components(sink : Array(Component)) : Nil
        sink << self
        @content.collect_components(sink)
        @actions_row.collect_components(sink)
      end

      def a11y_role : A11y::Role
        A11y::Role::Dialog
      end

      def a11y_name : String
        @title
      end

      def paint_token : UInt32
        @width.to_u32
      end
    end
  end
end
