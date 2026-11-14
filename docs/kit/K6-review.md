# Kit K6 复核（Go-with-conditions）

> 复核时点：2026-11-14，开发机 macOS arm64 / Crystal 1.21.1。
> 结论先说：**逻辑与 API 层 Go-with-conditions；不得宣称平台完整或真实窗口已验证。**
> 架构复盘已发 GitHub issue：[#13](https://github.com/ShiningRay/tessell/issues/13)。

## 1. 复核范围

对照 [plan.md](plan.md) 的 K0–K6 退出条件，检查：

- 可选入口与依赖方向。
- 8 个 P0 组件 + VirtualList 适配。
- Root/Overlay/Theme/Primitives/事件/a11y。
- 状态、键盘、指针、主题/DPI、绘制命令、节点复用与文档。
- 消费者、静态文档站、gate 接入。
- 真实窗口、平台 IME、屏幕阅读器、平台剪贴板。

## 2. 证据

| 检查 | 命令/输出 | 结果 |
|---|---|---|
| Kit spec | `crystal spec spec/kit` | 86 examples / 0 failures |
| Gallery light | `kit_gallery --verify --frames=30 --theme=light` | `verify=pass`，select/dialog/tooltip/input=true |
| Gallery dark + DPI 1.5 | `--theme=dark --dpi=1.5` | `verify=pass` |
| 外部消费者 | `tools/kit_consumer_verify.sh` | `CORE_CONSUMER_OK`、`KIT_CONSUMER_VERIFY verify=pass` |
| 核心入口 | `crystal build src/tessell.cr --no-codegen` | 通过；核心入口无 kit require |
| 格式 | `crystal tool format --check ...` | 通过 |
| 静态站 | `crystal run tools/build_kit_site.cr` | 生成 `site/kit/*.html` |
| 视觉预览 | `site/previews/gallery-{light,dark}.png` | SVG→PNG，不是 GL 回读 |

## 3. 组件 DoD 矩阵

| 组件 | 状态/事件 | 键盘 | a11y | 主题/DPI | 绘制 | 单测 | 文档 | 真实窗口 |
|---|---|---|---|---|---|---|---|---|
| Button | 是 | Space/Enter | Button | 是 | 是 | 是 | 是 | 否 |
| Checkbox | 是 | Space | CheckBox | 是 | 是 | 是 | 是 | 否 |
| Text | 是 | 不适用 | Text | 是 | 是（截断/wrap） | 是 | 是 | 否 |
| Input | 是 | 光标/选区/剪贴板 | TextField | 是 | 是 | 是 | 是 | 否 |
| Select | 是 | Up/Down/Enter/Escape | ComboBox/ListBox/Option | 是 | 是 | 是 | 是 | 否 |
| Tooltip | 是 | 不抢焦点 | Tooltip | 是 | 是 | 是 | 是 | 否 |
| Dialog | 是 | 焦点陷阱/Escape | Dialog | 是 | 是 | 是 | 是 | 否 |
| ScrollView | 是 | 滚轮/翻页/Home/End | ScrollView | 是 | 是（裁切） | 是 | 是 | 否 |
| VirtualList | 是 | 滚轮/键盘 | List/ListItem + 逻辑总数 | 是 | 是 | 是 | 是 | 否 |

“真实窗口”一列全为否：本机 macOS 不能运行既有 Windows/WGL 路径，且没有可用的 macOS 后端。headless gallery、SVG 预览与 PaintList 断言不能替代真实窗口像素/IME/焦点证据。

## 4. 未关闭项

1. Windows + msys2 真实窗口 gate 未在本次 K6 运行；`tools/gate.ps1` 已加入 Kit 步骤但未执行。
2. 平台 IME composition 事件未接入 `Kit::Event`；Input 只有 `set_preedit/commit_preedit` API，C7 人工验证仍未关闭。
3. 屏幕阅读器 provider（UIA/AppKit/AT-SPI）未实现；只有进程内 A11y 树。
4. 平台剪贴板适配未实现；只有 `MemoryClipboard` 与注入接口。
5. GL 后端尚未消费 `DrawCmd` 的 RoundRect/StrokeRoundRect/Line；真实绘制路径未闭合。
6. SVG 预览文本由浏览器字体渲染，不证明 HarfBuzz/FreeType 上屏。
7. 变量行高 VirtualList 的 Kit 入口、滚动条拖动、菜单/多选等 P1 组件未交付。

## 5. 发布判断

- **可发布为“同仓可选组件库（logic/API preview）”**：核心入口不加载 Kit，外部消费者可编译，组件契约与测试齐全。
- **不可发布为“平台完整组件库”**：真实窗口、IME、屏幕阅读器、平台剪贴板、GL DrawList 闭环均未验证。
- 文档必须同时保留“已交付”和“未验证”两栏；不得用组件目录数量替代平台证据。

## 6. 下一步优先级

1. 核心 `Backend#draw_draw_list` / Canvas：让 Rect/RoundRect/Stroke/Clip 真正上屏，再接 Kit Painter。
2. Win32 平台事件适配：modifiers、wheel delta、pointer enter/leave/cancel、IME composition。
3. 核心布局/焦点作用域：measure/arrange 声明管线与 modal focus scope，减少 Kit 侧映射层。
4. 平台剪贴板与 IME provider。
5. P1 组件按真实需求排队，不按目录数量扩张。
