# M4-WP1 DSL 与状态 API 设计草案

> 基线：HEAD `1f238b2`。读码：`core/node.cr`、`layout.cr`、
> `render/{draw_list,backend,theme}.cr`、`widgets/virtual_list.cr`、
> `input/{event,focus,router}.cr`、`a11y/tree.cr`、`docs/plan.md:263`。
> 仅设计草案，未实现、未跑实测（见§8）。

## 1. 目标与非目标
- **结论**：目标=声明式构建 UI 树、外部状态驱动更新、最小失效传播到
  `Invalidation` 三级。非目标：不做宏生成骨架 UI、不做 CSS 级样式、
  不做布局约束求解器。
- **依据**：`core/node.cr:19-23` 三级；`:66-76` `mark_dirty` 传播；
  `layout.cr:128-132` `solve` 两遍；`plan.md:263` M4-WP1 3–5 pd。
- **缺口**：无声明式层/状态容器；`tessell.cr` require 清单无 DSL 模块。

## 2. API 形状候选与取舍
- **结论**：推荐 A（链式 builder + 稳定 key）；B 备选；C 暂缓。

### A. 链式 builder（推荐）
```crystal
module Tessell::UI
  def self.panel(id : String,
      w : Layout::Dimension = Auto.new,
      h : Layout::Dimension = Auto.new,
      pad : Insets = Insets.new,
      & : BuildContext -> Nil) : Tessell::Node; end
  def self.text(id : String, value : String,
      font_id : Int32 = 0,
      font_px : Float32 = 0.0_f32) : Tessell::Node; end
end
class Tessell::UI::BuildContext
  def child(node : Tessell::Node) : Nil; end
  def keyed(key : String,
      & : -> Tessell::Node) : Tessell::Node; end
end
```
接缝：产出 `Node`（`core/node.cr:26-33` id/bounds/children），几何由
`Layout.solve(LayoutNode,Constraints)` 回写（`layout.cr:15-48,128-132`）。
`keyed` 为稳定 id 复用入口。

### B. 结构体树装配（备选）
```crystal
record VNode, key : String, kind : Symbol,
  props : NamedTuple, children : Array(VNode)
def self.mount(v : VNode,
  parent : Tessell::Node) : Tessell::Node; end
```
接缝同 A，但需额外 VNode 缓冲；diff 易做。

### C. 宏 `build_ui!`（暂缓）
```crystal
macro build_ui!(root, &blk); end
```
省运行时分配但错误可读性差、编译耗时升（`plan.md:263` 风险）。

- **依据**：`core/node.cr:103-115` `add_child`；`:119-128` `remove_child`；
  `layout.cr:36-38` children 为 `Array(LayoutNode)`。
- **缺口**：Node 无通用属性槽；Node 与 LayoutNode 两套类型需桥接层。

## 3. 状态与重建策略
- **结论**：
  **每帧重建树在零分配判据（A `<1000`、B `<=256`）下等价于自杀**。
  全量 new Node/LayoutNode/Array 及闭包捕获会击穿 A/B。采用
  「外部不可变状态快照 + 渲染函数 + 稳定 id 复用/节点池 + 脏集最小化」。
- **与失效级对应**：
  - 仅样式/文本变 → `mark_dirty(Paint)`（`:72`，不向上传播）。
  - 尺寸/结构/顺序变 → `mark_dirty(Layout)`（`:69-70`，向上传播父链）。
  - 仅合成层变 → `mark_dirty(CompositeOnly)`（`:74`）。
  池复用已 detach 节点（`:132-137`）免 new；key 命中原位更新并择级
  mark_dirty；`collect_dirty`（`:97-100`）+ sink 复用产出最小脏集，
  供 `Backend.begin_frame(dirty, theme)`（`backend.cr:25`）。
- **依据**：`core/node.cr:66-76,97-100,132-137`；`backend.cr:25`；
  `draw_list.cr:58-60` clear 仅重置计数可复用；`plan.md:263`。
- **缺口**：池容量、key 冲突、diff 选型未定 `[未验证]`。

## 4. 与 VirtualList 不物化万行契约
- **结论**：DSL 不得展开 `row_count` 子节点；仅声明数据源与可见窗口，
  由 `VirtualList` 计算范围并回调绑定。
- **形状（草案）**：
```crystal
UI.virtual_list(id, row_count : Int32, row_h : Int32,
  viewport_h : Int32, fetch : Proc(Int32, Nil)) { |i, y|
    UI.row(i, y) { } }
```
- **依据**：`widgets/virtual_list.cr:57-59` ctor；`:299-364`
  `prepare_visible` 只处理 `[visible_first,last]`；`:404-406`
  `recycle_stats` 约束 pool/created；`a11y/tree.cr:141-184`
  `VirtualWindow.emit` 仅产可见项，`children_count=list.row_count`
  （`:157`）、`scroll_offset=list.scroll_y`（`:159`）保留逻辑总数。
- **缺口**：row builder 与 `fetch`/回收槽位对齐待原型验证。

## 5. 可测判据 D1–D6
| ID | 判据 | 怎么测 |
|---|---|---|
| D1 幂等脏集 | 同态两次 build，`collect_dirty` 空或同 | build→clean!→同态 build，比 sink |
| D2 脏集最小 | 单点变化仅脏受影响子树 | 改一叶 props，断言 sink 最小 |
| D3 不增节点 | 稳态 rebuild 节点数不增，池命中>0 | 计 Node.new/命中；断言复用或恒定 |
| D4 零分配帧 | 稳态帧满足 A `<1000`、B `<=256` | 复用 zero_alloc_frame 探针法 |
| D5 a11y 同步 | DSL 变更后 a11y 镜像一致 | `A11y::Builder.build`(`:87-89`) 对比 |
| D6 事件单入口 | 交互只经单一路由 | 只入 `Router.handle`(`:35-59`) 断言 |

- **依据**：`core/node.cr:86-100`；`a11y/tree.cr:87-126`，focused 取自
  `FocusManager#focused?`（`:105`）；`router.cr:35-59`；`focus.cr:37-39`。
- **缺口**：D3/D4 度量脚本与阈值待对齐 perf-band `[未验证]`。

## 6. 风险 R1–R8
| ID | 风险 | 影响/缓解 |
|---|---|---|
| R1 | 宏/泛型编译期成本 | 增量变慢；限宏层级，计时（`plan.md:263`） |
| R2 | 闭包捕获分配 | 击穿 A/B；热路径禁捕获，复用 Proc |
| R3 | 误用 `mark_dirty(Layout)` 全树重排 | 祖先全脏（`:69-70,139-145`）；封装 Paint |
| R4 | 树生命周期与 FocusManager 悬挂 | detach 后失效（`focus.cr:60-78`）；先迁移焦点 |
| R5 | DSL 树与 a11y 双树不一致 | 漏同步；build 后统一 walk（`a11y/tree.cr:87-126`） |
| R6 | 调试困难（无 DevTools） | 脏集不可视；提供 dump/trace 与可读 id |
| R7 | 宏错误可读性差 | C 路线放大；推荐 A/B，宏仅薄糖 |
| R8 | 与 VirtualList 语义冲突 | 误物化万行/双滚动态；§4 契约+spec 守护 |

- **依据**：`node.cr:69-70,139-145`；`focus.cr:60-78`；`a11y/tree.cr:87-126`；
  `widgets/virtual_list.cr:299-364`；`plan.md:263`。
- **缺口**：R1 编译样本、R2 实际分配点需原型剖析 `[未验证]`。

## 7. 工作量估算与拆分（3–5 pd）
| 子步 | 交付物 | 判据 | 估算 |
|---|---|---|---|
| S1 接缝+最小 builder | `UI.panel/text`+桥接+稳定 key | 可 `solve`+渲染；D1 幂等绿 | 1–1.5 pd |
| S2 状态更新与最小脏集 | 外部快照→diff→择级 mark_dirty+池复用 | D2/D3 过；无全树 Layout 误传 | 1–2 pd |
| S3 VList+a11y+perf | 绑 `prepare_visible`；a11y 同步；取数 | D4–D6；1k 行不物化 | 1–1.5 pd |

- **依据**：`plan.md:263`（3–5 pd）；`core/node.cr:66-100`；
  `widgets/virtual_list.cr:299-364`；`a11y/tree.cr:87-126`；`router.cr:35-59`。
- **缺口**：S2 diff 复杂度与池调参或溢出至 2 pd `[未验证]`。

## 8. 未验证清单
- `[未验证]` 宏/链式 builder 稳态帧分配与 GC 行为；
  **所需**：原型+alloc 探针（对齐 D4），Windows ucrt64 实测。
- `[未验证]` 稳定 key diff 大子树重排 CPU/编译开销；
  **所需**：1k/10k 样本基准与编译耗时采样（`plan.md:263`）。
- `[未验证]` 节点池与 `virtual_list.cr:107-111` pool_size 协同；
  **所需**：长列表滚动压力 spec。
- `[未验证]` FocusManager 在节点复用/替换下焦点保持语义；
  **所需**：结合 `focus.cr:60-78`、`router.cr:35-49` 交互 spec。
- `[未验证]` Node↔LayoutNode 桥接是否引入每帧额外对象；
  **所需**：对照 `layout.cr:15-48` 做复用方案与测量。
- `[未验证]` `a11y/tree.cr` Meta 在 DSL 更新下增量同步成本；
  **所需**：Builder.build 全量 vs 增量基准对比。