# Tessell Kit text editor demo.
#
# macOS:
#   crystal run examples/app_text_editor.cr --link-flags "-L/opt/homebrew/lib"
# Windows: 安装 SDL2 开发库，确保 SDL2.dll 在 PATH 或 exe 同目录。
#
# 交互：点击编辑器聚焦；输入文本；方向键/Home/End；Cmd/Ctrl+C/V；Save 写 notes.txt。

require "./apps/text_editor_app"
require "./lib/kit_sdl_host"

class TextEditorWindow < TessellKitSdl::KitDemoApp
  getter app : TessellApps::TextEditorApp

  def initialize
    @app = TessellApps::TextEditorApp.new
  end

  def title : String
    "Tessell Notes"
  end

  def width : Int32
    900
  end

  def height : Int32
    680
  end

  def build_root(metrics : Tessell::Kit::TextMetrics,
                 clipboard : Tessell::Kit::Clipboard) : Tessell::Kit::Root
    @app.build_root(metrics, clipboard)
  end

  def handle_app_event(event : Tessell::Input::Event) : Bool
    false
  end

  def on_root_ready(root : Tessell::Kit::Root) : Nil
    root.focus(@app.editor)
  end
end

TextEditorWindow.new.run(ARGV)
