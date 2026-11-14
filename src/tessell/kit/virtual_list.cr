# Tessell::Kit::VirtualList — 现有 Widgets::VirtualList 的 Kit 适配（K2）
#
# 不复制虚拟化算法：可见范围、回收、滚动钳制全部由核心 VirtualList 负责。
# Kit 只把可见行声明为稳定 keyed 文本节点，并报告逻辑行数给 a11y。

module Tessell
  module Kit
    class VirtualList < Component
      getter row_count : Int32
      getter row_height : Int32
      getter label_for : Proc(Int32, String)
      getter list : Widgets::VirtualList
      property preferred_height : Float32

      def initialize(@key : UI::UiKey, @row_count : Int32, @row_height : Int32,
                     @label_for : Proc(Int32, String),
                     name : String = "", enabled : Bool = true)
        super(@key, enabled)
        @name = name
        @list = Widgets::VirtualList.new(@row_count, @row_height, 1,
          ->(index : Int32) { nil }, 1)
        @preferred_height = 240.0_f32
      end

      def measure(ctx : Context, constraints : Constraints) : Size
        w = constraints.max_width.infinite? ? 240.0_f32 : constraints.max_width
        h = constraints.max_height.infinite? ? @preferred_height : Math.min(constraints.max_height, @preferred_height)
        constraints.constrain(Size.new(w, h))
      end

      def arrange(ctx : Context, bounds : Rect) : Nil
        @bounds = bounds
        @list.resize_viewport(bounds.size.width.to_i, bounds.size.height.to_i)
        @list.prepare_visible
      end

      def emit(b : UI::Builder, ctx : Context) : Nil
        b.group(@key, @bounds, paint: paint_token,
          a11y_role: A11y::Role::List, a11y_name: @name,
          a11y_focusable: focusable?, a11y_enabled: @enabled) do
          first = @list.visible_first
          last = @list.visible_last
          if last >= first
            i = first
            while i <= last
              row_rect = row_bounds(i)
              b.text(@key.child((i + 1).to_u64), @label_for.call(i), row_rect,
                paint: i.to_u32,
                a11y_role: A11y::Role::ListItem, a11y_name: @label_for.call(i),
                a11y_focusable: false, a11y_enabled: true)
              i += 1
            end
          end
        end
      end

      def paint(p : Painter, ctx : Context) : Nil
        return unless @visible
        p.push_clip(@bounds)
        first = @list.visible_first
        last = @list.visible_last
        fs = ctx.theme.font_size(ControlSize::Medium)
        m = ctx.text_metrics(fs)
        if last >= first
          i = first
          while i <= last
            rect = row_bounds(i)
            p.text(rect.origin.x + 8.0_f32,
              TextDrawing.middle_baseline(rect, m),
              @label_for.call(i), ctx.theme.palette.foreground, fs)
            i += 1
          end
        end
        paint_scrollbar(p, ctx)
        p.pop_clip
      end

      def clip_bounds : Rect?
        @bounds
      end

      def focusable? : Bool
        @visible && @enabled && @row_count > 0
      end

      def a11y_role : A11y::Role
        A11y::Role::List
      end

      def a11y_name : String
        @name
      end

      def handle(event : Event, ctx : Context) : Bool
        case event.kind
        when Event::Kind::Wheel
          return false unless @enabled
          delta = event.wheel_dy != 0.0_f32 ? event.wheel_dy : event.wheel_dx
          return false if delta == 0.0_f32
          @list.scroll_by(-delta.to_i)
          true
        when Event::Kind::KeyDown
          return false unless @enabled && @focused
          case event.key
          when Key::Down     then @list.scroll_by(@row_height); true
          when Key::Up       then @list.scroll_by(-@row_height); true
          when Key::PageDown then @list.scroll_by(@bounds.size.height.to_i); true
          when Key::PageUp   then @list.scroll_by(-@bounds.size.height.to_i); true
          when Key::Home     then @list.scroll_to(0); true
          when Key::End      then @list.scroll_to(@list.total_height); true
          else                    false
          end
        else
          false
        end
      end

      def collect_components(sink : Array(Component)) : Nil
        sink << self
      end

      def a11y_children_count : Int32?
        @row_count
      end

      def a11y_scroll_offset : Int32
        @list.scroll_y
      end

      def paint_token : UInt32
        token = @list.scroll_y.to_u32
        token ^= (@list.visible_first.to_u32 << 12)
        token ^= (@list.visible_last.to_u32 << 20)
        token
      end

      def row_bounds(index : Int32) : Rect
        Rect.new(@bounds.origin.x, @bounds.origin.y + @list.node_offset(index).to_f32,
          @bounds.size.width, @row_height.to_f32)
      end

      private def paint_scrollbar(p : Painter, ctx : Context) : Nil
        total = @list.total_height
        return if total <= @bounds.size.height
        track_w = 10.0_f32
        track_x = @bounds.max_x - track_w
        p.fill_rect(Rect.new(track_x, @bounds.origin.y, track_w, @bounds.size.height),
          ctx.theme.palette.surface_raised)
        ratio = @bounds.size.height / total.to_f32
        thumb_h = Math.max(20.0_f32, @bounds.size.height * ratio)
        travel = @bounds.size.height - thumb_h
        max_scroll = (total - @bounds.size.height).to_f32
        thumb_y = @bounds.origin.y + (max_scroll > 0.0_f32 ? travel * (@list.scroll_y / max_scroll) : 0.0_f32)
        p.fill_round_rect(Rect.new(track_x + 2.0_f32, thumb_y, track_w - 4.0_f32, thumb_h),
          3.0_f32, ctx.theme.palette.muted)
      end
    end
  end
end
