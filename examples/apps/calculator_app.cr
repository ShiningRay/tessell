# Tessell Kit calculator app (pure UI/state, no SDL dependency).
#
# 由 examples/app_calculator.cr 提供 SDL2/OpenGL 窗口宿主；
# 本文件可在 macOS/Linux 上用于 headless spec 与 SVG 预览。

require "../../src/tessell/kit"

module TessellApps
  class CalculatorDisplay < Tessell::Kit::Component
    property text : String

    def initialize(@key : Tessell::UI::UiKey, @text : String = "0")
      super(@key)
    end

    def measure(ctx : Tessell::Kit::Context, constraints : Tessell::Constraints) : Tessell::Size
      constraints.constrain(Tessell::Size.new(0.0_f32, 92.0_f32))
    end

    def arrange(ctx : Tessell::Kit::Context, bounds : Tessell::Rect) : Nil
      @bounds = bounds
    end

    def emit(b : Tessell::UI::Builder, ctx : Tessell::Kit::Context) : Nil
      b.node(@key, @bounds, paint: paint_token,
        a11y_role: Tessell::A11y::Role::Text, a11y_name: "Display",
        a11y_value: @text, a11y_enabled: true)
    end

    def paint(p : Tessell::Kit::Painter, ctx : Tessell::Kit::Context) : Nil
      radius = ctx.theme.metrics.radius_lg
      p.fill_round_rect(@bounds, radius, ctx.theme.palette.surface)
      p.stroke_round_rect(@bounds, radius, ctx.theme.palette.border,
        ctx.theme.metrics.border_width)
      fs = 32.0_f32
      text_w = ctx.measure_text(@text, fs).width
      x = @bounds.max_x - ctx.theme.metrics.spacing_lg - text_w
      baseline = @bounds.origin.y + (@bounds.size.height + fs) / 2.0_f32 - fs * 0.1_f32
      p.text(x, baseline, @text, ctx.theme.palette.foreground, fs)
    end

    def a11y_role : Tessell::A11y::Role
      Tessell::A11y::Role::Text
    end

    def a11y_name : String
      "Display"
    end

    def a11y_value : String
      @text
    end

    def paint_token : UInt32
      h = 0xcbf29ce484222325_u64
      @text.each_byte { |b| h = (h ^ b.to_u64) &* 0x100000001b3_u64 }
      (h & 0xffffffff_u64).to_u32
    end
  end

  class CalcButton < Tessell::Kit::Button
    getter cell_width : Float32
    getter cell_height : Float32

    def initialize(@key : Tessell::UI::UiKey, label : String,
                   @cell_width : Float32 = 96.0_f32,
                   @cell_height : Float32 = 58.0_f32,
                   variant : Tessell::Kit::Variant = Tessell::Kit::Variant::Secondary)
      super(@key, label, variant, Tessell::Kit::ControlSize::Large)
    end

    def measure(ctx : Tessell::Kit::Context, constraints : Tessell::Constraints) : Tessell::Size
      constraints.constrain(Tessell::Size.new(@cell_width, @cell_height))
    end
  end

  class CalculatorState
    getter current : String
    getter accumulator : Float64?
    getter pending_op : Char?
    getter error : Bool
    getter expression : String

    def initialize
      @current = "0"
      @accumulator = nil
      @pending_op = nil
      @error = false
      @just_evaluated = false
      @expression = ""
    end

    def reset : Nil
      @current = "0"
      @accumulator = nil
      @pending_op = nil
      @error = false
      @just_evaluated = false
      @expression = ""
    end

    def display : String
      @error ? "Error" : @current
    end

    def press(token : String) : Nil
      case token
      when "C"
        reset
      when "±"
        toggle_sign
      when "%"
        percent
      when "⌫"
        backspace
      when "="
        equals
      when "+", "-", "*", "/"
        apply_operator(token[0])
      when "."
        decimal
      else
        input_digit(token[0]) if token.size == 1 && token[0].ascii_number?
      end
    end

    def self.compute(a : Float64, b : Float64, op : Char) : Float64?
      case op
      when '+' then a + b
      when '-' then a - b
      when '*' then a * b
      when '/'
        return nil if b == 0.0
        a / b
      else
        nil
      end
    end

    private def input_digit(ch : Char) : Nil
      if @error || @just_evaluated
        @current = "0"
        @error = false
        @just_evaluated = false
        @expression = ""
      end
      if @current == "0"
        @current = ch.to_s
      elsif @current.size < 18
        @current += ch
      end
    end

    private def decimal : Nil
      if @error || @just_evaluated
        @current = "0"
        @error = false
        @just_evaluated = false
      end
      @current += "." unless @current.includes?('.')
    end

    private def toggle_sign : Nil
      return if @error || @current == "0"
      @current = @current.starts_with?('-') ? @current[1, @current.size - 1] : "-#{@current}"
    end

    private def percent : Nil
      return if @error
      @current = format(@current.to_f64 / 100.0)
      @just_evaluated = true
    end

    private def backspace : Nil
      if @error || @just_evaluated
        reset
        return
      end
      if @current.size > 1
        @current = @current[0, @current.size - 1]
        @current = "0" if @current == "-" || @current.empty?
      else
        @current = "0"
      end
    end

    private def apply_operator(op : Char) : Nil
      return if @error
      value = @current.to_f64
      if @pending_op && @accumulator && !@just_evaluated
        result = CalculatorState.compute(@accumulator.not_nil!, value, @pending_op.not_nil!)
        if result.nil?
          @error = true
          @current = "Error"
          @pending_op = nil
          @accumulator = nil
          return
        end
        @accumulator = result
        @current = format(result)
      else
        @accumulator = value
      end
      @pending_op = op
      @just_evaluated = true
      @expression = "#{format(@accumulator.not_nil!)} #{op}"
    end

    private def equals : Nil
      return if @error
      if @pending_op && @accumulator
        result = CalculatorState.compute(@accumulator.not_nil!, @current.to_f64, @pending_op.not_nil!)
        if result.nil?
          @error = true
          @current = "Error"
        else
          @current = format(result)
        end
        @pending_op = nil
        @accumulator = nil
      end
      @just_evaluated = true
      @expression = ""
    end

    private def format(value : Float64) : String
      if value == value.round && value.abs < 1.0e15
        value.to_i64.to_s
      else
        value.round(8).to_s.rstrip('0').rstrip('.')
      end
    end
  end

  class CalculatorApp
    getter state : CalculatorState
    getter display : CalculatorDisplay
    getter root : Tessell::Kit::Root?

    def initialize(@theme : Tessell::Kit::Theme = Tessell::Kit::Theme.light)
      @state = CalculatorState.new
      @display = CalculatorDisplay.new(Tessell::UI::UiKey.root.child(1_u64), "0")
      @root = nil
    end

    def build_root(metrics : Tessell::Kit::TextMetrics,
                   clipboard : Tessell::Kit::Clipboard) : Tessell::Kit::Root
      column = Tessell::Kit::Column.new(Tessell::UI::UiKey.root.child(2_u64),
        Tessell::Insets.all(18.0_f32), 10.0_f32, Tessell::Kit::Alignment::Stretch)
      title = Tessell::Kit::Text.new(Tessell::UI::UiKey.root.child(3_u64),
        "Tessell Calculator", Tessell::Kit::TextTone::Muted,
        Tessell::Kit::ControlSize::Small)
      column.add(title)
      column.add(@display)

      add_row(column, ["C", "±", "%", "/"], 100_u64,
        [Tessell::Kit::Variant::Danger, Tessell::Kit::Variant::Secondary,
         Tessell::Kit::Variant::Secondary, Tessell::Kit::Variant::Primary])
      add_row(column, ["7", "8", "9", "*"], 110_u64,
        [Tessell::Kit::Variant::Secondary, Tessell::Kit::Variant::Secondary,
         Tessell::Kit::Variant::Secondary, Tessell::Kit::Variant::Primary])
      add_row(column, ["4", "5", "6", "-"], 120_u64,
        [Tessell::Kit::Variant::Secondary, Tessell::Kit::Variant::Secondary,
         Tessell::Kit::Variant::Secondary, Tessell::Kit::Variant::Primary])
      add_row(column, ["1", "2", "3", "+"], 130_u64,
        [Tessell::Kit::Variant::Secondary, Tessell::Kit::Variant::Secondary,
         Tessell::Kit::Variant::Secondary, Tessell::Kit::Variant::Primary])
      key = 140_u64
      last = Tessell::Kit::Row.new(Tessell::UI::UiKey.root.child(key), Tessell::Insets.new,
        8.0_f32, Tessell::Kit::Alignment::Start)
      key += 1
      zero = CalcButton.new(Tessell::UI::UiKey.root.child(key), "0", 200.0_f32, 58.0_f32)
      zero.on_click = -> { press("0"); nil }
      key += 1
      dot = CalcButton.new(Tessell::UI::UiKey.root.child(key), ".")
      dot.on_click = -> { press("."); nil }
      key += 1
      equals = CalcButton.new(Tessell::UI::UiKey.root.child(key), "=", 96.0_f32, 58.0_f32,
        Tessell::Kit::Variant::Primary)
      equals.on_click = -> { press("="); nil }
      last.add(zero)
      last.add(dot)
      last.add(equals)
      column.add(last)

      @root = Tessell::Kit::Root.new(column, @theme, metrics,
        Tessell::Rect.new(0.0_f32, 0.0_f32, 480.0_f32, 640.0_f32))
      @root.not_nil!
    end

    def press(token : String) : Nil
      @state.press(token)
      @display.text = @state.display
    end

    def handle_app_event(event : Tessell::Input::Event) : Bool
      case event.kind
      when Tessell::Input::Event::Kind::TextInput
        return false unless text = event.text
        handled = false
        text.each_char do |ch|
          if ch.ascii_number? || "+-*/.".includes?(ch)
            press(ch.to_s)
            handled = true
          end
        end
        handled
      when Tessell::Input::Event::Kind::KeyDown
        case event.key
        when Tessell::Input::KeyCode::Enter
          press("=")
          true
        when Tessell::Input::KeyCode::Escape
          press("C")
          true
        when Tessell::Input::KeyCode::Backspace, Tessell::Input::KeyCode::Delete
          press("⌫")
          true
        else
          false
        end
      else
        false
      end
    end

    private def add_row(column : Tessell::Kit::Container, labels : Array(String),
                        key : UInt64, variants : Array(Tessell::Kit::Variant)) : Nil
      row = Tessell::Kit::Row.new(Tessell::UI::UiKey.root.child(key),
        Tessell::Insets.new, 8.0_f32, Tessell::Kit::Alignment::Start)
      k = key + 1
      labels.each_with_index do |label, i|
        button = CalcButton.new(Tessell::UI::UiKey.root.child(k), label,
          96.0_f32, 58.0_f32, variants[i])
        button.on_click = -> { press(label); nil }
        row.add(button)
        k += 1
      end
      column.add(row)
    end
  end
end
