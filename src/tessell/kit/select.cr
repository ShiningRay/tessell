# Tessell::Kit::Select — 单选下拉（K3）
#
# 受控 selected_index；触发区与弹出列表分离。打开时通过 OverlayHost 打开
# 非模态 popover，关闭后焦点恢复到触发区。

module Tessell
  module Kit
    class Select < Component
      getter options : Array(String)
      property selected_index : Int32?
      property placeholder : String
      property label : String
      property highlighted : Int32
      property on_change : Proc(Int32, String, Nil)?
      getter open : Bool
      getter entry : OverlayEntry?
      getter hovered : Bool
      getter pressed : Bool

      def initialize(@key : UI::UiKey, @options : Array(String),
                     @selected_index : Int32? = nil,
                     @placeholder : String = "Select…",
                     @label : String = "",
                     enabled : Bool = true)
        super(@key, enabled)
        @highlighted = @selected_index || 0
        @on_change = nil
        @open = false
        @entry = nil
        @hovered = false
        @pressed = false
      end

      def measure(ctx : Context, constraints : Constraints) : Size
        fs = ctx.theme.font_size(ControlSize::Medium)
        text = ctx.measure_text(selected_text, fs)
        width = Math.max(160.0_f32, text.width + ctx.theme.padding_x(ControlSize::Medium) * 2.0_f32 + 20.0_f32)
        constraints.constrain(Size.new(width, ctx.theme.control_height(ControlSize::Medium)))
      end

      def arrange(ctx : Context, bounds : Rect) : Nil
        @bounds = bounds
      end

      def emit(b : UI::Builder, ctx : Context) : Nil
        b.node(@key, @bounds, paint: paint_token,
          a11y_role: A11y::Role::ComboBox, a11y_name: @label,
          a11y_value: selected_text, a11y_focusable: focusable?,
          a11y_enabled: @enabled)
      end

      def paint(p : Painter, ctx : Context) : Nil
        return unless @visible
        radius = ctx.theme.metrics.radius_md
        bg = @enabled ? ctx.theme.palette.surface : ctx.theme.palette.surface_raised
        border = @focused ? ctx.theme.palette.focus : ctx.theme.palette.border
        p.fill_round_rect(@bounds, radius, bg)
        p.stroke_round_rect(@bounds, radius, border,
          @focused ? ctx.theme.metrics.focus_ring_width : ctx.theme.metrics.border_width)
        fs = ctx.theme.font_size(ControlSize::Medium)
        color = if @selected_index
                  @enabled ? ctx.theme.palette.foreground : ctx.theme.palette.muted
                else
                  ctx.theme.palette.muted
                end
        p.text(@bounds.origin.x + ctx.theme.padding_x(ControlSize::Medium),
          TextDrawing.middle_baseline(@bounds, ctx.text_metrics(fs)),
          selected_text, color, fs)
        cx = @bounds.max_x - 16.0_f32
        cy = @bounds.origin.y + @bounds.size.height / 2.0_f32
        p.line(cx - 4.0_f32, cy - 2.0_f32, cx, cy + 2.0_f32, color, 1.5_f32)
        p.line(cx, cy + 2.0_f32, cx + 4.0_f32, cy - 2.0_f32, color, 1.5_f32)
      end

      def focusable? : Bool
        @visible && @enabled
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
            toggle(ctx)
            return true
          end
          false
        when Event::Kind::PointerUp
          was = @pressed
          @pressed = false
          was
        when Event::Kind::KeyDown
          return false unless @enabled && @focused
          case event.key
          when Key::Down, Key::Space, Key::Enter
            open_popup(ctx) unless @open
            true
          when Key::Escape
            close_popup(ctx)
          else
            false
          end
        else
          false
        end
      end

      def toggle(ctx : Context) : Nil
        if @open
          close_popup(ctx)
        else
          open_popup(ctx)
        end
      end

      def open_popup(ctx : Context) : Nil
        return if @open
        host = ctx.overlay_host
        return unless host
        popup = SelectPopup.new(@key.child(9_000_u64), @options, @selected_index,
          @highlighted)
        popup.on_highlight = ->(index : Int32) { @highlighted = index; nil }
        popup.on_select = ->(index : Int32) {
          select_index(index)
          nil
        }
        popup.on_close = -> {
          close_popup(ctx)
          nil
        }
        entry = OverlayEntry.new(popup, OverlayKind::Popover, owner: self,
          anchor: @bounds, preferred: OverlaySide::Below, modal: false,
          dismiss_on_outside: true, dismiss_on_escape: true, gap: 4.0_f32)
        entry.on_close = -> {
          @open = false
          @entry = nil
          nil
        }
        @open = true
        @entry = entry
        host.open(entry)
      end

      def close_popup(ctx : Context) : Bool
        entry = @entry
        return false unless entry
        @entry = nil
        @open = false
        ctx.overlay_host.try(&.close(entry)) || false
      end

      def select_index(index : Int32) : Nil
        return if index < 0 || index >= @options.size
        @selected_index = index
        @highlighted = index
        @on_change.try(&.call(index, @options[index]))
      end

      def selected_text : String
        if index = @selected_index
          return @options[index]? || @placeholder
        end
        @placeholder
      end

      def on_focus_changed(focused : Bool) : Nil
        super
      end

      def paint_token : UInt32
        token = @selected_index.try(&.to_u32) || 0_u32
        token |= (1_u32 << 16) if @focused
        token |= (1_u32 << 17) if @hovered
        token |= (1_u32 << 18) if @open
        token |= (1_u32 << 19) unless @enabled
        token
      end

      def a11y_role : A11y::Role
        A11y::Role::ComboBox
      end

      def a11y_name : String
        @label
      end

      def a11y_value : String
        selected_text
      end

      private def inside?(x : Float32, y : Float32) : Bool
        @bounds.contains?(Point.new(x, y))
      end
    end

    class SelectPopup < Component
      getter options : Array(String)
      property highlighted : Int32
      property selected_index : Int32?
      property on_select : Proc(Int32, Nil)?
      property on_highlight : Proc(Int32, Nil)?
      property on_close : Proc(Nil)?

      @pressed_index : Int32?
      @row_height : Float32

      def initialize(@key : UI::UiKey, @options : Array(String),
                     @selected_index : Int32? = nil, @highlighted : Int32 = 0)
        super(@key, true, true)
        @on_select = nil
        @on_highlight = nil
        @on_close = nil
        @pressed_index = nil
        @row_height = 28.0_f32
      end

      def measure(ctx : Context, constraints : Constraints) : Size
        fs = ctx.theme.font_size(ControlSize::Small)
        max_text = 0.0_f32
        @options.each do |option|
          max_text = Math.max(max_text, ctx.measure_text(option, fs).width)
        end
        padding = ctx.theme.metrics.spacing_sm
        width = max_text + padding * 4.0_f32 + 8.0_f32
        width = Math.max(160.0_f32, width)
        @row_height = ctx.theme.control_height(ControlSize::Small)
        height = @options.size * @row_height + padding * 2.0_f32
        constraints.constrain(Size.new(width, height))
      end

      def arrange(ctx : Context, bounds : Rect) : Nil
        @bounds = bounds
        @row_height = ctx.theme.control_height(ControlSize::Small)
      end

      def emit(b : UI::Builder, ctx : Context) : Nil
        b.group(@key, @bounds, paint: paint_token,
          a11y_role: A11y::Role::ListBox, a11y_name: "Options",
          a11y_focusable: true, a11y_enabled: true) do
          @options.each_with_index do |option, index|
            b.text(@key.child((index + 1).to_u64), option, row_rect(index),
              paint: (index == @highlighted ? 1_u32 : 0_u32),
              a11y_role: A11y::Role::Option, a11y_name: option,
              a11y_value: index == @selected_index ? "selected" : "",
              a11y_focusable: false, a11y_enabled: true)
          end
        end
      end

      def paint(p : Painter, ctx : Context) : Nil
        radius = ctx.theme.metrics.radius_md
        p.fill_round_rect(@bounds, radius, ctx.theme.palette.surface)
        p.stroke_round_rect(@bounds, radius, ctx.theme.palette.border,
          ctx.theme.metrics.border_width)
        fs = ctx.theme.font_size(ControlSize::Small)
        m = ctx.text_metrics(fs)
        @options.each_with_index do |option, index|
          rect = row_rect(index)
          if index == @highlighted
            p.fill_rect(rect, ctx.theme.palette.selection)
          end
          color = index == @selected_index ? ctx.theme.palette.accent : ctx.theme.palette.foreground
          p.text(rect.origin.x + ctx.theme.metrics.spacing_md,
            TextDrawing.middle_baseline(rect, m),
            option, color, fs)
        end
      end

      def focusable? : Bool
        true
      end

      def handle(event : Event, ctx : Context) : Bool
        case event.kind
        when Event::Kind::PointerMove
          index = index_at(event.x, event.y)
          if index && index != @highlighted
            @highlighted = index
            @on_highlight.try(&.call(index))
          end
          true
        when Event::Kind::PointerDown
          @pressed_index = index_at(event.x, event.y)
          true
        when Event::Kind::PointerUp
          index = index_at(event.x, event.y)
          if index && index == @pressed_index
            choose(index)
          end
          @pressed_index = nil
          true
        when Event::Kind::KeyDown
          case event.key
          when Key::Down
            move_highlight(1)
            true
          when Key::Up
            move_highlight(-1)
            true
          when Key::Home
            set_highlight(0)
            true
          when Key::End
            set_highlight(@options.size - 1)
            true
          when Key::Enter, Key::Space
            choose(@highlighted)
            true
          when Key::Escape
            @on_close.try(&.call)
            true
          else
            false
          end
        else
          false
        end
      end

      def row_rect(index : Int32) : Rect
        padding = 4.0_f32
        Rect.new(@bounds.origin.x + padding,
          @bounds.origin.y + padding + index * @row_height,
          @bounds.size.width - padding * 2.0_f32, @row_height)
      end

      def paint_token : UInt32
        @highlighted.to_u32 | ((@selected_index.try(&.to_u32) || 0_u32) << 12)
      end

      def a11y_role : A11y::Role
        A11y::Role::ListBox
      end

      def a11y_name : String
        "Options"
      end

      private def choose(index : Int32) : Nil
        return if index < 0 || index >= @options.size
        @selected_index = index
        @on_select.try(&.call(index))
        @on_close.try(&.call)
      end

      private def move_highlight(delta : Int32) : Nil
        return if @options.empty?
        set_highlight((@highlighted + delta).clamp(0, @options.size - 1))
      end

      private def set_highlight(index : Int32) : Nil
        return if @options.empty?
        @highlighted = index.clamp(0, @options.size - 1)
        @on_highlight.try(&.call(@highlighted))
      end

      private def index_at(x : Float32, y : Float32) : Int32?
        return nil unless @bounds.contains?(Point.new(x, y))
        relative = y - @bounds.origin.y - 4.0_f32
        index = (relative / @row_height).floor.to_i
        index >= 0 && index < @options.size ? index : nil
      end
    end
  end
end
