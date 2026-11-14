# Tessell Kit text editor app (pure UI/state, no SDL dependency).
#
# 多行 EditorView 是 demo 级组件：复用 Kit::TextEditing 的 grapheme 光标/选区，
# 自己负责多行布局、滚动、点击定位与绘制。它不进入 Kit 公共组件集。

require "../../src/tessell/kit"

module TessellApps
  record LineRange, start : Int32, finish : Int32

  class EditorView < Tessell::Kit::Component
    getter editing : Tessell::Kit::TextEditing
    property clipboard : Tessell::Kit::Clipboard
    property on_change : Proc(String, Nil)?
    property font_size : Float32
    property padding : Float32
    property preferred_height : Float32
    getter scroll_x : Float32
    getter scroll_y : Float32

    def initialize(@key : Tessell::UI::UiKey, text : String = "",
                   @font_size : Float32 = 16.0_f32,
                   @padding : Float32 = 12.0_f32,
                   @preferred_height : Float32 = 440.0_f32)
      super(@key, true, true)
      @editing = Tessell::Kit::TextEditing.new(text)
      @clipboard = Tessell::Kit::MemoryClipboard.new
      @on_change = nil
      @scroll_x = 0.0_f32
      @scroll_y = 0.0_f32
      @dragging = false
    end

    def text : String
      @editing.text
    end

    def set_text(value : String) : Nil
      @editing.set_text(value)
      @scroll_x = 0.0_f32
      @scroll_y = 0.0_f32
    end

    def measure(ctx : Tessell::Kit::Context, constraints : Tessell::Constraints) : Tessell::Size
      w = constraints.max_width.infinite? ? 640.0_f32 : constraints.max_width
      h = constraints.max_height.infinite? ? @preferred_height : Math.min(constraints.max_height, @preferred_height)
      constraints.constrain(Tessell::Size.new(w, h))
    end

    def arrange(ctx : Tessell::Kit::Context, bounds : Tessell::Rect) : Nil
      @bounds = bounds
      ensure_caret_visible(ctx)
    end

    def emit(b : Tessell::UI::Builder, ctx : Tessell::Kit::Context) : Nil
      b.node(@key, @bounds, paint: paint_token,
        a11y_role: Tessell::A11y::Role::TextField, a11y_name: "Editor",
        a11y_value: @editing.text, a11y_focusable: focusable?,
        a11y_enabled: @enabled)
    end

    def paint(p : Tessell::Kit::Painter, ctx : Tessell::Kit::Context) : Nil
      return unless @visible
      radius = ctx.theme.metrics.radius_md
      p.fill_round_rect(@bounds, radius, ctx.theme.palette.surface)
      p.stroke_round_rect(@bounds, radius,
        @focused ? ctx.theme.palette.focus : ctx.theme.palette.border,
        @focused ? ctx.theme.metrics.focus_ring_width : ctx.theme.metrics.border_width)

      inner = inner_rect
      p.push_clip(inner)
      ranges = line_ranges
      line_h = line_height(ctx)
      first = (inner.size.height > 0.0_f32 ? (@scroll_y / line_h).floor.to_i : 0).clamp(0, ranges.size - 1)
      last = ((@scroll_y + inner.size.height) / line_h).ceil.to_i.clamp(0, ranges.size - 1)
      i = first
      while i <= last
        range = ranges[i]
        y = inner.origin.y + i * line_h - @scroll_y
        paint_selection(p, ctx, range, i, inner, line_h)
        line = @editing.text.byte_slice(range.start, range.finish - range.start)
        p.text(inner.origin.x - @scroll_x, y + @font_size, line,
          ctx.theme.palette.foreground, @font_size)
        i += 1
      end
      paint_caret(p, ctx, inner, line_h) if @focused
      p.pop_clip
      paint_scrollbar(p, ctx, inner, ranges.size, line_h)
    end

    def focusable? : Bool
      @visible && @enabled
    end

    def clip_bounds : Tessell::Rect?
      @bounds
    end

    def handle(event : Tessell::Kit::Event, ctx : Tessell::Kit::Context) : Bool
      case event.kind
      when Tessell::Kit::Event::Kind::PointerDown
        if inner_rect.contains?(Tessell::Point.new(event.x, event.y))
          @editing.set_cursor(caret_index_at(ctx, event.x, event.y))
          @dragging = true
          ensure_caret_visible(ctx)
          return true
        end
        false
      when Tessell::Kit::Event::Kind::PointerMove
        if @dragging
          @editing.set_cursor(caret_index_at(ctx, event.x, event.y), extending: true)
          ensure_caret_visible(ctx)
          true
        else
          false
        end
      when Tessell::Kit::Event::Kind::PointerUp
        was = @dragging
        @dragging = false
        was
      when Tessell::Kit::Event::Kind::TextInput
        return false unless @enabled
        if value = event.text
          changed = @editing.insert(value)
          notify_change if changed
          ensure_caret_visible(ctx)
          true
        else
          false
        end
      when Tessell::Kit::Event::Kind::KeyDown
        return false unless @enabled
        handle_key_down(event, ctx)
      when Tessell::Kit::Event::Kind::Blur
        @dragging = false
        if @editing.preedit?
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
      @dragging = false unless focused
    end

    def paint_token : UInt32
      h = 0xcbf29ce484222325_u64
      @editing.text.each_byte { |b| h = (h ^ b.to_u64) &* 0x100000001b3_u64 }
      h ^= @editing.cursor.to_u64
      h &*= 0x100000001b3_u64
      h ^= (@editing.anchor || 0).to_u64
      h ^= (@scroll_x.to_u32.to_u64 << 16)
      h ^= (@scroll_y.to_u32.to_u64 << 32)
      h ^= (1_u64 << 40) if @focused
      (h & 0xffffffff_u64).to_u32
    end

    def a11y_role : Tessell::A11y::Role
      Tessell::A11y::Role::TextField
    end

    def a11y_name : String
      "Editor"
    end

    def a11y_value : String
      @editing.text
    end

    private def handle_key_down(event : Tessell::Kit::Event, ctx : Tessell::Kit::Context) : Bool
      if event.ctrl? || event.meta?
        case event.key
        when Tessell::Kit::Key::KeyA
          @editing.select_all
          true
        when Tessell::Kit::Key::KeyC
          @editing.copy(@clipboard)
          true
        when Tessell::Kit::Key::KeyX
          changed = @editing.cut(@clipboard)
          notify_change if changed
          ensure_caret_visible(ctx)
          true
        when Tessell::Kit::Key::KeyV
          changed = @editing.paste(@clipboard)
          notify_change if changed
          ensure_caret_visible(ctx)
          true
        else
          false
        end
      else
        extending = event.shift?
        case event.key
        when Tessell::Kit::Key::Left
          @editing.move_left(extending)
          ensure_caret_visible(ctx)
          true
        when Tessell::Kit::Key::Right
          @editing.move_right(extending)
          ensure_caret_visible(ctx)
          true
        when Tessell::Kit::Key::Up
          move_line(ctx, -1, extending)
          true
        when Tessell::Kit::Key::Down
          move_line(ctx, 1, extending)
          true
        when Tessell::Kit::Key::Home
          move_to_line_edge(ctx, :start, extending)
          true
        when Tessell::Kit::Key::End
          move_to_line_edge(ctx, :finish, extending)
          true
        when Tessell::Kit::Key::Enter
          changed = @editing.insert("\n")
          notify_change if changed
          ensure_caret_visible(ctx)
          true
        when Tessell::Kit::Key::Backspace
          changed = @editing.backspace
          notify_change if changed
          ensure_caret_visible(ctx)
          true
        when Tessell::Kit::Key::Delete
          changed = @editing.delete
          notify_change if changed
          ensure_caret_visible(ctx)
          true
        when Tessell::Kit::Key::Escape
          @editing.collapse_selection
          true
        else
          false
        end
      end
    end

    private def move_line(ctx : Tessell::Kit::Context, delta : Int32, extending : Bool) : Nil
      ranges = line_ranges
      current = line_index_for(@editing.cursor)
      target = (current + delta).clamp(0, ranges.size - 1)
      return if target == current
      current_range = ranges[current]
      prefix = @editing.text.byte_slice(current_range.start, @editing.cursor - current_range.start)
      desired_x = ctx.measure_text(prefix, @font_size).width
      target_range = ranges[target]
      index = closest_index_on_line(ctx, target_range, desired_x)
      @editing.set_cursor(index, extending: extending)
      ensure_caret_visible(ctx)
    end

    private def move_to_line_edge(ctx : Tessell::Kit::Context, edge : Symbol, extending : Bool) : Nil
      ranges = line_ranges
      current = line_index_for(@editing.cursor)
      range = ranges[current]
      target = edge == :start ? range.start : range.finish
      @editing.set_cursor(target, extending: extending)
      ensure_caret_visible(ctx)
    end

    private def closest_index_on_line(ctx : Tessell::Kit::Context, range : LineRange, x : Float32) : Int32
      best = range.start
      best_distance = Float32::INFINITY
      @editing.boundaries.each do |boundary|
        next if boundary < range.start
        break if boundary > range.finish
        prefix = @editing.text.byte_slice(range.start, boundary - range.start)
        width = ctx.measure_text(prefix, @font_size).width
        distance = (width - x).abs
        if distance < best_distance
          best_distance = distance
          best = boundary
        end
      end
      best
    end

    private def caret_index_at(ctx : Tessell::Kit::Context, x : Float32, y : Float32) : Int32
      ranges = line_ranges
      inner = inner_rect
      line_h = line_height(ctx)
      line_index = ((y - inner.origin.y + @scroll_y) / line_h).floor.to_i.clamp(0, ranges.size - 1)
      range = ranges[line_index]
      local_x = x - inner.origin.x + @scroll_x
      closest_index_on_line(ctx, range, local_x)
    end

    private def paint_selection(p : Tessell::Kit::Painter, ctx : Tessell::Kit::Context,
                                range : LineRange, index : Int32, inner : Tessell::Rect,
                                line_h : Float32) : Nil
      return unless @editing.selection?
      sel_start = @editing.selection_start
      sel_end = @editing.selection_end
      start = Math.max(sel_start, range.start)
      finish = Math.min(sel_end, range.finish)
      return if finish <= start
      x1 = inner.origin.x - @scroll_x + ctx.measure_text(
        @editing.text.byte_slice(range.start, start - range.start), @font_size).width
      x2 = inner.origin.x - @scroll_x + ctx.measure_text(
        @editing.text.byte_slice(range.start, finish - range.start), @font_size).width
      y = inner.origin.y + index * line_h - @scroll_y
      p.fill_rect(Tessell::Rect.new(x1, y, x2 - x1, line_h - 2.0_f32),
        ctx.theme.palette.selection)
    end

    private def paint_caret(p : Tessell::Kit::Painter, ctx : Tessell::Kit::Context,
                            inner : Tessell::Rect, line_h : Float32) : Nil
      ranges = line_ranges
      index = line_index_for(@editing.cursor)
      range = ranges[index]
      prefix = @editing.text.byte_slice(range.start, @editing.cursor - range.start)
      x = inner.origin.x - @scroll_x + ctx.measure_text(prefix, @font_size).width
      y = inner.origin.y + index * line_h - @scroll_y
      p.line(x, y + 2.0_f32, x, y + line_h - 2.0_f32,
        ctx.theme.palette.foreground, 1.0_f32)
    end

    private def paint_scrollbar(p : Tessell::Kit::Painter, ctx : Tessell::Kit::Context,
                                inner : Tessell::Rect, line_count : Int32,
                                line_h : Float32) : Nil
      content_h = line_count * line_h
      return if content_h <= inner.size.height
      track_w = 8.0_f32
      track_x = @bounds.max_x - track_w - 2.0_f32
      track = Tessell::Rect.new(track_x, inner.origin.y, track_w, inner.size.height)
      p.fill_rect(track, ctx.theme.palette.surface_raised)
      ratio = inner.size.height / content_h
      thumb_h = Math.max(20.0_f32, inner.size.height * ratio)
      max_scroll = Math.max(1.0_f32, content_h - inner.size.height)
      travel = inner.size.height - thumb_h
      thumb_y = inner.origin.y + travel * (@scroll_y / max_scroll)
      p.fill_round_rect(Tessell::Rect.new(track_x + 2.0_f32, thumb_y,
        track_w - 4.0_f32, thumb_h), 3.0_f32, ctx.theme.palette.muted)
    end

    private def ensure_caret_visible(ctx : Tessell::Kit::Context) : Nil
      ranges = line_ranges
      index = line_index_for(@editing.cursor)
      range = ranges[index]
      prefix = @editing.text.byte_slice(range.start, @editing.cursor - range.start)
      caret_x = ctx.measure_text(prefix, @font_size).width
      line_h = line_height(ctx)
      inner = inner_rect
      if caret_x - @scroll_x > inner.size.width
        @scroll_x = caret_x - inner.size.width
      elsif caret_x - @scroll_x < 0.0_f32
        @scroll_x = caret_x
      end
      caret_y = index * line_h
      if caret_y - @scroll_y + line_h > inner.size.height
        @scroll_y = caret_y + line_h - inner.size.height
      elsif caret_y - @scroll_y < 0.0_f32
        @scroll_y = caret_y
      end
      max_x = Math.max(0.0_f32, content_width(ctx) - inner.size.width)
      max_y = Math.max(0.0_f32, ranges.size * line_h - inner.size.height)
      @scroll_x = @scroll_x.clamp(0.0_f32, max_x)
      @scroll_y = @scroll_y.clamp(0.0_f32, max_y)
    end

    private def content_width(ctx : Tessell::Kit::Context) : Float32
      max = 0.0_f32
      line_ranges.each do |range|
        line = @editing.text.byte_slice(range.start, range.finish - range.start)
        max = Math.max(max, ctx.measure_text(line, @font_size).width)
      end
      max
    end

    private def line_ranges : Array(LineRange)
      ranges = [] of LineRange
      start = 0
      offset = 0
      @editing.text.each_char do |ch|
        if ch == '\n'
          ranges << LineRange.new(start, offset)
          start = offset + 1
        end
        offset += ch.bytesize
      end
      ranges << LineRange.new(start, offset)
      ranges
    end

    private def line_index_for(offset : Int32) : Int32
      ranges = line_ranges
      ranges.each_with_index do |range, index|
        return index if offset <= range.finish
      end
      ranges.size - 1
    end

    private def line_height(ctx : Tessell::Kit::Context) : Float32
      ctx.line_height(@font_size) + 2.0_f32
    end

    private def inner_rect : Tessell::Rect
      Tessell::Kit::Geometry.inset(@bounds, @padding)
    end

    private def notify_change : Nil
      @on_change.try(&.call(@editing.text))
    end
  end

  class TextEditorApp
    getter editor : EditorView
    getter status : Tessell::Kit::Text
    getter root : Tessell::Kit::Root?
    property path : String

    def initialize(@path : String = "notes.txt",
                   @theme : Tessell::Kit::Theme = Tessell::Kit::Theme.light,
                   initial_text : String = "Welcome to Tessell Notes.\n\nType something, then use Save.\nCmd/Ctrl+C/V, arrows, Home/End work.")
      @editor = EditorView.new(Tessell::UI::UiKey.root.child(1_u64), initial_text)
      @status = Tessell::Kit::Text.new(Tessell::UI::UiKey.root.child(2_u64),
        "Ready", Tessell::Kit::TextTone::Muted, Tessell::Kit::ControlSize::Small)
      @root = nil
    end

    def build_root(metrics : Tessell::Kit::TextMetrics,
                   clipboard : Tessell::Kit::Clipboard) : Tessell::Kit::Root
      @editor.clipboard = clipboard
      @editor.on_change = ->(text : String) { update_status; nil }

      column = Tessell::Kit::Column.new(Tessell::UI::UiKey.root.child(3_u64),
        Tessell::Insets.all(16.0_f32), 10.0_f32, Tessell::Kit::Alignment::Stretch)
      header = Tessell::Kit::Row.new(Tessell::UI::UiKey.root.child(4_u64),
        Tessell::Insets.new, 8.0_f32, Tessell::Kit::Alignment::Center)
      title = Tessell::Kit::Text.new(Tessell::UI::UiKey.root.child(5_u64),
        "Tessell Notes", Tessell::Kit::TextTone::Normal,
        Tessell::Kit::ControlSize::Large)
      header.add(title)
      header.add(spacer(Tessell::UI::UiKey.root.child(6_u64)))
      header.add(button(Tessell::UI::UiKey.root.child(7_u64), "New",
        Tessell::Kit::Variant::Secondary) { new_file })
      header.add(button(Tessell::UI::UiKey.root.child(8_u64), "Open",
        Tessell::Kit::Variant::Secondary) { open_file })
      header.add(button(Tessell::UI::UiKey.root.child(9_u64), "Save",
        Tessell::Kit::Variant::Primary) { save_file })
      column.add(header)
      column.add(@editor)
      column.add(@status)

      @root = Tessell::Kit::Root.new(column, @theme, metrics,
        Tessell::Rect.new(0.0_f32, 0.0_f32, 900.0_f32, 680.0_f32))
      update_status
      @root.not_nil!
    end

    def new_file : Nil
      @editor.set_text("")
      @status.content = "New document"
    end

    def open_file : Nil
      if File.exists?(@path)
        @editor.set_text(File.read(@path))
        @status.content = "Opened #{@path}"
      else
        @status.content = "No file at #{@path}"
      end
    end

    def save_file : Nil
      File.write(@path, @editor.text)
      @status.content = "Saved #{@path}"
    end

    def update_status : Nil
      @status.content = "#{@editor.text.size} chars, #{line_count} lines  ·  #{@path}"
    end

    def line_count : Int32
      @editor.text.count('\n') + 1
    end

    private def button(key : Tessell::UI::UiKey, label : String,
                       variant : Tessell::Kit::Variant, &action : -> Nil) : Tessell::Kit::Button
      button = Tessell::Kit::Button.new(key, label, variant,
        Tessell::Kit::ControlSize::Medium)
      button.on_click = action
      button
    end

    private def spacer(key : Tessell::UI::UiKey) : Tessell::Kit::Component
      Spacer.new(key)
    end
  end

  # 横向撑开 header 的空白；Row 没有 flex，用最小占位 + Row 拉伸由父 Column 完成。
  class Spacer < Tessell::Kit::Component
    def initialize(@key : Tessell::UI::UiKey)
      super(@key)
    end

    def measure(ctx : Tessell::Kit::Context, constraints : Tessell::Constraints) : Tessell::Size
      Tessell::Size.new(0.0_f32, 1.0_f32)
    end

    def emit(b : Tessell::UI::Builder, ctx : Tessell::Kit::Context) : Nil
      b.node(@key, @bounds)
    end
  end
end
