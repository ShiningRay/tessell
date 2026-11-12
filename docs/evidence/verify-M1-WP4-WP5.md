# verify-M1-WP4-WP5 — M1-WP4/WP5 复验（P1 保留字关闭 + 零分配实测与工具诚实性）

- 复验人：大理寺卿 dalisi-qing（独立核验，只读+重跑）
- 复验时间：2026-11-12T21:48:19+08:00（本步采样）
- 仓库：`C:\Users\ShiningRay\projects\ShiningRay\tessell`
- HEAD：`0c4990c`（`git rev-parse --short HEAD`）
- 环境：`Crystal 1.22.1 [23828b0a40] (2026-10-23) LLVM 23.1.3 x86_64-w64-windows-gnu`；OS `Microsoft Windows NT 10.0.26300.0` AMD64；PATH 含 `C:\msys64\ucrt64\bin`
- 任务：task-35「M1-WP4/WP5 复验：P1 保留字关闭 + 零分配实测与工具诚实性」（writeScope 仅本报告）

## 0. 范围与边界
- 核验对象：`src/tessell/render/draw_list.cr`、`src/tessell/render/dirty.cr`、`src/tessell/core/node.cr`、`spec/render_draw_list_spec.cr`、`spec/render_dirty_into_spec.cr`、`spec/core_node_zero_alloc_spec.cr`、`tools/zero_alloc_frame.cr`、`docs/evidence/M1-WP5-zero-alloc.md`。
- 只读源码/规约/工具与既有证据；未修改 `src/`、`spec/`、`tools/`、`examples/`、`docs/` 既有文件（仅新增本报告）。未 commit。
- `git status --short`（复验时）：` M src/tessell.cr`；`?? docs/evidence/M1-WP5-zero-alloc.md`、`?? docs/evidence/verify-M1-WP3.md`、`?? docs/evidence/verify-M1-WP4.md`、`?? spec/core_node_spec.cr`、`?? spec/core_node_zero_alloc_spec.cr`、`?? spec/render_dirty_into_spec.cr`、`?? spec/render_draw_list_spec.cr`、`?? src/tessell/core/`、`?? src/tessell/render/`、`?? tools/zero_alloc_frame.cr`；另将新增 `?? docs/evidence/verify-M1-WP4-WP5.md`（本报告）。根目录无 `*.exe`（`NO_EXE_IN_ROOT`）。临时语义验证脚本 `bin/_verify_wp45.cr`、`bin/_verify_extra.cr` 运行后已删除，无残留。
- grep 残留 `out` 参数（`def\s+.*\bout\s*:`）于 `src\tessell\render\dirty.cr`、`src\tessell\core\node.cr`、`tools\zero_alloc_frame.cr`、`src\tessell\render\draw_list.cr`：**无命中**（`GREP_DONE`）。注：此前 task-33 P1 为 `src/tessell/render/dirty.cr:30` 参数名 `out`（保留字）导致编译阻断；现已改为 `sink`（见源码与下文）。

## 1. P1 关闭确认（官方重跑）
命令：`crystal spec`；`crystal build src/tessell.cr`（构建后删 exe）

原始输出（关键行）：
```
=== crystal spec ===
..........................................................................
Finished in 70.28 milliseconds
74 examples, 0 failures, 0 errors, 0 pending
SPEC_EXITCODE=0

=== crystal build src/tessell.cr ===
BUILD_EXITCODE=0
EXE_REMOVED=true
```
结论：官方 spec/build **均通过**（74/0/0，EXITCODE 0 / 0），此前 task-33 因 `dirty.cr` 参数 `out` 保留字引发的编译阻断 **已关闭**。grep 无 `def ... out :` 残留佐证。

## 2. 源码核实（P1 修复点与 WP5 接口）

### 2.1 `src/tessell/render/dirty.cr`
- `merge` 委托 `merge_into`：`:17-22` `regions=[] of Rect; merge_into(rects, regions, max_regions); regions`。
- `merge_into` 签名：`:30` `def self.merge_into(rects : Array(Rect), sink : Array(Rect), max_regions : Int32 = 8) : Nil`（参数名 `sink`，非保留字 `out`）。
- 行为：`:31` `sink.clear`；`:32-39` while 索引过滤退化矩形（`width>0 && height>0`）写入 sink；`:41-59` 第一遍原地合并重叠/相接（`adjacent?` 两轴投影相交或贴边，`:99-103`）`union + delete_at`；`:61-86` 超 `max_regions` 时贪心按面积增量最小合并直至 ≤max；`:68-74` `area`；`:105-107` `area_of`。注释声明不新分配、依赖调用方预分配容量（`:24-29`）。

### 2.2 `src/tessell/core/node.cr`
- `dirty_subtree`：`:86-90` 新建数组后委托 `collect_dirty`。
- `collect_dirty`：`:97-100` `sink.clear` 后调 `collect_dirty_impl`；签名参数 `sink`。
- `collect_dirty_impl`：`:122-130` 若 dirty 则 `sink << node`，子节点用 `while` 索引递归（无块闭包）；注释声明稳态零分配路径前提（`:92-96`）。

### 2.3 `tools/zero_alloc_frame.cr`（工具诚实性核查）
- `--frames`/`--json` 从 CLI 解析：`:105-113` 默认 `frames=200,json_out=false`，`--frames=N` 取值，`--json` 置真；未硬编码帧数/结果。
- 无硬编码 `alloc_bytes=0`：`:73` `measure_scenario` 返回 `after-before`（UInt64）；`:145-146` 记录两场景实测值；`:149-154` 输出 `alloc_bytes=#{static_alloc/paint_alloc}` 与 `delta_zero=#{(... == 0) ? "true" : "false"}`（由比较得出）；`:157-162` 非 0 时如实打印 `alloc_note`，不凑 0。
- GC 协议与 `GC.enable` 在 `ensure`：`:85-101` warmup 10 帧 → `GC.collect` → `GC.disable` → `begin { before; N 帧; after } ensure { GC.enable }`。
- paint1 每帧真实 mark_dirty+clean：`:55-69` `paint1_frame` 取轮转目标 `target = @nodes[frame % @node_count]`，`target.mark_dirty(Tessell::Invalidation::Paint)`，`collect_dirty`，clear+仅对 `@dirty_buf` 中节点重建命令，`dirty_rects_in` 置为 `target.bounds` 后 `merge_into`，最后 `target.clean!`；测量循环每帧调用（`:76,92`）。
- 场景实现：static 全净 `collect_dirty + DrawList.clear + 全量命令重建 + merge_into(空输入)`（`:43-52`）；缓冲预分配（`:26-40`）。树 ≥200 节点（205=1+4+200，`:115-130`），StubMeasurer 仅建树期一次测量写 bounds（`:133-141`），热帧不调用。

## 3. WP4 关键语义复跑（等效脚本，官方 spec/build 已通过）

临时脚本（`bin/_verify_wp45.cr`、`bin/_verify_extra.cr`，均运行后删除，ASCII 编码）结果：

### 3.1 DrawList 复用与边界
- `reserve(64)`：`reserve64_capacity=64`、`reserve64_size=0`（调 `DrawList#capacity`/`size` 确认）；`clear` 后 `clear_capacity=64`、`clear_size=0`。
- 10,000 次 `clear + push×64`：`10k_size_stable=true`（末次 size=64），`10k_reuse_readback=true`（`dl[0]`/`dl[63]` 可读且 kind 正确）。
- 空 list 批：`empty_batches0=true`。

### 3.2 6 命令手排批次（start/count）
命令序列（atlas/clip）：(1,1,nil),(1,1,nil),(2,2,nil),(2,2,clipR),(2,2,clipR),(3,3,nil)；规则：相邻同 atlas+clip 合批（`draw_list.cr:116-118`）。
- `six_cmds_batch_count=true`（4 批）
- `batch0_start0_count2=true`（atlas1, nil）
- `batch1_start2_count1=true`（atlas2, nil）
- `batch2_start3_count2=true`（atlas2, clipR）
- `batch3_start5_count1=true`（atlas3, nil）

### 3.3 Dirty 关键用例
- 重叠合并：`dirty_overlap_size1=true` → `[(0,0,15,15)]`
- 相接合并：`dirty_adjacent_size1=true` → `[(0,0,20,10)]`
- 退化忽略：`dirty_degenerate_ignored=true`（`(0,0,0,10)` 忽略，仅保留 `(1,1,3,3)`）
- 空输入/area：`dirty_empty=true`（merge 空，`Dirty.area([])=0.0_f64`）
- 8 不相交、`max_regions=4`：`dirty_8_to_le4=true`（结果 size≤4 且无空矩形）
- 手算 area：`dirty_area_125=true`（`area([(0,0,10,5),(0,0,5,15)]) = 50 + 75 = 125.0_f64`）

## 4. WP5 语义复跑（merge_into / collect_dirty）

### 4.1 `merge_into` vs `merge` 等价与顺序（6 组）
输入组：`[]`；`[(0,0,10,10),(5,5,10,10)]` 重叠；`[(0,0,10,10),(10,0,10,10)]` 相接；`[(0,0,10,10),(20,20,5,5)]` 不相交；`[(0,0,0,5),(1,1,2,2),(3,3,4,4)]` 退化+相接链；8 个不相交矩形（`x=i*10,0,5,5`，`max_regions=8`）。
- `merge_into_equivalent_6groups=true`（结果 `==`）
- `merge_into_order_same_6groups=true`（`map(&.to_s)` 序列一致）

### 4.2 `sink` 复用与无残留
- 预填 50 个矩形后 `merge_into(groups[overlap], sink)`：`sink_no_stale=true`（size==1 且仅 `(0,0,15,15)`，旧元素无残留）。
- 重复 1000 次调用（同一输入）size 稳定且与 `merge` 一致（调试脚本，ASCII）：
  - `merge_g4_size=1`，`merge_g4_rects=(1,1,6,6)`（退化+相接链并为 1 个包围盒）
  - `sink1000_g4_size=1`（1000 次后仍 1，内容 `(1,1,6,6)`）
  - `sink1000_g3_size=2`（不相交组）
  - `sink1000_g1_size=1`（重叠组）
  - `sink1000_empty_size=0`（空输入后清空）
- 结论：sink 在重复调用中被正确 `clear` 并写入当前结果，无残留；size 随输入语义稳定（不因调用次数增长）。Array 容量无跨平台公开 API，容量不增长由 spec GC 探针与 tool 零分配实测兜底（见 §5、spec 读码：`core_node_zero_alloc_spec.cr:86-105`、`render_dirty_into_spec.cr:68-83` 均 `GC.stats.bytes_since_gc` 差值 0）。

### 4.3 `collect_dirty` 与 `dirty_subtree` 集合一致、sink 复用
- 全净：`collect_clean_empty=true`，`collect_clean_matches_subtree=true`。
- root 自身 Layout 脏：`collect_root_self=true`（`["root"]`），`collect_root_matches_subtree=true`。
- 中间节点 Paint（不染祖先）：`collect_paint_only_mid0=true`（`["mid0"]`），`collect_paint_matches_subtree=true`。
- 中间节点 Layout（上传祖先）：`collect_layout_mid0_ancestors=true`（`["root","mid1"]`），`collect_layout_matches_subtree=true`。
- 10 层深链末端 CompositeOnly：`collect_deep_chain=true`（`["deep_root","deep0".. "deep9"]`），`collect_deep_matches_subtree=true`（含 root 自身在内全链）。
- sink 复用 1000 次（全净输入）：`collect_sink_1000_no_residue=true`。

## 5. 零分配实测（`tools/zero_alloc_frame.cr`）

### 5.1 默认 `--frames=200`（两场景）
```
=== zero_alloc_frame default (200) ===
scenario=static frames=200 nodes=205 alloc_bytes=0 delta_zero=true
scenario=paint1 frames=200 nodes=205 alloc_bytes=0 delta_zero=true
EXIT_DEFAULT=0
```

### 5.2 `--frames=50 --json`（可解析行）
```
=== zero_alloc_frame --frames=50 --json ===
{"scenario":"static","frames":50,"nodes":205,"alloc_bytes":0,"delta_zero":true}
{"scenario":"paint1","frames":50,"nodes":205,"alloc_bytes":0,"delta_zero":true}
EXIT_JSON50=0
```
JSON 行结构合法（每行独立对象，键 `scenario,frames,nodes,alloc_bytes,delta_zero` 齐全）。

### 5.3 重复 `--frames=200`（可重复性）
```
=== zero_alloc_frame --frames=200 (repeat) ===
scenario=static frames=200 nodes=205 alloc_bytes=0 delta_zero=true
scenario=paint1 frames=200 nodes=205 alloc_bytes=0 delta_zero=true
EXIT_REPEAT200=0
```
三次运行（默认/JSON50/重复200）均 `alloc_bytes=0 delta_zero=true`，EXITCODE 0；无非 0 字节。

### 5.4 与既有证据一致性
`docs/evidence/M1-WP5-zero-alloc.md` 记录协议与实测 token 与本次重跑一致（两场景 200 帧 `alloc_bytes=0 delta_zero=true`）；其局限声明（不含布局重算/文本 shaping/GPU 提交、预付槽位前提、GC 语义版本限定）与源码/工具实现相符，未发现夸大。

## 6. 单测/规约读码（有效性抽查）
- `spec/core_node_zero_alloc_spec.cr`：5 it，含 `collect_dirty` 与 `dirty_subtree` 一致性（root 自脏/深树混合/全净）、sink 复用清空、预分配后重复调用有界、GC 探针 1000 次 `bytes_since_gc` 差值 0（`:86-105`）。
- `spec/render_dirty_into_spec.cr`：6 组 `merge_into==merge`（含顺序）、`max_regions` 贪心、无空矩形、预分配 sink 重复调用有界、GC 探针 1000 次差值 0（`:68-83`）。
- `spec/render_draw_list_spec.cr`（task-32 交付，官方 suite 含于 74 examples）：本次未逐行重读，但官方 `crystal spec` 全绿且 §3 关键语义独立复跑通过；先前 task-33 抽查锚点 `:24-33` capacity 稳定、`:123-134` 8→≤4 与当前实现/结果一致（参见 b16 摘要）。

## 7. 缺陷清单与观察
- **P1（已关闭）**：`src/tessell/render/dirty.cr:30` 原参数名 `out`（Crystal 保留字）导致 `crystal spec/build` 编译失败（task-33 verify-M1-WP4 裁定 FAIL，P1-1）。现已改为 `sink`；grep 无 `def ... out :` 残留；官方 spec 74/0/0、build EXITCODE 0，P1 关闭。
- **P2**：无。
- **P3（观察，非阻断）**：
  1. `Render::Dirty.merge_into` 使用 `Array#delete_at`/原地 union 循环（`:51,84`），算法复杂度与分配特性依赖输入规模；稳态零分配成立于预分配且无扩容前提（spec/tool 已证），极端大输入/超限合并仍属实现细节风险（非本次场景）。
  2. `collect_dirty`/`merge_into` 要求调用方预分配足够容量（注释声明）；容量不足时 `<<` 可能扩容——本次验证场景与工具均满足前提。
  3. `tools/zero_alloc_frame.cr` paint1 场景因 Paint 仅标自身，`dirty_buf` 通常仅 1 节点；未覆盖 Layout 脏导致多节点收集的零分配路径（但 `collect_dirty` 零分配已由 spec GC 探针覆盖）。
  4. WP4 既有 P3 缺口仍在（draw cmd 无 z-order/blend/UV、clip 不参与合并优化、Dirty 非通用零分配等），属后续 WP 范畴，非本复验回归。
  5. ` M src/tessell.cr` 与并行未提交产物存在于工作区（边界可见），非本次复验修改。

## 8. 最终裁定
**PASS**

- P1（`dirty.cr` 保留字 `out`）已关闭：源码改为 `sink`、无 `def ... out :` 残留、官方 `crystal spec` **74 examples, 0 failures, 0 errors, 0 pending (EXITCODE 0)**、`crystal build src/tessell.cr` **EXITCODE 0**。
- WP4 关键语义复跑通过：DrawList `reserve(64)`/clear 容量保持、10k `clear+push×64` 稳定、6 命令批次 start/count 正确、Dirty 重叠/相接/退化/空/`8→≤4`/`area=125` 正确。
- WP5 语义复跑通过：`merge_into` 与 `merge` 6 组等价且顺序一致、sink 复用 1000 次无残留且 size 稳定；`collect_dirty` 与 `dirty_subtree` 集合一致（全净/root 自脏/深树）、sink 复用 1000 次无残留。
- 零分配实测通过且可重复：`zero_alloc_frame` 默认/`--frames=50 --json`/重复 `--frames=200` 三次均 `scenario=static,paint1 alloc_bytes=0 delta_zero=true`、EXITCODE 0；JSON 可解析。工具诚实性核实：无硬编码 0、N 来自 CLI、`GC.enable` 在 `ensure`、paint1 每帧 `mark_dirty(Paint)+clean!`。
- P2 无；P3 为范围/实现观察，不构成阻断。边界合规（仅新增本报告，未改 src/spec/tools，临时脚本已清理，根目录无 exe）。
