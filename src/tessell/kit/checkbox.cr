# Tessell::Kit::Checkbox — K2 基础组件
#
# 受控 checked/indeterminate；指针在框内按下并抬起或 Space 抬起时切换一次。
# 标签由组件绘制，根节点携带 CheckBox a11y 元数据，不重复曝光标签文本节点。

module Tessell
  module Kit
    class Checkbox < Component
      property checked : Bool
      property indeterminate : Bool
      property label : String
      property size : ControlSize
      property on_change : Proc(Bool, Nil)?
      getter hovered : Bool
      getter pressed : Bool

      def initialize(@key : UI::UiKey, @label : String,
                     @checked : Bool = false, @indeterminate : Bool = false,
                     @size : ControlSize = ControlSize::Medium,
                     enabled : Bool = true)
        super(@key, enabled)
        @hovered = false
        @pressed = false
        @on_change = nil
      end

      def measure(ctx : Context, constraints : Constraints) : Size
        box = box_size(ctx)
        fs = ctx.theme.font_size(@size)
        text = ctx.measure_text(@label, fs)
        w = box + ctx.theme.metrics.spacing_sm + text.width
        h = Math.max(box, ctx.line_height(fs))
        constraints.constrain(Size.new(w, h))
      end

      def arrange(ctx : Context, bounds : Rect) : Nil
        @bounds = bounds
      end

      def emit(b : UI::Builder, ctx : Context) : Nil
        b.node(@key, @bounds, paint: paint_token,
          a11y_role: A11y::Role::CheckBox, a11y_name: @label,
          a11y_value: value_text, a11y_focusable: focusable?,
          a11y_enabled: @enabled)
      end

      def paint(p : Painter, ctx : Context) : Nil
        return unless @visible
        box = box_size(ctx)
        box_rect = Rect.new(@bounds.origin.x,
          @bounds.origin.y + (@bounds.size.height - box) / 2.0_f32, box, box)
        radius = ctx.theme.metrics.radius_sm
        colors = ctx.theme.button_colors(Variant::Secondary, @size,
          InteractionState.new(hovered: @hovered, pressed: @pressed,
            focused: @focused, disabled: !@enabled))
        p.fill_round_rect(box_rect, radius, @checked ? ctx.theme.palette.accent : colors.background)
        p.stroke_round_rect(box_rect, radius, colors.border, ctx.theme.metrics.border_width)
        if @focused && @enabled
          p.stroke_round_rect(Geometry.inset(box_rect, 2.0_f32), radius,
            ctx.theme.palette.focus, ctx.theme.metrics.focus_ring_width)
        end

        mark_color = @checked ? ctx.theme.palette.accent_foreground : colors.foreground
        if @checked
          p.line(box_rect.origin.x + box * 0.22_f32, box_rect.origin.y + box * 0.52_f32,
            box_rect.origin.x + box * 0.42_f32, box_rect.origin.y + box * 0.72_f32,
            mark_color, 2.0_f32)
          p.line(box_rect.origin.x + box * 0.42_f32, box_rect.origin.y + box * 0.72_f32,
            box_rect.origin.x + box * 0.78_f32, box_rect.origin.y + box * 0.28_f32,
            mark_color, 2.0_f32)
        elsif @indeterminate
          p.line(box_rect.origin.x + box * 0.22_f32, box_rect.origin.y + box * 0.5_f32,
            box_rect.origin.x + box * 0.78_f32, box_rect.origin.y + box * 0.5_f32,
            mark_color, 2.0_f32)
        end

        fs = ctx.theme.font_size(@size)
        color = @enabled ? ctx.theme.palette.foreground : ctx.theme.palette.muted
        baseline = @bounds.origin.y + (@bounds.size.height + fs) / 2.0_f32 - fs * 0.1_f32
        p.text(box_rect.max_x + ctx.theme.metrics.spacing_sm, baseline, @label, color, fs)
      end

      def focusable? : Bool
        @visible && @enabled
      end

      def a11y_role : A11y::Role
        A11y::Role::CheckBox
      end

      def a11y_name : String
        @label
      end

      def a11y_value : String
        value_text
      end

      def handle(event : Event, ctx : Context) : Bool
        case event.kind
        when Event::Kind::PointerEnter
          @hovered = @enabled
          true
        when Event::Kind::PointerLeave
          @hovered = false
          @pressed = false
          true
        when Event::Kind::PointerDown
          return false unless @enabled
          if inside?(event.x, event.y)
            @pressed = true
            return true
          end
          false
        when Event::Kind::PointerUp
          was_pressed = @pressed
          @pressed = false
          toggle if was_pressed && @enabled && inside?(event.x, event.y)
          was_pressed
        when Event::Kind::PointerCancel
          was_pressed = @pressed
          @pressed = false
          was_pressed
        when Event::Kind::KeyDown
          @enabled && focusable? && event.key == Key::Space
        when Event::Kind::KeyUp
          if @enabled && @focused && event.key == Key::Space
            toggle
            true
          else
            false
          end
        when Event::Kind::Blur
          @pressed = false
          false
        else
          false
        end
      end

      def on_focus_changed(focused : Bool) : Nil
        @focused = focused
        @pressed = false unless focused
      end

      def paint_token : UInt32
        token = @size.value.to_u32
        token |= (1_u32 << 8) if @checked
        token |= (1_u32 << 9) if @indeterminate
        token |= (1_u32 << 10) if @hovered
        token |= (1_u32 << 11) if @pressed
        token |= (1_u32 << 12) if @focused
        token |= (1_u32 << 13) unless @enabled
        token
      end

      def value_text : String
        if @indeterminate
          "mixed"
        elsif @checked
          "checked"
        else
          "unchecked"
        end
      end

      private def toggle : Nil
        if @indeterminate
          @indeterminate = false
          @checked = true
        else
          @checked = !@checked
        end
        @on_change.try(&.call(@checked))
      end

      private def box_size(ctx : Context) : Float32
        Math.max(16.0_f32, ctx.theme.font_size(@size) + 2.0_f32)
      end

      private def inside?(x : Float32, y : Float32) : Bool
        @bounds.contains?(Point.new(x, y))
      end
    end
  end
end
