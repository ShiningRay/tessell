# X3 Windows L1 真实窗口证据（issue #61，2026-11-20）

## 环境

- Windows 11（本机真机），Crystal 1.22.1（MSYS2 UCRT64），SDL2 2.x
  （mingw-w64-ucrt-x86_64-SDL2），FreeType/HarfBuzz ucrt64。
- 示例宿主：`examples/lib/kit_sdl_host.cr`（issue #61 X1 重构后）——
  窗口/GL context/事件/剪贴板全部来自可选宿主
  `require "tessell/platform/sdl2"`（`Platform::SDL2::Host`）。

## 运行命令与 token

```text
crystal run examples/app_calculator.cr -- --frames=3 --screenshot=docs/evidence/X3-windows-l1/calculator_win.png
  → KIT_DEMO_RUN app=Tessell Calculator frames=3 size=480x640 scale=1.0

crystal run examples/app_text_editor.cr -- --frames=3 --screenshot=docs/evidence/X3-windows-l1/editor_win.png
  → KIT_DEMO_RUN app=Tessell Notes frames=3 size=900x680 scale=1.0
```

- 真实窗口（SDL_WINDOW_SHOWN | RESIZABLE | ALLOW_HIGHDPI）+ OpenGL 2.1
  兼容 context + SDL 事件循环；`--frames` 自动帧数退出。
- 截图为 `glReadPixels` 前缓冲回读（PNG，tools/lib/png.zlib 编码），
  非全黑、含完整组件绘制（见同目录 PNG）。

## 证据文件

- `calculator_win.png`：计算器真实窗口截图（480×640，文本/按钮/主题/圆角）。
- `editor_win.png`：Notes 编辑器真实窗口截图（900×680，含文本输入组件）。

## 合成输入与像素口径

- 像素级合成输入/像素回读负例由 headless 套件承担：
  `spec/render_text_batch_window_spec.cr`（SoftwareBackend 像素级）、
  `spec/kit/` 键盘/指针路径、`examples/kit_gallery.cr --verify`
  （合成 click → KIT_GALLERY_VERIFY verify=pass，2026-11-20 本机实测）。
- 真机交互（鼠标/键盘/滚轮/resize）按 plan §5.2 由宿主事件映射承担
  （SDL2 → Input::Event，含 wheel/repeat/timestamp/modifiers 透传）。

## 已知边界

- Windows SDL2 宿主是**可选**入口（`require "tessell/platform/sdl2"`），
  不进核心默认依赖（`src/tessell.cr` 无该 require，spec 有编译期兜底）。
- Linux L1 由 CI 的 Xvfb + Mesa（真实 X11 显示服务器 + GL）承担；
  macOS L1 待真机（GitHub runner 不冒充真实窗口，plan §5.4）。
