# Tessell::Kit::ScrollView — 单子组件滚动容器（K2）
#
# 垂直/水平滚动、裁切、滚动条、滚轮与键盘。子组件仍按绝对 bounds 绘制，
# ScrollView 通过 clip_bounds 限制命中与绘制区域。

module Tessell
  module Kit
    class ScrollView < Component
      getter child : Component
      property scroll_x : Float32
      property scroll_y : Float32
      getter content_size : Size
      property horizontal : Bool
      property vertical : Bool
      property scrollbar_width : Float32
      property wheel_step : Float32
      property preferred_height : Float32

      def initialize(@key : UI::UiKey, @child : Component,
                     @horizontal : Bool = false, @vertical : Bool = true,
                     enabled : Bool = true)
        super(@key, enabled)
        @scroll_x = 0.0_f32
        @scroll_y = 0.0_f32
        @content_size = Size.new
        @scrollbar_width = 10.0_f32
        @wheel_step = 1.0_f32
        @preferred_height = 240.0_f32
        attach(@child)
      end

      def measure(ctx : Context, constraints : Constraints) : Size
        w = constraints.max_width
        h = constraints.max_height
        w = 160.0_f32 if w.infinite?
        h = @preferred_height if h.infinite?
        h = Math.min(h, @preferred_height) unless h.infinite?
        constraints.constrain(Size.new(w, h))
      end

      def arrange(ctx : Context, bounds : Rect) : Nil
        @bounds = bounds
        max_w = @horizontal ? Float32::INFINITY : bounds.size.width
        max_h = @vertical ? Float32::INFINITY : bounds.size.height
        child_size = @child.measure(ctx, Constraints.new(0.0_f32, max_w, 0.0_f32, max_h))
        content_w = @horizontal ? Math.max(child_size.width, bounds.size.width) : bounds.size.width
        content_h = @vertical ? Math.max(child_size.height, bounds.size.height) : bounds.size.height
        @content_size = Size.new(content_w, content_h)
        clamp_scroll
        child_bounds = Rect.new(
          bounds.origin.x - @scroll_x,
          bounds.origin.y - @scroll_y,
          content_w,
          content_h
        )
        @child.arrange(ctx, child_bounds)
      end

      def emit(b : UI::Builder, ctx : Context) : Nil
        b.group(@key, @bounds, paint: paint_token,
          a11y_role: A11y::Role::ScrollView, a11y_name: a11y_name,
          a11y_focusable: focusable?, a11y_enabled: @enabled) do
          @child.emit(b, ctx)
        end
      end

      def paint(p : Painter, ctx : Context) : Nil
        return unless @visible
        p.push_clip(@bounds)
        @child.paint(p, ctx)
        paint_scrollbars(p, ctx)
        p.pop_clip
      end

      def clip_bounds : Rect?
        @bounds
      end

      def focusable? : Bool
        @visible && @enabled && (can_scroll_y? || can_scroll_x?)
      end

      def a11y_role : A11y::Role
        A11y::Role::ScrollView
      end

      def handle(event : Event, ctx : Context) : Bool
        case event.kind
        when Event::Kind::Wheel
          return false unless @enabled
          delta = if event.wheel_dy != 0.0_f32
                    event.wheel_dy
                  else
                    event.wheel_dx
                  end
          return false if delta == 0.0_f32
          if @vertical && can_scroll_y?
            scroll_by(-delta * @wheel_step)
            true
          elsif @horizontal && can_scroll_x?
            scroll_by_x(-delta * @wheel_step)
            true
          else
            false
          end
        when Event::Kind::KeyDown
          return false unless @enabled && @focused
          handle_key(event.key)
        else
          false
        end
      end

      def scroll_by(dy : Float32) : Float32
        scroll_to(@scroll_y + dy)
      end

      def scroll_by_x(dx : Float32) : Float32
        scroll_to_x(@scroll_x + dx)
      end

      def scroll_to(y : Float32) : Float32
        @scroll_y = y.clamp(0.0_f32, max_scroll_y)
        @scroll_y
      end

      def scroll_to_x(x : Float32) : Float32
        @scroll_x = x.clamp(0.0_f32, max_scroll_x)
        @scroll_x
      end

      def max_scroll_y : Float32
        value = @content_size.height - @bounds.size.height
        value < 0.0_f32 ? 0.0_f32 : value
      end

      def max_scroll_x : Float32
        value = @content_size.width - @bounds.size.width
        value < 0.0_f32 ? 0.0_f32 : value
      end

      def can_scroll_y? : Bool
        @vertical && max_scroll_y > 0.0_f32
      end

      def can_scroll_x? : Bool
        @horizontal && max_scroll_x > 0.0_f32
      end

      def collect_components(sink : Array(Component)) : Nil
        sink << self
        @child.collect_components(sink)
      end

      def paint_token : UInt32
        token = @scroll_y.to_u32
        token ^= (@scroll_x.to_u32 << 7)
        token ^= (@content_size.height.to_u32 << 13)
        token
      end

      private def clamp_scroll : Nil
        @scroll_y = @scroll_y.clamp(0.0_f32, max_scroll_y)
        @scroll_x = @scroll_x.clamp(0.0_f32, max_scroll_x)
      end

      private def handle_key(key : Key?) : Bool
        case key
        when Key::Down
          scroll_by(24.0_f32)
          true
        when Key::Up
          scroll_by(-24.0_f32)
          true
        when Key::PageDown
          scroll_by(@bounds.size.height * 0.9_f32)
          true
        when Key::PageUp
          scroll_by(-@bounds.size.height * 0.9_f32)
          true
        when Key::Home
          scroll_to(0.0_f32)
          true
        when Key::End
          scroll_to(max_scroll_y)
          true
        else
          false
        end
      end

      private def paint_scrollbars(p : Painter, ctx : Context) : Nil
        if @vertical && max_scroll_y > 0.0_f32
          track_w = @scrollbar_width
          track_x = @bounds.max_x - track_w
          track = Rect.new(track_x, @bounds.origin.y, track_w, @bounds.size.height)
          p.fill_rect(track, ctx.theme.palette.surface_raised)
          ratio = @bounds.size.height / @content_size.height
          thumb_h = Math.max(20.0_f32, @bounds.size.height * ratio)
          travel = @bounds.size.height - thumb_h
          thumb_y = @bounds.origin.y + (max_scroll_y > 0.0_f32 ? travel * (@scroll_y / max_scroll_y) : 0.0_f32)
          thumb = Rect.new(track_x + 2.0_f32, thumb_y, track_w - 4.0_f32, thumb_h)
          p.fill_round_rect(thumb, 3.0_f32, ctx.theme.palette.muted)
        end
        if @horizontal && max_scroll_x > 0.0_f32
          track_h = @scrollbar_width
          track_y = @bounds.max_y - track_h
          track = Rect.new(@bounds.origin.x, track_y, @bounds.size.width, track_h)
          p.fill_rect(track, ctx.theme.palette.surface_raised)
          ratio = @bounds.size.width / @content_size.width
          thumb_w = Math.max(20.0_f32, @bounds.size.width * ratio)
          travel = @bounds.size.width - thumb_w
          thumb_x = @bounds.origin.x + (max_scroll_x > 0.0_f32 ? travel * (@scroll_x / max_scroll_x) : 0.0_f32)
          thumb = Rect.new(thumb_x, track_y + 2.0_f32, thumb_w, track_h - 4.0_f32)
          p.fill_round_rect(thumb, 3.0_f32, ctx.theme.palette.muted)
        end
      end
    end
  end
end
