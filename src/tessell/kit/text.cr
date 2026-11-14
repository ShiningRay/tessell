# Tessell::Kit::Text — 只读文本组件（K2）
#
# 正文/标签/标题用同一组件 + size/tone 表达；不是编辑器。
# 换行按 codepoint 贪心断行，不做双向文本/复杂脚本排版。

module Tessell
  module Kit
    enum TextTone
      Normal
      Muted
      Danger
      Success
    end

    class Text < Component
      property content : String
      property tone : TextTone
      property size : ControlSize
      property wrap : Bool
      property max_lines : Int32?

      def initialize(@key : UI::UiKey, @content : String,
                     @tone : TextTone = TextTone::Normal,
                     @size : ControlSize = ControlSize::Medium,
                     @wrap : Bool = false,
                     @max_lines : Int32? = nil,
                     enabled : Bool = true)
        super(@key, enabled)
      end

      def measure(ctx : Context, constraints : Constraints) : Size
        fs = ctx.theme.font_size(@size)
        max_w = constraints.max_width
        measured = if @wrap
                     ctx.measure_text(@content, fs, max_w)
                   else
                     ctx.measure_text(@content, fs)
                   end
        width = if @wrap && !max_w.infinite?
                  Math.min(max_w, measured.width)
                else
                  measured.width
                end
        height = measured.height
        if lines = @max_lines
          line_h = ctx.line_height(fs)
          height = Math.min(height, line_h * lines)
        end
        constraints.constrain(Size.new(width, height))
      end

      def arrange(ctx : Context, bounds : Rect) : Nil
        @bounds = bounds
      end

      def emit(b : UI::Builder, ctx : Context) : Nil
        b.text(@key, @content, @bounds, paint: paint_token,
          a11y_role: A11y::Role::Text, a11y_name: @content,
          a11y_focusable: false, a11y_enabled: @enabled)
      end

      def paint(p : Painter, ctx : Context) : Nil
        return unless @visible
        fs = ctx.theme.font_size(@size)
        color = resolve_color(ctx)
        lines = layout_lines(ctx, fs)
        m = ctx.text_metrics(fs)
        line_h = ctx.line_height(fs)
        # 行距与测量同源（issue #19）：基线 = top + ascent，行距 = line_height；
        # 不再用 top + fs 的第三种口径。
        baseline = @bounds.origin.y + m.ascent
        lines.each_with_index do |line, index|
          break if index >= (@max_lines || Int32::MAX)
          p.text(@bounds.origin.x, baseline + index * line_h, line, color, fs)
        end
      end

      def a11y_role : A11y::Role
        A11y::Role::Text
      end

      def a11y_name : String
        @content
      end

      def paint_token : UInt32
        token = @size.value.to_u32
        token |= (@tone.value.to_u32 << 3)
        token |= (1_u32 << 8) unless @enabled
        token
      end

      private def resolve_color(ctx : Context) : UInt32
        return ctx.theme.palette.muted unless @enabled
        case @tone
        when TextTone::Muted   then ctx.theme.palette.muted
        when TextTone::Danger  then ctx.theme.palette.danger
        when TextTone::Success then ctx.theme.palette.success
        else                        ctx.theme.palette.foreground
        end
      end

      private def layout_lines(ctx : Context, fs : Float32) : Array(String)
        if @wrap
          lines = break_lines(ctx, @content, fs, @bounds.size.width)
        else
          lines = [truncate(ctx, @content, fs, @bounds.size.width)]
        end
        if max = @max_lines
          if lines.size > max
            lines = lines[0, max]
            if lines.size > 0
              lines[lines.size - 1] = truncate(ctx, lines[lines.size - 1] + "…", fs, @bounds.size.width)
            end
          end
        end
        lines
      end

      private def break_lines(ctx : Context, text : String, fs : Float32, max_width : Float32) : Array(String)
        return [text] if max_width.infinite? || max_width <= 0.0_f32
        lines = [] of String
        builder = String::Builder.new
        current_w = 0.0_f32
        text.each_char do |ch|
          w = ctx.measure_text(ch.to_s, fs).width
          if current_w > 0.0_f32 && current_w + w > max_width
            lines << builder.to_s
            builder = String::Builder.new
            current_w = 0.0_f32
          end
          builder << ch
          current_w += w
        end
        lines << builder.to_s unless builder.empty?
        lines.empty? ? [""] : lines
      end

      private def truncate(ctx : Context, text : String, fs : Float32, max_width : Float32) : String
        return text if max_width.infinite? || max_width <= 0.0_f32
        return text if ctx.measure_text(text, fs).width <= max_width
        ellipsis = "…"
        ellipsis_w = ctx.measure_text(ellipsis, fs).width
        builder = String::Builder.new
        width = 0.0_f32
        text.each_char do |ch|
          w = ctx.measure_text(ch.to_s, fs).width
          break if width + w + ellipsis_w > max_width
          builder << ch
          width += w
        end
        "#{builder}#{ellipsis}"
      end
    end
  end
end
