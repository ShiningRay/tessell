# M2-WP5 无障碍最小树 — 证据报告

- 任务：task-72（M2-WP5：无障碍最小树 A11y::Node/Role/Builder/VirtualWindow + J1–J9 判据 spec）
- 时间：2026-11-13（Asia/Shanghai，本轮收口）
- 工作区：`C:\Users\ShiningRay\projects\ShiningRay\tessell`，HEAD `7cfb44f`（未 commit）
- 设计依据：`docs/research/a11y-tree.md`（158 行，hanlin-bianxiu，task-69）；M2 仅做平台无关最小无障碍树 + 判据，不做 Windows UIA COM provider
- 交付文件：`src/tessell/a11y/tree.cr`，`spec/a11y_tree_spec.cr`，`docs/evidence/M2-WP5-a11y-tree.md`；`src/tessell.cr` 末尾追加 `require "./tessell/a11y/tree"`
- 约束遵守：**未改** `src/tessell/core/node.cr`、`src/tessell/input/*`、`src/tessell/render/*`、`src/tessell/text/*`、`src/tessell/widgets/*`；未 commit；无 FFI
- 关联裁断：M2-WP4 真实 CPU 帧路径残余（~4KB/1000 帧，低频重复分配事件）**由 task-73 承接**（承 lead m01527 裁断），本任务不扩挖

## 1. 实现概述（schema / 组件）

- `Tessell::A11y::Role`（enum）：`Window, Group, Text, Button, List, ListItem, ScrollView, Scrollbar`（M2 最小集）。
- `Tessell::A11y::Meta`（struct，旁挂元数据，不改 core::Node）：`role, name, value, focusable, enabled`；`Builder#set_meta(id, ...)` / `meta_for` 维护 `Hash(UInt64, Meta)`。
- `Tessell::A11y::Node`（struct，与 `Tessell::Node` core 冲突命名隔离）：`id: UInt64, role: Role, name: String, value: String, bounds: Tessell::Rect, focusable: Bool, focused: Bool, enabled: Bool, children_count: Int32, index_in_parent: Int32, scroll_offset: Int32`。
- `Tessell::A11y::Builder`：`initialize(@focus : Input::FocusManager? = nil)`；`build(root : Tessell::Node, sink : Array(A11y::Node))` DFS 先序遍历 retained 树向**复用 sink**追加（内部先 `sink.clear`）；`build(nil, sink)` 清空 sink（J1 空树）；`focused` 由 `@focus.try(&.focused?(node))` **实时查询**，不另存焦点状态；`children_count = node.children.size`；`index_in_parent` 由遍历下标给出；`name/value/role/focusable/enabled` 取自 Meta，未设置时 `name/value` 为空串。
- `Tessell::A11y::VirtualWindow`：`emit(list : Widgets::VirtualList, sink, ...)` 先 `prepare_visible`，输出 1 个容器 `List` 节点（`children_count=list.row_count`，`scroll_offset=list.scroll_y`）+ 仅可见窗口 `ListItem` 节点（按 `visible_first..visible_last`），**不为 10000 行物化 10000 节点**；item id 为稳定合成（list 身份 × 行索引混合）。

## 2. schema 与 `core/node.cr` 映射表

| A11y 字段 | 来源 / 规则 | core::Node 对应 | 说明 |
|---|---|---|---|
| `id` (UInt64) | `Builder`: `node.object_id.to_u64`；`VirtualWindow`: list/item 合成 id | `Node` 无稳定业务 id 字段 | 只读身份；未改 core（core 有 `id:String` 但 A11y 取 object 身份以直接对应实例） |
| `role` (Role) | `Meta.role`，默认 `Group` | 无 | 旁挂，不污染 core |
| `name` (String) | `Meta.name`，未设置 `""`（非 `"(null)"`） | 无 | 旁挂；J6 证实 |
| `value` (String) | `Meta.value`，未设置 `""` | 无 | 旁挂 |
| `bounds` (Rect) | `node.bounds` 逐字段同值 | `bounds : Rect` (`core/node.cr:28`) | 同坐标系，只读拷贝；J8 证实 |
| `focusable` (Bool) | `Meta.focusable`，默认 false | 无（可聚焦谓词在 `Input::FocusManager`） | 旁挂声明；焦点真相见下 |
| `focused` (Bool) | `@focus.try(&.focused?(node))` 实时查询 | 无 | **单一真相**：`FocusManager`（`input/focus.cr`）唯一源，不另存 |
| `enabled` (Bool) | `Meta.enabled`，默认 true | 无 | 旁挂 |
| `children_count` (Int32) | `node.children.size`（Builder）/ `list.row_count`（VirtualWindow 容器） | `children : Array(Node)` (`core/node.cr:30`) | 虚拟列表用逻辑总量，不等于物化子节点数 |
| `index_in_parent` (Int32) | DFS 遍历时父传入下标 | `parent : Node?` (`core/node.cr:29`) 可派生 | 遍历序稳定；J7 |
| `scroll_offset` (Int32) | Builder 普通节点 0；VirtualWindow 容器 `list.scroll_y` | 无 | 虚拟列表三元组信息（设计稿 §4） |

结论：core::Node 未修改；A11y 以只读镜像/旁挂方式复用 `bounds/children/parent` 关系与 `FocusManager` 焦点源。

## 3. J1–J9 实测结果

执行命令（`$env:PATH="C:\msys64\ucrt64\bin;$env:PATH"`，工作目录仓库根）：
- `crystal spec spec/a11y_tree_spec.cr` → **10 examples, 0 failures, 0 errors, 0 pending**，EXIT=0
- `crystal spec`（全量）→ **171 examples, 0 failures, 0 errors, 0 pending**，EXIT=0

零分配/复用探针输出（J9）：
`zero-alloc probe(a11y_build): delta_prime=0 delta_calib=0 delta_work=0 N=1000 windows=[0,0,0] retried=false attempt=1`

| 判据 | 结果 | 证据要点 |
|---|---|---|
| J1 空树 → sink 空 | PASS | `Builder#build(nil, sink)` 后 `sink.size==0`（预填充后仍清空） |
| J2 单节点 → 1 节点且 `index_in_parent==0`、`children_count==0` | PASS | root 单节点 DFS 产出 1，字段与 role=Group 符合 |
| J3 焦点同源 | PASS | `FocusManager#focus(a)` 后仅 a `focused==true`（`focused_nodes.size==1` 且 id 匹配），b 为 false；`blur` 后全 false |
| J4 焦点节点被移除（detach/remove_child）后重建树不崩、无残留 focused | PASS | detach(a) 且 focus 仍指向 a 时，重建树不含 a 且 `any? focused==false`；remove_child(c) 同理 |
| J5 10000 行 VirtualWindow → 节点数 ≤32 | PASS | 10000×20px, viewport 600：`sink.size <= 32` 且 `== 1 + visible_count`（31 可见 → 32），容器 `children_count==10000`、`scroll_offset==0` |
| J5b 滚动后仍 ≤32 且暴露 scroll_offset/children_count | PASS | `scroll_to(12340)` 后 `sink.size <= 32`、`container.children_count==10000`、`container.scroll_offset==vl.scroll_y` |
| J6 name/value 来源 | PASS | `set_meta` 后 name/value/role/focusable 一致；未设置节点 `name==""` 且 `name != "(null)"` |
| J7 遍历顺序稳定（DFS 先序） | PASS | 两次 build id 序列相同，等于 `[root,a,b,c]`（先序，a 下挂 b） |
| J8 bounds 与 `node.bounds` 逐字段相等 | PASS | origin.x/y、size.width/height 全等（含小数 Rect） |
| J9 sink 复用 + 稳态零分配 | PASS | 预热后 1000 次 build `sink.to_unsafe` 不变；稳态探针 A/B（`delta_work < N` 且 `<=256`）3 窗 max、允许 1 次整套重试、`GC.enable` in ensure：`delta_work=0 windows=[0,0,0] retried=false attempt=1` |

节点数硬证据：J5/J5b 在 10000 行虚拟列表上 `emit` 后节点数 **≤32**（容器 1 + 可见窗口项 ≤31），`children_count` 保持 10000 逻辑总量。

## 4. 未做 UIA 的理由与残留接口形状（引 `docs/research/a11y-tree.md` §5）

- **未做理由（M2 决策）**：Windows UIA 需 COM provider（`IRawElementProviderSimple` 等）与 UI Automation Core 导出（如 `UiaReturnRawElementProvider` / `UiaHostProviderFromHwnd`）。本机仅实测 `UIAutomationCore.dll` 存在（System32/SysWOW64），**未核实导出符号清单与 vtable/线程模型/生命周期**；COM vtable 手写与 STA 亲和风险高，且 task 范围为 M2 最小树（`docs/research/a11y-tree.md` §5 C4/R1/R2，`docs/architecture.md:181` provider 后置）。贸然落地违反“未实测不编造”纪律，故 M2 不做 provider。
- **残留接口形状（供 M3 适配）**：`A11y::Role` / `A11y::Meta` / `A11y::Node` / `A11y::Builder` / `A11y::VirtualWindow` 为平台无关数据与构建层；`focused` 已按 FocusManager 单一真相只读查询。未来 Windows provider 可在不改 core 的前提下以 `A11y::Node` 序列为数据源做适配（如 `IRawElementProviderSimple`/`WM_GETOBJECT` 探针路径，`docs/research/a11y-tree.md` §5/§8 建议）——**[未验证/推断]** 具体导出名、vtable 布局与 M3 接入细节未在本机实测。

## 5. 未验证清单

- 屏幕阅读器兼容（NVDA / Narrator）与真实可访问性语义：**未验证**（M2 无 UIA provider，无法端到端朗读验证）。
- DPI（物理像素 vs DIP）与高 DPI（96/144）下 bounds 解释：**未验证**。
- 双树一致性（retained 树增删/脏变更与 a11y 重建同步时机、遗漏风险）：**未验证**（R7）。
- UIA COM 线程模型（STA/UI 线程亲和）、AddRef/Release 生命周期、PE 导出符号：**未验证**（R1/R2）。
- 焦点谓词动态变更后 a11y focusable 视图刷新策略：**未验证**（R8）；焦点落在虚拟列表被回收行时回落与 a11y 联动：**未验证**（设计稿 §4）。
- J9 零分配判据：按现行 A/B（`delta_work < N` 且 `<=256`，3 窗 max，重试 ≤1）观测为通过，但**不能证明绝对零分配**（≤256B 稀疏/簇状仍可能放过，见 `docs/evidence/M2-WP2c-zero-alloc-criterion.md`「能证明什么/不能证明什么」）。

## 6. 结论与备注

- M2-WP5 最小无障碍树已落地：只读镜像 + 旁挂 Meta，不改 core/input/render/text/widgets；`focused` 实时同源 `FocusManager`；万行虚拟列表 a11y 窗口节点 ≤32 且携带 `children_count/scroll_offset`。J1–J9 全部通过，spec/a11y 10/0，全量 171/0。
- 遗留：UIA provider 与端到端可达性验证留待 M3；M2-WP4 真实 CPU 帧路径低频重复分配残余（~3.9KB/1000 帧，A 门未过）**由 task-73 承接**（m01527）。

(End of file)
