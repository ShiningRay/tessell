# M2-WP4/WP5 设计预研：虚拟列表（复用/CompositeOnly/零分配滚动）与 a11y 最小树

> 状态：纯调研草案（未实现/未改码）。每条事实标来源（文件:行 或命令输出）；推演/未测标 `[未验证]`；禁编造 API/数值。
> 任务：task-50「M2-WP4/WP5 设计预研」（HEAD=76ef5d6，任务书）；采集 2026-11-13 02:13:02 +08:00（`git rev-parse HEAD` = 76ef5d6e6f06b6358329049a049c89d32c913a1e）。
> 锚点：`docs/plan.md:91,118,167,169-173,219,246-247`；`docs/architecture.md:160-162,168,181,219,235`；`src/tessell/core/node.cr:19-23,66-76,97-100`；`src/tessell/render/dirty.cr:18,24-30,30-88`；`docs/evidence/M0-WP5m-metrics.md:203-224,273-274`；`docs/evidence/M1-WP5-zero-alloc.md:3-4,26-34,39-51,54-59`。
> 写入范围：仅本文件；未改 `src/`/`spec/`/`tools/`/`examples/`/其他 docs。

## 0) 范围与口径（可执行边界）

- 仅设计预研，不写实现；接口签名均为建议草案，命名与 `docs/plan.md`/`docs/architecture.md` 术语对齐（`Invalidation`/`CompositeOnly`/`MeasureKey`）。
- 零分配判据一律走 M1-WP5 协议窗口，default/首帧/冷启动/扩页路径不得计入通过（`docs/plan.md:167`；`docs/evidence/M1-WP5-zero-alloc.md:54-59`）。
- 帧时间一律以分布（p50/p95/p99）判定，不设具体 ms/FPS 门限（`docs/plan.md:169-173`；`docs/architecture.md:219`）。
- 7 节覆盖：模型/脏区/零分配/帧时间/a11y/验收判据/风险，每节首行为结论句，便于评审抽取。

## 1) 虚拟列表模型（可见区间/复用池/CompositeOnly/数据源回调）

**结论**：列表容器按「视口实例化 + 复用池」工作；滚动位移走 `Invalidation::CompositeOnly`（只平移合成、不触 Layout/Paint 重排），数据源只提供「索引→行内容」回调，禁止一次性物化万行。

- 可见区间两档：固定行高（`first_visible = scroll_y / row_h`，整数区间直接算）与可变行高（需高度前缀和/估算区间，测量成本见 §7 `[未验证]`）。视口 `Rect` 与 `Constraints` struct 对齐（`src/tessell/geometry.cr`，`docs/plan.md:76`）。
- 复用池（recycler）：滚动时移出视口的行节点回收入池，新进入视口的行从池取节点并重绑定内容；池容量按「视口行数 + 缓冲行数」预付，避免每帧 new（对照 `DrawList` clear 保留物理槽位/push 原位复用策略，`src/tessell/render/draw_list.cr:56-67,76-87`）。
- `CompositeOnly` 路径：滚动仅改容器/内容偏移，节点 bounds 几何不变 → 只标 `CompositeOnly`（`src/tessell/core/node.cr:73-75`），布局与绘制缓存不重算；缓存平移而非重绘（`docs/architecture.md:160-162`「滚动走这里」「平移缓存而非重绘」）。
- 数据源接口：`fetch(index : Int32) : RowData`（建议签名，非实现）按需取行；列表容器只对可见+缓冲行建 retained 节点；万行只实例化可见子集（`docs/plan.md:118`「视口实例化 + 复用」「禁止一次性超大节点集」；`docs/architecture.md:168`「不提供一次性建十万节点的用法」）。
- 索引→槽位映射：建议以「行索引 → 池槽位」预分配表（固定行高可 O(1) 直接定位；可变行高以前缀和+二分定位，O(log n)）`[推断]`；锚点行（anchor index）在复用重绑定时保持不变，避免滚动抖动 `[推断]`。
- 滚动与跳转差异：`scroll` 为增量位移（池命中路径），`jump` 为绝对定位（可能整窗重绑，属非稳态首帧豁免，见 §3）。

## 2) 失效与脏区（滚动 N 行策略、merge_into、复用重绑定标 Paint 不标 Layout）

**结论**：滚动脏区用「条带 + `Dirty.merge_into` 合并到 max_regions=8」；复用节点重绑定内容时几何不变只标 `Paint`，结构/尺寸变化才标 `Layout`。

- 三级失效语义：`Layout` 向上传播父链、`Paint` 仅自身、`CompositeOnly` 仅合成（`src/tessell/core/node.cr:3-12,53-76,139-151`；`docs/plan.md:91`）。
- 滚动 N 行方案对比：整窗标记（简单但全量重绘，违背部分提交）/ 条带标记（仅新暴露+移出区，`Rect` 并集）/ 条带+`merge_into`（推荐：对接 `Dirty.merge_into(rects, sink, max_regions=8)`，while 索引+原地 union，不新分配，`src/tessell/render/dirty.cr:24-30,30-88`；`docs/evidence/M1-WP5-zero-alloc.md:11-12`）。
- 条带 Rect 计算：新暴露区 = 滚动位移扫过的视口外条带；移出区内容由复用池回收，其旧 `DrawCmd` 经 `DrawList.clear` 逻辑清零（保留物理槽位，`src/tessell/render/draw_list.cr:56-57`）`[推断]`。
- 复用重绑定：行内容变化但行高/几何不变 → `mark_dirty(Paint)`（只重绘该行，`src/tessell/core/node.cr:70-71`）；行高/结构变化 → `mark_dirty(Layout)` 并传播父链（:66-69,139-145）；纯滚动位移 → `mark_dirty(CompositeOnly)`（:73-75）。
- 与 M1-WP3 衔接：滚动帧不触发 Layout 子树重排，`collect_dirty` 只收集真正脏节点（`src/tessell/core/node.cr:92-100`；`docs/evidence/M1-WP5-zero-alloc.md:9`）。
- `merge_into` 超出 `max_regions=8` 时的行为（丢弃/合并为大区/回退整窗）未实测 `[未验证]`（`src/tessell/render/dirty.cr:18,30-88` 仅证合并逻辑本身）。

## 3) 零分配口径（scenario=scroll/jump、协议一致、豁免路径）

**结论**：新增 `scenario=scroll`（200 帧、每帧 1 行、复用池稳态）与 `scenario=jump`（跳转后单帧）必须复用 M1-WP5 协议；首帧/扩容/新行内容加载可豁免但须单独观测。

- 协议（与 `tools/zero_alloc_frame.cr` 一致）：`warmup → GC.collect → before=GC.stats.bytes_since_gc → GC.disable → N 帧 → after → GC.enable(ensure)`，`alloc_bytes=after-before`，`delta_zero=(alloc_bytes==0)`（`docs/evidence/M1-WP5-zero-alloc.md:3-4,26-34`；`tools/zero_alloc_frame.cr:83-103`）。
- 稳态要求：复用池命中仅查表/重绑定字段、写预分配缓冲；不 new Array/字符串/闭包（对照 `zero_alloc_frame.cr:4-8,42-69` 纪律）；`DrawList.reserve` 预付槽位避免热路径扩容（`src/tessell/render/draw_list.cr:82-87`；`docs/evidence/M1-WP5-zero-alloc.md:57`）。
- 数据源边界：`fetch` 回调内部若分配（字符串/数组）属数据源责任，建议回调写入预分配 `RowData` struct；零分配窗口内回调不得触发 GC 分配 `[推断]`。
- 豁免路径（允许分配但不得计入通过）：首次建池/池扩容、首帧、跳转后首次新行内容 fetch/raster、GC 窗口外的结构变更帧（`docs/plan.md:167`「启动、首帧、资源加载、结构变化帧不计入稳态」；`docs/evidence/M1-WP5-zero-alloc.md:54-59`）。
- `GC.enable` 必须置于 `ensure` 块，窗口内异常也恢复 GC（`docs/evidence/M1-WP5-zero-alloc.md:26-34` 协议顺序；task-23 补证 `tools/bench_frame_time.cr` 同纪律）。
- 判据：`scenario=scroll` 200 帧 `alloc_bytes==0 && delta_zero==true`；`scenario=jump` 单帧非 0 须记录来源（不凑 0，`tools/zero_alloc_frame.cr:8,156-162` 同纪律）；输出 token 对齐现有 `scenario/frames/nodes/alloc_bytes/delta_zero`（`tools/zero_alloc_frame.cr:149-154`）。

## 4) 帧时间判据（万行滚动 p50/p95/p99、量级参考、度量方法）

**结论**：万行（10000 行 × 20px）滚动以帧时间分布判定；目标值属 `[未验证]` 推演，量级参考 M0-WP5m 实测。

- 量级参考（M0-WP5m 实测，纯逻辑 200 节点）：steady 3 次中位 `p50_us=14.6 p95_us=17.2 p99_us=22.4`；default 3 次中位 `p50_us=17.5 p95_us=23.0 p99_us=28.8`（`docs/evidence/M0-WP5m-metrics.md:203-224,273-274`）；task-23 补证 120 帧 steady `p50_us=17.7 p95_us=26.5 p99_us=29.4`、default `p50_us=22.6 p95_us=36.4 p99_us=45.8`（`docs/evidence/M0-WP5m-metrics.md:289-327`）。
- 目标值 `[未验证]` 推演：万行稳态滚动 p99 建议 < 1 帧预算的 1/3（如 60Hz → < ~5.5ms）；该数值无本机实测支撑，仅作设计目标，不作门禁断言（`docs/plan.md:169,173`「不设定具体 ms/FPS 数值门限」；`docs/architecture.md:219,223`「以帧时间分布为准，非平均帧率」）。
- 度量方法：复用/扩展 `tools/bench_frame_time.cr`（`--frames/--warmup/--json/--steady`，token `p50_us/p95_us/p99_us/alloc_bytes`，`docs/evidence/M0-WP5m-metrics.md:13,192-194`）新增 `scenario=scroll/jump`；或按 `zero_alloc_frame.cr` 协议扩展；嵌入真实窗口 `SwapBuffers` 前后采样见 M0-WP5m §7 `[未验证]`（:249-259）。
- 口径纪律：warmup 帧数与 N 帧窗口须与 M1-WP5 一致（static/paint1 为 200 帧/205 节点基线，`docs/evidence/M1-WP5-zero-alloc.md:39-51`）；滚动场景的「每帧 1 行」位移量须固定，避免位移量差异污染 p99 `[推断]`。
- 分布记录：除 p50/p95/p99 外保留逐帧样本或直方图，避免均值掩盖尖刺（`docs/plan.md:219`「帧时间分布非平均 FPS」）。

## 5) a11y 最小树（节点模型/与 core 关系/最小 API/焦点同步/UIA FFI）

**结论**：a11y 树建议与 retained 树并行维护（视图包装或镜像节点），最小 API 支持遍历/检视；焦点复用 `FocusManager` 焦点环；Windows UIA 接入纯 FFI 可行性 `[未验证]`。

- 节点模型：`role/name/value/bounds/focusable/children`（建议 struct/record，`bounds` 复用 `Rect`）；与视觉树前序对齐（`docs/plan.md:247`「最小可检视/可遍历树」；`docs/architecture.md:181`「无障碍树与 widget 树同步维护」）。
- 与 `core/node` 关系：并行树（a11y 节点引用 `Node` 或独立镜像）优于改 `Node` 类（`src/tessell/input/focus.cr:9`「本包不修改 Node 类」同理）；视图包装可在 M2-WP5 先做只读镜像 `[未验证]`。
- 坐标系：`HitTest.deepest` 视节点 `bounds` 为 root 坐标系绝对坐标（`src/tessell/input/hit_test.cr:6`），a11y `bounds` 可直接复用节点 bounds，无需二次换算 `[推断]`。
- 最小遍历/检视 API（建议签名）：`children() : Array(A11yNode)`、`get(role/name/value/bounds)`、`find_focusable`；遍历顺序 == 视觉树前序（对照 `FocusManager.collect_descendants` 前序 DFS，`src/tessell/input/focus.cr:80-90`）。
- 焦点同步：复用 `FocusManager` 焦点环（`next/prev/focus/blur`，`src/tessell/input/focus.cr:27-49,59-78`）；a11y 焦点变化可观察（事件/回调 `[未验证]`）；路由层 `Router` 已按 PointerDown/KeyDown 维护 focus/hover/pressed（`src/tessell/input/router.cr:34-60`）。
- `value` 暴露建议：滚动位置/可见行区间/总行数只读属性，供检视 API 查询 `[推断]`。
- Windows UIA 接入：UIA/IAccessible2 provider 纯 FFI 需要的 COM 接口、工作量与稳定性 `[未验证]`（`docs/plan.md:247` 仅要求最小树；`docs/architecture.md:181` macOS NSAccessibility、其他平台后置）；建议 M2 只做树模型+遍历，UIA 接入列 M3/M4 风险评估。

## 6) 验收判据（可测）

| # | 判据 | 方法/断言 | 来源 |
|---|---|---|---|
| 1 | a11y 遍历顺序 == 视觉树前序 | 同树 DFS 序列逐节点比对（复用 `collect_descendants` 前序口径） | `src/tessell/input/focus.cr:80-90`；`docs/plan.md:247` |
| 2 | 焦点变化可观察 | `focus(node)` 前后 `focused?`/返回值变化可断言 | `src/tessell/input/focus.cr:27-39,59-78` |
| 3 | 万行只实例化可见+缓冲行 | 计数断言 `instantiated_nodes <= viewport_rows + buffer_rows`（10000 行 × 20px 场景） | `docs/plan.md:118,246`；`docs/architecture.md:168` |
| 4 | 滚动稳态零分配 | `scenario=scroll` 200 帧 `alloc_bytes==0 && delta_zero==true`（协议同 §3） | `docs/evidence/M1-WP5-zero-alloc.md:26-34,39-51`；`docs/plan.md:167` |
| 5 | 帧时间 p99 在目标内 | `bench_frame_time` 扩展场景输出 p50/p95/p99；目标值 `[未验证]` 推演（§4） | `docs/evidence/M0-WP5m-metrics.md:13,192-224`；`docs/architecture.md:219,223` |
| 6 | 滚动不重排 | 滚动帧 `Layout` 脏计数==0、仅 `CompositeOnly`/Paint 脏 | `src/tessell/core/node.cr:53-76`；`docs/architecture.md:160-162` |
| 7 | 复用池命中 | 滚动 N 帧后池内节点复用计数>0、新建节点数==0（稳态） | `src/tessell/render/draw_list.cr:112-114` reuse_stats 口径类比 `[推断]` |

## 7) 风险与 [未验证] 清单

- 可变行高测量成本：每行高度需测量/缓存，前缀和维护成本与失效传播 `[未验证]`（`src/tessell/text/measurer.cr:12-41` 缓存键可复用，但行高缓存未实现）。
- 十万行数据源：回调延迟/内存峰值/分页策略 `[未验证]`（本预研仅万行口径）。
- UIA COM 复杂度：provider/可检视树/事件通知纯 FFI 工作量与稳定性 `[未验证]`；屏幕阅读器实测缺失（NVDA/Narrator 未测）。
- `DrawCmd` 无 UV/源矩形字段，滚动平移若需逐行重绑 atlas 引用，批次/clip 交互 `[未验证]`（`src/tessell/render/draw_list.cr:24-35,89-118`；`docs/research/glyph-atlas.md:60-65`）。
- 帧时间目标值无本机实测；`GC.disable` 窗口语义跨版本一致性 `[未验证]`（`docs/evidence/M0-WP5m-metrics.md:263-268`；`docs/evidence/M1-WP5-zero-alloc.md:58`）。
- 复用池稳态扩容/首帧/冷加载路径不得计入零分配通过（§3 豁免）；`reserve` 一次性扩容非稳态 `[未验证]`（`docs/evidence/M1-WP5-zero-alloc.md:57-59`）。
- 变行高 + 复用池：回收行行高与新内容行高不匹配导致布局抖动 `[推断]`；`CompositeOnly` 平移与 clip 合批键交互（`src/tessell/render/draw_list.cr:116-118`）`[未验证]`。
- a11y 树与 retained 树双维护的一致性成本：增删子树时镜像同步遗漏风险 `[推断]`；焦点环与 a11y focusable 谓词需同源（`src/tessell/input/focus.cr:22-25` 可注入谓词）。
- 复用池容量上限：视口行数+缓冲行数之外的长尾行（如快速滚动/跳转）处理策略 `[推断]`。

## 参考索引

- `docs/plan.md:91,118,160,162,167,169,173,219,246-247`；`docs/architecture.md:160-162,168,181,219,223,235`。
- `src/tessell/core/node.cr:53-76,92-100,139-151`；`src/tessell/render/dirty.cr:24-30,30-88`；`src/tessell/render/draw_list.cr:56-87,89-118`。
- `src/tessell/input/focus.cr:27-49,59-90`；`src/tessell/input/router.cr:34-60`；`src/tessell/input/hit_test.cr:12-29`。
- `docs/evidence/M1-WP5-zero-alloc.md:3-4,26-34,39-51,54-59`；`docs/evidence/M0-WP5m-metrics.md:13,192-194,203-224,249-259,263-268,289-327`。
- `docs/research/glyph-atlas.md:47-56,60-65`；`docs/research/text-acceptance.md:8-13,63-72`。
