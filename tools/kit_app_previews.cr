# Render calculator/text editor app scenes to SVG without a window.
# Usage: crystal run tools/kit_app_previews.cr
# Output: site/previews/calculator-app.svg, site/previews/text-editor-app.svg

require "../examples/apps/calculator_app"
require "../examples/apps/text_editor_app"
require "../src/tessell/kit/svg_painter"

module KitAppPreviews
  def self.build : Nil
    Dir.mkdir_p("site/previews")
    render_calculator
    render_editor
  end

  private def self.render_calculator : Nil
    app = TessellApps::CalculatorApp.new
    root = app.build_root(Tessell::Kit::StubTextMetrics.new,
      Tessell::Kit::MemoryClipboard.new)
    ["1", "+", "2", "="].each { |token| app.press(token) }
    root.layout(480.0_f32, 640.0_f32)
    root.build
    svg = Tessell::Kit::SvgPainter.new(480, 640)
    svg.background = Tessell::Kit::Theme.light.palette.canvas
    root.paint(svg)
    File.write("site/previews/calculator-app.svg", svg.svg)
    puts "wrote site/previews/calculator-app.svg elements=#{svg.elements}"
  end

  private def self.render_editor : Nil
    app = TessellApps::TextEditorApp.new(initial_text: "Tessell Notes\n\nHello, Tessell Kit.\n\nThis is a multiline editor demo.\nTry arrows, Home/End, Cmd/Ctrl+C/V, and Save.")
    root = app.build_root(Tessell::Kit::StubTextMetrics.new,
      Tessell::Kit::MemoryClipboard.new)
    root.layout(900.0_f32, 680.0_f32)
    root.build
    svg = Tessell::Kit::SvgPainter.new(900, 680)
    svg.background = Tessell::Kit::Theme.light.palette.canvas
    root.paint(svg)
    File.write("site/previews/text-editor-app.svg", svg.svg)
    puts "wrote site/previews/text-editor-app.svg elements=#{svg.elements}"
  end
end

KitAppPreviews.build
