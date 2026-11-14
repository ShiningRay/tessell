# Tessell Kit 执行记录

> 本文件只记录实际做了什么、验证了什么、还没验证什么。计划与范围见 [plan.md](plan.md)；未验证项不得因为本文件写了“完成”而消失。

## 环境口径

- 当前开发机：macOS arm64，Crystal 1.21.1（Homebrew），FreeType/HarfBuzz 库可加载但既有 Windows FFI 结构在本机不可安全用于真实字体渲染。
- 既有 M0–M4 的真实窗口证据来自 Windows + msys2 ucrt64；本机不能替代运行 `tools/gate.ps1`。
- Kit 的纯逻辑、声明、绘制命令、布局、输入与 a11y 测试可在 macOS 运行；真实 GL 上屏仍以 Windows 证据为准。

## K0 契约与纵向原型

状态：进行中。

计划交付：

- `docs/kit/plan.md`、`component-contract.md`、`design-tokens.md`、`repository-strategy.md`。
- 可选入口 `require "tessell/kit"` 与 `Tessell::Kit`；核心入口 `require "tessell"` 不加载 Kit。
- `Kit::Theme`、`Kit::Component`、`Kit::Painter`、`Kit::Context`、`Kit::Root` 最小契约。
- `Kit::Button` 纵向原型：measure → arrange → emit declarations → paint → input activation → a11y。
- `spec/kit/` 纯逻辑测试与可选入口测试。

退出条件：

- 核心入口不加载 Kit；`require "tessell/kit"` 可单独编译。
- Button 的指针、键盘、disabled、单次激活、声明与 a11y 有 spec。
- 记录未验证项，尤其是真实窗口与平台 a11y。

验证记录将在每轮结束时追加。

### 迭代记录

#### K0

- 完成：`docs/kit/` 计划与契约文档；`src/tessell/kit.cr` 可选入口；Theme/token、Painter、Component、Context、Root、Button 最小闭环。
- 验证：`crystal spec spec/kit` → 19 examples / 0 failures；`crystal build src/tessell.cr --no-codegen` 通过；`crystal tool format --check` 通过。
- 未验证：真实窗口交互、GL 上屏、平台 a11y provider、Windows gate、完整 `crystal spec`（本机缺 Windows 字体）。
- 提交：`918e7f7`。

#### K1

- 完成：核心 `Input::Event` 增加 modifiers、wheel delta、PointerEnter/Leave/Cancel 与常用键码；`Router` 跟踪 enter/leave/cancel；`Node#clip` 与 `HitTest` 裁切；`DrawCmd` 增加 RoundRect/StrokeRect/StrokeRoundRect 与 radius/stroke_width；Kit 增加 `DrawListPainter`、核心 Theme 适配器与运行中换主题。
- 验证：`crystal spec` 选定核心/Kit 用例 238 examples / 0 failures（不含 Windows 字体依赖文件）；`crystal build src/tessell.cr --no-codegen` 与 `examples/app_demo.cr --no-codegen` 通过。
- 未验证：GL 后端尚未消费新增 DrawCmd；真实窗口裁切/圆角未上屏；核心 Event 的 modifiers 尚未由 Win32 示例填充。
- 提交：`5c7270e`。

#### K2

- 完成：`Kit::Container/Column/Row` 线性布局；`Kit::Text`（wrap/截断/max_lines）；`Kit::Checkbox`；`Kit::ScrollView`（裁切/滚动条/键盘）；`Kit::VirtualList` 适配（可见行、逻辑 children_count）；headless `examples/kit_gallery.cr` 与组件文档。
- 核心补层：`Node#clip` 命中继承、`A11y::Meta` 逻辑 children_count/scroll_offset、`Widgets::VirtualList#resize_viewport`、Kit Painter `line` 命令。
- 验证：选定核心/Kit 用例 261 examples / 0 failures；`kit_gallery --verify --frames=60 --theme=dark --dpi=1.5` 输出 `verify=pass`；`crystal build examples/kit_gallery.cr --no-codegen` 通过。
- 未验证：真实窗口/GL 上屏、滚动条拖动、变量行高 Kit 入口、Windows 像素回读。
- 提交：`cdcf4df`。

#### K3（本轮）

- 完成：`Kit::OverlayPlacement/OverlayEntry/OverlayHost/Barrier`；Root 统一处理浮层层级、模态屏障、Escape/外部点击/blur dismiss、焦点圈定与恢复；`Kit::Tooltip` hover 延迟；`Kit::Dialog` 标题/内容/动作区与焦点陷阱；`Kit::Select` 触发区 + Popover 列表、键盘/指针选择与选中回调。
- 验证：`crystal spec spec/kit` 62 examples / 0 failures；`kit_gallery --verify` 输出 `select=true dialog=true tooltip=true`；Dialog 背景点击被屏障阻断、Escape 恢复焦点、Tab 不逃逸。
- 未验证：真实窗口上屏、浮层像素裁切/翻转、Windows GL 路径、屏幕阅读器。
- 提交：待回填。
