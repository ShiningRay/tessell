# verify-M1-WP2：M1-WP2 测量缓存语义/FNV 正确性/布局注入兼容性 核验报告

- 核验角色：大理寺卿（dalisi-qing，独立核验），受首辅 lead 节制
- 核验任务：`task-28`「M1-WP2 核验：测量缓存语义/FNV 正确性/布局注入兼容性」
- 核验对象（task-27 交付）：`src/tessell/text/measurer.cr`、`spec/text_measurer_spec.cr`、`src/tessell/layout.cr`、`src/tessell.cr`、`.gitignore`
- 依据：`docs/plan.md` M1-WP2（契约 `measure(font_id,size,text_hash,max_width):Size`，缓存键 `(font_id,size,text_hash,max_width)`）、lead 指派（m00279）
- 核验时间（本地采样）：2026-11-12 20:08:33 +08:00 ～ 会话内（Asia/Shanghai）
- 仓库：`C:\Users\ShiningRay\projects\ShiningRay\tessell`
- HEAD：`eeee8e6`（`docs: 回填 W3 提交 hash`）
- OS/Arch：`Microsoft Windows NT 10.0.26300.0` / `AMD64`
- Crystal：`C:\msys64\ucrt64\bin\crystal.exe`，`Crystal 1.22.1 [23828b0a40] (2026-10-23)`，`LLVM 23.1.3`，`Default target: x86_64-w64-windows-gnu`
- 命令 PATH 前置：`$env:PATH="C:\msys64\ucrt64\bin;"+$env:PATH`

## 0. 范围与边界

- 唯一写入：本报告 `docs/evidence/verify-M1-WP2.md`。**未修改** `src/tessell/text/measurer.cr`、`spec/text_measurer_spec.cr`、`src/tessell/layout.cr`、`src/tessell.cr`、`.gitignore` 及其他源码/证据/任务交付物。
- `git status --short`（核验末态）：
  - task-27 范围：` M .gitignore`、` M src/tessell.cr`、`?? spec/layout_spec.cr`、`?? spec/text_measurer_spec.cr`、`?? src/tessell/layout.cr`、`?? src/tessell/text/`（`src/tessell/text/measurer.cr`）
  - 预存/非本次修改（未触碰）：`?? docs/evidence/verify-M1-WP1.md` 等工作区既有 untracked
  - 本报告新增：`?? docs/evidence/verify-M1-WP2.md`
- 根目录：`tessell.exe` **不存在**（`NO_tessell_exe_in_root`）。核验中 `crystal build src/tessell.cr` 产生过根目录 `tessell.exe` 构建产物，已在验证后删除并复核清理；`.gitignore` 已含 `/*.exe`（见 §6）。
- 文件行数实测：`src/tessell/text/measurer.cr` 111 行、`spec/text_measurer_spec.cr` 108 行、`src/tessell/layout.cr` 193 行、`src/tessell.cr` 18 行（`layout.cr` 行数与任务描述 193 行一致）。

## 1. 重跑命令与原始结果

### 1.1 `crystal spec`
命令：`$env:PATH="C:\msys64\ucrt64\bin;"+$env:PATH; crystal spec`
原始输出：
```
..............................

Finished in 2.04 milliseconds
30 examples, 0 failures, 0 errors, 0 pending
SPEC_EXITCODE=0
```

### 1.2 `crystal build src/tessell.cr`
命令：`$env:PATH="C:\msys64\ucrt64\bin;"+$env:PATH; crystal build src/tessell.cr`
原始输出：
```
BUILD_EXITCODE=0
TESSell_EXE_EXISTS
```
（随后清理构建产物并复核：`REMOVED_tessell_exe` → `NO_tessell_exe_in_root`；`git status` 未因该产物新增受管变更。）

### 1.3 根目录与 `.gitignore` 检查
- `Test-Path .\tessell.exe`（最终）：`NO_tessell_exe_in_root`
- `.gitignore:6`：`/*.exe`（`Select-String -Path .gitignore -Pattern 'exe' -SimpleMatch` → `6: /*.exe`）

## 2. 契约一致性：MeasureKey、FNV-1a、hash/==（逐项）

### 2.1 `MeasureKey` 字段与相等/哈希
- `src/tessell/text/measurer.cr:12-41` `struct MeasureKey` 字段：`font_id : Int32`、`size : Float32`、`text_hash : UInt64`、`max_width : Float32`（`:13-16`），构造器接收四元组（`:18-19`）。键含 `(font_id, size, text_hash, max_width)`，与 M1-WP2 契约一致。
- `==`（`:21-26`）：四字段逐一比较，且要求 `other : MeasureKey`。
- `hash`（`:28-30`）：返回 `{font_id, size, text_hash, max_width}.hash`（`UInt64` 语义由 Crystal tuple hash 提供），包含与 `==` 完全一致的四字段，**`hash` 与 `==` 一致**（相等键必同 hash；等价性基于同一字段集）。

### 2.2 FNV-1a 64 正确性（手算）
实现（`:33-40`）：`offset_basis = 0xcbf29ce484222325_u64`，`prime = 0x100000001b3_u64`；对每字节 `b`：`h = h ^ b`，`h = h &* 0x100000001b3_u64`（64 位模乘）。

**手算 `"a"`（`'a' = 0x61`）**：
- `h0 = 0xcbf29ce484222325`
- `h1 = h0 XOR 0x61 = 0xcbf29ce484222344`
- `h2 = (h1 * 0x100000001b3) mod 2^64 = 0xaf63dc4c8601ec8c`

**实测验证**（临时脚本 `crystal run`，同算法）：  
`fnv_a=af63dc4c8601ec8c` / `expected=af63dc4c8601ec8c` / `match=true`，`EXIT=0`。与任务要求值一致。

**文本哈希稳定性**：`spec/text_measurer_spec.cr:9-13` 断言 `"hello".dup` 两实例 `MeasureKey.text_hash` 相等；`:15-17` 断言不同文本哈希不同。`measurer.cr:6` 注明“自实现 FNV-1a（跨运行稳定；String#hash 依赖运行时随机种子，不满足缓存键稳定要求）”——选择合理。

### 2.3 `==` / `hash` 一致性实测
临时脚本（require geometry+measurer，构造 key）原始输出：
```
eq=true
hash_eq=true
diff_font_eq=false
diff_text_eq=false
diff_mw_eq=false
diff_size_eq=false
KEY_EXIT=0
```
- 同内容（含 `text_hash("hi".dup)`）相等且 hash 相等。
- `font_id`/`text`/`max_width`/`size` 任一不同则 `==` 为 false（键区分正确）。未观察到“相等但 hash 不同”。

**结论 2：通过**。

## 3. 缓存语义（`CachingMeasurer`）与统计

源码（`src/tessell/text/measurer.cr:69-113`）：
- 命中：`has_key?` 为真则 `@hits += 1` 并返回 `@cache[key]`，**不调用** `@inner`（`:79-81`）。
- 未命中：`@misses += 1`，调用 `@inner.measure(...)`，写入缓存并返回（`:82-87`）。
- `invalidate_font(font_id)`：`reject!` 移除 `k.font_id == font_id` 的项，`@evictions += (before - @cache.size)`（`:104-108`），仅影响目标 font。
- `clear`：`@cache.clear`，不改计数（`:110-112`）。
- `stats`：`{hits, misses, evictions}`（`:100-102`）；每次查路径各自只增一次对应计数，无重复计数路径。
- `measure(key : MeasureKey)` 形式命中计 hit，未命中计 miss 并 `raise KeyError`（`:90-98`，spec 未覆盖但实现自洽）。

spec 断言（`spec/text_measurer_spec.cr:35-108`，8 个 caching examples）：
- 首次 miss、二次 hit：`hits==1, misses==1, evictions==0`（`:36-45`）。
- 不同 `font_id`/`size`/`max_width`/`text` 各自 miss：`misses==2`（`:47-77`）。
- `invalidate_font(7)` 在缓存含 font 7 两条、font 9 一条时：`evictions==2`，再测 font 7 → `misses==4`（`:79-89`），font 9 条目未被计入 evictions（仅目标 font 移除）。
- `clear` 后再同键查询：`misses==2`（`:91-98`）。
- 缓存返回值等于 `inner.measure` 结果：`a.width==b.width && a.height==b.height`（`:100-107`）。

**“命中不重复计算”证据**：相同键第二次调用后 `misses` 仍为 1（未增加），且实现路径不经 `@inner`；统计与路径一致。

**结论 3：通过**。

## 4. 布局注入兼容性（`Layout` + `Measurer`）

- `src/tessell/layout.cr:60,93,128`：`measure/arrange/solve` 增加可选参数 `measurer : Text::Measurer? = nil`，默认 `nil`，**不破坏既有调用方**；内部递归传递 measurer（`:83,106,120,129,131`）。
- `:67-76`：仅当叶子、`measurer` 非 nil、`!node.text.empty?` 且对应维度为 `Auto` 时，调用 `measurer.measure(text,font_id,font_size,avail_w)` 取 `width/height` 作为 intrinsic；否则 intrinsic 为 0，保持原行为。`LayoutNode` 新增 `text/font_id/font_size` 字段默认空/0（`:28-31,40-42`），既有构造不受影响。
- **默认等价性**：全量 `crystal spec` **30 examples, 0 failures**，其中 `spec/layout_spec.cr` **12 个 `it`** 全绿（与 WP1 行为兼容）；无 measurer/无文本 Auto 叶子仍得 0。
- **注入生效实测**（临时脚本）：`StubMeasurer`，`"abcd"`(4 chars) `size=10`、`max_width=0`、Auto 叶子 → `measured_w=24.0 measured_h=12.0`；默认 `nil`、无文本 Auto 叶子 → `default_w=0.0 default_h=0.0`，`INJ_EXIT=0`。

**结论 4：通过**。

## 5. 单测有效性与手算复核

- `spec/text_measurer_spec.cr`：**12 个 `it`**（`MeasureKey` 2、`StubMeasurer` 2、`CachingMeasurer` 8），≥8，且无 `should_not be_nil`/`should be_nil`（grep 空）。断言均为具体 `eq`/`be_true` 数值或统计比较，非空泛。
- `spec/layout_spec.cr`：12 个 `it`；全量 `crystal spec` 30 examples（含 geometry/layout/text 等）。

**手算复核 1 — StubMeasurer 宽度单调**（`spec/text_measurer_spec.cr:21-26`，`measurer.cr:57-64`：`char_w = size*0.6`，`total_w = text.size*char_w`，`height = size*1.2` 无换行）：  
`"ab"` size 10 → `2*10*0.6 = 12.0`，h `12.0`；`"abcd"` → `4*10*0.6 = 24.0`。断言 `s2.width(24.0) > s1.width(12.0)` **正确**。

**手算复核 2 — max_width 换行高度**（`spec/text_measurer_spec.cr:28-32`）：  
`"abcdefghij"`(10 chars) size 10，`max_width 20` → `total_w = 10*10*0.6 = 60.0`，`lines = ceil(60.0/20.0) = 3`，`height = 10*1.2*3 = 36.0`。断言 `height > 10.0*1.2 (12.0)` **正确**。

**结论 5：通过**。

## 6. 无 FFI / 桩值声明

- `grep`（`@[Link]|LibC|libharfbuzz|libfreetype|harfbuzz|freetype|FFI`）命中仅注释：
  - `src/tessell/text/measurer.cr:4`：`# 约束：不引用 FFI/FreeType/HarfBuzz（真实 shaping 属 M2）；`
  - `src/tessell/text/measurer.cr:43`：`# 文本测量抽象。真实实现（M2 FreeType/HarfBuzz）不得引用本文件`
  - `src/tessell/layout.cr:3`：`# 约束：不依赖 widget/UI/FFI；相同输入得到相同输出；无全局状态。`
  无 `@[Link]`、无 `LibC`、无 libharfbuzz/libfreetype 实际调用。
- 桩值声明：`measurer.cr:5` “StubMeasurer 桩值为确定性桩，不得当真实度量使用”；`:54-55` “仅用于布局与单测；不得当真实度量”。

**结论 6：通过**。

## 7. 缺陷清单（P1/P2/P3）

| ID | 级别 | 位置 | 描述 | 影响/说明 |
|---|---|---|---|---|
| 观察-1 | P3 | `src/tessell/text/measurer.cr:28-30` | `MeasureKey#hash` 委托 `{font_id,size,text_hash,max_width}.hash`（tuple hash）而非基于 `text_hash` 的自定义组合；`==` 与字段集一致，当前与 `==` 一致且 spec/实测通过。 | 非缺陷；若未来为跨进程/持久化要求自定义 hash 需另行约定，但与本任务“与 == 一致”要求相符。 |
| 观察-2 | P3 | `src/tessell/text/measurer.cr:110-112` | `clear` 仅清空缓存，不重置/不增加 `evictions`（`invalidate_font` 才计 evictions）。spec 未断言 clear 的 evictions 语义。 | 行为清晰；若需审计“被清除条目数”可在后续增强，但不影响当前契约与测试。 |
| 观察-3 | P3 | `src/tessell/layout.cr:67-76` | 注入 measurer 时对 Auto 宽/高可分别调用两次 `measure`（同参数），由 `CachingMeasurer` 吸收重复计算；功能正确。 | 微小性能特性，缓存命中保证无重复内层计算压力可控。 |
| 观察-4 | P3 | `crystal build` 产物 | `crystal build src/tessell.cr` 在根目录生成 `tessell.exe`（已清理）。`.gitignore` 含 `/*.exe` 已覆盖。 | 构建副作用，不属于 task-27 交付；核验后已移除并复核 `NO_tessell_exe_in_root`。 |

- **P1**：无。**P2**：无。

## 8. 最终裁定

**裁定：PASS**

**理由**：`MeasureKey` 四字段与 `(font_id,size,text_hash,max_width)` 契约一致，`==`/`hash` 字段集一致且实测同键等价同 hash、差异键不等；FNV-1a 64 实现对 `"a"` 手算与实测均得 `0xaf63dc4c8601ec8c` 且文本哈希跨实例稳定。`CachingMeasurer` 命中不重复计算（misses 不增）、各维度 miss、`invalidate_font` 定向清除并计 evictions、`clear` 后 miss、统计正确，spec 12 例（≥8）断言具体无空泛；StubMeasurer 宽度单调与换行高度手算复核正确。布局注入可选且默认 `nil` 等价（全量 30 examples, 0 failures，layout 12 例绿），注入时 Auto 叶子尺寸来自 measurer（24.0x12.0 vs 默认 0.0x0.0）。无 FFI/harfbuzz/freetype/LibC 实际引用，桩值非真实度量声明明确。`crystal spec` 30/0/0/0 EXITCODE=0，`crystal build` EXITCODE=0，根目录无 `tessell.exe`，`.gitignore` 含 `/*.exe`。边界合规（仅 task-27 变更 + 本报告/预存 untracked）。
