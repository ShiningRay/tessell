# Tessell

Tessell 是 **Crystal 的 retained-mode 自绘 GUI 框架**：纯 FFI 绑定
FreeType / HarfBuzz / OpenGL，**无第三方运行时绑定**，渲染与文本栈全部
自绘，不依赖原生控件工具包。

## 当前状态（M0–M4）

| 阶段 | 状态 | 内容 | 证据 |
|---|---|---|---|
| M0 | 完成 | 本机基线、Isolated UI 上下文、WGL 窗口+GL 提交、文本 FFI（FT/HB）、IMM32 IME 探针、度量工具链 | [M0-summary](docs/evidence/M0-summary.md)、[M0-gate](docs/evidence/M0-gate.md) |
| M1 | 完成 | 两遍布局内核、文本测量缓存、retained 树与三级失效、DrawList/批次、稳态零分配 | [M1-iteration-log](docs/evidence/M1-iteration-log.md)、[M1-WP5-zero-alloc](docs/evidence/M1-WP5-zero-alloc.md) |
| M2 | 完成 | 输入焦点/命中测试、FT+HB 文本栈、字形图集/光栅化、文本上屏、IME 探针、万行虚拟列表、a11y 树、彩色 Emoji（Windows seguiemj 单样例，COLRv0/CPAL；已完成，带限定） | [M2-summary](docs/evidence/M2-summary.md)、[M2-gate](docs/evidence/M2-gate.md) |
| M3 | S1 收口 | 后端抽象+脏矩形部分提交、DPI/主题、真实 GL 万行滚动、路径填充 stencil/cover（even-odd，五角星与 CPU 参考逐像素对拍）；macOS 已有 SDL2/OpenGL 示例证据，Linux 未验证 | [M3-iteration-log](docs/evidence/M3-iteration-log.md)、[M3-gate-r4](docs/evidence/M3-gate-r4.md) |
| M4 | 完成 | UI DSL（S1）、打包 DLL 清单、真实示例应用+使用文档、一键质量门禁 | [M4-iteration-log](docs/evidence/M4-iteration-log.md)、[M4-WP4-gate](docs/evidence/M4-WP4-gate.md) |

当前 Windows 全量 spec：263 examples / 0 failures（M3-WP4 stencil/cover 新增 17 例：polygon 9 + path_gl 6 + backend_protocol +2；M2 彩色 Emoji 历史新增 13 例）。macOS 因通用 spec 仍有 Windows 字体路径依赖，当前使用 `spec/apps + spec/text_unix_smoke_spec.cr + spec/kit` 共 100 examples / 0 failures；测试分层与字体解析是跨平台 X0 的首项工作。

> M2 Emoji 已完成（带限定）：Windows + `C:/Windows/Fonts/seguiemj.ttf` 单一样例 +
> COLRv0/CPAL + glReadPixels 数值回读；R8 灰度路径保留；不得外推为
> 全域/跨平台/严格零分配。M3 为 S1 范围收口，不等于全平台完成。详见上表证据文件的「未验证」清单。

## Kit 组件库（K0–K6）

组件库以同仓可选入口提供，核心入口不聚合：

```crystal
require "tessell/kit"

button = Tessell::Kit::Button.new(
  Tessell::UI::UiKey.root.child(1_u64),
  "Save",
  Tessell::Kit::Variant::Primary
)
```

已交付：Button、Checkbox、Text、Input、Select、Tooltip、Dialog、ScrollView，
以及 VirtualList 适配、Root Overlay、主题/尺寸 token、grapheme 光标/选区与
剪贴板接口。组件文档见 [docs/kit/index.md](docs/kit/index.md)；
计划、契约与执行记录见 [docs/kit/plan.md](docs/kit/plan.md)、
[docs/kit/component-contract.md](docs/kit/component-contract.md)、
[docs/kit/execution.md](docs/kit/execution.md)。

无窗口组件矩阵、示例应用、外部消费者与静态文档站：

```bash
crystal run examples/kit_gallery.cr -- --verify --frames=30 --theme=dark --dpi=1.5
./tools/run_kit_demo.sh examples/app_calculator.cr
./tools/run_kit_demo.sh examples/app_text_editor.cr
bash tools/kit_consumer_verify.sh
crystal run tools/build_kit_site.cr   # 输出 site/index.html
```

示例应用文档：[docs/kit/apps.md](docs/kit/apps.md)。计算器与文本编辑器使用
SDL2 窗口 + OpenGL；SDL2 目前只存在于 `examples/` 宿主，计划提升为可选
`require "tessell/platform/sdl2"`，不进入核心默认依赖。

预览：[light](site/previews/gallery-light.png)、[dark](site/previews/gallery-dark.png)。

复核与内核建议：[K6-review](docs/kit/K6-review.md)、
[GitHub issue #13](https://github.com/ShiningRay/tessell/issues/13)。

限制：Windows SDL2 窗口、Linux GUI/GL、平台 IME 预编辑、屏幕阅读器 provider、
三平台打包仍未验证；不得把 headless gallery 当作真实窗口证据。
三平台分级方案与工作包见 [docs/cross-platform-plan.md](docs/cross-platform-plan.md)。

## 快速开始

环境：Crystal 1.21+；Windows 10/11 x64、macOS 13+、Linux x64。

Windows（MSYS2 UCRT64）：

```powershell
$env:PATH="C:\msys64\ucrt64\bin;$env:PATH"
crystal build examples/app_demo.cr -o bin/app_demo.exe
bin/app_demo.exe --frames=120 --verify
```

macOS（已安装 Crystal 1.21+；Homebrew 依赖）：

```bash
brew install sdl2 freetype harfbuzz
./tools/run_kit_demo.sh examples/app_calculator.cr
crystal spec spec/apps spec/text_unix_smoke_spec.cr spec/kit
```

Linux（已安装 Crystal 1.21+；Ubuntu/Debian，X11/XWayland）：

```bash
sudo apt install libsdl2-dev libfreetype6-dev libharfbuzz-dev libgl1-mesa-dev
crystal build src/tessell.cr --no-codegen
crystal run examples/app_calculator.cr
```

- 字体要求：Windows 示例默认 `C:/Windows/Fonts/msyh.ttc`；macOS/Linux 示例会自动探测系统字体，也可用 `TESSELL_FONT` 覆盖。
- 三平台支持级别与待验证项见 [docs/cross-platform-plan.md](docs/cross-platform-plan.md)。
- 一键质量门禁（目前仅 Windows PowerShell；三平台 `gate.sh`/CI 是跨平台 X2 工作）：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/gate.ps1
```

- 完整参数、交互与判据说明见 [docs/usage.md](docs/usage.md)。

## 架构

| 层 | 目录 | 职责 |
|---|---|---|
| core | `src/tessell/core/` | retained Node 树；三级失效 Layout/Paint/CompositeOnly |
| layout | `src/tessell/layout.cr` | 两遍布局（约束下行、尺寸上行），纯函数内核 |
| text | `src/tessell/text/` | FreeType/HarfBuzz、字形 atlas、rasterizer、measurer |
| render | `src/tessell/render/` | DrawList、Dirty 脏矩形、Backend 抽象、GL、Theme、Dpi |
| platform（计划） | `src/tessell/platform/` | 可选窗口/事件/DPI/剪贴板/IME 宿主；SDL2 不进入核心默认依赖 |
| input | `src/tessell/input/` | event、hit_test、focus、Router 事件分发 |
| widgets | `src/tessell/widgets/` | VirtualList 等基础控件 |
| a11y | `src/tessell/a11y/` | A11yNode 无障碍树（进程内） |
| ui | `src/tessell/ui/` | key/builder/apply 声明式 DSL 与状态协调 |

数据流与线程模型见 [docs/architecture.md](docs/architecture.md)。

## 证据索引

- [M0-summary](docs/evidence/M0-summary.md)：M0 各 WP 证据链与 Go（条件）建议。
- [M2-summary](docs/evidence/M2-summary.md)：M2 WP 状态与 C1–C9 条件台账。
- [M3-iteration-log](docs/evidence/M3-iteration-log.md)：M3 三次迭代收口记录。
- [M3-gate-r4](docs/evidence/M3-gate-r4.md)：M3 收口门禁终审（Go-with-conditions）。
- [M4-iteration-log](docs/evidence/M4-iteration-log.md)：M4 迭代 4 任务与 gate 14/14 证据。
- [M4-WP4-gate](docs/evidence/M4-WP4-gate.md)：一键门禁 14 项与 DoD 对照。
- [verify-M4-WP3-WP4](docs/evidence/verify-M4-WP3-WP4.md)：WP3/WP4 独立核验。
- [M2-WP2c-zero-alloc-criterion](docs/evidence/M2-WP2c-zero-alloc-criterion.md)：零分配判据 A/B 定义。
- [M2-WP2-emoji-color](docs/evidence/M2-WP2-emoji-color.md)：彩色 Emoji 实现、反证与限定。
- [verify-M2-WP2-emoji-color](docs/evidence/verify-M2-WP2-emoji-color.md)：彩色 Emoji 独立核验（PASS-WITH-DEFECTS）。
- [M3-WP4-stencil-cover](docs/evidence/M3-WP4-stencil-cover.md)：路径 stencil/cover 实现与正负例证据。
- [verify-M3-WP4](docs/evidence/verify-M3-WP4.md)：路径 stencil/cover 独立核验（PASS-WITH-DEFECTS）。
- [cross-platform-plan](docs/cross-platform-plan.md)：Windows/macOS/Linux 的 L0–L3 支持矩阵、Platform::Host 方案与 X0–X8 工作包。

## 已知限制（如实）

- 真实键盘 IME 组合输入未手测（C7，需人工）；程序化 IME 注入不可用。SDL2 只能稳定提供已提交文本，预编辑/候选窗需 L3 平台适配。
- macOS 已有 SDL2/OpenGL 示例真实窗口证据；Windows SDL2 与 Linux GUI 尚未验证，不能据此宣称三平台完成。
- UIA/NSAccessibility/AT-SPI provider 未实现；a11y 仅进程内 A11yNode 树，未接屏幕阅读器。
- Emoji 彩色仅 msys2/Windows + `seguiemj.ttf` 单样例、COLRv0/CPAL、glReadPixels 数值回读；R8 灰度路径保留。Noto Color Emoji/Bitmap 彩色（CBDT/CBLC）与 macOS/Linux 彩色未验证。
- 安装器、代码签名、干净 VM 端到端未做；跨机器性能/零分配基线未建。
- 零分配判据为 A `delta_work < 1000`、B `delta_work <= 256`（3 窗 max），
  **不是严格 0**；本机 16–96B GC/簿记噪声可落任意窗。

## License

项目本体 MIT（见 [LICENSE](LICENSE)，Copyright (c) 2026 ShiningRay）。
依赖许可（FreeType / HarfBuzz / Boehm GC / msys2 运行时 DLL / 字体）见
[docs/evidence/M4-WP2-licensing.md](docs/evidence/M4-WP2-licensing.md)。
Windows 系统字体（如 `msyh.ttc`）不随包分发，运行时依赖用户本机已装字体。
