# Tessell::Kit::Button — K0 纵向原型
#
# 行为：受控按压态；指针按下后在同一按钮内抬起 → 一次回调；
# Space/Enter 按下-抬起 → 一次回调；disabled 不聚焦、不回调。
# 绘制：背景/边框/焦点环/居中文本，全部经 Painter。

module Tessell
  module Kit
    class Button < Component
      property label : String
      property variant : Variant
      property size : ControlSize
      property on_click : Proc(Nil)?
      # 字重（issue #29）：与 Kit::Text 同口径，font_id 经 Context 解析。
      property weight : FontWeight
      getter hovered : Bool
      getter pressed : Bool

      def initialize(@key : UI::UiKey, @label : String,
                     @variant : Variant = Variant::Secondary,
                     @size : ControlSize = ControlSize::Medium,
                     enabled : Bool = true,
                     @weight : FontWeight = FontWeight::Normal)
        super(@key, enabled)
        @hovered = false
        @pressed = false
        @on_click = nil
      end

      def measure(ctx : Context, constraints : Constraints) : Size
        fs = ctx.theme.font_size(@size)
        text = ctx.measure_text(@label, fs, ctx.font_id_for(@label, @weight))
        w = text.width + ctx.theme.padding_x(@size) * 2.0_f32
        h = ctx.theme.control_height(@size)
        constraints.constrain(Size.new(w, h))
      end

      def emit(b : UI::Builder, ctx : Context) : Nil
        # 按用户所见驱动（issue #35）：不可见即不进命中树（与 paint 同口径）
        return unless @visible
        b.text(@key, @label, @bounds, paint: paint_token,
          a11y_role: A11y::Role::Button, a11y_name: @label,
          a11y_focusable: focusable?, a11y_enabled: @enabled)
      end

      def paint(p : Painter, ctx : Context) : Nil
        return unless @visible
        fs = ctx.theme.font_size(@size)
        colors = resolve_colors(ctx)
        radius = ctx.theme.radius(@size)
        # 可覆写切面（issue #66）：子类改单个切面，其余行为（焦点环/
        # disabled 分支/绘制顺序）由骨架保证
        draw_background(p, ctx, colors, radius)
        draw_border(p, ctx, colors, radius)
        draw_focus_ring(p, ctx, colors, radius)
        draw_content(p, ctx, colors, fs)
      end

      # ---- 可覆写切面（issue #66 契约，见 docs/kit/component-contract.md）----
      # emit 仍由内置实现发自身 key；hook 只改绘制与行为。
      protected def resolve_colors(ctx : Context) : ButtonColors
        ctx.theme.button_colors(@variant, @size, interaction_state)
      end

      protected def interaction_state : InteractionState
        InteractionState.new(
          hovered: @hovered,
          pressed: @pressed,
          focused: @focused,
          disabled: !@enabled
        )
      end

      protected def draw_background(p : Painter, ctx : Context,
                                    colors : ButtonColors, radius : Float32) : Nil
        if alpha(colors.background) > 0
          p.fill_round_rect(@bounds, radius, colors.background)
        end
      end

      protected def draw_border(p : Painter, ctx : Context,
                                colors : ButtonColors, radius : Float32) : Nil
        if alpha(colors.border) > 0
          p.stroke_round_rect(@bounds, radius, colors.border,
            ctx.theme.metrics.border_width)
        end
      end

      # 焦点环由骨架条件调用（focused && enabled），disabled 分支不丢
      protected def draw_focus_ring(p : Painter, ctx : Context,
                                    colors : ButtonColors, radius : Float32) : Nil
        if @focused && @enabled
          focus_rect = Geometry.inset(@bounds, ctx.theme.metrics.focus_ring_width / 2.0_f32)
          p.stroke_round_rect(focus_rect, radius, colors.focus,
            ctx.theme.metrics.focus_ring_width)
        end
      end

      protected def draw_content(p : Painter, ctx : Context,
                                 colors : ButtonColors, fs : Float32) : Nil
        text_size = ctx.measure_text(@label, fs, ctx.font_id_for(@label, @weight))
        tx = @bounds.origin.x + (@bounds.size.width - text_size.width) / 2.0_f32
        # 垂直居中走 text_metrics 口径（issue #19），不用 fs*0.1 经验系数
        baseline = TextDrawing.middle_baseline(@bounds, ctx.text_metrics(fs))
        p.text(tx, baseline, @label, colors.foreground, fs,
          ctx.font_id_for(@label, @weight))
      end

      def focusable? : Bool
        @visible && @enabled
      end

      def a11y_role : A11y::Role
        A11y::Role::Button
      end

      def a11y_name : String
        @label
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
          if was_pressed && @enabled && inside?(event.x, event.y)
            activate
          end
          was_pressed
        when Event::Kind::PointerCancel
          was_pressed = @pressed
          @pressed = false
          was_pressed
        when Event::Kind::KeyDown
          return false unless @enabled && focusable?
          if event.key == Key::Space || event.key == Key::Enter
            @pressed = true
            true
          else
            false
          end
        when Event::Kind::KeyUp
          if @pressed && (event.key == Key::Space || event.key == Key::Enter)
            @pressed = false
            activate if @enabled
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
        token = 0_u32
        token |= @variant.value.to_u32
        token |= (@size.value.to_u32 << 4)
        token |= (1_u32 << 8) if @hovered
        token |= (1_u32 << 9) if @pressed
        token |= (1_u32 << 10) if @focused
        token |= (1_u32 << 11) unless @enabled
        token
      end

      # 命中判定与激活（issue #66 契约：子类可改命中区域/激活行为，
      # handle 骨架保证状态机不变）
      protected def inside?(x : Float32, y : Float32) : Bool
        @bounds.contains?(Point.new(x, y))
      end

      protected def activate : Nil
        @on_click.try(&.call)
      end

      private def alpha(color : UInt32) : UInt8
        (color & 0xff).to_u8
      end
    end
  end
end
