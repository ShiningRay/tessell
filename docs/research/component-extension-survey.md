# 参考框架的组件扩展机制调研：第三方怎么写组件、怎么扩展组件

- 调研日期：2026-11-15（Asia/Shanghai）
- 目的：回答"我们的参考对象如何允许应用开发者写自定义组件、扩展已有组件"，并对照 Tessell Kit 现状给出取舍建议。
- 证据口径：本仓事实标 `path:line`；外部事实只取官方文档/源码，URL 见 §8；**未编译运行任何参考框架示例**，涉及运行时行为的结论标 `[未验证]`；§6 全部是**建议（未采纳）**，不是决策。
- 关联文档：`docs/architecture.md:65-70`（六路线对照）、`docs/research/asuka-comparison.md`（asuka 方法论对照）、`docs/kit/plan.md`（Kit 边界与非目标）。

## 0. 结论

1. **七家参考对象都没有"组件注册表"或运行时插件系统。** 扩展性来自语言/类型系统机制（函数、接口、继承、trait、GType）加包管理器；框架本身只提供基类、协议或 class 表。Tessell 现在没有 registry（`src/tessell/kit.cr:6-31` 是固定 require 列表），与参考对象一致，**不必补 registry**。
2. **自定义组件有两条主流路线**：组合/函数式（asuka、Gio、Clay、GPUI 默认）与受控继承（Fyne 的 Widget+Renderer、GTK4 的 GObject 子类+vfunc、LVGL 的 class 常量+base_class 链）。两条路线可以混用，GTK4/Fyne 也支持组合，GPUI 也保留底层 `Element`。
3. **扩展已有组件的官方入口集中在四层**：结构（children/slot）、行为（事件回调或覆写 vfunc）、外观（theme / CSS / renderer / 变体 props）、语义（a11y）。没有一家鼓励应用改组件私有字段或替换内置实现。
4. **状态归属是共同约定**：组件只持有 hover/pressed/focus/scroll 等瞬态，业务值归应用；生命周期有显式销毁（Fyne `Destroy`、GTK `dispose`、LVGL `destructor_cb`、GPUI `Drop`、asuka `OnCleanup`）。Tessell 的 `Component#dispose` 与 `signal_owner`（`src/tessell/kit/component.cr:166-191`）属于同一类，契约也已写明（`docs/kit/component-contract.md:11`）。
5. **Tessell 现状是"受控继承 + 声明式组合"的混合**，方向并不落后；真正的缺口是**内置组件的可覆写点没有契约化**——`Button` 的 measure/emit/paint/handle 都是整段实现，子类只能整体替换（`src/tessell/kit/button.cr:30-140`），第三方无法只改一处外观或行为。
6. **建议**：保留基类四阶段契约；对外主打组合；为内置组件抽 `protected` 绘制/命中/激活 hook；主题短期只支持整套 `Theme` 注入；分发用 Crystal shards 约定而非注册中心；另补一篇面向应用开发者的 `docs/kit/extending.md`。均未采纳。

## 1. 我们把谁当参考对象

| 对象 | 在本仓中的角色 | 来源 |
|---|---|---|
| asuka（Go，原生控件） | 方法论对照：编译语言 + retained 树 + 声明式 builder + 细粒度更新 | `docs/research/asuka-comparison.md:1-13` |
| Gio（Go，immediate） | 路线 1 代表：事件驱动、后端抽象、命令流 | `docs/architecture.md:65` |
| Fyne（Go，retained + 自绘） | 路线 2 主路线：retained 树 + 脏重绘 | `docs/architecture.md:66` |
| GTK4（C/GObject，原生控件） | 路线 4 代表：vfunc 继承模型 | `docs/architecture.md:68` |
| Clay（C，布局引擎） | 路线 5：独立两遍布局内核 | `docs/architecture.md:69` |
| LVGL（C，嵌入式对象树） | 路线 6：class 表 + 无效区域/部分刷新 | `docs/architecture.md:70` |
| GPUI / gpui-kit（Rust） | 组件目录、文档组织、Root/Theme/状态分离的参照 | `docs/kit/plan.md:6` |

排除项：Wails v3、Capy、CrystKit、CrymbleUI 属于路线对照或绑定/WebView 路线，没有"第三方组件扩展"的独立机制可供对照；Flutter/SwiftUI/Compose 不在本仓参考对象清单内，只在 asuka 的对照/bench 语境中出现。

## 2. 逐对象：怎么写、怎么扩

### 2.1 asuka：组件就是返回 `ui.Node` 的普通函数

- 组件是普通 Go 函数，返回不透明句柄 `ui.Node`（`ui/element.go:15` `type Node struct{ e *element }`）；**没有基类、接口、生命周期方法，也没有 renderer 概念**。组件体只执行一次，signal 变化只重发读取它的 prop，不做树 diff。
- props 是值结构体（如 `ui.ButtonProps`）。可变 prop 用 `signal.Accessor[T]`（`*signal.Signal[T]` / memo / `signal.Func`），静态值用 `ui.Val(v)`；事件是裸函数（`OnPress func()`）；children 作为函数实参直接传入。
- 写新控件的两条路：
  1. 组合内置 view + `ui.Style`；
  2. 原生 view 用 `//asuka:view` 标注 `<View>Props`，生成 `func Segmented(p SegmentedProps) ui.Node`。prop 规则固定：普通字段设一次、`Accessor` 变化时重设、`func` 是事件、`Style ui.Style | ui.Styler`。平台侧实现 view 协议：Swift 每 prop 一个 setter + events；Go 桌面为 `Handle() uintptr`、`Measure(w, h float32) (float32, float32)`、`Destroy()`。
- 扩展已有组件：无继承、无 renderer 替换。官方途径是**包装函数 + children/slot + 变体构造器**（`ui.ButtonFilled` / `ui.ButtonGlass` 等）+ `ui.StyleFunc(func() ui.Style)` 做差量覆盖 + 语义 token（`colors.Label`、`fonts.Title2`）。
- 状态与生命周期：signal owner 树（Show/For/Dynamic/screen/sheet 各有子 owner）+ `signal.OnCleanup`；UI/事件/effect 必须主线程，goroutine 用 `ui.Post`。
- 分发：Go module + 原生包随包提交生成代码（`asuka native check` 校验是否过期）；无 registry；当前 alpha。
- 来源：https://asuka.egoist.dev/zh 、https://github.com/egoist/asuka （docs/concepts.md、docs/components.md、docs/native.md）。

**对 Tessell 的提示**：asuka 的"组件体只跑一次、props 分静态/动态"与 Tessell 的 `emit` 每帧声明模型不同；可借的是"静态/动态分离"和"children 即参数"的表达方式，而不是生命周期。

### 2.2 Gio：带 `Layout` 方法的 struct

- 官方定义："custom widget"就是带 `Layout(gtx layout.Context) layout.Dimensions` 的普通 struct；**无基类、无接口约束、无 registry**（https://gioui.org/doc/architecture/widget ）。
- 关键类型：`type Widget func(gtx Context) Dimensions`（`layout/layout.go:47`）；`Dimensions{Size image.Point; Baseline int}`（`layout/layout.go:30`）；`Context` 携带 `Constraints`、`Metric`、`Now`、`Locale`、`Values`、`Source` 与 `Ops`（`layout/context.go:17`）。
- 从零写：状态放 struct 字段（指针接收者）；`Layout` 内 `clip.Rect(...).Push(gtx.Ops)` → `event.Op(gtx.Ops, b)` → 循环 `gtx.Event(pointer.Filter{Target: b, Kinds: pointer.Press | pointer.Release})` → `paint.ColorOp/PaintOp` 或子 widget → 返回 `Dimensions`。
- **纠偏**：不存在 `Event(gtx)` 方法约定；事件在 `Layout` 内消费。`widget.Clickable` 只是把命中/按压状态封装好的辅助类型，它的查询方法（是否被点击、是否按下）是可选的，不构成组件协议的一部分。
- 扩展：组合 / decorator——接收 `layout.Widget` 子闭包、改 `gtx.Constraints`、`op.Offset/op.Record`、`clip.Rect` 包裹。Split 教程的签名就是 `Layout(gtx layout.Context, left, right layout.Widget) layout.Dimensions`。
- 外观：`material.NewTheme()` 的 `*material.Theme`（颜色/尺寸/字体，需设 `th.Shaper`）；官方明确 material 只实现一种设计，应由其它设计包补充，**不是替换 renderer**。
- 状态归调用方，无 mount/unmount 钩子；分发走 Go module，无注册表。

**对 Tessell 的提示**：Gio 证明"单方法 + 组合"可以撑起完整控件库；Tessell 若提供轻量入口，应允许只实现 measure/paint，同时仍能声明自身 key（见 §6.3 的约束）。

### 2.3 Fyne：Widget 与 Renderer 分离（与 Kit 最接近）

- `fyne.Widget = CanvasObject + CreateRenderer() WidgetRenderer`；`WidgetRenderer` 只有五个方法：`Destroy()`、`Layout(Size)`、`MinSize() Size`、`Objects() []CanvasObject`、`Refresh()`。**没有 Resize**——Resize/Move/Hide 属于 `CanvasObject`，由框架调用。
- 自定义：嵌入 `widget.BaseWidget`（或已有 widget），构造器里**只调一次** `ExtendBaseWidget(self)`（当前源码对重复调用是 no-op，但不要依赖这个实现细节）。然后实现 `CreateRenderer` 返回自定义 renderer，可用 `widget.NewSimpleRenderer` 包装现成对象。
- 接口约定：renderer 每个 widget **恰好一个实例**、销毁后不复用；renderer 可能被销毁并重建（例如部件不可见之后），因此**状态必须留在 widget，不能放 renderer**。
- 扩展已有组件：嵌入 + 覆写方法 + `container` 组合；外观实现 `fyne.Theme`（Color/Font/Icon/Size）+ `Settings.SetTheme`，局部用 `container.ThemeOverride`。没有"替换内置 renderer"的公开 API。
- 无 registry；分发 = 独立 Go module + addons.fyne.io 目录。
- 来源：https://docs.fyne.io/extend/custom-widget 、https://docs.fyne.io/extend/ 、https://pkg.go.dev/fyne.io/fyne/v2#WidgetRenderer 。

**对 Tessell 的提示**：Fyne 把"布局/最小尺寸/对象列表"与"绘制"拆开，第三方可只换 renderer 而不动 widget 状态；Tessell 的 `emit`（声明树）与 `paint`（命令流）已经是分离的，缺的是让子类**只换一段绘制**的受控切面。

### 2.4 GTK4：GObject 子类 + 三个 vfunc

- 自定义 = GObject 子类：`G_DECLARE_FINAL_TYPE` + `G_DEFINE_TYPE`，在 `class_init` 覆写 `GtkWidgetClass` 的虚函数。
- 三个关键 vfunc（官方文档，均已抓取核对；版本号以站点当前 stable 为准）：
  - `measure(GtkWidget*, GtkOrientation, int for_size, int *min, int *nat, int *min_bl, int *nat_bl)`；`for_size` 未知传 -1（https://docs.gtk.org/gtk4/vfunc.Widget.measure.html ）。
  - `size_allocate(GtkWidget*, int width, int height, int baseline)`；官方原文："Called to set the allocation, **if the widget does not have a layout manager**."（https://docs.gtk.org/gtk4/vfunc.Widget.size_allocate.html ）。
  - `snapshot(GtkWidget*, GtkSnapshot*)`（https://docs.gtk.org/gtk4/vfunc.Widget.snapshot.html ）。
- 布局协作者：`gtk_widget_class_set_layout_manager_type()` 只能在 `class_init` 调；装入 layout manager 后它接管布局，不再走 `size_allocate`。
- 扩展：子类 + CSS（`GtkCssProvider` + `gtk_style_context_add_provider_for_display`）+ template（`set_template_from_resource` / `init_template`，4.8+ 在 dispose 时 `gtk_widget_dispose_template`）+ GParamSpec 属性。
- 分发：无包 registry；GType 在运行时注册，GIR 供语言绑定与 GtkBuilder 按类型名实例化。
- `[未验证]` C 侧 `g_object_class_install_properties` 的官方锚点未取到；PyGObject Gtk-4.0 文档页 404；`docs.gtk.org/gtk4/subclassing.html` 已 404，不要作为链接引用。

**对 Tessell 的提示**：GTK 的扩展点粒度最细（measure / allocate / snapshot / CSS 各管一段），且"有 layout manager 时不覆写 allocate"是显式的职责划分。Tessell 的 `arrange` 默认实现 + `clip_bounds` 已有类似分工，但没有把 `paint` 拆成背景/内容/前景多段。

### 2.5 LVGL v9：class 常量 + `base_class` 链

- 控件是静态 `lv_obj_class_t` 常量，字段包括 `base_class`、`constructor_cb(const lv_obj_class_t*, lv_obj_t*)`、`destructor_cb`、`event_cb(const lv_obj_class_t*, lv_event_t*)`、`instance_size`（v9.6 字段定义见 `src/core/lv_obj_class_private.h`）。
- 创建固定两步（内部）：`lv_obj_class_create_obj()`（按 `instance_size` 零初始化、挂 parent）→ `lv_obj_class_init_obj()`（`lv_theme_apply` → 递归 `lv_obj_construct`：先 base 后本类 → refresh style → group → parent 收 `LV_EVENT_CHILD_CREATED/CHANGED`）。
- 扩展：`base_class` 单向链 + 样式 part/state；自定义 part 从 `LV_PART_CUSTOM_FIRST`（`0x080000`）起，自定义 state 用 `LV_STATE_USER_1..4`，主题可设 `theme_inheritable`。行为覆写**没有虚表**：自己在 `event_cb` 里处理 `LV_EVENT_DRAW_MAIN/DRAW_POST` 等。
- 无 registry（class 是编译期常量）；唯一运行时注册是 `lv_event_register_id()`。
- 文档站已从 `docs.lvgl.io/master` 302 到 https://lvgl.io/docs/open ；官方 `widgets/new_widget` 教程正文为空（占位），实操以源码 `lv_button.c` 为准 `[未验证]`。
- 来源：https://lvgl.io/docs/open/common-widget-features/parts_and_states 、https://github.com/lvgl/lvgl/blob/release/v9.6/src/core/lv_obj_class.c 、https://github.com/lvgl/lvgl/blob/release/v9.6/src/widgets/button/lv_button.c 。

**对 Tessell 的提示**：LVGL 的"类表存方法指针 + base 链只覆盖差异"可替代每对象 vtable，适合内存受限场景；Tessell 是 GC 环境，收益主要在**把可覆写点集中到类表**，便于文档化，而不是省内存。

### 2.6 Clay：没有组件抽象

- README 原文："Re-useable components are just normal functions"；`CLAY(...)` 宏只是包装 designated initializer，产物是当帧布局节点，`Clay_EndLayout()` 才输出 `Clay_RenderCommandArray`。
- 自定义绘制：`.custom = { .customData = ptr }` + `Clay_CustomElementConfig`；renderer 遇到 `CLAY_RENDER_COMMAND_TYPE_CUSTOM` 时取 `config.customElementConfig->customData` 自绘。
- 状态不归 Clay：`Clay_SetPointerState` / `Clay_Hovered` / `Clay_OnHover(cb, userData)` / `Clay_GetElementData`；跨帧键是 `Clay_ElementId`（`CLAY_ID` / `CLAY_IDI` / `CLAY_AUTO_ID`）。
- 无 registry / 继承 / variant；https://clay-layout.com 抓取失败 `[未验证]`，以 https://github.com/nicbarker/clay 的 README 为准。
- `[未验证]` 未编译运行 Clay 示例；宏与字段名来自 README 与头文件静态阅读。

**对 Tessell 的提示**：Clay 反证了"组件抽象不是布局引擎的必需项"；但通用桌面组件需要焦点、键盘、a11y，Clay 把这些问题全部留给宿主，不适合直接照搬。

### 2.7 GPUI / gpui-kit：三层 trait，官方劝退底层实现

- 三层 trait：
  - `Render`: `fn render(&mut self, window: &mut Window, cx: &mut Context<Self>) -> impl IntoElement`；
  - `RenderOnce`: `fn render(self, window: &mut Window, cx: &mut App) -> impl IntoElement`（配 `#[derive(IntoElement)]`）；
  - `Element`: 关联类型 `RequestLayoutState` / `PrepaintState`，方法 `request_layout`、`prepaint`、`paint`。
- `element.rs` 模块文档明确：**多数情况不要实现 `Element`**，只有需要自控布局/绘制（自写布局算法、代码编辑器）才做；普通组件用 `Render` / `RenderOnce` + `div()` 组合。
- children：`ParentElement::extend(impl IntoIterator<Item = AnyElement>)`，默认提供 `child()` / `children()`。
- gpui-kit 的定制方式是 trait 组合：`ButtonVariants`（primary/danger/outline/compact…）+ `Sizable`（xsmall/small/…）+ 语义 token 主题（Theme/ThemeColor/ActiveTheme）；**无继承、无注册表**。
- 状态在 `Entity` / `Context<Self>`；元素树每帧重建、帧末丢弃，跨帧仅靠 `Element::id()` → `GlobalElementId`；`PrepaintState` 是单帧临时量。
- 来源：https://github.com/zed-industries/zed/blob/main/crates/gpui/src/element.rs 、https://gpui-kit.com/zh-CN/component/button/ 。

**对 Tessell 的提示**：GPUI 把"声明式组合（Render）"与"底层自绘（Element）"分成两层，且明确劝退后者；Tessell 的 Kit::Component 目前把两者压在一层，复杂自绘件与普通组合件用同一套四阶段，学习成本偏高但不失灵活。

## 3. 横向对比

表 1：组件定义与扩展方式

| 对象 | 自定义组件的最小单元 | 扩展已有组件的官方方式 | 扩展点性质 |
|---|---|---|---|
| asuka | 函数 → `ui.Node` | 包装函数 + children + 变体构造器 + `StyleFunc` | 组合 / 值覆盖 |
| Gio | struct + `Layout(gtx) Dimensions` | 组合 / decorator（子闭包、约束、clip） | 组合 |
| Fyne | `Widget` 接口 + `WidgetRenderer` | 嵌入 BaseWidget 覆写方法 + `ThemeOverride` | 继承 + 接口替换 |
| GTK4 | GObject 子类 + vfunc | 子类覆写 vfunc + CSS + template + 属性 | 继承 + 样式层 |
| LVGL | `lv_obj_class_t` 常量 | `base_class` 链 + part/state + `event_cb` | 类表继承 |
| Clay | 普通函数 | 无（只能组合函数） | 无抽象 |
| GPUI | `Render` / `RenderOnce`（底层 `Element`） | trait 组合 + 变体 props + 主题 token | 组合 + trait |

表 2：状态、生命周期、外观、分发

| 对象 | 状态归属 | 生命周期 / 销毁 | 外观 / 主题扩展 | 分发 / 注册 |
|---|---|---|---|---|
| asuka | signal owner 树 | `signal.OnCleanup` | `ui.Style` + 语义 token | Go module，无 registry |
| Gio | 调用方 struct 字段 | 无钩子（GC/调用方） | `material.Theme`（设计包补充） | Go module，无 registry |
| Fyne | widget 持有；renderer 可重建 | `Destroy()` | `fyne.Theme` + `ThemeOverride` | module + addons 目录 |
| GTK4 | GObject 实例 | `dispose` / `finalize` | CSS provider + template | GType/GIR，无包 registry |
| LVGL | `lv_obj_t` 实例 | `destructor_cb` | style part/state + theme apply | 类=编译期常量，无 registry |
| Clay | 完全外部 | 宿主管理 | 无主题系统 | 无 registry |
| GPUI | `Entity` / `Context` | `Drop` + 单帧 PrepaintState | `Theme` / `ActiveTheme` | crate，无 registry |

## 4. 五种扩展模型与 Tessell 的位置

| 模型 | 代表 | 扩展方式 | 优点 | 代价 |
|---|---|---|---|---|
| A 函数/闭包组合 | asuka、Gio、Clay、GPUI 默认 | 组件是函数，children 是参数/闭包 | 无继承负担、组合自由 | 焦点/键盘/a11y 需框架或应用自理 |
| B 接口 + renderer | Fyne | Widget 持状态，Renderer 画 | 状态/绘制分离，可换皮 | 双对象生命周期，renderer 可重建 |
| C 子类 + 虚函数 | GTK4 | 覆写 measure/allocate/snapshot | 粒度细、可只改一段 | 继承链脆弱，需约定虚函数 |
| D 类表 + base 链 | LVGL | class 常量 + base_class | 内存省、继承关系显式 | 无虚表，行为扩展靠事件分支 |
| E 无组件抽象 | Clay | 组件=函数，自绘走 customData | 内核小 | 通用交互全交给宿主 |

Tessell 现状 = **C（抽象基类 + 模板方法）+ A（Builder 声明 + Container 组合）**，再加一条独有的 key↔Node 映射。四阶段与参考对象的对应关系：

| Tessell 阶段 | GTK4 | Fyne | LVGL | GPUI |
|---|---|---|---|---|
| `measure` | `measure` | `MinSize` | 构造/刷新时算尺寸 | `request_layout` |
| `arrange` | `size_allocate` | `Layout(Size)` | 布局更新 | `request_layout` 后半 |
| `emit` | 无对应（子节点即对象树） | `Objects()` | 无对应（子对象即树） | `Render` 产出元素 |
| `paint` | `snapshot` | renderer 绘制 `Objects` | `DRAW_MAIN/POST` | `prepaint` + `paint` |
| `handle` | 事件控制器/信号 | `Tappable` 等接口 | `event_cb` | 事件冒泡/回调 |

> 表为语义近似，不是 API 一一对应；Fyne 的 `Objects()` 是"返回子对象供 canvas 绘制"，不是 Tessell 的声明缓冲。

## 5. Tessell 现状盘点

### 5.1 已经具备

| 能力 | 位置 | 说明 |
|---|---|---|
| 组件基类 | `src/tessell/kit/component.cr:9` | `abstract class Component`，四阶段 + 可选钩子 |
| 必需实现 | `component.cr:36,42` | `measure` / `emit` 是 abstract；`arrange` 有默认实现（`:38`） |
| 默认行为 | `component.cr:44-89` | `paint`、`focusable?`、`wants_tab?`、`handle`、`tick`、`hit?`、`clip_bounds`、`collect_components`、`paint_token` |
| a11y 元数据 | `component.cr:93-158` | role/name/value/focusable/enabled 等字段随声明同步 |
| 响应式作用域 | `component.cr:166-191` | 懒创建 `signal_owner`，`watch`，`dispose` |
| 组合容器 | `src/tessell/kit/container.cr:15,33,45,119,139` | `add`/`remove`、`b.group` 包子件、`collect_components` |
| 挂载入口 | `src/tessell/kit/root.cr:51` | `Root.new(@content : Component, theme, metrics, viewport, scale)` |
| 主题注入 | `src/tessell/kit/theme.cr:130` | `Theme` 是 struct，应用可用 `Palette` + `Metrics` 构造整套主题 |
| 外部组件范例 | `examples/apps/text_editor_app.cr:11` | `EditorView < Component`，注释明确"demo 级、不进 Kit 公共组件集"（`:3-4`） |
| 无 registry | `src/tessell/kit.cr:6-31` | 固定 require 列表；第三方组件不需要注册 |

`EditorView` 的关键一行（`:55-60`）：`emit` 里发 `b.node(@key, @bounds, paint: paint_token, a11y_role: TextField, ...)`。**只发子件、不发自身 key 的组件不会进入 `Root` 的映射**：`src/tessell/kit/root.cr:392` 用 `@pool.map[component.key]?` 绑定 Node，绑定失败就没有指针/焦点事件，也没有 a11y meta。这是参考对象里没有的、Tessell 特有的约束。

### 5.2 缺口（按扩展层面）

1. **结构层**：没有通用 slot/children 协议。`Container` 可以组合，但 `Button` 这类叶组件不能接受子内容；自定义复合组件只能在 `emit` 里手写子声明，或自建容器。参考对象里 Fyne/GTK 用 `Objects()`/子控件树、asuka 用函数实参解决。
2. **行为层**：内置组件的可覆写点没有契约化。`Button#measure/emit/paint/handle` 全是整段实现（`button.cr:30-140`），`inside?`/`activate`/`alpha` 是 `private`（`:158-168`）；子类想改"按下时多画一圈"只能重写整个 `paint`，容易漏掉焦点环或 disabled 分支。GTK 把这段拆成 vfunc，Fyne 拆成 renderer，LVGL 拆成 `event_cb` 分支。
3. **外观层**：主题只能整套注入 `Root.new`，没有 per-subtree override；`docs/kit/plan.md:65` 明确不做"任意样式覆盖或主题注册中心"，`plan.md:311` 才把 Theme token/适配器/作用域列为后续项。短期内第三方换肤只能换整套 `Theme`。
4. **语义层**：a11y 字段齐全，但第三方组件没有"必测清单"模板；`docs/kit/component-contract.md:77-86` 的六条门槛是内部约定，外部组件作者不一定知道。
5. **分发层**：没有第三方组件包约定（命名、入口、版本兼容、测试脚手架）；`AGENTS.md` 里的 `tools/kit_consumer_verify.sh` 只验证最小消费者，不验证"外部组件包"。
6. **生命周期**：`dispose` 契约清楚（`component.cr:188`、`root.cr:369-379`），但第三方组件容易忘记"重挂树后重建 watch"——`component-contract.md:31-35` 写了，缺一个可执行的模板。

### 5.3 一个外部组件的最小写法（示意，未编译）

```crystal
# 应用侧文件；不需要改 src/tessell/kit/
class Badge < Tessell::Kit::Component
  def initialize(@key : Tessell::UI::UiKey, @label : String)
    super(@key, true)
  end

  def measure(ctx : Tessell::Kit::Context, constraints : Tessell::Constraints) : Tessell::Size
    constraints.constrain(Tessell::Size.new(24.0_f32, 24.0_f32))
  end

  def emit(b : Tessell::UI::Builder, ctx : Tessell::Kit::Context) : Nil
    return unless @visible
    # 必须发带自身 key 的声明，否则 root.cr:392 绑不回本组件
    b.text(@key, @label, @bounds, paint: paint_token)
  end

  def paint(p : Tessell::Kit::Painter, ctx : Tessell::Kit::Context) : Nil
    return unless @visible
    # 只用 Painter 原语；不可见时与 emit 同口径早退
  end
end
```

方法签名以 `component.cr:36-44` 为准；`b.text` 的完整参数见 `src/tessell/ui/builder.cr:137`。这段代码只演示约束，未在仓库编译。

## 6. 建议（提案，未采纳）

### 6.1 扩展模型：组合优先，受控继承兜底

对外文档把"写组件"分成三条路径，按推荐顺序：

1. **组合**：用 `Container`/`Row`/`Column` 拼装内置组件；覆盖大多数应用自定义 UI 的需求。
2. **包装**：持有内置组件 + 追加绘制/事件；适合"加个角标/加个快捷键"。
3. **自绘 leaf**：继承 `Component`，实现 measure/emit/paint；适合图表、画布、编辑器。

这与 asuka/Gio 的组合优先、Fyne 的"嵌入 + renderer"一致；不鼓励应用直接继承 `Button` 改内部。

### 6.2 受控继承：给内置组件抽 `protected` 切面

建议在 `Button`（以及后续 Checkbox/Input）上抽以下几类 hook，默认实现保持现状，子类只覆写差异：

| hook | 职责 | 对应参考 |
|---|---|---|
| `protected def content_bounds : Rect` | 文本/图标可用区域 | GTK `snapshot` 前的 allocation、Fyne `Layout` |
| `protected def draw_background(p, ctx)` | 背景/边框 | GTK CSS 背景、LVGL `DRAW_MAIN` |
| `protected def draw_content(p, ctx)` | 文本/图标 | Fyne renderer 的 `Objects` |
| `protected def draw_foreground(p, ctx)` | 焦点环/覆盖层 | LVGL `DRAW_POST` |
| `protected def activate` / `protected def inside?` | 命中与激活 | GTK 事件控制器、Fyne `Tappable` |

约束：`emit` 仍由基类/内置实现负责发**自身 key** 的声明，hook 只改绘制与行为，不允许子类跳过 key（否则重蹈 `root.cr:392` 的坑）。这是一次重构提案，需按 `AGENTS.md` 不变量 6（零分配）与组件契约 spec 验证。

### 6.3 轻量入口（可选，优先级低）

参考 Gio 的单方法、asuka 的单函数，可为"只画不交互"的组件提供 `LeafComponent`（只要求 `measure` + `paint`，`emit` 由基类发一条自身 key 的 `b.node`）。但这会新增第二条组件路径，且必须保证 key 声明不被绕过；在 K6 之后、有真实第三方需求时再评估。

### 6.4 主题：短期整套注入，中期做作用域

- 短期：文档写明"第三方组件从 `Context#theme` 取 token，不读全局变量"；换肤 = 构造整套 `Theme` 传给 `Root.new`（`root.cr:51`）。
- 中期：按 `plan.md:311` 做 Theme token/适配器/作用域，不做注册中心、不做 Tailwind 式工具类（`plan.md:65`）。
- 不建议为第三方组件开放"任意样式覆盖"：参考对象里只有 GTK 的 CSS 层做到这个粒度，代价是样式解析与优先级复杂度；Tessell 的 `Metrics`/`Palette` 结构更接近 Fyne 的 Theme，整套替换已够用。

### 6.5 分发：shards 约定，不建 registry

- 组件包命名与入口：建议 `tessell-<name>`，入口 `require "tessell-<name>"`，只依赖 `tessell/kit` 公共 API，不 require 核心内部路径。
- 版本：在 shard.yml 里对 `tessell` 用 `~>` 约束；组件包自带 `spec/`，复用 `StubTextMetrics` + `PaintListPainter`（`spec/kit/spec_helper.cr:4-12`）。
- 契约：把 `component-contract.md:77-86` 的六条门槛做成模板 spec；`tools/kit_consumer_verify.sh` 增加"外部组件包"用例（当前只验证最小消费者）。
- 不做 registry：七家参考对象都没有；Crystal 生态也没有集中索引的强需求。

### 6.6 文档：补 `docs/kit/extending.md`

现有文档分工：`component-contract.md` 是内部约定，`cookbook-custom-widget.md` 讲表格/时间线类大控件，`apps.md` 是示例索引；**缺一篇面向应用开发者的"如何写组件/如何扩展"**。建议新增 `docs/kit/extending.md`，内容即 §6.1 的三条路径 + §5.3 的最小模板 + §5.2 的六个坑（key、visible 双守卫、dispose/watch、a11y、Painter 边界、主题 token），并从 `docs/kit/index.md` 链接。`EditorView` 可提炼为"应用内组件"的完整例子。

## 7. 未验证与风险

- **未运行任何参考框架示例**；asuka/Gio/Fyne/GTK/LVGL/Clay/GPUI 的运行时行为结论均来自官方文档与源码静态阅读。GTK 三个 vfunc 页面已 200 核对；Fyne custom-widget 页面 200 但正文由 JS 渲染，接口签名以 `pkg.go.dev` 与源码为准；`raw.githubusercontent.com` 直连失败。
- asuka 仍为 alpha，API 可能变动；LVGL 文档站迁移中，`widgets/new_widget` 正文为空；Clay 官网抓取失败；GPUI 的 `Element` 关联类型与方法签名按 `element.rs` 当前 main 阅读，Zed 迭代快。
- Tessell 侧未实测"第三方 shard 消费组件库"（只有 `tools/kit_consumer_verify.sh` 的最小消费者）；§6.2 的 hook 重构未做零分配与契约 spec 验证。
- 本文的"五种模型"是归纳，不是参考对象的自我分类；跨框架的"扩展点"并非严格同构，表 1/表 2 只用于找差异。

## 8. 参考链接

**asuka**
- https://asuka.egoist.dev/zh
- https://github.com/egoist/asuka

**Gio**
- https://gioui.org/doc/architecture/widget
- https://gioui.org/doc/architecture/layout
- https://gioui.org/doc/learn/split-widget
- https://github.com/gioui/gio （源码镜像；官方仓库为 git.sr.ht/~eliasnaur/gio）

**Fyne**
- https://docs.fyne.io/extend/custom-widget
- https://docs.fyne.io/extend/
- https://pkg.go.dev/fyne.io/fyne/v2#WidgetRenderer

**GTK4**
- https://docs.gtk.org/gtk4/vfunc.Widget.measure.html
- https://docs.gtk.org/gtk4/vfunc.Widget.size_allocate.html
- https://docs.gtk.org/gtk4/vfunc.Widget.snapshot.html
- https://docs.gtk.org/gtk4/class.Widget.html

**LVGL**
- https://lvgl.io/docs/open （parts/states 见 common-widget-features 子页）
- https://github.com/lvgl/lvgl/blob/release/v9.6/src/core/lv_obj_class.c
- https://github.com/lvgl/lvgl/blob/release/v9.6/src/widgets/button/lv_button.c

**Clay**
- https://github.com/nicbarker/clay

**GPUI / gpui-kit**
- https://github.com/zed-industries/zed/blob/main/crates/gpui/src/element.rs
- https://gpui-kit.com/zh-CN/component/button/
