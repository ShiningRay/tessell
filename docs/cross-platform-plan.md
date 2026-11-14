# Tessell 跨平台方案与实施计划（Windows / macOS / Linux）

> 状态：2026-11-14 修订，计划基线 `4106f2b`。本文只修订方案与计划，不宣称三平台已经完成。
> 关系：核心架构见 [architecture.md](https://github.com/ShiningRay/tessell/blob/main/docs/architecture.md)；Kit 的 K0–K6 计划见 [kit/plan.md](https://github.com/ShiningRay/tessell/blob/main/docs/kit/plan.md)；本文接管 K6 之后的跨平台收口，并替代 [roadmap.md](https://github.com/ShiningRay/tessell/blob/main/docs/roadmap.md) 中“Windows 先行、macOS/Linux 后置”的平台顺序假设。
> 证据边界：macOS 已有真实窗口与文本上屏证据；Windows 有 M0–M4 的 Win32/WGL 证据；Linux 尚无 GUI 运行证据。未运行的项目一律标为未验证。

## 0. 结论先行

1. **跨平台不是把 Win32 代码复制三遍。** 保留自绘核心，把“窗口/事件/剪贴板/DPI/IME”收敛为可选的 `Tessell::Platform` 平台层；`Render::Backend` 继续只负责渲染。
2. **SDL2 从示例宿主提升为可选的官方平台宿主，但不进入核心默认依赖。** 新增 `require "tessell/platform/sdl2"`；核心入口 `require "tessell"` 不加载 SDL2，`shard.yml` 不新增 SDL2 依赖。
3. **先做可验证的 L1，再做可交付的 L2。** L1 = 三平台真实窗口、输入、文本、GL 上屏；L2 = DPI、剪贴板、字体回退、基础 IME、打包。完整 IME 预编辑与平台无障碍 provider 单独列为 L3，不阻塞 L1/L2。
4. **最大的风险不是 OpenGL，而是 IME、无障碍和字体差异。** SDL2 能解决窗口/上下文/普通文本输入，但不能单独解决 macOS/Windows/Linux 的完整 IME 预编辑与屏幕阅读器。
5. **先建立跨平台质量门，再扩组件。** 没有三平台 CI、真实窗口证据和字体测试分层，不做 P1 组件扩张。

## 1. 现状与证据

| 平台 | 已有证据 | 关键缺口 |
|---|---|---|
| macOS arm64 | SDL2/OpenGL 真实窗口跑通计算器与文本编辑器；FreeType LP64 布局修复；`spec/apps + spec/text_unix_smoke + spec/kit` 100 examples / 0 failures | 完整 `crystal spec` 仍受 Windows 字体路径影响；无 CI；无 IME 预编辑、平台剪贴板已验证的跨平台门禁、无打包 |
| Windows 10/11 x64 | M0–M4 的 Win32/WGL 真实窗口、文本、脏区、DPI、路径填充与 gate 证据 | SDL2 宿主未构建/运行；`package.ps1` 与 `gate.ps1` 仅 Windows；无 Linux/macOS 对等门禁 |
| Linux | 仅有工具与静态站可在非 Windows 构建的局部事实 | 无 GUI 运行证据；SDL2/GLX/EGL、X11/Wayland、字体与输入法均未验证 |
| 核心 | `GLBackend` 使用 OpenGL 2.1 兼容路径；`@[Link]` 已按 Windows/macOS/Linux 分支；FreeType/HarfBuzz FFI 已按 LP64/LLP64 分支 | 平台层尚未正式化；字体发现散落在 examples/spec；测试大量硬编码 `C:/Windows/Fonts/...` |

### 1.1 现有 SDL2 宿主的定位

当前 [examples/lib/kit_sdl_host.cr](https://github.com/ShiningRay/tessell/blob/main/examples/lib/kit_sdl_host.cr) 已包含：

- 窗口创建、OpenGL context、帧循环、resize、截图。
- SDL 事件到 `Tessell::Input::Event` 的映射。
- `SDL_GetClipboardText` / `SDL_SetClipboardText`。
- 通过 `SDL_GL_GetDrawableSize` 推导 Retina/高 DPI 的 drawable scale。
- 字体候选路径与示例生命周期。

它是“示例宿主”，不是稳定库 API：包含 `KitDemoApp`、示例专用参数和 Kit 依赖。跨平台方案要把通用部分上移，示例只保留应用装配。

## 2. 目标、支持矩阵与支持级别

### 2.1 支持级别

| 级别 | 定义 | 必须证据 | 不包含 |
|---|---|---|---|
| L0 构建/逻辑 | 三平台都能编译核心、Kit、纯逻辑 app；headless 组件矩阵通过 | CI 编译日志、`crystal spec` 选定套件、headless gallery 输出 | 真实窗口、像素、IME |
| L1 真实窗口 | 三平台都能创建窗口、GL context、处理鼠标/键盘/滚轮、显示文本与组件 | 真实窗口启动日志、截图、`--frames`/`--verify`、像素回读 | 完整 IME、屏幕阅读器、安装器 |
| L2 可交付 | 三平台 DPI、剪贴板、字体回退、基础 IME、可分发产物 | 平台矩阵表、干净机器/容器运行、产物清单 | 完整预编辑、UIA/NSAccessibility/AT-SPI |
| L3 完整桌面 | 各平台 IME 预编辑/候选窗、无障碍 provider、签名/公证 | 平台 IME 人工记录、a11y 客户端验收、签名产物 | 移动端、WebView |

**本轮把 L1 + L2 作为跨平台目标；L3 单列，不隐藏在“已跨平台”里。**

### 2.2 目标平台矩阵

| 维度 | 首版承诺 | 后续/不承诺 |
|---|---|---|
| 架构 | 64-bit：x86_64 与 arm64 | 32-bit 不支持（FreeType 断言按 64-bit 指针） |
| Windows | Windows 10 1809+ / Windows 11，MSYS2 UCRT64 | ARM64 Windows 后续 |
| macOS | macOS 13+，arm64 与 x86_64 | macOS 12 及更早不承诺 |
| Linux | Ubuntu 22.04/24.04、Debian 12/13，glibc，x86_64/arm64 | 其他发行版需单独验证 |
| 图形 | OpenGL 2.1 兼容上下文 | OpenGL 3.3 core、Metal、Vulkan 后续 |
| Linux 显示 | X11 与 XWayland 为基线 | 原生 Wayland 后续；不得把 XWayland 当原生 Wayland |
| 工具链 | Crystal 1.21+；SDL2 2.x；FreeType/HarfBuzz 系统库 | 版本矩阵在 CI 中固定 |
| 文本 | 普通 Unicode 文本、CJK、基础 Emoji 回退 | 彩色 Emoji 三平台完全一致不承诺 |
| IME | 已提交文本（committed text） | 预编辑/候选窗按 L3 平台适配 |
| 无障碍 | 进程内 A11y 树 | 平台 provider 按 L3 |

### 2.3 非目标

- 不把 SDL2 放进 `Tessell::Render::Backend`，不强制所有消费者安装 SDL2。
- 不在本轮做原生 Wayland、Metal、Vulkan 或 OpenGL core profile。
- 不在 L1 承诺完整中文/日文/韩文 IME 预编辑、候选窗与屏幕阅读器。
- 不承诺三平台彩色 Emoji 完全一致；先保证不崩溃、有合理回退。
- 不做移动端、WebView、DOM/CSS、Web 组件运行时。

## 3. 方案

### 3.1 分层与依赖方向

```text
应用 / Kit
   │  Input::Event、Root、PaintList
   ▼
Platform::Host（可选：SDL2 / Win32 / Cocoa / X11-Wayland）
   │  窗口、事件循环、DPI、剪贴板、IME、光标
   ▼
Render::Backend（GLBackend）
   │  DrawList、atlas、scissor、stencil
   ▼
OpenGL 2.1 兼容上下文

文本栈：FreeType + HarfBuzz（独立于平台宿主）
```

依赖规则：

- `Tessell::Platform` 不依赖 Kit；Kit/示例依赖平台宿主。
- `Render::Backend` 不知道窗口系统；平台宿主不知道组件。
- 核心入口不自动加载任何平台宿主。
- 平台宿主可以可选依赖 SDL2，但 SDL2 不得成为核心入口的隐式依赖。

### 3.2 为什么不把 SDL2 塞进 `Render::Backend`

`Tessell::Render::Backend` 的职责是渲染管线：`init/resize/begin_frame/sync_atlas/draw_text/draw_draw_list/end_frame`。SDL2 的职责是窗口、GL context、事件与系统集成。二者混在一起会导致：

1. 所有消费者被迫安装 SDL2，包括 headless、服务端和纯逻辑测试。
2. 平台实现被写死，无法再提供 Win32/Cocoa/GLFW 等宿主。
3. Kit 组件被迫感知平台 FFI，违反现有仓策略。
4. 测试无法用假宿主验证事件与生命周期。

因此新增的是 `Platform::Host`，不是新的 `Render::Backend`。

### 3.3 `Platform::Host` 契约（形状，未冻结）

```crystal
require "tessell"

module Tessell::Platform
  abstract class Host
    abstract def logical_size : Size
    abstract def drawable_size : Size
    abstract def scale : Float32
    abstract def poll_event : Input::Event?
    abstract def clipboard : Platform::Clipboard
    abstract def ime : ImeCapabilities
    abstract def close : Nil
  end

  # OpenGL 宿主在 Host 上增加 make_current/swap_buffers；
  # 未来的 Metal/Vulkan 宿主不实现这组 GL 方法。
  abstract class GLHost < Host
    abstract def make_current : Nil
    abstract def swap_buffers : Nil
  end

  class SDL2 < Host
    # 可选入口：require "tessell/platform/sdl2"
  end
end
```

首个实现只覆盖 GL 宿主需要的最小能力：

- 窗口创建/销毁、标题、resizable、高 DPI。
- `poll_event`：Quit/Close、resize、key down/up、text input、mouse move/down/up、wheel、focus/blur。
- `logical_size` / `drawable_size` / `scale`：布局用逻辑像素，绘制用 drawable 像素。
- `clipboard`：平台层定义 `Platform::Clipboard`（get/set）；Kit 只做适配，避免 `Platform → Kit` 反向依赖；测试用 `MemoryClipboard`。
- `ime`：至少报告 `committed_text` 能力；预编辑能力按平台报告 `unsupported`，不允许假装支持。
- 截图/像素回读：只作为测试/示例工具，不进入组件 API。

后续可扩展但不在首版：多窗口、光标形状、文件对话框、菜单、拖放、原生 IME 候选窗、屏幕阅读器 provider。

### 3.4 平台宿主策略对比

| 策略 | 覆盖 | 优点 | 代价 | 决策 |
|---|---|---|---|---|
| **A. SDL2 可选宿主** | Win/Mac/Linux | 已有 macOS 验证；窗口/GL/事件/剪贴板齐全；实现量最小 | IME 预编辑、a11y、原生菜单弱；多一个系统库 | **L1/L2 基线** |
| B. 原生 Win32/WGL | Windows | 现有证据最完整；IME/IMM32 可控 | 仅 Windows；样板多 | 保留为 Windows 参考/IME 适配路径 |
| C. Cocoa/NSOpenGL | macOS | 原生 IME/a11y 可控 | 新写宿主；OpenGL deprecated | L3 需要时再评估 |
| D. X11/Wayland 原生 | Linux | 原生显示/IME 可控 | 两套显示服务器；工作量大 | L3 需要时再评估 |
| E. GLFW | 三平台 | API 简洁 | 与 SDL2 重叠；无现有集成 | 不采用，避免二次迁移 |

**结论：A 作为跨平台基线；B 保留现有 Windows 证据并为 IME 提供参考；C/D 只作为 L3 的平台补洞，不并行重写。**

### 3.5 OpenGL 策略

- 继续使用当前 `GLBackend` 的固定管线兼容路径，最低 OpenGL 2.1；它已在 macOS 26.6 + SDL2 实测。
- Windows 继续用 `opengl32`，macOS 用 `OpenGL` framework，Linux 用 `libGL`；链接分支已存在。
- 不在本轮迁 OpenGL 3.3 core；固定管线能覆盖矩形/文本/圆角/描边/路径 stencil，迁移收益低、风险高。
- macOS 的 OpenGL 已 deprecated 但仍可用；在支持矩阵中明确“当前可用，不等于长期承诺”。Metal 后端是独立后续项。
- Linux 以 X11/XWayland + Mesa 为基线；原生 Wayland 的 EGL/GL 上下文作为 L3 验证，不与 X11 混为一谈。

### 3.6 文本、字体与 Emoji

当前 `FtMeasurer.open` 和多个 spec/example 硬编码 Windows 字体路径，这是跨平台的第一道硬障碍。方案：

1. 新增 `Text::FontCatalog` / `Platform::Fonts`：
   - Windows：`Segoe UI`、`Microsoft YaHei`、`Segoe UI Emoji`、`Arial`。
   - macOS：`Helvetica`/`SF Pro`、`PingFang SC`、`Apple Color Emoji`、`Arial Unicode`。
   - Linux：`DejaVu Sans`、`Noto Sans`、`Noto Sans CJK`、`Noto Color Emoji`。
   - 统一支持 `TESSELL_FONT` 覆盖；找不到字体时返回明确错误，不静默回退到空字体。
2. 测试字体：
   - 通用测试使用 `TESSELL_TEST_FONT`；CI 按平台安装 DejaVu/Noto。
   - 平台特有测试加 `windows`/`macos`/`linux` tag；缺字体时 `pending` 并打印原因，不伪装通过。
   - 需要固定度量的测试使用可再分发字体 fixture（OFL/DejaVu 许可），不把系统字体复制进仓库。
3. Emoji：
   - 现有 COLRv0/CPAL 路径继续保留；Windows Segoe UI Emoji 是已验证样例。
   - Linux Noto Color Emoji 常见 CBDT/CBLC，macOS Apple Color Emoji 是 sbix；在 L2 先做“可显示/可回退”，L3 再补格式。
   - 彩色 Emoji 不支持时回退单色或豆腐块，必须可观测，不得崩溃。

### 3.7 IME 策略

SDL2 只稳定提供 `SDL_TEXTINPUT`（已提交文本），不提供可靠的预编辑事件。这决定了：

- **L1/L2**：保证普通 Unicode 文本输入；`Kit::Input` 的 `set_preedit/commit_preedit` 仍可由测试驱动，但平台预编辑显示标记为“未接入”。
- **L3 前置 spike**：比较三条路线，再决定：
  1. 迁 SDL3：原生 text editing/composition 事件与候选矩形 API；
  2. Windows 原生 IMM32（已有探针基础）；
  3. macOS NSTextInputClient / Linux IBus 或 GTK IM context。
- 候选窗位置、组合取消、重复提交、死键、输入法切换必须有平台人工记录；没有记录不得写“IME 完成”。

| 平台 | L1/L2 | L3 候选方案 | 风险 |
|---|---|---|---|
| Windows | SDL2 committed text | IMM32 + WndProc/IME 消息，接 SDL 窗口句柄 | 组合消息与 SDL 事件顺序、候选窗位置 |
| macOS | SDL2 committed text | Cocoa NSTextInputClient 宿主或 SDL3 | OpenGL/Cocoa 生命周期、候选窗定位 |
| Linux | SDL2 committed text | IBus/Fcitx + GTK/Qt IM context 或 SDL3 | X11/Wayland 差异、输入法守护进程 |

### 3.8 无障碍

进程内 A11y 树保留；平台 provider 单列 L3：

- Windows：UIA provider（COM vtable、跨线程封送）。
- macOS：NSAccessibility。
- Linux：AT-SPI。

在 L1/L2 文档中必须写“进程内树，不可被屏幕阅读器读取”，不得用组件目录或 a11y 元数据冒充平台支持。

### 3.9 打包与分发

| 平台 | 首版产物 | 依赖策略 | 验证 |
|---|---|---|---|
| Windows | zip + exe + DLL 闭包 | 现有 `package.ps1` 扩展 SDL2.dll、FreeType/HarfBuzz 依赖；`objdump` 闭包 | 无 msys2 PATH 的干净目录运行 |
| macOS | `.app` 或带 dylib 的 tar | `otool -L` + `install_name_tool` 打包 FreeType/HarfBuzz/SDL2；签名/公证后续 | 干净用户目录运行；Gatekeeper 记录 |
| Linux | tar.gz 或 AppImage | `ldd` 收集；依赖系统 GL/字体；AppImage 需 FUSE 说明 | Ubuntu 22.04/24.04 容器/真机运行 |

不在首版承诺安装器、自动更新、商店发布。

## 4. 工作包、顺序与工期

估算为单人全职 pd，仅作排期参考，未实测。L1 与 L2 是最小跨平台承诺；L3 单独排期。

### 4.1 工作包

| ID | 工作包 | 内容 | 依赖 | 估算 |
|---|---|---|---|---|
| X0 | 基线清理与测试分层 | 冻结支持矩阵；拆 `spec/core`、`spec/text`、`spec/platform`、`spec/visual`；移除通用 spec 的 Windows 字体路径；加 `TESSELL_TEST_FONT`；平台 tag；跨平台 gate 脚本骨架 | 无 | 2–4 pd |
| X1 | Platform::Host 与 SDL2 提取 | 新增 `src/tessell/platform/host.cr`、`src/tessell/platform/sdl2.cr`、`src/tessell/platform/sdl2/host.cr`；迁移 `examples/lib/kit_sdl_host.cr` 的通用部分；示例改为装配；加假宿主测试 | X0 | 4–6 pd |
| X2 | 三平台 L0 CI | GitHub Actions matrix：Ubuntu/Windows/macOS；安装 Crystal、SDL2、FreeType/HarfBuzz、Xvfb/Mesa；编译核心/Kit/apps/demos；headless gallery；产物日志 | X0, X1 | 4–6 pd |
| X3 | 三平台真实窗口 L1 | 三平台运行计算器/编辑器/Kit gallery；`--frames`、截图、鼠标/键盘/滚轮、resize、关闭；GL 像素回读；记录 DPI/GL 版本 | X1, X2 | 5–8 pd |
| X4 | 字体、DPI、Emoji 跨平台 | FontCatalog/字体发现、测试字体、CJK/Emoji 回退、DPI 1.0/1.5/2.0、Linux/macOS/Windows 字体矩阵 | X0, X1 | 4–7 pd |
| X5a | IME 路线 spike | SDL3 vs 原生适配对比；选定 L3 路线；输出决策记录与最小探针 | X1, X3 | 2–3 pd |
| X5b | Windows IME 预编辑 | IMM32/窗口消息 → `Input::Event` 的 preedit/commit/cancel；候选窗位置 | X5a | 3–5 pd |
| X5c | macOS IME 预编辑 | Cocoa NSTextInputClient 或 SDL3 方案；候选窗与生命周期 | X5a | 4–6 pd |
| X5d | Linux IME 预编辑 | IBus/Fcitx + GTK/Qt IM context 或 SDL3；X11/Wayland 差异 | X5a | 4–6 pd |
| X6 | 三平台打包 | Windows 扩展 DLL 闭包；macOS dylib bundle；Linux tar/AppImage；干净环境运行 | X3, X4 | 5–9 pd |
| X7 | 平台无障碍 provider | UIA / NSAccessibility / AT-SPI；独立验收客户端；不阻塞 L1/L2 | X3 | 10–20+ pd |
| X8 | 跨平台发布门与文档 | 三平台证据表、支持矩阵、已知限制、CI badge、发布检查单 | X2–X6 | 2–3 pd |

### 4.2 阶段

| 阶段 | 工作包 | 目标 | 估算 |
|---|---|---|---|
| A 跨平台可运行（L1） | X0 → X1 → X2 → X3 | 三平台真实窗口、输入、文本、GL 上屏 | 15–24 pd |
| B 跨平台可交付（L2） | X4 → X5a → X6 → X8 | 字体/DPI/基础 IME/打包/发布门 | 13–22 pd |
| C 完整桌面（L3） | X5b/c/d → X7 | 平台 IME 预编辑、候选窗、屏幕阅读器、签名 | 20–40+ pd |

### 4.3 依赖与并行边界

- X0 必须先于 X1/X2；否则测试与宿主会继续绑定 Windows。
- X1 与 X2 可部分并行：Host 契约稳定后即可搭 CI 骨架；但 CI 的 GUI 步骤依赖 X1。
- X3 必须用真实硬件/真实显示环境；CI 的 Xvfb/dummy 不能替代 L1 证据。
- X4 与 X3 可并行，但字体 API 冻结前不要改 Kit 文本组件。
- X5a 必须在 X6 打包前完成，因为 IME 路线可能影响宿主依赖（SDL2 vs SDL3 vs 原生）。
- X7 不与 L1/L2 抢同一核心接口；provider 只读 A11y 树/焦点状态。

## 5. 验证与门禁

### 5.1 每平台 L0

```bash
crystal build src/tessell.cr --no-codegen
crystal build examples/app_demo.cr --no-codegen
crystal build examples/app_calculator.cr --no-codegen
crystal build examples/app_text_editor.cr --no-codegen
crystal spec spec/core spec/kit spec/apps
crystal run examples/kit_gallery.cr -- --verify --frames=30
```

通过条件：编译 0 退出；spec 0 failures；gallery 输出 `KIT_GALLERY_VERIFY verify=pass`。Windows 保留 `tools/gate.ps1`，新增 `tools/gate.sh`（或跨平台 Crystal 脚本），两者共享同一组判据。

### 5.2 每平台 L1

- 窗口创建成功，`--frames=3` 退出 0。
- 截图非空，像素回读与全量重绘一致；至少验证一个负例（裁切/弹层/滚动）。
- 键盘：Tab/Shift+Tab、Enter/Space、方向键、Escape、Backspace、文本输入。
- 鼠标：click、drag、wheel、resize、关闭。
- DPI：1.0/1.5/2.0（平台支持范围内）。
- 记录 GL 版本、renderer、drawable size、scale、字体路径。

### 5.3 每平台 L2

- 字体发现不依赖硬编码路径；缺字体时错误明确。
- 剪贴板读写；Windows/macOS/Linux 各一次。
- 基础 IME committed text；预编辑状态按能力表报告。
- 干净目录/容器运行打包产物；记录依赖清单与 SHA256。
- 文档包含该平台截图、运行命令、已知限制。

### 5.4 CI 矩阵

| 任务 | Ubuntu | Windows | macOS |
|---|---|---|---|
| Crystal 安装 | 官方 tarball/action | MSYS2 UCRT64 | Homebrew/官方 tarball |
| 系统依赖 | `libsdl2-dev libfreetype6-dev libharfbuzz-dev libgl1-mesa-dev xvfb` | `mingw-w64-ucrt-x86_64-SDL2 freetype harfbuzz` | `brew install sdl2 freetype harfbuzz` |
| L0 | headless + `xvfb-run` | headless | headless |
| L1 | Xvfb + Mesa llvmpipe；真机另跑 | Windows runner 或 self-hosted；记录是否有交互桌面 | self-hosted macOS 或本地真机；runner 不冒充真实窗口 |
| 产物 | log + screenshot | log + screenshot | log + screenshot |

CI 只证明“可构建/可跑”；L1 的“真实窗口”必须有人工或 self-hosted 证据，不能把 dummy video driver 当真实窗口。

## 6. 风险与控制

| 风险 | 影响 | 控制 |
|---|---|---|
| SDL2 不提供可靠 IME 预编辑 | 中文/日文输入体验不完整 | L1/L2 明确 committed text；X5a 早做 SDL3/原生决策；不写“IME 完成” |
| Linux X11/Wayland 差异 | 窗口/输入/GL 行为不一致 | 先 X11/XWayland 基线；Wayland 单列；CI 用 Xvfb；真机记录 |
| macOS OpenGL deprecated | 未来系统可能移除 | 当前支持矩阵写明；Metal 后端独立评估；不阻塞 L1 |
| 三平台字体/Emoji 差异 | 文本布局/截图不一致 | FontCatalog + 测试字体 + 回退；彩色 Emoji 分格式验收 |
| 平台真实窗口 CI 不可用 | 把 headless 当真实证据 | L1 必须 self-hosted/真机；CI 只做 L0/L2 自动项 |
| 测试仍硬编码 Windows 路径 | 非 Windows 全量 spec 不可跑 | X0 先拆测试与字体解析；平台 tag/pending 明确 |
| 打包动态库/签名 | 产物不可移植 | 三平台闭包清单；干净环境验证；签名/公证单列 |
| 过早做 P1 组件 | 平台债扩大 | 跨平台 L1/L2 未达标前不扩组件 |

## 7. 文档与发布规则

- 每个平台的支持声明必须附证据：命令、截图/日志、日期、Crystal/SDL2/GL/字体版本。
- `README` 的“当前状态”按 L0/L1/L2/L3 标注，不写笼统的“跨平台完成”。
- `docs/kit/plan.md` 只保留 K0–K6 历史；K6 之后的跨平台工作以本文为准。
- 新增平台/宿主时先加 `Platform::Host` 契约测试，再改示例；禁止在组件里 `require "sdl2"`。
- 发布前跑三平台 L0；L1/L2 未完成的平台不得出现在“支持”列，只能列“待验证/实验”。

## 8. 立即执行顺序（建议）

1. **X0（2–4 pd）**：冻结本文矩阵；拆测试目录；把 `C:/Windows/Fonts/...` 从通用 spec 中清除；加 `TESSELL_TEST_FONT` 与平台 tag。
2. **X1（4–6 pd）**：抽 `Platform::Host` + `Platform::SDL2`；示例只保留应用装配；核心入口与 `shard.yml` 不出现 SDL2。
3. **X2（4–6 pd）**：三平台 L0 CI 先绿；Windows 用 MSYS2，Linux 用 Xvfb，macOS 用 Homebrew。
4. **X3（5–8 pd）**：三平台真实窗口 L1；先 Windows/Linux 补证据，再汇总 macOS 已有证据。
5. **X4（4–7 pd）**：字体/DPI/Emoji 矩阵；再决定是否扩 P1 组件。
6. **X5a（2–3 pd）**：IME 路线 spike；在此之前不承诺预编辑。

## 9. 待确认事项

以下问题会实质改变工期，但在当前上下文无法从代码/证据推断；本文按“L1/L2 先交付、L3 单列”的假设修订：

1. 跨平台 1.0 是否必须包含三平台完整 IME 预编辑/候选窗？若是，L3 的 X5b/c/d 要并入 1.0，工期显著增加。
2. 是否必须包含屏幕阅读器（UIA/NSAccessibility/AT-SPI）？若是，X7 不能后置。
3. Linux 是否要求原生 Wayland（非 XWayland）？若是，需增加独立显示后端与输入法验证。
4. macOS 是否要求 Intel + arm64 双架构、签名/公证？这会改变打包与 CI 成本。
5. 是否允许把 SDL2 作为可选系统依赖（而非核心内置）？本文按允许处理；若不允许，所有平台宿主需原生实现，工期翻倍。

## 10. 证据与未验证项

- 已读：`README.md`、`docs/architecture.md`、`docs/roadmap.md`、`docs/kit/plan.md`、`docs/kit/execution.md`、`docs/kit/K6-review.md`、`docs/kit/apps.md`、`docs/research/m3-platform-matrix.md`、`src/tessell/render/gl/gl_backend.cr`、`src/tessell/text/ffi/freetype.cr`、`src/tessell/text/ffi/harfbuzz.cr`、`examples/lib/kit_sdl_host.cr`、`tools/gate.ps1`、`tools/package.ps1`。
- 已实证：macOS SDL2/OpenGL 真实窗口与文本上屏；FreeType LP64 修复；选定 Kit/apps 套件 100/0；三平台链接分支存在于源码。
- 未实测：Windows SDL2 构建/窗口；Linux 编译/GUI/GL；三平台 CI；SDL2/系统字体版本矩阵；SDL3 IME；macOS/Linux 打包；UIA/NSAccessibility/AT-SPI。
- 本文只修订方案与计划，未改代码、未新增依赖、未提交实现。
