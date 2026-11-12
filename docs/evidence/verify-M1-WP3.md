# verify-M1-WP3：M1-WP3 三级失效语义/祖先传播边界/dirty_subtree 核验报告

- 核验角色：大理寺卿（dalisi-qing，独立核验），受首辅 lead 节制
- 核验任务：`task-31`「M1-WP3 核验：三级失效语义/祖先传播边界/dirty_subtree」
- 核验对象（task-30 交付）：`src/tessell/core/node.cr`、`spec/core_node_spec.cr`、`src/tessell.cr`（require 行）
- 依据：lead 指派（m00334）、task-31 任务书
- 核验时间（本地采样）：2026-11-12 20:39:18 +08:00 ～ 会话内（Asia/Shanghai）
- 仓库：`C:\Users\ShiningRay\projects\ShiningRay\tessell`
- HEAD：`0c4990c`
- OS/Arch：`Microsoft Windows NT 10.0.26300.0` / `AMD64`
- Crystal：`C:\msys64\ucrt64\bin\crystal.exe`，`Crystal 1.22.1 [23828b0a40] (2026-10-23)`，`LLVM 23.1.3`，`Default target: x86_64-w64-windows-gnu`
- 命令 PATH 前置：`$env:PATH="C:\msys64\ucrt64\bin;"+$env:PATH`

## 0. 范围与边界

- 唯一写入：本报告 `docs/evidence/verify-M1-WP3.md`。**未修改** `src/tessell/core/node.cr`、`spec/core_node_spec.cr`、`src/tessell.cr` 及其他 src/spec 文件。
- 行数实测（与任务书描述有偏差，以实测为准）：
  - `src/tessell/core/node.cr`：**99 行**（任务书描述 85 行）
  - `spec/core_node_spec.cr`：**179 行**（任务书描述 143 行），13 个 `it`（与任务书一致）
  - `src/tessell.cr`：**19 行**（`:11` 新增 `require "./tessell/core/node"`）
- `git status --short`（核验末态）：
  - task-30 范围：` M src/tessell.cr`、`?? spec/core_node_spec.cr`、`?? src/tessell/core/`
  - 本报告：`?? docs/evidence/verify-M1-WP3.md`
  - **非本核验产生**：`?? src/tessell/render/`（核验期间工作区新出现，疑似并行 task-32 交付物；本核验未读未改，仅如实记录）
- 临时验证脚本 `_verify_wp3_tree.cr`（仓库根）与 `bin/_verify_wp3_tree.cr` 均已删除；`crystal build` 产物 `tessell.exe` 已删除并复核根目录无 exe。

## 1. 重跑命令与原始结果

### 1.1 `crystal spec`
命令：`$env:PATH="C:\msys64\ucrt64\bin;"+$env:PATH; crystal spec`
原始输出：
```
...........................................

Finished in 496 microseconds
43 examples, 0 failures, 0 errors, 0 pending
SPEC_EXITCODE=0
```

### 1.2 `crystal build src/tessell.cr`
命令：`$env:PATH="C:\msys64\ucrt64\bin;"+$env:PATH; crystal build src/tessell.cr`
原始输出：
```
BUILD_EXITCODE=0
REMOVED_tessell_exe
NO_tessell_exe_in_root
```
（构建后在根目录产生 `tessell.exe`，已删除并复核 `NO_tessell_exe_in_root`。）

### 1.3 手写 5 层树逐节点实测（独立临时脚本，非仅 spec 绿）
命令：`crystal run _verify_wp3_tree.cr`（脚本即删），原始输出（44 项断言全 PASS）：
```
PASS T1 L4.layout_dirty
PASS T1 L3.layout_dirty
PASS T1 L2.layout_dirty
PASS T1 L1.layout_dirty
PASS T1 L0.layout_dirty
PASS T1 L0.paint_dirty=false
PASS T1 L0.composite_dirty=false
PASS T1 L1.paint_dirty=false
PASS T1 L1.composite_dirty=false
PASS T1 L2.paint_dirty=false
PASS T1 L2.composite_dirty=false
PASS T1 L3.paint_dirty=false
PASS T1 L3.composite_dirty=false
PASS T1 L4.paint_dirty=false
PASS T1 L4.composite_dirty=false
PASS T1 L4.dirty?==Layout
PASS T2 m.paint_dirty
PASS T2 m.layout_dirty=false
PASS T2 r.dirty?==nil
PASS T2 c.dirty?==nil
PASS T3 m.composite_dirty
PASS T3 m.layout_dirty=false
PASS T3 m.paint_dirty=false
PASS T3 r.dirty?==nil
PASS T3 c.dirty?==nil
PASS T4 after Paint dirty?==Paint
PASS T4 upgrade to Layout
PASS T4 no downgrade by CompositeOnly
PASS T4 Layout then Paint stays Layout
PASS T5 dirty_subtree size 2
PASS T6 child still dirty after parent clean!
PASS T6 child clean after own clean!
PASS T7 ra.layout_dirty
PASS T7 rb clean
PASS T8 contains a
PASS T8 contains c
PASS T8 excludes root
PASS T8 excludes b
PASS T8 size 2
PASS T9 DFS order root,x,y
PASS T10 clean empty
PASS T11 c.parent == r
PASS T11 r.children includes c
PASS T11 bounds default readable
VERIFY_ALL_PASS
TREE_EXIT=0
```

## 2. 三级失效语义（逐项实测）

### 2.1 `enum Invalidation` 与 `dirty?` 优先级
- `src/tessell/core/node.cr:19-23` `enum Invalidation`：`Layout`、`Paint`、`CompositeOnly`（普通 enum，任务书/plan.md:91 要求）。
- 选型说明（`:8-11` 注释）：不用单一 enum 字段（无法表达 Layout+Paint 同时脏）、不用 flags enum（合并/优先级易把 CompositeOnly 误升 Paint）；用三个独立 Bool + `dirty?` 显式按 `Layout > Paint > CompositeOnly` 取最高级。
- `dirty?`（`:53-63`）：`@layout_dirty` → `Layout`；`elsif @paint_dirty` → `Paint`；`elsif @composite_dirty` → `CompositeOnly`；否则 `nil`。
- 实测（脚本 T4）：Paint 后标 Layout → `Layout`（升级）；Layout 后标 Paint/CompositeOnly → 仍 `Layout`（不降级）；CompositeOnly 后标 Paint → `Paint`（升级）。优先级 `Layout > Paint > CompositeOnly > nil` 成立。

### 2.2 mark_dirty(Layout)：自身 + 祖先链 Layout，兄弟/Paint 不动
- 实现：`mark_dirty(Invalidation::Layout)`（`:66-70`）置 `@layout_dirty = true` 并 `propagate_to_parent`；`propagate_to_parent`（`:98-104`）沿 `@parent` 链调 `mark_layout_only`（`:108-110`，仅置 `@layout_dirty`，不碰 Paint/CompositeOnly）。
- 手写 5 层树实测（T1，`L0→L1→L2→L3→L4`，`L4.mark_dirty(Layout)`）：`L0..L4` 全部 `layout_dirty? == true`；全部 `paint_dirty? == false`、`composite_dirty? == false`；`L4.dirty? == Invalidation::Layout`。
- spec 佐证：`spec/core_node_spec.cr:15-34`（leaf 标 Layout，root/mid Layout 脏，sib 不脏，Paint 不动）、`:90-101`（6 层全祖先 Layout 脏）、`:144-154`（父标 Layout 不下传子）。

### 2.3 mark_dirty(Paint)：仅自身 Paint，不动祖先/兄弟/Layout
- 实现：`mark_dirty(Invalidation::Paint)`（`:71-72`）仅 `@paint_dirty = true`，无传播。
- 实测（T2）：中间节点标 Paint → 自身 `paint_dirty? == true`、`layout_dirty? == false`；root 与 child `dirty? == nil`。
- spec 佐证：`:36-48`（child Paint，root 三级全净）、`:165-178`（sib A Paint 不影响 sib B 与 root）。

### 2.4 mark_dirty(CompositeOnly)：仅自身 CompositeOnly，不产生 Layout/Paint 脏
- 实现：`mark_dirty(Invalidation::CompositeOnly)`（`:73-74`）仅 `@composite_dirty = true`。
- 实测（T3）：中间节点标 CompositeOnly → 自身 `composite_dirty? == true`，`layout_dirty? == false`、`paint_dirty? == false`；root/child `dirty? == nil`。
- spec 佐证：`:50-61`（child CompositeOnly，root `dirty? == nil`）。

### 2.5 传播方向：只向上，不向下
- `propagate_to_parent`（`:98-104`）只沿 `@parent` 向上；`mark_dirty` 不触碰 `children`。
- 实测（脚本 T1/T2/T3 + spec `:144-154`）：父标 Layout 不下传子；子标 Paint/CompositeOnly 不上染父 Paint。

## 3. 边界语义（幂等/升级/降级/clean!/多根）

- **幂等**：重复 `mark_dirty(Layout)` 不改变脏集合（脚本 T5：`dirty_subtree.size == 2`；spec `:77-88` 同结论）。三 Bool 置位天然幂等。
- **升级/降级**：已脏节点标更高级别升级（Paint→Layout 升 Layout）；标低级别不降级（Layout 后标 Paint/CompositeOnly 仍 Layout）。实测 T4 通过；`dirty?` 优先级判定（`:53-63`）保证。
- **clean! 影响范围**：`clean!`（`:79-83`）仅清自身三级标记，不递归子树。实测 T6：父 `clean!` 后子仍 Paint 脏；子自 `clean!` 后 `dirty? == nil`。spec `:63-75` 佐证逐级清除。
- **多根/无父节点**：root 无 `@parent`，`propagate_to_parent` 循环不执行（`:99-103`），不崩。实测 T7：`ra.mark_dirty(Layout)` 仅 `ra` 脏，`rb` 净。
- **`mark_layout_only` 可见性**：`:108-110` 为 public（注释 `:107` 说明 Crystal private 为对象级，不能跨实例调用，故 public 但仅限内部传播语义）。功能正确；外部可直接调用属 API 表面略宽，见 §7 观察-3。

## 4. `dirty_subtree` 语义

- 实现：`self.dirty_subtree(root)`（`:86-90`）DFS 前序收集 `dirty? != nil` 的节点（含 root 自身），返回 `Array(Node)`；静态全净树返回空数组。
- 实测：
  - T8：`a`(Paint) + `c`(CompositeOnly) 脏，`root`/`b` 净 → 结果仅 `["a","c"]`，size 2，不含干净中间节点 `b`。
  - T9：root 自身脏 → 包含 root；DFS 顺序 `["root","x","y"]` 稳定（与 `collect_dirty` 递归顺序 `:112-115` 一致）。
  - T10：全净树 → `empty?` 为 true。
- spec 佐证：`:103-121`（只含脏节点、size 断言）、`:136-142`（静态全净空）、`:77-88`（幂等后 count 不变）。

## 5. 结构与依赖

- **parent/children 双向一致**：`add_child`（`:92-96`）先 `child.parent = self` 再 `@children << child`。实测 T11：`c11.parent == r11` 且 `r11.children.includes?(c11)`。
- **bounds 默认可读**：`@bounds : Rect = Rect.new`（`:32`），实测 T11 `r11.bounds.is_a?(Rect)` 通过；spec `:156-163` 断言自定义 bounds 可读。
- **无全局/Platform/FFI/Render 依赖**：`grep`（`@[Link]|LibC|libharfbuzz|libfreetype|harfbuzz|freetype|FFI|Platform|Render|@@`）命中仅注释：
  - `src/tessell/core/node.cr:13`：`# 本文件不依赖 Platform/FFI/Render；纯内存状态，可单测。`
  - `src/tessell.cr:5`：`#       → render（DrawList 与后端）→ platform（窗口/输入）→ widget / dsl`
  无 `@@` 全局、无实际 FFI/Platform/Render 调用。

## 6. 单测有效性

- `spec/core_node_spec.cr`：**13 个 `it`**（实测 179 行/13 it；任务书描述 143 行/13 it，it 数一致，行数以实测为准）。
- 断言具体：均为 `should eq/be_true/be_false/be_nil/be_empty/contain/includes?` 等具体值断言；`grep should_not be_nil|should be_nil` 仅命中 `should be_nil`（`:9,60,72,74,153`，断言全净态 `dirty? == nil`，为有效断言而非空泛占位），无 `should_not be_nil`。
- 覆盖：初始全净（`:7-13`）、Layout 祖先链+兄弟不脏（`:15-34`）、Paint 不染祖先（`:36-48`）、CompositeOnly 不产 Layout/Paint（`:50-61`）、clean! 逐级（`:63-75`）、幂等（`:77-88`）、6 层深树（`:90-101`）、dirty_subtree 只含脏（`:103-121`）、优先级（`:123-134`）、静态全净空（`:136-142`）、向上不向下（`:144-154`）、bounds（`:156-163`）、兄弟 Paint 隔离（`:165-178`）。
- 抽查 2 例逐节点核对：
  - `spec:15-34`：leaf 标 Layout → root/mid/leaf Layout 脏、sib 全净、全部 Paint 净。与脚本 T1 逐节点断言一致。
  - `spec:123-134`：同节点 CompositeOnly→Paint→Layout 依次升级，`dirty?` 分别返回 CompositeOnly/Paint/Layout。与脚本 T4 一致。

## 7. 缺陷清单（P1/P2/P3）

| ID | 级别 | 位置 | 描述 | 影响/说明 |
|---|---|---|---|---|
| 观察-1 | P3 | `src/tessell/core/node.cr`（整体） | 未实现 `detach`/`remove_child`/重新挂载语义；`add_child` 会覆盖 `child.parent`，若子节点已属另一父节点，旧父 `children` 仍持有引用，产生双向不一致。 | 当前 M1-WP3 范围未要求；后续 retained 树增删节点时必须补，否则 `dirty_subtree`/传播可能遗漏旧父链。 |
| 观察-2 | P3 | `src/tessell/core/node.cr:35-37,53-63` | 三级脏用三个独立 Bool 而非位掩码 flags enum；`dirty?` 需顺序判断，合并/比较需手工逻辑。 | 当前可审计、无功能缺陷；若后续需位运算合并或持久化脏集，可评估 flags enum（任务书亦要求列为观察）。 |
| 观察-3 | P3 | `src/tessell/core/node.cr:108-110` | `mark_layout_only` 为 public（注释说明 Crystal private 对象级限制），外部可直接调用，绕过 `mark_dirty` 的语义入口。 | 功能正确；API 表面略宽，建议后续用 `protected`/文档约束或保持现状并说明。 |
| 观察-4 | P3 | `src/tessell/core/node.cr:86-90,112-115` | `dirty_subtree` 每次调用 `Array(Node)` 新分配并递归；未做零分配/复用缓冲。 | 属 M1-WP5 零分配范畴；当前为正确性优先的可测实现，已在 node.cr 头部声明范围。 |
| 观察-5 | P3 | 任务书 vs 实测 | 任务书描述 `node.cr` 85 行/`core_node_spec.cr` 143 行；实测 99 行/179 行（13 it 一致）。 | 行数描述偏差，以实测为准；不影响功能与裁定。 |
| 观察-6 | P3 | 工作区 | 核验期间 `git status` 新出现 `?? src/tessell/render/`（疑似并行 task-32 交付），非本核验写入。 | 仅如实记录；本核验未读未改该目录。 |

- **P1：无。P2：无。**

## 8. 最终裁定

**裁定：PASS**

**理由**：`enum Invalidation` 三级语义与 `dirty?` 优先级（Layout > Paint > CompositeOnly > nil）实现正确；`mark_dirty(Layout)` 自身+祖先链 Layout 脏、兄弟与 Paint 不动；`mark_dirty(Paint)`/`CompositeOnly` 仅自身、不产生 Layout/Paint 脏、不传播；手写 5 层树 44 项逐节点断言全 PASS（T1–T11），边界（幂等、升级/降级、clean! 范围、多根不崩、dirty_subtree 含 root/只含脏/DFS 稳定、parent/children 双向一致、bounds 默认可读）全部实测通过。`crystal spec` **43 examples, 0 failures, 0 errors, 0 pending**（EXITCODE 0，满足 ≥40）；`crystal build src/tessell.cr` EXITCODE 0，构建产物 `tessell.exe` 已删、根目录无 exe。无 FFI/Platform/Render 实际依赖（grep 仅注释命中），无 `@@` 全局。13 个 spec `it` 断言具体、无空泛 `should_not be_nil`。边界合规（仅 task-30 范围 + 本报告；`src/tessell/render/` 为并行交付，非本核验写入）。P1/P2 无，P3 观察 6 条（detach/remove_child、位掩码、mark_layout_only 可见性、零分配 dirty_subtree、行数描述偏差、并行 render 目录）均已列出，不构成功能缺陷。
