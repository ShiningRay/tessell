# verify-W2-ime-metrics：W2-核验2（task-11 IME 探针 / task-12 度量工具链）独立核验报告

- 核验角色：大理寺卿（dalisi-qing，独立核验），受首辅 lead 节制
- 核验任务：`task-14`「W2-核验2：IME 探针与度量工具链独立核验（task-11/12）」
- 核验时间（本地）：2026-11-12 17:08:39 +08:00 ～ 2026-11-12 17:20:00 +08:00（Asia/Shanghai，会话采样）
- 仓库：`C:\Users\ShiningRay\projects\ShiningRay\tessell`
- HEAD：`1b0d832220f3017e9efd6f42d59b5d7fab6b09f3`
- OS/Arch：`Microsoft Windows NT 10.0.26300.0` / `AMD64`
- Crystal：`Crystal 1.22.1 [23828b0a40] (2026-10-23)`，`LLVM 23.1.3`，`Default target: x86_64-w64-windows-gnu`
- 命令 PATH 前置：`$env:PATH="C:\msys64\ucrt64\bin;"+$env:PATH`

## 0. 范围与边界

- 核验对象（只读）：`examples/m0_ime_probe.cr`、`docs/evidence/M0-WP4-ime.md`、`tools/bench_frame_time.cr`、`tools/bench_frame_time.ps1`、`docs/evidence/M0-WP5m-metrics.md`。
- 唯一写入：本报告 `docs/evidence/verify-W2-ime-metrics.md`。**未修改**被核验文件、`examples/`、`src/`、`spec/`、`shard.yml`、`docs/plan*`、`docs/roadmap.md`、`README`。
- `git status --short`（核验时可见）：`?? docs/evidence/M0-WP4-ime.md`、`?? docs/evidence/M0-WP4-text-deps.md`、`?? docs/evidence/M0-WP4-text.md`、`?? docs/evidence/M0-WP5m-metrics.md`、`?? docs/evidence/verify-W2-text.md`、`?? docs/research/layout-two-pass.md`、`?? examples/m0_ffi_load.cr`、`?? examples/m0_ime_probe.cr`、`?? examples/m0_text_probe.cr`、`?? tools/`（均为 untracked 预期交付/证据/工具；本报告新增后亦为 untracked）。
- `git status --short -- src spec shard.yml docs/plan.md docs/roadmap.md docs/plan-execution.md README`：无输出。

## 1. IME 探针重跑（task-11）

### 1.1 基线 `--frames=60`

命令：
```powershell
$env:PATH="C:\msys64\ucrt64\bin;"+$env:PATH
crystal run examples/m0_ime_probe.cr -- --frames=60
```

原始输出：
```
ime_start=0 ime_composition=0 ime_end=0 ime_setcontext=1 ime_notify=3 ime_test_injected=0
imm_available=true imm_open_status=1 ime_messages=4 imm_error=none hwnd=0x210756 imm_context=0x39100e17 imm_associate_ret=0x39100e17 imm_set_open_ret=1 imm_set_comp_ret=1 iso_tid=2061471267888 main_tid=2061471268512 frames=60
EXITCODE=0
```

### 1.2 `--frames=60 --ime-test`

命令：
```powershell
$env:PATH="C:\msys64\ucrt64\bin;"+$env:PATH
crystal run examples/m0_ime_probe.cr -- --frames=60 --ime-test
```

原始输出：
```
ime_start=0 ime_composition=0 ime_end=0 ime_setcontext=2 ime_notify=3 ime_test_injected=1
imm_available=true imm_open_status=1 ime_messages=5 imm_error=none hwnd=0x9d06f4 imm_context=0x1a660ee9 imm_associate_ret=0x1a660ee9 imm_set_open_ret=1 imm_set_comp_ret=1 iso_tid=2647205887024 main_tid=2647205887648 frames=60
EXITCODE=0
```

### 1.3 与证据 token 比对（`docs/evidence/M0-WP4-ime.md`）

| token/项 | 证据值（§2.1/2.2） | 本次实测 | 结论 |
|---|---|---|---|
| `imm_available` | true / true | true / true | 一致 |
| `imm_open_status` | 1 / 1 | 1 / 1 | 一致 |
| `ime_messages` | 4 / 5 | 4 / 5 | 一致 |
| `ime_test_injected` | 0 / 1 | 0 / 1 | 一致 |
| `imm_error` | none / none | none / none | 一致 |
| 基线计数构成 | `ime_setcontext=1 ime_notify=3`，其余 0 | `ime_setcontext=1 ime_notify=3`，其余 0 | 一致 |
| `--ime-test` 增量 | `ime_setcontext` +1 → 2，`ime_messages` +1 → 5 | 同左 | 一致 |
| `imm_set_open_ret` / `imm_set_comp_ret` | 1 / 1 | 1 / 1 | 一致 |
| `hwnd/imm_context/iso_tid/main_tid` | 运行时地址/ID | 不同运行时值 | 预期差异（非稳定 token） |
| `EXITCODE` | 0 / 0 | 0 / 0 | 一致 |

## 2. 度量工具链重跑（task-12）

### 2.1 三次 `--frames=300 --warmup=30`

命令（逐次等价）：
```powershell
$env:PATH="C:\msys64\ucrt64\bin;"+$env:PATH
crystal run tools/bench_frame_time.cr -- --frames=300 --warmup=30
```

原始输出：
```
---RUN1---
frames=300
warmup=30
p50_us=15.8
p95_us=18.5
p99_us=23.6
mean_us=16.0
min_us=12.9
max_us=29.0
alloc_bytes=5779056
gc_disabled=true
EXITCODE=0
---RUN2---
frames=300
warmup=30
p50_us=16.0
p95_us=19.9
p99_us=28.6
mean_us=16.5
min_us=11.9
max_us=37.7
alloc_bytes=5779056
gc_disabled=true
EXITCODE=0
---RUN3---
frames=300
warmup=30
p50_us=15.8
p95_us=19.9
p99_us=23.2
mean_us=16.4
min_us=11.9
max_us=46.5
alloc_bytes=5779056
gc_disabled=true
EXITCODE=0
```

本次中位数（3 次）：`p50_us_median=15.8`，`p95_us_median=19.9`，`p99_us_median=23.6`，`alloc_bytes_median=5779056`。

与证据 `docs/evidence/M0-WP5m-metrics.md` 对比：证据中位数 `p50_us=17.5 p95_us=23.0 p99_us=28.8`、`alloc_bytes=5779056`。`alloc_bytes/frames/warmup/gc_disabled/EXITCODE` 一致；分位数存在波动（证据与本次均属同量级微秒级），属计时噪声范围（OS 调度/频率/缓存），非功能性不一致。三次 run `alloc_bytes` 恒为 5779056。

### 2.2 `--json` 可解析性与耗时

命令（含计时）：
```powershell
$env:PATH="C:\msys64\ucrt64\bin;"+$env:PATH
Measure-Command { crystal run tools/bench_frame_time.cr -- --frames=300 --warmup=30 --json }
```

原始输出（节选，含 JSON 行与 token 行）：
```
{"frames":300,"warmup":30,"p50_us":17.2,"p95_us":37.5,"p99_us":46.3,"mean_us":21.6,"min_us":12.9,"max_us":58.2,"alloc_bytes":5779056,"gc_disabled":true}
frames=300
warmup=30
p50_us=17.2
p95_us=37.5
p99_us=46.3
mean_us=21.6
min_us=12.9
max_us=58.2
alloc_bytes=5779056
gc_disabled=true
EXITCODE=0
ELAPSED_SEC=1.7021873
JSON_PARSE_OK=true
json_frames=300
json_p50_us=17.2
json_alloc_bytes=5779056
```

结论：`--json` 首行 JSON 可被 PowerShell `ConvertFrom-Json` 解析（`JSON_PARSE_OK=true`），字段与 token 行一致；300 帧单次 run 总耗时约 `1.70s`，**远 < 30s**（满足）。

## 3. 真实性检查（源码 grep/读码）

### 3.1 IME 计数与 token 来源（`examples/m0_ime_probe.cr`）

grep 关键点（摘录）：
- `:235` `ProbeState.ime_start += 1`（`WM_IME_STARTCOMPOSITION`）
- `:237` `ProbeState.ime_composition += 1`（`WM_IME_COMPOSITION`）
- `:239` `ProbeState.ime_end += 1`（`WM_IME_ENDCOMPOSITION`）
- `:241` `ProbeState.ime_setcontext += 1`（`WM_IME_SETCONTEXT`）
- `:243` `ProbeState.ime_notify += 1`（`WM_IME_NOTIFY`）
- `:373,:430` `ime_messages = ProbeState.ime_start + ProbeState.ime_composition + ProbeState.ime_end + ProbeState.ime_setcontext + ProbeState.ime_notify`
- `:378,:437` 输出行由运行时变量插值生成（`imm_available/imm_open_status/ime_messages/imm_error/hwnd/imm_context/...`），非硬编码常量字符串。
- `:403-406` `--ime-test` 通过 `SendMessageW(hwnd, WM_IME_SETCONTEXT, 1_u64, 0_i64)` 注入并 `ProbeState.ime_test_injected += 1`；同线程 `SendMessageW` 同步派发至 WndProc，计数增量可由 WndProc 分支解释。
- `:346-382` `ImmGetContext` 为空时设置 `imm_available=false`、记录 `imm_error`、仍跑帧后 `exit 0` 打印 token（符合任务书约束）。

未见将 `ime_messages`/`imm_available` 等结果 token 硬编码为固定值的赋值伪装；失败路径（GL/窗口创建失败）经 `fail`/异常路径输出 error（`:185-189,:442-451`）。

### 3.2 度量计算与分配采样（`tools/bench_frame_time.cr`）

grep 关键点（摘录）：
- `:32-41` `percentile` 线性插值；`:150` `sorted.sort!`；`:152-154` `p50/p95/p99 = percentile(sorted, 50/95/99)`（由排序样本计算得出）。
- `:117-119` `GC.collect; GC.disable; before_bytes = GC.stats.bytes_since_gc`；`:141-142` `after_bytes = GC.stats.bytes_since_gc; GC.enable`；`:160` `alloc_bytes = after_bytes >= before_bytes ? (after_bytes - before_bytes) : 0_u64`（由 GC 统计差值计算）。
- grep `5779056` 在源码中无匹配；`alloc_bytes`/分位数均非硬编码。
- `:124` 测量循环内每帧 `cmds = Array(DrawCmd).new(node_count * 2)` 并多次 `<<`（分配/写入 workload）。

`tools/bench_frame_time.ps1` 取三次 run 并计算中位数（`:29-46`），与证据描述一致。

## 4. 关键核验点审问

### 4.1 `ImmGetContext` 非空与“关联成功”

- `ImmGetContext(hwnd)` 返回非空 HIMC（`:346-347`，实测 `imm_context` 非 0x0）表明为窗口获取到输入法上下文句柄，这是 IMM32 挂接可用的必要信号。
- 代码随后执行 `ImmAssociateContext(hwnd, himc)`、`ImmSetOpenStatus(himc,1)` 并读回 `ImmGetOpenStatus`、`ImmSetCompositionWindow`（`:384-401`），实测返回 `imm_associate_ret`（前一关联值）、`imm_set_open_ret=1`、`imm_set_comp_ret=1`、`imm_open_status=1`，说明这些调用在 API 层面返回成功。
- **但**：非空 HIMC + 调用返回成功并不等价于“真实 IME 组合输入路径已闭环验证”（现代 Windows 多经 TSF 兼容层，START/COMPOSITION/END 依赖实际输入与 IME 行为）。证据将真实组合列为 `[未验证]` 并给人工步骤，**该诚实性判定成立**。

### 4.2 基线 `ime_messages=4`（setcontext 1 + notify 3）是否真实系统消息/伪造

- 计数仅在 WndProc 对应 `msg` 分支自增（`:235,237,239,241,243`），`ime_messages` 为五类求和（`:373,430`），无事后注入/篡改计数逻辑；重跑基线稳定得到 `ime_setcontext=1 ime_notify=3`、其余 0，与窗口创建/系统派发的 `WM_IME_SETCONTEXT`/`WM_IME_NOTIFY` 现象相符。
- 判定：**构成来自实际进入 WndProc 的系统消息计数，非源码伪造常量**（运行时仍依赖系统行为，但非探针造假）。

### 4.3 `--ime-test` 注入路径是否真的走 WndProc

- `:403-405` 在 Isolated UI 线程同一窗口上调用 `SendMessageW(hwnd, WM_IME_SETCONTEXT, 1, 0)`；`SendMessageW` 对同线程窗口同步调用窗口过程，触发 `:240-241` 分支 `ime_setcontext += 1`。实测 `ime_test_injected` 0→1 且 `ime_setcontext` 1→2、`ime_messages` 4→5，**证明注入消息经 WndProc 计数路径**。该注入为合成消息（证据已声明），不等同真实 IME 输入。

### 4.4 `alloc_bytes=5779056` 在 `GC.disable` 窗口内非 0 的合理性与 M1-WP5「差值=0」判据适用性（M-3）

- 合理性：`GC.disable` 禁止 GC 回收但**不禁止分配**；`GC.stats.bytes_since_gc` 为自上次 GC/计数点以来的分配字节累计，采样窗口内每帧执行 `cmds = Array(DrawCmd).new(node_count * 2)` 并 push（`:124,133,136`）必然产生分配，故 after-before 非 0 且三次稳定（5779056）是**符合当前 workload/实现语义**的观测。
- 对 M1-WP5「差值=0」判据的适用性：**不能直接用当前工具/当前 workload 的原始 `alloc_bytes` 判定“稳态热路径差值=0”**。原因：该 spike 明确模拟并计入每帧新建数组与绘制命令对象的分配（见 `:99-101,124`），测得的是“该模拟场景的分配体量”，而非零分配稳态帧。若 M1-WP5 目标为热路径帧内分配差值 0，需替换/改造 workload 为预分配与复用缓冲、避免帧内堆分配，并在同一 `GC.collect→GC.disable→采样→GC.enable` 协议下验证（warmup 已在采集前完成并于采集前 collect，协议方向正确）。
- 建议口径：将本工具输出解释为“给定帧工作负载在禁 GC 窗口内的 `bytes_since_gc` 增量”；M1-WP5 门禁应明确定义“待测帧步骤集合 + 零分配实现约束 + 同协议采样”，以 Δalloc_bytes==0 为通过条件，并记录 GC 后端/版本敏感性（[未验证]）。`tools/bench_frame_time.ps1`/证据文档应同步注明“当前默认 workload 非零分配基线”，避免误用。

### 4.5 IME 缺口与证据诚实性

- `START/COMPOSITION/END=0`（自动基线/合成注入）说明本次**未观测到真实输入法组合生命周期消息**；只能证明窗口与 IMM32 API/消息通路可达，不能证明真实中文/日文等 IME 上屏组合已验证。
- `docs/evidence/M0-WP4-ime.md` 明确标注“真实 IME 组合输入 **[未验证]**”（`:20,:72,:85,:94`）、给出人工步骤（§5）并将结论表述为“部分可用…真实 IME 组合输入待人工验证”（§7）：**诚实且步骤基本可执行**（含延长 frames、切 IME、输入样例、观测计数项）。仍缺少对“需前台焦点/系统 IME 状态/TSF 兼容差异”的强保证，但作为手测指引可操作。

## 5. 逐项结论

| # | 核验项 | 结论 | 证据要点 |
|---|---|---|---|
| 1 | IME 重跑与 token 比对 | 通过 | 基线/`--ime-test` EXITCODE=0；关键 token（imm_available/imm_open_status/ime_messages/ime_test_injected/imm_error/计数构成）与 `M0-WP4-ime.md` 一致 |
| 2 | 度量 3 次与 `--json`/耗时 | 通过 | 3 次 EXITCODE=0，alloc_bytes 恒 5779056；中位数同量级可复现（计时波动）；`--json` 可解析，单次 ~1.7s < 30s |
| 3 | 真实性（无硬编码/计算得出） | 通过 | IME 计数为 WndProc 自增求和、token 变量插值；bench 分位数排序插值、alloc_bytes=GC.stats 差值，无 5779056/固定分位数硬编码 |
| 4 | M-3 口径（alloc_bytes 非 0 合理性；能否直接用于 M1-WP5“差值=0”） | 通过（有条件）+ 缺陷 D1 | 非 0 合理；**当前默认 workload 不可直接作为 M1-WP5 零分配判据的通过证据**，需零分配 workload 与明确口径（见 D1） |
| 5 | IME 缺口与 [未验证] 诚实性/步骤 | 通过 | START/COMPOSITION/END=0 仅反映未做真实组合；证据诚实标注 [未验证] 且人工步骤可执行 |
| 6 | 边界 | 通过 | 仅新增预期 untracked 交付/证据；未改 `src/spec/shard.yml/docs/plan*`；本次仅写本报告 |

## 6. 缺陷清单

| ID | 严重性 | 文件:行号 | 问题 | 复现/证据 | 影响与建议 |
|---|---|---|---|---|---|
| D1 | 中 | `tools/bench_frame_time.cr:99-101,124`（采样口径相关 `:117-119,141-142,160`） | 默认测量 workload 在采样循环内每帧 `Array(DrawCmd).new(node_count * 2)` 并持续分配，`alloc_bytes` 稳定非 0（5779056）；工具/证据未将“默认 workload 非零分配”与 M1-WP5“热路径差值=0”判据的适用边界显式固化为门禁前置条件，易被误读为可直接判定零分配达标/不达标。 | `crystal run tools/bench_frame_time.cr -- --frames=300 --warmup=30` → `alloc_bytes=5779056`（三次一致，EXITCODE=0）；源码显示每帧新建数组与 push。 | 影响：若直接套用当前输出给 M1-WP5“差值=0”结论将产生口径错误。建议：为 M1-WP5 提供零分配 steady-state workload（预分配/复用缓冲）或参数化场景，文档显式定义 Δalloc_bytes==0 判据与 GC.collect→disable→采样→enable 协议；在 `docs/evidence/M0-WP5m-metrics.md`/工具帮助中标注当前基线为非零分配模拟。 |
| D2 | 低（证据/验证缺口，已声明） | `docs/evidence/M0-WP4-ime.md:20,72,85,94`；`examples/m0_ime_probe.cr:403-406`（仅合成注入） | 真实 IME START/COMPOSITION/END 组合消息未自动/实测验证；`--ime-test` 仅证明合成 `WM_IME_SETCONTEXT` 经 WndProc。 | 基线/注入实测均 `ime_start=0 ime_composition=0 ime_end=0`；证据已标 `[未验证]` 并给人工步骤。 | 影响：M-1 闭环仍依赖人工手测。建议：按证据 §5 在真实 IME 输入下补采计数与候选窗位置观察，更新证据与 [未验证] 状态。 |

## 7. 最终裁定

**裁定：PASS**

理由：在指定环境下对 task-11/task-12 交付物完成只读独立重跑与源码审查；IME 基线/`--ime-test` token 与计数构成同证据一致且计数来自 WndProc 真实增量（含同步注入路径验证），EXITCODE=0；度量工具 3 次 run `alloc_bytes` 稳定、分位数同量级可复现、`--json` 可解析且单次 <30s，分位数与分配值由计算得出无硬编码；证据中对真实 IME 组合与 GC 语义等 `[未验证]` 标注诚实。发现的缺陷主要为 M1-WP5 零分配判据的口径/适用性风险（D1，需 workload/文档约束）与已声明的真实 IME 组合缺口（D2），不构成对本次 W2 spike 可复现性与真实性的否定，但须在后续里程碑使用前按建议收口。

（备注：任务书要求裁定格式为 PASS/FAIL；本报告另列缺陷 D1/D2 及建议以供首辅裁断与后续整改。）
