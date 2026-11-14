# Tessell Kit：UI 组件库方案与实施计划

> 状态：K0–K6 已完成；K6 之后的跨平台收口已转入 [跨平台方案](https://github.com/ShiningRay/tessell/blob/main/docs/cross-platform-plan.md)。本文保留 Kit 组件库的 K0–K6 计划与验收历史。
> 计划基线为 `649c59a`；K0 起在本仓落地，执行记录见 [execution.md](execution.md)。
> 基线：本地 `tessell` 仓库，HEAD `649c59a`（2026-11-14 调查时点）。
> 参考：[gpui-kit 组件目录](https://gpui-kit.com/zh-CN/component/)，借用其组件覆盖、文档组织与 Root/Theme/状态分离思想；不照搬 Rust/GPUI API，不复制其聊天、编辑器等全部范围。

## 1. 决策摘要

1. **需要独立的组件层，但当前不另建仓库。** 在现有 `tessell` 仓库新增可选入口 `require "tessell/kit"`，命名空间 `Tessell::Kit`；核心入口 `require "tessell"` 不自动加载组件。
2. **“同仓”不等于“同一巨石模块”。** Kit 只能依赖核心公开能力；核心不得反向依赖 Kit。组件状态、交互、绘制、文档、测试各有明确边界，保证以后可拆。
3. **首个可用版本不以组件数量为目标。** 先建立 Theme、组件状态协议、绘制原语、Root/Overlay、输入与无障碍契约，再交付可组合的通用桌面组件。
4. **先交付 8 个可验收组件 + Showcase，而非一次复制 gpui-kit 全目录。** P0 为 Button、Checkbox、Text、Input、Select、Tooltip、Dialog、ScrollView；已有 `VirtualList` 作为数据容器接入，不计新组件数。
5. **组件以行为正确、键盘可用、DPI/主题正确、脏区与分配不退化为验收条件。** 截图和组件数量不能单独作为完成依据。

## 2. 为什么现在不拆仓库

### 2.1 当前现实

- 核心与组件仍会同频修改。现有 `Theme` 只有 6 个颜色字段；`DrawCmd` 只有 Rect/Text/Line；输入缺修饰键、完整按键、滚轮 delta；a11y 只有进程内树。首批组件会反向暴露核心缺口。
- 当前历史验证基线为 Windows + msys2 ucrt64；K6 之后 macOS 已补 SDL2/OpenGL 真实窗口与 FreeType LP64 文本证据，Linux 仍未运行验证。平台能力由 [跨平台方案](https://github.com/ShiningRay/tessell/blob/main/docs/cross-platform-plan.md) 接管；拆仓不会解决平台能力，只会增加跨仓联调。
- Shards 官方规范以一个项目中的 `shard.yml` 描述名称、版本与依赖，Git tag 用于版本解析；没有为同仓多 shard 独立发版设计的机制。
- Crystal 官方 `require` 规则支持嵌套路径。同一 shard 可提供 `require "tessell/kit"`，使 Kit 保持可选加载，而不必立即拆仓。

### 2.2 仓库方案对比

| 方案 | 优点 | 代价 | 当前判断 |
|---|---|---|---|
| 同仓，核心入口直接聚合全部组件 | 使用最简单 | 核心与组件耦合，加载和命名边界消失 | 不采用 |
| **同仓，独立 `tessell/kit` 入口与测试目录** | 核心变更即时联调；单一 CI、发布与 issue 入口；可选加载 | 核心与 Kit 同步发版；需守住依赖边界 | **采用** |
| 立即新建 `tessell-kit` 仓库 | 独立 issue、版本和维护权限 | 版本矩阵、path 依赖、双仓 PR/CI、核心缺口往返修改 | 暂不采用 |

### 2.3 未来拆仓触发条件

以下至少满足两项，且确需独立发布时再评审拆仓：

- Kit 已有仓外消费者，需要与核心不同的发布节奏。
- 核心 API 已稳定，连续两个 Kit 版本无需修改核心。
- Kit 需要独立维护者、issue/PR 分流或访问权限。
- 已定义并实测 `tessell` 与 `tessell-kit` 的版本兼容矩阵。
- 已在临时消费者项目验证拆分后的 `path`/Git 依赖、构建、测试和发布流程。

拆仓时用 `git filter-repo` 或等价历史保留方案迁移 Kit 路径；主仓保留迁移说明。当前不创建该仓库，也不承诺未来仓名可用。若保留主仓全部历史而非拆分历史，也可先建干净仓库并记录来源提交；具体迁移方式届时评审。

## 3. 目标、范围与非目标

### 3.1 目标

- 给 Crystal 桌面应用提供一致、可组合、可换主题的 Tessell 组件。
- 让常见控件不再要求应用手写命中、焦点、状态、绘制和 a11y 元数据。
- 提供原生可运行 Showcase、可执行示例和在线组件文档。
- 将组件变更纳入现有质量门禁，保持核心 retained/失效/低分配设计。

### 3.2 首版范围

- 设计 token、light/dark 主题、主题作用域。
- 统一组件状态、尺寸、禁用、焦点、事件和可访问名称契约。
- 基础绘制、文本、选择、弹层所需的最小核心补层。
- 8 个 P0 组件、一个组件画廊、每组件文档和真实消费者示例。
- Windows 本机逻辑测试、真实窗口验证、像素/脏区/分配检查。

### 3.3 非目标

- 不做 WebView、DOM/CSS 兼容、Web 组件运行时。
- 不做 Tailwind 式工具类、任意样式覆盖或主题注册中心。
- 首版不做动画系统、复杂矢量图标、Markdown/HTML、代码编辑器、图表、Dock、GridLayout。
- 不把聊天 Bubble/Message/Attachment 等行业组件纳入通用首版。
- 不宣称屏幕阅读器可用：UIA/平台无障碍 provider 仍需独立项目阶段。
- K0–K6 不把 macOS/Linux 支持当作完成条件；K6 之后的三平台支持由 [跨平台方案](https://github.com/ShiningRay/tessell/blob/main/docs/cross-platform-plan.md) 按 L0/L1/L2/L3 分级推进，未真实验证的平台仍不得宣称支持。
- 不在本计划中改核心版本号、发布 release 或迁移既有 `Widgets::VirtualList` 路径。

## 4. 现状依据与核心缺口

### 4.1 可复用能力

| 现有能力 | 位置 | Kit 使用方式 |
|---|---|---|
| 稳定组件身份 | `src/tessell/ui/key.cr` | 以 `UiKey` 作为组件与子部件身份，不新增字符串 ID 系统 |
| 声明式构建与节点复用 | `src/tessell/ui/builder.cr`、`apply.cr` | Kit 产出声明，不另建 widget 树；沿用缓冲与失效流程 |
| 输入焦点与路由 | `src/tessell/input/` | 组件经 Router/FocusManager 交互，不直接读平台消息 |
| 主题与 DPI | `src/tessell/render/theme.cr`、`dpi.cr` | 扩为分层 token；沿用逻辑布局与设备像素文本边界 |
| 文本 shaping/栅格化 | `src/tessell/text/` | 文本、标签、输入编辑复用；不引入第二套文本栈 |
| 虚拟化与脏区 | `src/tessell/widgets/virtual_list.cr`、`render/dirty.cr` | List/Select 大数据内容复用；禁止全量物化 |
| 进程内 a11y | `src/tessell/a11y/tree.cr` | 扩展 role/state/value；明确不是平台 provider |
| 真实窗口与回读 | `examples/app_demo.cr`、`tools/gate.ps1` | 抽取 Showcase 宿主和验证方式，不复制大段 Win32 样板 |

### 4.2 必须先补的缺口

1. **绘制**：通用矩形/描边/圆角/裁切路径未形成后端公共契约；图标路径也未定。
2. **事件**：缺 PointerEnter/Leave、PointerCapture、消费/冒泡、修饰键、完整激活键、滚轮 delta、上下文菜单事件。
3. **文本编辑**：缺光标、选区、剪贴板、撤销和已验证的 IME 集成。首版 Input 只能在这些能力到位后宣称完整。
4. **弹层**：缺 overlay 层、定位、焦点圈定/恢复、模态输入隔离与 dismiss 规则。
5. **语义**：A11y Role/状态集合不足以表达 checkbox、textbox、dialog、combobox、tooltip 等。
6. **工程**：测试统一从核心入口加载，不能证明 Kit 可选； Showcase/文档构建尚未建立。

这些缺口允许修改核心公共契约，但每处修改须先补兼容性测试，不能用 Kit 内部 workaround 固化平台行为。

## 5. 组件库架构

### 5.1 目录与依赖

```text
src/
  tessell.cr                    # 核心入口，不 require kit
  tessell/
    kit.cr                      # Kit 聚合入口，供 require "tessell/kit"
    kit/
      context.cr                # Root/Theme/Overlay/资源上下文
      theme.cr                  # Kit token 与 light/dark 主题
      component.cr              # 公共状态、尺寸、声明辅助
      events.cr                 # 组件事件与回调类型
      primitives.cr             # 核心绘制/布局/文本能力的受控适配
      overlay.cr                # 弹层定位与焦点策略
      button.cr
      checkbox.cr
      text.cr
      input.cr
      select.cr
      tooltip.cr
      dialog.cr
      scroll_view.cr
      virtual_list.cr           # 对现有 VirtualList 的 Kit 适配，不复制算法
examples/
  kit_gallery.cr                # 原生可运行组件画廊
  kit_consumer.cr               # 最小、可编译的外部使用方式范例
spec/
  kit/
    ...                         # 每组件状态/交互/语义测试
  support/                      # 可复用测试宿主、像素与输入驱动
docs/
  kit/
    index.md
    design-tokens.md
    component-contract.md
    components/<name>.md
    repository-strategy.md
site/                           # 仅静态文档站；非 UI Web 运行时
tools/
  kit_gallery_verify.cr
  kit_visual_matrix.ps1
```

依赖方向：

```text
应用 → Tessell::Kit → Tessell 核心公开 API → 平台/渲染后端
                ↘
             Kit 内部状态与主题

禁止：Tessell 核心 → Tessell::Kit
禁止：Kit 组件 → Win32/WGL/GL 具体 API
禁止：组件绕过 Input::Router 自建平行焦点系统
```

### 5.2 组件分层

| 层 | 职责 | 测试方式 |
|---|---|---|
| Behavior/State | 值、选中、按压、开关、编辑、打开状态与状态迁移 | 纯 Crystal spec，无窗口 |
| View/Declaration | 按状态产出稳定 keyed 子树、布局与 a11y 元数据 | Builder/apply 与 a11y spec |
| Paint | 依据 resolved token 产出绘制，处理裁切与 DPI | DrawList 协议 + 真实后端回读 |
| Composition | Root、Overlay、ScrollView、slots 与子组件组合 | 集成 spec + Showcase |
| Documentation | API、可复制 recipe、状态矩阵、限制 | 示例编译 + 链接/截图/发布检查 |

### 5.3 状态与 API 契约

- **应用持有业务状态。** 输入值、选中项、开关值由应用 state 持有；组件可持有按压、hover、弹层定位等瞬态。首版以受控组件为主，不默认维护第二份业务值。
- **稳定 key 必传。** 组件根与子部件从传入 `UiKey` 派生，禁止按显示文本生成身份。
- **统一状态维度。** `disabled/read_only/hovered/pressed/focused/selected/open/invalid` 按组件适用；不得把 disabled 与 read-only 混为一谈。
- **统一尺寸。** 首版仅 `small/medium/large`；紧凑密度作为 token，不为每个组件另造尺寸枚举。
- **变更只报一次。** 一次用户动作至多触发一次语义 change；PointerUp 与 Enter 不得双发；程序化 setter 是否发事件逐组件写明。
- **回调不跨线程隐式执行。** 组件回调在 UI context；业务跨 context 仍用 Channel/不可变快照。
- **失效最小化。** 文本/颜色变化走 Paint；尺寸/结构变化走 Layout；滚动/位移按现有 CompositeOnly 语义；禁止因 hover 重排整棵树。
- **热路径复用。** 声明、绘制、文本和 sink 缓冲可复用；不在每帧创建回调、格式化字符串或全量子树。
- **可访问名称是必需契约。** 无可见文本的按钮必须提供名称；Input 关联 label/description/error；装饰内容不重复曝光。
- **样式覆盖分层。** 应用优先使用 token、variant 和 slots；首版不开放任意绘制回调。确需完全定制时使用核心原语自建组件。

示意形状，不是冻结签名：

```crystal
require "tessell/kit"

button = Kit::Button.new(
  key: root_key.child(1_u64),
  label: "Save",
  variant: Kit::Variant::Primary,
  disabled: false
)

# 在既有 UI.build 中声明；实际签名由 K0 原型验证后冻结。
button.build(builder, kit_context)
button.on_action { save_via_channel }
```

### 5.4 Theme 与视觉方案

采用“语义色 + 组件 token + 尺寸/排版”三层，不直接在各组件使用 `bg/fg` 猜颜色。

- 语义色：canvas/surface/surface_raised/foreground/muted/border/accent/danger/success/focus/selection/scrim。
- 组件 token：button/input/dialog 等仅引用语义色，不重复维护整套色板。
- 排版：font family/fallback、正文/标签/标题字号与行高；DPI 只经核心缩放，不在组件重复乘 scale。
- 尺寸：spacing、control height、padding、border width、focus ring、圆角。
- 状态：normal/hover/pressed/focus/disabled/read-only/invalid 的对比与视觉差异。
- 外观：中性灰、单一蓝 accent、克制圆角；无渐变、阴影动画或大面积品牌色。
- `Kit::Theme` 保留核心 `Render::Theme` 的适配器，避免核心清屏色与组件主题分裂。
- 首版 light/dark 为编译进 shard 的值类型主题；不支持运行时监听主题目录。

### 5.5 Root 与 Overlay

Root 是窗口级组合边界，不承担业务状态：

- 持有当前 Theme、DPI/文本上下文引用、overlay 栈与共享组件资源。
- 内容层先绘制，tooltip/menu/dialog/notification 等 overlay 后绘制并位于内容之上。
- Dialog 打开时建立模态输入边界；关闭后恢复原焦点。
- Tooltip 不抢焦点；Escape、点击外部、窗口 blur 的行为逐类定义。
- overlay 裁切、窗口边界翻转、嵌套弹层和 z-order 必须有测试。
- Root 不隐藏现有应用启动/关闭流程，不在 `require` 时安装全局副作用。

## 6. 组件清单与优先级

| 优先级 | 组件/能力 | 首版交付内容 | 依赖 |
|---|---|---|---|
| 基础设施 | Theme/Root/Component contract | token、上下文、状态、尺寸、key、回调与 a11y 约定 | K0 |
| 基础设施 | Primitives/Overlay | 矩形、描边、圆角、裁切、弹层与焦点策略 | 核心补层 |
| P0 | Button | primary/secondary/ghost/danger；small/medium/large；disabled；键盘与指针激活 | Primitives |
| P0 | Checkbox | checked/unchecked/indeterminate；label；disabled；键盘切换 | Button 状态协议 |
| P0 | Text | 正文/标签/标题、muted、换行/截断；非编辑器 | Theme/Text |
| P0 | Input | 单行值、placeholder、label、read-only/disabled/invalid、光标/选区/剪贴板、IME 明示状态 | 文本编辑补层 |
| P0 | Select | 单选、键盘导航、弹层列表、空/禁用选项；不实现多选和搜索 | Overlay/VirtualList |
| P0 | Tooltip | 延迟显示、键盘焦点等价入口、边界定位、不抢焦点 | Overlay |
| P0 | Dialog | modal、标题/内容/action slots、Escape、焦点圈定与恢复 | Overlay |
| P0 | ScrollView | 垂直/水平滚动、裁切、滚动条、键盘与滚轮、子内容测量 | 核心事件/裁切 |
| 已有适配 | VirtualList | 复用现有算法，加入 Kit 行声明、焦点与 a11y 适配；不物化全量行 | ScrollView |
| P1 | Radio/RadioGroup、Switch、Slider、Progress、Badge、Alert、Tabs、Accordion | 常用桌面控件扩展 | P0 契约稳定 |
| P1 | Menu/Popover/Combobox、Textarea、Toast、Toolbar/StatusBar/Sidebar、Tree/DataTable | 复杂导航、编辑与数据组件 | 按依赖逐项立项 |
| 暂缓 | Icon、Avatar、Image、Carousel、Date/Time/ColorPicker | 需要图标、图片、日期时间等额外底层能力 | 独立技术验证 |
| 不随首版 | Editor、Diff、TextView、Message/Bubble/Attachment、Chart、Dock、GridLayout、Speech | 非通用最小桌面组件集 | 独立产品需求 |

范围说明：gpui-kit 的组件目录用作覆盖面参考，而非功能承诺。首版完成 P0 后可发布“基础组件集”，不能称“对齐 gpui-kit”。

## 7. Showcase 与文档站

### 7.1 原生 Showcase

`examples/kit_gallery.cr` 同时是开发工具与验收载体：

- 左侧组件导航，右侧示例；每组件含默认、各 variant/size、disabled、focus、invalid、长文本、CJK/Emoji 等适用状态。
- 全局 light/dark 与 DPI 切换；切换后组件布局和像素结果正确。
- 提供纯键盘路径与事件日志，可检查焦点、change 次数、Dialog 焦点恢复。
- `--component=<name>`、`--theme=<name>`、`--dpi=<scale>`、`--frames=N`、`--verify`、截图输出。
- `--verify` 使用确定性输入脚本驱动真实组件，不只渲染静态截图。
- Showcase 不复制 app_demo 的平台样板；先抽一个可复用示例宿主，保持现有示例可运行。

### 7.2 文档站

- 中文优先，路径 `/zh-CN/component/<name>/`；英文待内容稳定后再补。
- 每组件固定章节：何时使用、导入、可复制最小示例、状态/variant/size、键盘交互、无障碍、主题 token、限制、相关组件。
- 文档代码来自可编译示例或 CI 抽取编译，禁止长期维护不可运行的伪代码。
- 截图由 Showcase 固定场景生成，注明 Windows/主题/DPI/版本。
- 静态站技术选型在 K5 单独比较；优先现有团队可维护的静态生成器，不为文档引入桌面运行时。
- `crystal docs` 生成 API 参考，与手写指南互补，不用 API 页面代替组件交互文档。
- 部署目标暂选 GitHub Pages，实施前核对现有 GitHub Pages 配置与域名；本计划不发布网站。

## 8. 测试与验收

### 8.1 每组件统一 DoD

一个组件只有全部满足以下条件才算完成：

1. 公共 API、状态迁移、键盘/指针行为和事件次数有 spec。
2. 正常、hover、pressed、focus、disabled 等适用状态有声明与绘制验证。
3. 有 a11y role/name/value/focusable/enabled 等适用元数据测试；文档注明平台 provider 缺口。
4. light/dark、至少 DPI 1.0/1.5/2.0、长英文/CJK/Emoji/空值/极窄宽度的适用场景有验证。
5. Showcase 有真实窗口交互与确定性 `--verify`；失败路径至少验证一个反例。
6. 稳态重复 build/render 不增长节点；适用场景沿用项目 A/B 分配判据，不写成严格零分配。
7. 文档有可编译 recipe、键盘说明和已知限制；API 变更与示例一致。
8. `crystal spec`、格式检查、Kit 单独入口构建、全量 `tools/gate.ps1` 通过。

### 8.2 验证矩阵

| 层 | 验证 | 失败判据示例 |
|---|---|---|
| 状态内核 | 非法状态、边界、重复动作、程序化 setter | disabled 仍触发 change；一次点击双回调 |
| 声明协调 | key 稳定、节点复用、最小失效、卸载清理 | 同态重建新增节点；hover 导致全树 Layout |
| 输入 | Tab/Shift+Tab、Enter/Space/Escape/方向键、pointer cancel/capture | 焦点逃逸模态；弹层后背景仍响应 |
| 文本 | CJK、组合字符、Emoji、选区边界、剪贴板、IME | 切断 grapheme；密码内容进入剪贴板 |
| 绘制 | 真实 GL readback、裁切、圆角/描边、overlay 次序 | 脏区与全量重绘不一致；文本越过裁切 |
| 主题/DPI | 运行中切换、窗口边界、长文本、组件尺寸 | 主题残留；DPI 双重缩放 |
| 数据 | 大列表可见范围、回收、滚动到端点 | 物化全部行；回收后状态串行 |
| 交付 | `require "tessell"` 不含 Kit；`require "tessell/kit"` 可单独使用；消费者 recipe 编译 | 核心入口引入组件；示例依赖仓内私有路径 |

性能与零分配沿用现有 `A delta_work < 1000`、`B delta_work <= 256`、3 窗最大值口径。首版不新造统一 FPS 门限；新增场景记录帧时间分布与本机环境。

## 9. 实施工作包与顺序

以下 `K0–K6` 是组件库新增工作包，不改写既有 `M0–M4` 历史记录。估算是单人全职人日（pd），只用于排期参考，未实测。

### K0：契约与纵向原型（3–5 pd）

- 写组件公共契约、状态/尺寸/事件/a11y 矩阵和 token 清单。
- 建立 `src/tessell/kit.cr`、`Tessell::Kit`、可选入口编译测试与依赖方向检查。
- 用一个 Button 纵向打通 state → declaration → input → paint → a11y → Showcase。
- 评审 API 后再批量实现；若 Button 必须绕过核心才能完成，先修核心契约。

**退出**：核心入口不加载 Kit；Kit 可独立 require；Button 原型真实窗口可操作；组件契约评审完成。

### K1：绘制、输入与主题底座（8–14 pd）

- 补齐通用矩形/描边/圆角/裁切的后端协议和 GL 实现，保留不支持能力的显式失败。
- 补 pointer enter/leave/cancel/capture、事件消费、修饰键、Space 等激活键和明确 wheel delta。
- 扩展 Theme token、Theme 适配器与作用域；完成 light/dark/DPI 状态样式。
- 建立组件测试宿主、输入驱动、像素与分配验证工具。

**退出**：Button/Checkbox/Text/ScrollView 所需底座完整；核心原有用例和示例回归通过；负例证明裁切、焦点和事件隔离有效。

### K2：P0 基础组件与容器（8–12 pd）

- 正式实现 Button、Checkbox、Text。
- 实现 ScrollView，适配现有 VirtualList，验证滚动条、键盘、裁切和虚拟行 a11y。
- Showcase 建立组件导航、状态矩阵、主题/DPI 开关和确定性验证。

**退出**：4 个新组件 + VirtualList 适配通过统一 DoD；万行列表不物化；脏区/全量像素一致。

### K3：Overlay 与弹层组件（7–12 pd）

- 实现 Root overlay 栈、定位、裁切、模态输入、焦点圈定/恢复和 dismiss 规则。
- 实现 Tooltip、Dialog、Select。
- 覆盖边界翻转、嵌套、Escape、外部点击、blur、卸载、重复打开与焦点恢复。

**退出**：3 组件通过统一 DoD；Dialog 背景不可交互；Select 键盘与指针选择结果一致；Tooltip 不抢焦点。

### K4：Input 文本编辑闭环（8–15 pd）

- 建立单行编辑状态：grapheme 安全光标/选区、插入/删除、方向键、Home/End、全选。
- 接剪贴板、只读/禁用/校验、placeholder、label/error；密码模式作为可选后续，不在基础 Input 自动承诺。
- 接真实 IME，完成当前未关闭的 C7 人工验证；未通过时 Input 标记受限，不得宣称完成。
- 实现并验证 Input 组件与 Showcase；记录复杂文本和撤销范围。

**退出**：Input 全部承诺行为通过；IME 人工证据与自动测试齐全；未实现项明确列入限制。若 IME 持续受阻，K4 No-Go，其他组件可交付但首版不得称完整表单组件集。

### K5：文档站与消费者交付（5–8 pd）

- 为全部已交付组件写固定结构中文文档和可编译 recipe。
- 建静态文档站、导航、主题/DPI 截图与 `crystal docs` 链接。
- 新建临时消费者目录，以 Shards `path` 依赖引用本仓，分别验证核心-only 与 Kit 用法。
- 更新 README、usage、组件覆盖表、平台限制；将 Kit 检查并入 `tools/gate.ps1`。

**退出**：干净消费者构建成功；文档链接、代码、截图和 Showcase 一致；完整 gate 通过；发布内容有明确版本和限制。

### K6：首批发布评审与后续路线（2–3 pd）

- 独立复核每组件 DoD、真实 Windows 窗口、键盘路径、像素、分配与文档。
- 形成组件库 Go/No-Go 报告，列出未完成组件与核心遗留，不隐藏限制。
- 依据真实使用和缺陷决定 P1；只有满足 §2.3 才发起拆仓评审。

**退出**：首批基础组件可发布或有明确 No-Go 项；下一阶段按需求而非目录数量排序。

**总计**：约 41–69 pd。K1/K2/K3 中纯逻辑测试和文档可并行，但公共契约、核心绘制/输入、Overlay 与 Input 存在串行依赖；不得为赶并行而同时改同一核心接口。

## 10. 兼容、发布与维护规则

- 首版 Kit 与 `tessell` 同版本发布，文档标注组件成熟度；不以目录存在代表 stable。
- 核心公共 API 改动需兼容测试；必要时保留适配层，不在一次组件提交中静默重写核心语义。
- `Widgets::VirtualList` 旧路径暂保留；Kit 适配稳定后再单独评估弃用和迁移。
- 组件文档明确受控/非受控、事件触发、只读/禁用、键盘、a11y 和平台限制。
- 新组件必须同时带 spec、Showcase 页面和文档；禁止只加视觉 demo。
- 每次发布在临时消费者项目复验，不只验证仓内相对 `require`。
- 文档站与 shard 发布解耦；文档失败不得被当作组件运行时验证通过，反之亦然。

## 11. 风险与控制

| 风险 | 影响 | 控制 |
|---|---|---|
| 先做大量组件，底层契约反复返工 | 进度虚高、API 不稳定 | K0 Button 纵向原型通过后才扩展 |
| 组件直接绑定 GL/Win32 | 无法跨后端、无法纯测试 | Kit 只依赖核心抽象，依赖检查入 gate |
| 每帧闭包/字符串/全树重建 | 分配和帧时间退化 | 应用持状态、稳定 key、缓冲复用、A/B 与节点数测试 |
| Input/IME/剪贴板复杂度被低估 | 表单能力不完整 | K4 独立门禁，受阻则明确受限，不以普通文本框冒充 |
| 弹层焦点与事件泄漏 | 模态失效、键盘不可用 | Root 统一 overlay；负例与 blur/嵌套测试 |
| a11y 树被误认为平台支持 | 错误生产承诺 | 文档明示 provider 未实现，后续独立验收 |
| 主题 token 膨胀 | 定制难、组件不一致 | 语义色优先，组件 token 仅在有差异时增加 |
| 文档截图与实现漂移 | 用户示例失效 | Showcase 生成截图、recipe 编译、发布复核 |
| 过早拆仓 | 双仓版本和 CI 成本 | 同仓可选入口；满足触发条件再拆 |
| 当前 macOS 环境产生错误跨平台推断 | 验证结论失真 | 只在真实环境声明支持；Windows gate 在 Windows 执行；三平台分级见 [跨平台方案](https://github.com/ShiningRay/tessell/blob/main/docs/cross-platform-plan.md) |

## 12. 本轮证据与未验证项

- 已读仓库：`README.md`、`docs/architecture.md`、`docs/plan.md`、`docs/roadmap.md`、`docs/usage.md`，以及核心 UI/Input/Render/A11y/VirtualList 源码和 gate。
- 已读参考：gpui-kit 组件目录、Button、Input、Root、Theme 页面。
- 已核实官方资料：[Crystal Requiring Files](https://crystal-lang.org/reference/latest/syntax_and_semantics/requiring_files.html)、[shard.yml 规范](https://github.com/crystal-lang/shards/blob/master/docs/shard.yml.adoc)、[Shards 命令](https://crystal-lang.org/reference/latest/man/shards/index.html)、[Writing Shards](https://crystal-lang.org/reference/latest/guides/writing_shards.html)。
- 本轮只制定计划；未运行 Crystal 测试或 Windows 图形 gate，未实现组件，未创建/发布仓库或网站。
- 文档站生成器、最终主题数值、冻结后的 Crystal API 签名和未来拆仓名均为实施时决策，不在此虚构定案。

## 13. K6 之后的跨平台收口

K6 的结论是“逻辑/API 层 Go-with-conditions；平台完整 No-Go”。2026-11-14 的 macOS SDL2/OpenGL 示例与 FreeType LP64 修复改变了证据边界，但不等于三平台完成。后续按 [跨平台方案](https://github.com/ShiningRay/tessell/blob/main/docs/cross-platform-plan.md) 执行：

- L0：三平台编译与逻辑测试。
- L1：三平台真实窗口、输入、文本、GL 上屏。
- L2：DPI、剪贴板、字体回退、基础 IME、打包。
- L3：完整 IME 预编辑、平台无障碍 provider、签名/公证。

在 L1/L2 证据齐全前，组件文档不得把“K0–K6 已交付”改写成“平台完整”。
