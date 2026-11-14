require "spec"
require "../../examples/apps/calculator_app"

describe "TessellApps::CalculatorState" do
  it "computes four-function expressions" do
    state = TessellApps::CalculatorState.new
    ["1", "+", "2", "="].each { |token| state.press(token) }
    state.display.should eq("3")

    state.press("C")
    ["7", "*", "8", "="].each { |token| state.press(token) }
    state.display.should eq("56")

    state.press("C")
    ["9", "/", "3", "="].each { |token| state.press(token) }
    state.display.should eq("3")
  end

  it "handles decimals, sign, percent and backspace" do
    state = TessellApps::CalculatorState.new
    ["1", ".", "5", "+", "2", ".", "2", "5", "="].each { |token| state.press(token) }
    state.display.should eq("3.75")

    state.press("C")
    ["4", "2", "±"].each { |token| state.press(token) }
    state.display.should eq("-42")

    state.press("%")
    state.display.should eq("-0.42")

    state.press("C")
    ["1", "2", "3", "⌫"].each { |token| state.press(token) }
    state.display.should eq("12")
  end

  it "reports division by zero and recovers with C" do
    state = TessellApps::CalculatorState.new
    ["1", "/", "0", "="].each { |token| state.press(token) }
    state.display.should eq("Error")
    state.error.should be_true
    state.press("C")
    state.display.should eq("0")
    state.press("2")
    state.display.should eq("2")
  end
end

describe "TessellApps::CalculatorApp" do
  it "updates the display on button presses" do
    app = TessellApps::CalculatorApp.new
    app.press("8")
    app.press("/")
    app.press("2")
    app.press("=")
    app.display.text.should eq("4")
  end

  it "handles keyboard text input and Enter" do
    app = TessellApps::CalculatorApp.new
    app.handle_app_event(Tessell::Input::Event.text_input("12+3")).should be_true
    app.handle_app_event(Tessell::Input::Event.key_down(Tessell::Input::KeyCode::Enter)).should be_true
    app.state.display.should eq("15")
  end

  it "builds a Root with display and button a11y metadata" do
    app = TessellApps::CalculatorApp.new
    metrics = Tessell::Kit::StubTextMetrics.new
    root = app.build_root(metrics, Tessell::Kit::MemoryClipboard.new)
    root.layout(480.0_f32, 640.0_f32)
    root.build
    sink = [] of Tessell::A11y::Node
    root.a11y_emit(sink)
    sink.any? { |n| n.name == "Display" && n.value == "0" }.should be_true
    sink.count { |n| n.role == Tessell::A11y::Role::Button }.should be >= 19
  end
end
