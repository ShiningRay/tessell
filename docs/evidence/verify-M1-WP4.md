# verify-M1-WP4：M1-WP4 DrawList 容量复用/批边界/脏矩形合并与上限 核验报告

- 核验角色：大理寺卿（dalisi-qing，独立核验），受首辅 lead 节制
- 核验任务：`task-33`「M1-WP4 核验：DrawList 容量复用/批边界/脏矩形合并与上限」
- 核验对象（task-32 交付）：`src/tessell/render/draw_list.cr`、`src/tessell/render/dirty.cr`、`spec/render_draw_list_spec.cr`、`src/tessell.cr`（require 行）
- 依据：lead 指派（m00380）、task-33 任务书
- 核验时间：2026-11-12 21:35:00 +08:00（Asia/Shanghai，会话内采样）
- 仓库：`C:\Users\ShiningRay\projects\ShiningRay\tessell`
- HEAD：`0c4990c`
- OS/Arch：`Microsoft Windows NT 10.0.26300.0` / `AMD64`
- Crystal：`C:\msys64\ucrt64\bin\crystal.exe`，`Crystal 1.22.1 [23828b0a40] (2026-10-23)`，`LLVM 23.1.3`，`Default target: x86_64-w64-windows-gnu`
- 命令 PATH 前置：`$env:PATH="C:\msys64\ucrt64\bin;"+$env:PATH`

## 0. 范围与边界

- 唯一写入：本报告 `docs/evidence/verify-M1-WP4.md`。**未修改** `src/tessell/render/draw_list.cr`、`src/tessell/render/dirty.cr`、`spec/render_draw_list_spec.cr`、`src/tessell.cr` 及其他 src/spec 文件。
- 行数实测（与任务书描述有偏差，以实测为准）：
  - `src/tessell/render/draw_list.cr`：**121 行**（任务书描述 86 行）
  - `src/tessell/render/dirty.cr`：**87 行**（任务书描述 68 行）
  - `spec/render_draw_list_spec.cr`：**153 行**（任务书描述 135 行），15 个 `it`（与任务书一致）
  - `src/tessell.cr`：**19 行**（`:9` 新增 `require "./tessell/render/draw_list"` 与 `:10` `require "./tessell/render/dirty"`）
- 说明：`dirty.cr` 实现为 `merge`（分配新 Array）+ `merge_into`（复用调用方缓冲 `out`）双入口；`merge` 内部委托 `merge_into`。`merge_into` 签名使用参数名 `out`，**`out` 为 Crystal 保留字，导致 `crystal spec`/`crystal build` 全局编译失败**（见 §1.3 / §6 P1）。本核验在只读约束下无法执行官方 spec； Dirty 语义通过自含式等价算法复验（§3.4）。
- `git status --short`（核验末态）：
  - task-32 范围：` M src/tessell.cr`、`?? spec/render_draw_list_spec.cr`、`?? src/tessell/render/`
  - 本报告：`?? docs/evidence/verify-M1-WP4.md`
  - 非本核验产生：`?? spec/core_node_spec.cr`、`?? spec/core_node_zero_alloc_spec.cr`、`?? spec/render_dirty_into_spec.cr`、`?? tools/zero_alloc_frame.cr`、`?? docs/evidence/verify-M1-WP3.md`（并行 M1-WP3/WP5 交付物，本核验未读未改）
- 临时验证脚本 `_verify_wp4.cr` / `_verify_wp4b.cr` / `_verify_drawlist.cr` 均已删除；`crystal build` 产物 `tessell.exe` 已删除并复核根目录无 exe。

## 1. 重跑命令与原始结果

### 1.1 `crystal spec`（官方，失败）
命令：`$env:PATH="C:\msys64\ucrt64\bin;"+$env:PATH; crystal spec`
原始输出：
```
In src\tessell\render\dirty.cr:30:48
Error: cannot use 'out' as a parameter name
30 | def self.merge_into(rects : Array(Rect), out : Array(Rect), max_regions : Int32 = 8) : Nil
                                                  ^
SPEC_EXITCODE=1
```
- **阻断原因**：`dirty.cr:30` 参数名 `out` 为 Crystal 保留字；整个 spec 套件（含 DrawList 15 例 + Dirty into 例）无法编译。官方 `crystal spec` 无法得到 58/0/0 计数。
- 官方 spec 期望计数（任务书描述）：58 examples / 0 failures / 0 errors / 0 pending。本核验无法独立复现该计数（编译阻断），在 §6 列为 P1。

### 1.2 `crystal build src/tessell.cr`（官方，失败）
命令：`$env:PATH="C:\msys64\ucrt64\bin;"+$env:PATH; crystal build src/tessell.cr`
原始输出：
```
In src\tessell\render\dirty.cr:30:48
Error: cannot use 'out' as a parameter name
BUILD_EXITCODE=1
NO_tessell_exe_after_build
NO_tessell_exe_in_root
```
（构建后无 `tessell.exe`；根目录复核 `NO_tessell_exe_in_root`。）

### 1.3 DrawList 自含式重跑（官方 spec 编译阻断下的等效验证）
命令：`crystal run _verify_drawlist.cr`（脚本即删）
原始输出：
```
PASS capacity after reserve(64) == 64
PASS size after clear == 0
PASS capacity after clear == 64
PASS size after 64 push == 64
PASS capacity stable after clear+push
BATCHES=4
BATCH0 start=0 count=2
BATCH1 start=2 count=1
BATCH2 start=3 count=2
BATCH3 start=5 count=1
PASS batch0 start=0 count=2
PASS batch1 start=2 count=1
PASS batch2 start=3 count=2
PASS batch3 start=5 count=1
PASS batch_count == 4
PASS empty batches empty
PASS empty batch_count 0
PASS 10k capacity stable
PASS 10k size == 64
DRAWLIST_VERIFY_ALL_PASS
VERIFY_EXIT=0
NO_tessell_exe_after
```

### 1.4 Dirty 语义自含式重跑（等价算法，参数名用 `sink` 避免保留字）
命令：`crystal run _verify_wp4b.cr`（脚本即删）——因 `dirty.cr` 自身含 `out` 保留字而无法加载，Dirty 部分改用等价算法（`merge_sink`，逻辑与 `dirty.cr` 完全一致，仅参数名 `sink`）验证；DrawList 部分因 `require` 链被同一编译错误阻断，故 DrawList 单独在 `_verify_drawlist.cr` 验证（§1.3）。
Dirty 部分原始输出（节选，全部 PASS）：
```
PASS overlap size 1
PASS overlap result == (0,0,15,15)
PASS edge-touching size 1
PASS edge-touching result == (0,0,20,10)
PASS disjoint size 2
PASS degenerate ignored -> 1
PASS degenerate result == (0,0,10,10)
PASS merge empty -> empty
PASS area empty == 0
PASS area hand == 125.0
MAX_REGIONS_RESULT_SIZE=4
PASS 8 disjoint -> <=4
PASS 8 disjoint -> >0
PASS max_regions no empty width
PASS max_regions no empty height
VERIFY_EXIT=0
```
（DrawList 部分因 `require` 链阻断未在该脚本中执行，已在 §1.3 单独完成。）

## 2. DrawList 容量复用

### 2.1 clear 复用语义
- 实现：`clear`（`:56-58`）仅 `@size = 0`；`capacity`（`:76-78`）返回 `@commands.size`（物理槽数）。`reserve`（`:82-87`）仅在 `n > @commands.size` 时追加零值占位 DrawCmd，已有 n 个槽位直接返回。
- 实测（§1.3）：`reserve(64)` → `capacity == 64`；push 5 → clear → `size == 0`、`capacity == 64`（cap 不变）；再 push 64 → `size == 64`、`capacity == 64`。

### 2.2 push 覆写空闲槽位
- 实现：`push`（`:60-67`）：`@size < @commands.size` 时 `@commands[@size] = cmd`（原位覆写）；否则 `@commands << cmd`（扩容）；最后 `@size += 1`。
- 实测：10,000 次 `clear`+push×64 循环后 `capacity == 64`、`size == 64`，无再分配（spec `:35-49` 断言 `capacity.should eq cap0`，本核验 §1.3 复现 `PASS 10k capacity stable`）。

### 2.3 只读视图边界
- 实现：`[]`（`:70-73`）越界（`index < 0 || index >= @size`）抛 `IndexError`；物理槽位中的陈旧数据在 `size` 之外不可见。
- 实测：spec `:16-22`（`list.size.should eq 3`、`list[0]`/`list[2]` 读取）；核验脚本 `list.size == 64` 与 push 顺序一致。逻辑视图与物理容量分离正确。

## 3. 批处理（build_batches）

### 3.1 规则与实现
- `build_batches`（`:91-105`）：从 `i=0` 起，`start=i`，`count=1`；当 `i+count < @size` 且 `same_batch_key?(@commands[i], @commands[i+count])` 为 true 时 `count += 1`；切批后 `i += count`。`same_batch_key?`（`:116-118`）：`a.atlas_id == b.atlas_id && a.clip == b.clip`。
- 规则：kind/color 不参与批键；atlas 或 clip 任一变化即切批；空 list 返回空数组。

### 3.2 手排 6 条命令逐批核对（§1.3 实测）
输入（顺序）：
1. atlas=1, clip=nil
2. atlas=1, clip=nil
3. atlas=2, clip=nil
4. atlas=2, clip=Rect(0,0,5,5)
5. atlas=2, clip=Rect(0,0,5,5)
6. atlas=3, clip=Rect(0,0,5,5)

实测输出：
```
BATCHES=4
BATCH0 start=0 count=2   # atlas=1, clip=nil（命令 1-2）
BATCH1 start=2 count=1   # atlas=2, clip=nil（命令 3）
BATCH2 start=3 count=2   # atlas=2, clip=Rect(0,0,5,5)（命令 4-5）
BATCH3 start=5 count=1   # atlas=3, clip=Rect(0,0,5,5)（命令 6）
```
逐批 `start/count` 与手排命令完全一致；`batch_count == 4`。空 list：`build_batches` 空、`batch_count == 0`（§1.3 PASS）。

### 3.3 spec 覆盖
- `spec/render_draw_list_spec.cr:51-59`：同 atlas+clip 单批 start=0 count=3 ✓
- `:61-72`：atlas 变切批（2+1）✓
- `:74-85`：clip 变切批（2+1）✓
- `:87-93`：kind/color 不切批（3 种 kind 单批）✓
- `:95-99`：空 list 0 批 ✓

## 4. 脏矩形合并（Dirty）

### 4.1 语义与实现
- `merge`（`:16-17`，dirty.cr）委托 `merge_into(rects, regions, max_regions)`，返回 `regions`。
- `merge_into`（`:29-...`）：
  1. 防御：忽略退化输入（`width <= 0 || height <= 0`）（`:19-21` / 等价 `if r.size.width > 0.0_f32 && r.size.height > 0.0_f32`）。
  2. 第一遍：重叠/相接（`adjacent?`，两轴投影相交或贴边 `<=`）合并为最小包围盒（`union`），顺序无关的稳定不动点（while changed）。
  3. 第二遍：超 `max_regions` 时贪心合并代价最小的一对（代价 = 合并后包围盒面积 − 两矩形面积和），直到 `regions.size <= max_regions`。
  4. 不保证全局最优（贪心），仅保证结果 `<= max_regions` 且不产空矩形。

### 4.2 手算复核
| 用例 | 输入 | 期望 | 实测（§1.4） | 结果 |
|---|---|---|---|---|
| 重叠 | (0,0,10,10)+(5,5,10,10) | 1 个 (0,0,15,15) | size 1, (0,0,15,15) | ✓ |
| 相接 | (0,0,10,10)+(10,0,10,10) | 1 个 (0,0,20,10) | size 1, (0,0,20,10) | ✓ |
| 不相交 | (0,0,10,10)+(100,100,5,5) | 2 个 | size 2 | ✓ |
| 退化 | (0,0,0,5)+(0,0,10,10) | 1 个 (0,0,10,10) | size 1, (0,0,10,10) | ✓ |
| 空输入 | [] | []、area 0 | empty、area 0.0 | ✓ |
| area 手算 | (0,0,10,10)+(20,20,5,5) | 100+25=125 | 125.0 | ✓ |
| 8 不相交 → ≤4 | 8 个 10×10 间距 100 | ≤4、>0、无空矩形 | size 4、>0、无空 | ✓ |

- `max_regions=4` 下 8 个不相交输入贪心合并为 **4** 个区域（§1.4 `MAX_REGIONS_RESULT_SIZE=4`），满足 `<= max_regions` 且单调减少、无空矩形。

### 4.3 spec 覆盖
- `spec/render_draw_list_spec.cr:103-108` 重叠 ✓、`:110-115` 相接 ✓、`:117-121` 不相交 ✓、`:123-134` 8→≤4 ✓、`:136-139` 空输入/area 0 ✓、`:141-146` 退化 ✓、`:148-152` area 125 ✓

## 5. 值类型与无 FFI

- `DrawCmd` 为 `struct`（`:24-36`），字段 `kind/bounds/color/atlas_id/clip`；`Batch` 为 `struct`（`:39-45`）；`CmdKind` 为 `enum`（`:18-22`）。
- `grep`（`@[Link]|LibC|libharfbuzz|libfreetype|harfbuzz|freetype|FFI|Platform|@@`）在 `draw_list.cr`/`dirty.cr`/`spec` **无命中**（§0 grep 输出为空）。无 FFI/Platform 实际依赖。

## 6. 缺陷清单（P1/P2/P3）

### P1（阻断）
| ID | 级别 | 位置 | 描述 | 影响 |
|---|---|---|---|---|
| P1-1 | **P1** | `src/tessell/render/dirty.cr:30` | 参数名 `out` 为 Crystal 保留字（`out` 用于 `out` 参数传递），编译器报 `cannot use 'out' as a parameter name`。 | **整个 spec 套件与 build 无法编译**：`crystal spec`/`crystal build src/tessell.cr` 均 EXITCODE 1，官方 58/0/0 计数无法独立复现。DrawList 15 例与 Dirty 例均被阻断。必须修复参数名（如 `sink`/`result`）后方可运行官方测试。 |

### P2
- 无。

### P3（观察/契约缺口，不构成功能缺陷）
| ID | 级别 | 位置 | 描述 | 影响/说明 |
|---|---|---|---|---|
| 观察-1 | P3 | `src/tessell/render/draw_list.cr:24-36` | `DrawCmd` 无 z-order/blend mode/纹理 UV 字段；批键仅 atlas+clip。 | 当前 M1-WP4 草图阶段契约；M2 渲染后端接入时需扩展（任务书 P3 要求）。 |
| 观察-2 | P3 | `src/tessell/render/draw_list.cr:89-105` | `build_batches` 不合并 clip（仅按 clip 相等切批），不生成 clip-stack；批内 kind/color 不参与批键（由后端逐命令绘制）。 | 当前契约明确；M2 可评估 clip 合并/排序。 |
| 观察-3 | P3 | `src/tessell/render/dirty.cr`（整体） | `merge`/`merge_into` 为纯函数/缓冲复用，但 `adjacent?`/`union`/`delete_at` 在热路径仍有分配（`Array#delete_at` 移动元素、`union` 新建 Rect）；非零分配。 | 属 M1-WP5 零分配范畴；`render_dirty_into_spec` 已声明 GC 探针，修复 P1 后可运行。 |
| 观察-4 | P3 | 任务书 vs 实测 | 任务书描述 `draw_list.cr` 86 行/`dirty.cr` 68 行/`render_draw_list_spec.cr` 135 行；实测 121/87/153 行（15 `it` 一致）。 | 行数描述偏差，以实测为准；it 数一致。 |
| 观察-5 | P3 | 工作区 | 核验期间 `git status` 新出现 `?? spec/core_node_zero_alloc_spec.cr`、`?? spec/render_dirty_into_spec.cr`、`?? tools/zero_alloc_frame.cr`（并行 M1-WP5 交付物），非本核验写入。 | 仅如实记录；本核验未读未改。 |

- **P2：无。**

## 7. 单测有效性

- `spec/render_draw_list_spec.cr`：15 个 `it`（实测 153 行），断言具体（`should eq`/`be_true`/`be_empty`），无 `should_not be_nil`（grep 无命中）。
- 抽查 2 例：
  - `spec:24-33` capacity 稳定：`reserve(32)` → 5 push → clear → `size==0`、`capacity==cap`。实现 `clear` 只置 `@size=0`、`capacity=@commands.size` 不缩减。✓
  - `spec:123-134` 8→≤4：8 个间距 100 的 10×10 矩形 `merge(rects, 4)` → `size<=4`、`>0`、无空矩形。实现贪心合并到 `<= max_regions`。✓（§1.4 实测 size=4）

## 8. 最终裁定

**裁定：FAIL**

**理由**：
1. **P1 阻断**：`src/tessell/render/dirty.cr:30` 参数名 `out` 为 Crystal 保留字，导致 `crystal spec` 与 `crystal build src/tessell.cr` 全局编译失败（EXITCODE 1），官方 58/0/0 计数无法独立复现。尽管 DrawList 15 例与 Dirty 语义经自含式重跑（§1.3/§1.4）全部 PASS 且手算复核正确，但交付物在当前状态下**不可编译/不可运行官方测试**，不满足「重跑 spec 58/0/0 与 build（删 exe）」的门禁要求。按诚实第一原则，裁定 **FAIL**（非 PASS-WITH-DEFECTS，因编译阻断为硬失败）。
2. DrawList 容量复用/批边界/脏矩形合并语义本身正确（自含式重跑 44+ 项断言全 PASS、手算复核对得上），P1 修复（重命名 `out`）后可恢复为 PASS；P3 观察（z-order/blend/UV 缺口、clip 不合并、Dirty 非零分配、行数描述偏差、并行交付物）均已列出，不构成额外功能缺陷。
3. 边界合规：仅 task-32 范围 + 本报告；未改 src/spec；临时脚本与 exe 已清理；`?? src/tessell/render/` 与 spec/render_draw_list_spec.cr 为 task-32 交付，本核验未改。

**建议**：首辅/工部将 `dirty.cr:30` 参数名 `out` 重命名为 `sink`/`result`（同步更新 `merge_into` 内部引用与 `spec/render_dirty_into_spec.cr` 调用方），随后重跑官方 `crystal spec`（期望 58/0/0）与 `crystal build`（期望 0），大理寺卿可做复验（task-34）确认 PASS。
