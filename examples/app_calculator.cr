# Tessell Kit calculator demo.
#
# macOS:
#   crystal run examples/app_calculator.cr --link-flags "-L/opt/homebrew/lib"
# Windows: 安装 SDL2 开发库，确保 SDL2.dll 在 PATH 或 exe 同目录。
#
# 交互：鼠标点击按钮；键盘数字/运算符；Enter =；Esc/C 清空；Backspace 退格。

require "./apps/calculator_app"
require "./lib/kit_sdl_host"

class CalculatorWindow < TessellKitSdl::KitDemoApp
  getter app : TessellApps::CalculatorApp

  def initialize
    @app = TessellApps::CalculatorApp.new
  end

  def title : String
    "Tessell Calculator"
  end

  def width : Int32
    480
  end

  def height : Int32
    640
  end

  def build_root(metrics : Tessell::Kit::TextMetrics,
                 clipboard : Tessell::Kit::Clipboard) : Tessell::Kit::Root
    @app.build_root(metrics, clipboard)
  end

  def handle_app_event(event : Tessell::Input::Event) : Bool
    @app.handle_app_event(event)
  end
end

CalculatorWindow.new.run(ARGV)
