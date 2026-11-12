# verify-W2-metrics-fix：W2-复验2（task-19 度量工具 steady 场景与判据映射）独立核验报告

- 核验角色：大理寺卿（dalisi-qing，独立核验），受首辅 lead 节制
- 核验任务：`task-20`「W2-复验2：度量工具 steady 场景与判据映射复验（task-19）」
- 复验依据：`docs/evidence/verify-W2-ime-metrics.md` 缺陷 D1（`tools/bench_frame_time.cr:99-101,124` 及口径 `:117-119,141-142,160`）：默认 workload 不可直接作为 M1-WP5「热路径帧内分配差值=0」判据
- 复验对象：`tools/bench_frame_time.cr`、`tools/bench_frame_time.ps1`、`docs/evidence/M0-WP5m-metrics.md`（task-19 修改后）
- 核验时间（本地）：2026-11-12 17:31:57 +08:00 ～ 2026-11-12 17:36:00 +08:00（Asia/Shanghai，会话采样）
- 仓库：`C:\Users\ShiningRay\projects\ShiningRay\tessell`
- HEAD：`1b0d832220f3017e9efd6f42d59b5d7fab6b09f3`（`docs: 明确 W1 回填提交 hash`）
- OS/Arch：`Microsoft Windows NT 10.0.26300.0` / `AMD64`
- Crystal：`C:\msys64\ucrt64\bin\crystal.exe`，`Crystal 1.22.1 [23828b0a40] (2026-10-23)`，`LLVM 23.1.3`，`Default target: x86_64-w64-windows-gnu`
- 命令 PATH 前置：`$env:PATH="C:\msys64\ucrt64\bin;"+$env:PATH`

## 0. 范围与边界

- 唯一写入：本报告 `docs/evidence/verify-W2-metrics-fix.md`。**未修改**被核验文件 `tools/bench_frame_time.cr`、`tools/bench_frame_time.ps1`、`docs/evidence/M0-WP5m-metrics.md`，未改 `src/`、`spec/`、`shard.yml`、`README`、`docs/plan*`、`docs/roadmap.md`、`examples/`。
- `git status --short -- tools/bench_frame_time.cr docs/evidence/M0-WP5m-metrics.md`：`?? docs/evidence/M0-WP5m-metrics.md`、`?? tools/bench_frame_time.cr`（task-19 目标在当前工作区为 untracked/修改态呈现）。
- `git status --short`（核验时全局）：另含预存 W2 untracked 产物 `?? docs/evidence/M0-WP4-ime.md`、`?? docs/evidence/M0-WP4-text-deps.md`、`?? docs/evidence/M0-WP4-text.md`、`?? docs/evidence/verify-W2-ime-metrics.md`、`?? docs/evidence/verify-W2-text.md`、`?? docs/evidence/verify-W2-text-fix.md`、`?? docs/research/layout-two-pass.md`、`?? examples/m0_ffi_load.cr`、`?? examples/m0_ime_probe.cr`、`?? examples/m0_text_probe.cr`、`?? tools/` 等；非本次复验引入，未触碰。`src/spec/shard.yml/docs/plan*` 无修改。

## 1. 复验项 1：代码核（`tools/bench_frame_time.cr` / `tools/bench_frame_time.ps1`）

### 1.1 场景与预分配（`tools/bench_frame_time.cr`）
- 参数解析：`--steady` 置 `steady=true`（`:71,87-88`）；`scenario = steady ? "steady" : "default"`（`:110`）。
- 预分配：固定场景 `node_count=200`、`nodes` 一次性构建（`:103-108`）；`cmds_cap=node_count*2`（`:113`）；`cmds_buf = Array(DrawCmd).new(cmds_cap) { DrawCmd.new(...) }` 预分配命令缓冲（`:114`）；`durations_us = Array(Float64).new(frames, 0.0)` 预分配采样数组（`:115`）。
- **steady 路径循环体**：warmup（`:118-129`）与采样帧（`:149-165`）均遍历 `nodes.each_with_index`，仅做数值计算并 `cmds_buf[base] = DrawCmd.new(...)` / `cmds_buf[base + 1] = DrawCmd.new(...)` 索引写入既有缓冲，累加 `work_sink`；**未见 `Array.new`、`<<`/push、字符串拼接/插值到新字符串对象、闭包捕获新建等循环内容器/字符串分配模式**（与 default 路径 `:130-139,166-178` 的每帧 `Array(DrawCmd).new` + `<<` 形成对照）。
- 结构体说明：`FakeNode`/`DrawCmd` 为 `struct`（`:16,28`）；循环中 `DrawCmd.new(...)` 赋值为值写入。`GC.stats.bytes_since_gc` 差值实测 steady 为 0（见 §2），与“预分配+索引写入”口径一致。
- **default 场景未被改坏**：无 `--steady` 时仍走每帧 `cmds = Array(DrawCmd).new(cmds_cap)` + `cmds << ...`（`:130,166`），保留分配体量语义。

### 1.2 采样协议顺序（`tools/bench_frame_time.cr:142-148,183-184`）
- warmup 完成后：`GC.collect` → `gc_stable_start = "collected"` → `GC.disable` → `before_bytes = GC.stats.bytes_since_gc`（`:144-147`）。
- N 帧采样后：`after_bytes = GC.stats.bytes_since_gc` → `GC.enable`（`:183-184`）。
- 输出含 `gc_disabled=true`、`gc_stable_start=#{gc_stable_start}`（`:241-242`，json `:222-223`）。
- **异常/ensure 路径**：`GC.enable` 位于主流程尾部 `:184`，**未包裹在 `ensure` 块中**；若采样循环/后续逻辑抛异常，可能导致 GC 在进程异常路径下保持 disabled（对短命 CLI 影响有限，但协议健壮性不足）。报告如实记录为观察项（非本次判 FAIL 理由，因正常路径与重跑结果正确且证据未声称“异常安全”）。

### 1.3 输出与脚本（`tools/bench_frame_time.cr` / `tools/bench_frame_time.ps1`）
- token：`scenario/frames/warmup/p50_us/p95_us/p99_us/mean_us/min_us/max_us/alloc_bytes/gc_disabled/gc_stable_start`；steady 额外 `alloc_bytes_steady`、`alloc_delta_zero`（`:236-240`，json `:218-221`）。
- `tools/bench_frame_time.ps1`：`-Steady` 透传 `--steady`（`:11-13,19-20,23,26`）；解析含 `alloc_bytes_steady/alloc_delta_zero`（`:30`）；steady 汇总输出 `alloc_bytes_steady_median` 与 `alloc_delta_zero_all`（`:56-60`），并打印 `scenario`（`:51`）；注释明确 default 不得用于 M1-WP5 零分配判据（`:9-10`）。

## 2. 复验项 2：steady 场景重跑 3 次（`--frames=300 --warmup=30 --steady`）

命令：
```powershell
$env:PATH="C:\msys64\ucrt64\bin;"+$env:PATH
Set-Location "C:\Users\ShiningRay\projects\ShiningRay\tessell"
for ($i=1; $i -le 3; $i++) {
  Write-Output "---STEADY_RUN$i---"
  & "C:\msys64\ucrt64\bin\crystal.exe" run tools/bench_frame_time.cr -- --frames=300 --warmup=30 --steady 2>&1
  Write-Output "EXITCODE=$LASTEXITCODE"
}
```

| RUN | scenario | frames | warmup | p50_us | p95_us | p99_us | mean_us | min_us | max_us | alloc_bytes | alloc_bytes_steady | alloc_delta_zero | gc_disabled | gc_stable_start | EXITCODE |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|---|---|---:|
| 1 | steady | 300 | 30 | 14.1 | 19.0 | 19.0 | 15.1 | 14.0 | 25.7 | 0 | 0 | true | true | collected | 0 |
| 2 | steady | 300 | 30 | 14.0 | 16.1 | 17.5 | 14.5 | 13.9 | 42.6 | 0 | 0 | true | true | collected | 0 |
| 3 | steady | 300 | 30 | 14.0 | 16.2 | 20.7 | 14.9 | 13.9 | 22.2 | 0 | 0 | true | true | collected | 0 |

原始输出（stderr 为空）：
```
---STEADY_RUN1---
scenario=steady
frames=300
warmup=30
p50_us=14.1
p95_us=19.0
p99_us=19.0
mean_us=15.1
min_us=14.0
max_us=25.7
alloc_bytes=0
alloc_bytes_steady=0
alloc_delta_zero=true
gc_disabled=true
gc_stable_start=collected
EXITCODE=0

---STEADY_RUN2---
scenario=steady
frames=300
warmup=30
p50_us=14.0
p95_us=16.1
p99_us=17.5
mean_us=14.5
min_us=13.9
max_us=42.6
alloc_bytes=0
alloc_bytes_steady=0
alloc_delta_zero=true
gc_disabled=true
gc_stable_start=collected
EXITCODE=0

---STEADY_RUN3---
scenario=steady
frames=300
warmup=30
p50_us=14.0
p95_us=16.2
p99_us=20.7
mean_us=14.9
min_us=13.9
max_us=22.2
alloc_bytes=0
alloc_bytes_steady=0
alloc_delta_zero=true
gc_disabled=true
gc_stable_start=collected
EXITCODE=0
```

结论：3 次均 `scenario=steady`、`alloc_bytes_steady=0`、`alloc_delta_zero=true`、`EXITCODE=0`；与 `docs/evidence/M0-WP5m-metrics.md:120-180,221-223` 记录的协议/结果方向一致（alloc 零值与 delta true 一致；分位数属计时波动范围）。**不存在“alloc 非 0 却声称通过”的情形。**

## 3. 复验项 3：默认场景 1 次（`--frames=300 --warmup=30`）

命令：
```powershell
& "C:\msys64\ucrt64\bin\crystal.exe" run tools/bench_frame_time.cr -- --frames=300 --warmup=30 2>&1
"EXITCODE=$LASTEXITCODE"
```

原始输出：
```
---DEFAULT_RUN---
scenario=default
frames=300
warmup=30
p50_us=16.0
p95_us=26.9
p99_us=33.1
mean_us=16.9
min_us=12.1
max_us=46.2
alloc_bytes=5776576
gc_disabled=true
gc_stable_start=collected
EXITCODE=0
```

结论：`scenario=default`、`alloc_bytes=5776576`（非 0）、`EXITCODE=0`；默认场景未被改坏，仍体现每帧分配体量（与 task-12 记录 5779056 同量级，细微差异属 GC/实现细节可接受波动）。

## 4. 复验项 4：`--json` 两场景可解析

命令与结果：
- default：`crystal run tools/bench_frame_time.cr -- --frames=300 --warmup=30 --json`
  - JSON 行：`{"scenario":"default","frames":300,"warmup":30,"p50_us":16.3,"p95_us":20.3,"p99_us":27.2,"mean_us":16.6,"min_us":12.3,"max_us":33.5,"alloc_bytes":5776576,"gc_disabled":true,"gc_stable_start":"collected"}`
  - `EXITCODE=0`，`DEFAULT_JSON_PARSE_OK=true`（PowerShell `ConvertFrom-Json`）
- steady：`crystal run tools/bench_frame_time.cr -- --frames=300 --warmup=30 --steady --json`
  - JSON 行：`{"scenario":"steady","frames":300,"warmup":30,"p50_us":14.0,"p95_us":16.0,"p99_us=17.5,"mean_us":14.2,"min_us":12.8,"max_us":26.9,"alloc_bytes":0,"alloc_bytes_steady":0,"alloc_delta_zero":true,"gc_disabled":true,"gc_stable_start":"collected"}`
  - `EXITCODE=0`，`STEADY_JSON_PARSE_OK=true`（PowerShell `ConvertFrom-Json`）

> 注：两场景在 `--json` 模式下均先输出 JSON 行，随后输出可 grep 的 token 行（由实现决定）；JSON 行本身字段完整且可解析，满足“--json 两场景可解析”。

## 5. 复验项 5：判据映射与证据诚实性（`docs/evidence/M0-WP5m-metrics.md`）

- 场景区分与禁用声明：`:14-15,119,240` 明确 default 每帧分配、**“不得用于 M1-WP5「稳态差值=0」判据”**；steady 预分配+索引写入用于零分配稳态观测。
- 协议可复现：`:13,226-236,241` 记录 `warmup → GC.collect (gc_stable_start=collected) → GC.disable → before → N frames → after → GC.enable` 及 `alloc_bytes/alloc_bytes_steady/alloc_delta_zero` 含义；与源码（§1.2）一致。
- 未夸大：`:241,274-275` 表述为“本环境下满足 M1-WP5 协议化的‘稳态 alloc delta == 0’观测（非声称全环境恒成立；若非 0 须如实记录）”及“与真实窗口帧集成待后续嵌入验证（§7/§8）”，**未把 spike 结果写成 M1-WP5 已通过**；`:262-268` 保留 GC 语义/隐式分配/窗口集成/稳定性/json 下游/参数敏感性 `[未验证]`。
- 本次重跑结果（steady alloc_delta_zero true 3/3、default 非 0）与证据主张一致，证据诚实。

## 6. 逐项结论表

| # | 复验项 | 结论 | 依据 |
|---|---|---|---|
| 1 | 代码核：--steady 预分配、循环内无新增容器/字符串分配模式；协议顺序；default 未改坏；ps1 透传 | 通过（附观察项） | `bench_frame_time.cr:103-115,118-129,142-165,183-184,236-242`；default 仍每帧分配 `:130,166`；`bench_frame_time.ps1:11-13,19-20,23,30,56-60`；**观察：`GC.enable` 无 `ensure`（`:184`）** |
| 2 | steady 重跑 3 次 | 通过 | 3 次均 `scenario=steady, alloc_bytes_steady=0, alloc_delta_zero=true, gc_stable_start=collected, EXITCODE=0`（§2） |
| 3 | default 场景 1 次未改坏 | 通过 | `scenario=default, alloc_bytes=5776576, EXITCODE=0`（§3） |
| 4 | --json 两场景可解析 | 通过 | default/steady JSON 行 `ConvertFrom-Json` 成功、EXITCODE=0（§4） |
| 5 | 判据映射与诚实性 | 通过 | `M0-WP5m-metrics.md` 明确 default 不得用于 M1-WP5 零分配判据、协议可复现、未声称 M1-WP5 已通过、保留 `[未验证]`（§5） |
| 6 | 边界 | 通过（按复验范围） | 仅新增本报告；未改被核验文件与 `src/spec/shard.yml/docs/plan*`；工作区含其他预存 W2 untracked 文件未触碰（§0） |

## 7. 缺陷与观察清单

| ID | 严重性 | 位置 | 描述 | 影响/建议 |
|---|---|---|---|---|
| （无新增阻断缺陷） | - | - | task-19 修复经复验有效：steady 3 次 `alloc_delta_zero=true` 且证据如实记录，default 未改坏，判据映射明确。 | - |
| 观察-1（协议健壮性） | 低 | `tools/bench_frame_time.cr:183-184` | `GC.enable` 在采样后直接调用，未置于 `ensure`；异常路径下 GC 可能保持 disabled。 | 短命 CLI 正常路径/重跑无影响；建议后续包裹 `ensure GC.enable` 提升健壮性（非本次裁定阻断）。 |
| 观察-2（已声明/环境性） | 低 | `docs/evidence/M0-WP5m-metrics.md:262-268` | GC 语义、隐式分配、真实窗口集成、跨环境稳定性等仍 `[未验证]`；steady 零分配仅为本环境/本 workload 观测。 | 证据已诚实标注；后续 M1-WP5/窗口集成时需按协议复测。 |

## 8. 最终裁定

**裁定：PASS**

理由：`--steady` 场景实现了预分配与循环内索引写入路径，采样遵循 `warmup → GC.collect (gc_stable_start) → GC.disable → before → 采样 → after → GC.enable` 协议并输出 `scenario=steady/alloc_bytes_steady/alloc_delta_zero`；3 次独立重跑均 `alloc_bytes_steady=0`、`alloc_delta_zero=true`、`EXITCODE=0`；默认场景仍为 `scenario=default` 且 `alloc_bytes` 非 0；`--json` 两场景可解析；证据明确“默认场景不得用于 M1-WP5 零分配判据”、协议可复现且未将 spike 写成 M1-WP5 已通过。verify-W2-ime-metrics.md D1 所指口径/场景缺失问题在 task-19 中已有效修复并经本次复验确认。无新增阻断缺陷（`GC.enable` 无 `ensure` 记为低风险观察）。
