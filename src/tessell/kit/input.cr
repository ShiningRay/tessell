# Tessell::Kit::Input — 单行文本输入（K4）
#
# 受控/非受控边界：应用读取 input.text；用户编辑会调用 on_change。
# 光标/选区按 grapheme cluster 移动与删除；preedit 只预览，commit 后写入文档。
# 平台 IME 组合事件尚未接入 Root；Input 提供 set_preedit/commit_preedit 接口。

require "./text_editing"

module Tessell
  module Kit
    class Input < Component
      getter editing : TextEditing
      property placeholder : String
      property label : String
      property error_text : String
      property invalid : Bool
      property read_only : Bool
      property size : ControlSize
      property on_change : Proc(String, Nil)?
      property on_submit : Proc(String, Nil)?
      property clipboard : Clipboard
      getter hovered : Bool
      getter pressed : Bool
      getter scroll_x : Float32

      def initialize(@key : UI::UiKey, text : String = "",
                     @placeholder : String = "", @label : String = "",
                     @size : ControlSize = ControlSize::Medium,
                     @read_only : Bool = false, @invalid : Bool = false,
                     enabled : Bool = true)
        super(@key, enabled)
        @editing = TextEditing.new(text)
        @error_text = ""
        @on_change = nil
        @on_submit = nil
        @clipboard = MemoryClipboard.new
        @hovered = false
        @pressed = false
        @scroll_x = 0.0_f32
      end

      def text : String
        @editing.text
      end

      def set_text(value : String) : Nil
        @editing.set_text(value)
        @scroll_x = 0.0_f32
      end

      def measure(ctx : Context, constraints : Constraints) : Size
        width = constraints.max_width.infinite? ? 240.0_f32 : constraints.max_width
        height = label_height(ctx) + ctx.theme.control_height(@size) + error_height(ctx)
        constraints.constrain(Size.new(width, height))
      end

      def arrange(ctx : Context, bounds : Rect) : Nil
        @bounds = bounds
        ensure_caret_visible(ctx)
      end

      def emit(b : UI::Builder, ctx : Context) : Nil
        b.node(@key, @bounds, paint: paint_token,
          a11y_role: A11y::Role::TextField, a11y_name: @label,
          a11y_value: @editing.text, a11y_focusable: focusable?,
          a11y_enabled: @enabled)
      end

      def paint(p : Painter, ctx : Context) : Nil
        return unless @visible
        field = field_rect(ctx)
        label_fs = ctx.theme.font_size(ControlSize::Small)
        if !@label.empty?
          p.text(@bounds.origin.x, @bounds.origin.y + label_fs,
            @label, ctx.theme.palette.muted, label_fs)
        end

        radius = ctx.theme.metrics.radius_md
        bg = @enabled ? ctx.theme.palette.surface : ctx.theme.palette.surface_raised
        border = if @invalid
                   ctx.theme.palette.danger
                 elsif @focused
                   ctx.theme.palette.focus
                 else
                   ctx.theme.palette.border
                 end
        p.fill_round_rect(field, radius, bg)
        p.stroke_round_rect(field, radius, border,
          @focused || @invalid ? ctx.theme.metrics.focus_ring_width : ctx.theme.metrics.border_width)

        area = text_area(ctx)
        fs = ctx.theme.font_size(@size)
        p.push_clip(area)
        paint_selection(p, ctx, area, fs)
        text_x = area.origin.x - @scroll_x
        baseline = field.origin.y + (field.size.height + fs) / 2.0_f32 - fs * 0.1_f32
        if @editing.text.empty? && !@placeholder.empty?
          p.text(text_x, baseline, @placeholder, ctx.theme.palette.muted, fs)
        else
          p.text(text_x, baseline, @editing.text, ctx.theme.palette.foreground, fs)
        end
        paint_preedit(p, ctx, area, fs)
        if @focused && @enabled
          caret_x = text_x + ctx.measure_text(prefix, fs).width
          p.line(caret_x, field.origin.y + 4.0_f32,
            caret_x, field.max_y - 4.0_f32, ctx.theme.palette.foreground, 1.0_f32)
        end
        p.pop_clip

        if @invalid && !@error_text.empty?
          err_fs = ctx.theme.font_size(ControlSize::Small)
          p.text(@bounds.origin.x, field.max_y + ctx.theme.metrics.spacing_xs + err_fs,
            @error_text, ctx.theme.palette.danger, err_fs)
        end
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
          false
        when Event::Kind::PointerDown
          return false unless @enabled
          if field_rect(ctx).contains?(Point.new(event.x, event.y))
            @editing.set_cursor(caret_index_at(ctx, event.x))
            @pressed = true
            true
          else
            false
          end
        when Event::Kind::PointerMove
          if @pressed
            @editing.set_cursor(caret_index_at(ctx, event.x), extending: true)
            ensure_caret_visible(ctx)
            true
          else
            false
          end
        when Event::Kind::PointerUp
          was = @pressed
          @pressed = false
          was
        when Event::Kind::KeyDown
          return false unless @enabled
          handle_key_down(event, ctx)
        when Event::Kind::TextInput
          return false unless @enabled
          if !@read_only && (value = event.text)
            changed = @editing.insert(value)
            notify_change if changed
            true
          else
            false
          end
        when Event::Kind::Blur
          @pressed = false
          if !@read_only && @editing.preedit?
            changed = @editing.commit_preedit
            notify_change if changed
          end
          false
        else
          false
        end
      end

      def on_focus_changed(focused : Bool) : Nil
        @focused = focused
        @pressed = false unless focused
      end

      def set_preedit(value : String) : Nil
        @editing.set_preedit(value) unless @read_only
      end

      def commit_preedit : Bool
        return false if @read_only
        changed = @editing.commit_preedit
        notify_change if changed
        changed
      end

      def caret_index_at(ctx : Context, x : Float32) : Int32
        area = text_area(ctx)
        fs = ctx.theme.font_size(@size)
        local = x - area.origin.x + @scroll_x
        return 0 if local <= 0.0_f32
        bounds = @editing.boundaries
        previous = 0
        bounds.each do |b|
          width = ctx.measure_text(@editing.text.byte_slice(0, b), fs).width
          return previous if width > local
          previous = b
        end
        @editing.text.bytesize
      end

      def field_rect(ctx : Context) : Rect
        top = @bounds.origin.y + label_height(ctx)
        Rect.new(@bounds.origin.x, top, @bounds.size.width,
          ctx.theme.control_height(@size))
      end

      def text_area(ctx : Context) : Rect
        field = field_rect(ctx)
        pad = ctx.theme.padding_x(@size)
        Rect.new(field.origin.x + pad, field.origin.y + 2.0_f32,
          Math.max(0.0_f32, field.size.width - pad * 2.0_f32),
          Math.max(0.0_f32, field.size.height - 4.0_f32))
      end

      def ensure_caret_visible(ctx : Context) : Nil
        area = text_area(ctx)
        fs = ctx.theme.font_size(@size)
        caret_x = ctx.measure_text(prefix, fs).width
        if caret_x - @scroll_x > area.size.width
          @scroll_x = caret_x - area.size.width
        elsif caret_x - @scroll_x < 0.0_f32
          @scroll_x = caret_x
        end
        total = ctx.measure_text(@editing.text, fs).width
        max_scroll = Math.max(0.0_f32, total - area.size.width)
        @scroll_x = @scroll_x.clamp(0.0_f32, max_scroll)
      end

      def paint_token : UInt32
        h = 0xcbf29ce484222325_u64
        @editing.text.each_byte do |b|
          h ^= b.to_u64
          h &*= 0x100000001b3_u64
        end
        h ^= @editing.cursor.to_u64
        h &*= 0x100000001b3_u64
        h ^= (@editing.anchor || 0).to_u64
        h &*= 0x100000001b3_u64
        h ^= @scroll_x.to_u32.to_u64
        h ^= (1_u64 << 32) if @focused
        h ^= (1_u64 << 33) if @enabled
        h ^= (1_u64 << 34) if @read_only
        h ^= (1_u64 << 35) if @invalid
        (h & 0xffffffff_u64).to_u32
      end

      def a11y_role : A11y::Role
        A11y::Role::TextField
      end

      def a11y_name : String
        @label.empty? ? @placeholder : @label
      end

      def a11y_value : String
        @editing.text
      end

      private def handle_key_down(event : Event, ctx : Context) : Bool
        if event.ctrl? || event.meta?
          case event.key
          when Key::KeyA
            @editing.select_all
            true
          when Key::KeyC
            @editing.copy(@clipboard)
            true
          when Key::KeyX
            return false if @read_only
            changed = @editing.cut(@clipboard)
            notify_change if changed
            true
          when Key::KeyV
            return false if @read_only
            changed = @editing.paste(@clipboard)
            notify_change if changed
            true
          else
            false
          end
        else
          extending = event.shift?
          case event.key
          when Key::Left
            @editing.move_left(extending)
            ensure_caret_visible(ctx)
            true
          when Key::Right
            @editing.move_right(extending)
            ensure_caret_visible(ctx)
            true
          when Key::Home
            @editing.move_home(extending)
            ensure_caret_visible(ctx)
            true
          when Key::End
            @editing.move_end(extending)
            ensure_caret_visible(ctx)
            true
          when Key::Backspace
            return false if @read_only
            changed = @editing.backspace
            notify_change if changed
            true
          when Key::Delete
            return false if @read_only
            changed = @editing.delete
            notify_change if changed
            true
          when Key::Enter
            @on_submit.try(&.call(@editing.text))
            true
          when Key::Escape
            @editing.collapse_selection
            true
          else
            false
          end
        end
      end

      private def notify_change : Nil
        @on_change.try(&.call(@editing.text))
      end

      private def prefix : String
        return "" if @editing.cursor <= 0
        @editing.text.byte_slice(0, @editing.cursor)
      end

      private def paint_selection(p : Painter, ctx : Context, area : Rect, fs : Float32) : Nil
        return unless @editing.selection?
        start_x = ctx.measure_text(@editing.text.byte_slice(0, @editing.selection_start), fs).width
        end_x = ctx.measure_text(@editing.text.byte_slice(0, @editing.selection_end), fs).width
        x1 = area.origin.x - @scroll_x + start_x
        x2 = area.origin.x - @scroll_x + end_x
        p.fill_rect(Rect.new(x1, area.origin.y, x2 - x1, area.size.height),
          ctx.theme.palette.selection)
      end

      private def paint_preedit(p : Painter, ctx : Context, area : Rect, fs : Float32) : Nil
        return unless @editing.preedit?
        x = area.origin.x - @scroll_x + ctx.measure_text(prefix, fs).width
        y = area.origin.y + (area.size.height + fs) / 2.0_f32 - fs * 0.1_f32
        p.text(x, y, @editing.preedit, ctx.theme.palette.accent, fs)
        width = ctx.measure_text(@editing.preedit, fs).width
        p.line(x, y + 2.0_f32, x + width, y + 2.0_f32, ctx.theme.palette.accent, 1.0_f32)
      end

      private def label_height(ctx : Context) : Float32
        return 0.0_f32 if @label.empty?
        ctx.line_height(ctx.theme.font_size(ControlSize::Small)) + ctx.theme.metrics.spacing_xs
      end

      private def error_height(ctx : Context) : Float32
        return 0.0_f32 unless @invalid && !@error_text.empty?
        ctx.line_height(ctx.theme.font_size(ControlSize::Small)) + ctx.theme.metrics.spacing_xs
      end
    end
  end
end
