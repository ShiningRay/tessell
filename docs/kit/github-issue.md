# Tessell Kit K0–K5 复盘：内核契约缺口与下一阶段建议

## 背景

按 `docs/kit/plan.md` 完成 K0–K5：同仓可选入口 `require "tessell/kit"`、8 个 P0 组件、VirtualList 适配、Root Overlay、主题 token、grapheme 编辑、headless gallery、静态文档站与外部消费者验证。K6 复核结论是 **逻辑/API 层 Go-with-conditions，平台完整 No-Go**。

本 issue 只记录开发过程中反复撞到的内核设计问题，以及建议的处理顺序。不复述组件功能清单。

## 已验证

- `crystal spec spec/kit`：86 examples / 0 failures。
- `kit_gallery --verify`：light 与 dark/DPI 1.5 均 `verify=pass`，select/dialog/tooltip/input 全 true。
- `tools/kit_consumer_verify.sh`：临时 Shards path 消费者编译并运行核心入口与 Kit 入口。
- `crystal build src/tessell.cr --no-codegen`：核心入口不加载 Kit。
- 证据与限制见 `docs/kit/execution.md`、`docs/kit/K6-review.md`。

未验证：Windows 真实窗口 gate、平台 IME composition、屏幕阅读器 provider、平台剪贴板、GL DrawList 上屏。

## 内核问题与建议

### 1. 扁平 UI DSL + 绝对 bounds 迫使 Kit 自建布局

`UI::Builder` 产出带绝对 `Rect` 的扁平声明，没有 measure/arrange 管线。Kit 为了实现 Column/Row、padding/spacing、Dialog/ScrollView 内容测量，只能另建 `Kit::Container` 的 measure/arrange，再把结果写回绝对 bounds。

**风险**：两套布局逻辑（核心 `Layout` 与 Kit Container）长期漂移；核心 `Layout` 的约束/比例能力没有被组件复用。

**建议**：优先处理 [#5](https://github.com/ShiningRay/tessell/issues/5)，让 UI DSL 接入核心两遍布局（auto bounds、padding/gap/flex），Kit 只声明语义组件，不再自己算容器几何。

### 2. DrawList 有命令，没有执行者

Kit 已有 `PaintList`、`DrawListPainter`、`SvgPainter`。K6 收尾时补了 `Backend#draw_draw_list` 默认契约与 `GLBackend#draw_draw_list` 源码实现（Rect/Line/RoundRect/Stroke + per-command scissor），并只在 `examples/app_demo.cr --no-codegen` 层面做过类型检查；该 GL 路径**尚未在 Windows 真机运行或像素回读**。此前 `GLBackend` 只消费 Text 顶点与 polygon，Kit 的按钮背景、焦点环、滚动条不会自动出现。

**风险**：组件“逻辑完成”但真实上屏未验证；测试与真实渲染之间仍缺可执行的 GL 证据。

**建议**：推进 [#2](https://github.com/ShiningRay/tessell/issues/2)，把 `draw_draw_list` 纳入 Windows gate，补 Rect/Line/RoundRect/Stroke + scissor clip 的像素回读与失败路径；SVG/PaintList 只能作为逻辑证据，不能替代 GL 回读。

### 3. 事件模型需要平台适配闭环

K1 已补 modifiers、wheel delta、PointerEnter/Leave/Cancel、常用键码，但 Win32 示例仍只发基础 pointer/key/text；Kit 的 Select 滚轮、Input 剪贴板快捷键、Dialog 焦点陷阱依赖这些字段。

**风险**：核心事件 struct 扩展了，平台层没填；组件在真实 Windows 窗口里行为与 headless 测试不一致。

**建议**：推进 [#4](https://github.com/ShiningRay/tessell/issues/4)，把 Win32 `WM_*` → `Input::Event` 的映射收敛到平台层，至少覆盖 modifiers、wheel、enter/leave/cancel、IME composition。

### 4. 焦点/命中需要“组件根”与“焦点作用域”概念

核心 `FocusManager` 只认 Node，没有“组件根”概念。Kit 为了让 Button/Checkbox/VirtualList 行命中后聚焦到正确组件，必须维护 Node↔Component 映射，并在命中子节点时回退到最近可聚焦祖先。Dialog 的焦点陷阱又要临时把 `next/prev` 的 root 切到模态子树。

**风险**：每个上层 UI 框架都要重写一遍映射、回退、作用域；焦点顺序与 a11y 容易分叉。

**建议**：核心提供轻量的 focus scope / focus group（或允许 FocusManager 以“可聚焦根”集合工作），并定义“命中子节点 → 最近可聚焦祖先”的默认语义。Kit 的映射层可以保留，但不应成为所有消费者的必经之路。

### 5. 裁切语义需要从 Node 下沉到绘制与命中两侧

K1/K2 给 `Node` 加了 `clip`，并让 `HitTest` 继承祖先 clip；但 `DrawCmd` 的 clip 只是每命令字段，GL 后端没有统一执行。Kit ScrollView 的命中正确、绘制靠 Painter push/pop，真实后端仍可能越界。

**建议**：把 clip 定义为 Node→DrawList→Backend 的单一语义；后端必须实现 scissor/嵌套 clip，缺失时显式失败而不是静默忽略。

### 6. A11y 需要“逻辑子节点数”与“滚动偏移”覆盖

VirtualList 只实例化可见行，但 a11y 必须报告逻辑总行数。K2 给 `A11y::Meta` 加了 `children_count`/`scroll_offset` override，证明只靠 retained 子节点数不够。

**建议**：把这两个字段纳入核心 a11y 契约（而不是 Kit 每次 rebuild 后覆写），并在文档中明确“进程内树 ≠ 平台 provider”。平台 provider 仍应单独立项，避免组件文档暗示屏幕阅读器可用。

### 7. 主题 token 仍然太薄

核心 `Render::Theme` 只有 6 个颜色。Kit 的三层 token（语义色 → 组件 token → 尺寸/排版）可用，但 `Theme.from_render` 是单向适配，核心与组件主题仍可能分裂。

**建议**：推进 [#8](https://github.com/ShiningRay/tessell/issues/8)，扩展语义 token 与主题作用域；Kit 保持“组件 token 只引用语义色”的约束。

### 8. 文本编辑/IME 不应由每个组件重造

Crystal stdlib 没有 grapheme cluster API。Kit 自带 `Graphemes`（常见 combining/emoji/ZWJ/RI/keycap 覆盖）与 `TextEditing`，但这不是完整 UAX #29；平台 IME composition 也还没进 `Kit::Event`。

**风险**：Input、Textarea、Editor 会重复实现光标/选区/组合输入；不同组件的 grapheme 语义可能不一致。

**建议**：把 grapheme 边界、选区模型、clipboard/IME composition 契约下沉到核心文本层；组件只负责布局与绘制。IME 人工验证（C7）未关闭前，Input 文档不得宣称完整表单输入。

### 9. 无窗口视觉验证工具缺口

本机没有可用的 macOS 后端，Kit 的视觉证据靠 `SvgPainter` + PaintList。这能检查布局/主题/命令顺序，但不能证明 GL 像素、字体 shaping 或 IME。

**建议**：推进 [#10](https://github.com/ShiningRay/tessell/issues/10)，提供离屏/软件后端与 golden-image 回归；同时保留真实窗口 gate 作为发布条件，不用 headless 结果替代。

## 建议优先级

1. **P0**：DrawList 后端执行 + clip 语义（#2）。
2. **P0**：Win32 事件/IME 映射（#4）。
3. **P1**：核心布局接入 UI DSL（#5）。
4. **P1**：focus scope / 组件根契约。
5. **P1**：核心文本编辑/grapheme/IME 契约。
6. **P2**：主题 token（#8）、a11y 逻辑子节点、离屏后端（#10）。

## 结论

Kit 证明了同仓可选入口、组件状态/绘制/a11y 契约与 headless 验证路径可行；真正的阻塞不在组件数量，而在核心的绘制执行、平台事件与焦点/布局契约。建议先把上述 P0/P1 内核项闭环，再扩 P1 组件目录，避免“组件目录增长、平台能力不变”。
