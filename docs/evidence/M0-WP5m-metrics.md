# M0-WP5m 度量工具链 spike 证据：帧时间分布 + 分配采样（W2-5 / task-12 + task-19 W2-fix，M-3）

- 采集时间（本地）：task-12 2026-11-12 16:58:00 +08:00（default 场景 3 次）；task-19 2026-11-12 17:24:42 +08:00（steady 场景 3 次 + json 验证）；时间来自本次会话记录，探针输出未内嵌时间戳。
- HEAD：`1b0d832220f3017e9efd6f42d59b5d7fab6b09f3`
- OS：`Microsoft Windows NT 10.0.26300.0`，ARCH=`AMD64`
- Crystal：`C:\msys64\ucrt64\bin\crystal.exe`，`Crystal 1.22.1 [23828b0a40] (2026-10-23) LLVM 23.1.3 Default target x86_64-w64-windows-gnu`
- 前置：task-9 完成；本 spike 为纯逻辑压测（layout+draw 记录生成模拟），不依赖未实现框架模块、不触及窗口探针运行路径。
- 任务：`task-12`「帧时间/分配度量工具链 spike」、`task-19`「补零分配稳态场景与 M1-WP5 判据协议（修复 verify-W2-ime-metrics.md D1）」
- 写入范围：`tools/bench_frame_time.cr`、`tools/bench_frame_time.ps1`、`docs/evidence/M0-WP5m-metrics.md`（未改 `src/`、`spec/`、`shard.yml`、`README`、`docs/plan*`、`docs/roadmap.md`、`examples/`）

## 1) 交付物

- `tools/bench_frame_time.cr`：模拟固定场景（200 nodes）每帧 layout 更新 + draw 命令生成；`--frames=N`（默认 300）、`--warmup=W`（默认 30）、`--json`、`--steady`（task-19 新增）。`Time.instant` 采样每帧耗时（µs）并排序输出分位数；协议：`warmup → GC.collect (gc_stable_start=collected) → GC.disable → before=GC.stats.bytes_since_gc → N frames → after → GC.enable`。输出 token `scenario/frames/warmup/p50_us/p95_us/p99_us/mean_us/min_us/max_us/alloc_bytes/gc_disabled/gc_stable_start`；steady 模式额外输出 `alloc_bytes_steady/alloc_delta_zero`。`work_sink` 防优化。输出 token 可 `grep` 解析。
  - **default 场景**（无 `--steady`）：每帧 `Array(DrawCmd).new` + `<<`，故意产生分配以反映分配体量；**不得用于 M1-WP5「稳态差值=0」判据**。
  - **steady 场景**（`--steady`）：预分配节点/命令缓冲与 durations 数组，循环内仅索引写入既有 buffer（`cmds_buf[base]=...`），不新建对象/数组/字符串/闭包。
- `tools/bench_frame_time.ps1`：跑 3 次取中位数；task-19 增加 `-Steady` 参数透传 `--steady`，并在 steady 模式汇总 `alloc_bytes_steady_median`/`alloc_delta_zero_all`。
- 本文档：default 3 次（task-12）+ steady 3 次（task-19）原始输出、中位数表、协议与判据映射、噪声说明、与窗口探针衔接伪代码、[未验证]。

## 2) 命令

### 2.1 单次验证（task-12 修复后，无 deprecation 警告，default）

```powershell
$env:PATH = "C:\msys64\ucrt64\bin;" + $env:PATH
Push-Location "C:\Users\ShiningRay\projects\ShiningRay\tessell"
& "C:\msys64\ucrt64\bin\crystal.exe" run tools/bench_frame_time.cr -- --frames=300 --warmup=30 2>&1
"EXITCODE=$LASTEXITCODE"
Pop-Location
```

> 备注：首次实现使用 `Time.monotonic`，`crystal run` 产生 2 条弃用警告（EXITCODE 仍为 0）；随后改为 `Time.instant`，正式采样无 stderr 警告。

### 2.2 default 场景正式采样（3 次，task-12）

```powershell
$env:PATH = "C:\msys64\ucrt64\bin;" + $env:PATH
Push-Location "C:\Users\ShiningRay\projects\ShiningRay\tessell"
for ($i=1; $i -le 3; $i++) {
  "---RUN$i---"
  & "C:\msys64\ucrt64\bin\crystal.exe" run tools/bench_frame_time.cr -- --frames=300 --warmup=30 2>&1
  "EXITCODE=$LASTEXITCODE"
}
Pop-Location
```

### 2.3 steady 场景正式采样（3 次，task-19）

```powershell
$env:PATH = "C:\msys64\ucrt64\bin;" + $env:PATH
Push-Location "C:\Users\ShiningRay\projects\ShiningRay\tessell"
for ($i=1; $i -le 3; $i++) {
  "---STEADY_RUN$i---"
  & "C:\msys64\ucrt64\bin\crystal.exe" run tools/bench_frame_time.cr -- --frames=300 --warmup=30 --steady 2>&1
  "EXITCODE=$LASTEXITCODE"
}
Pop-Location
```

### 2.4 json 可解析性验证（task-19，default/steady 各 1 次）

```powershell
& "C:\msys64\ucrt64\bin\crystal.exe" run tools/bench_frame_time.cr -- --frames=300 --warmup=30 --json 2>&1
& "C:\msys64\ucrt64\bin\crystal.exe" run tools/bench_frame_time.cr -- --frames=300 --warmup=30 --steady --json 2>&1
```

## 3) 原始输出

### 3.1 default 场景 3 次（task-12，stderr 为空）

#### RUN 1
```
---RUN1---
frames=300
warmup=30
p50_us=17.5
p95_us=30.8
p99_us=39.5
mean_us=19.2
min_us=13.3
max_us=52.2
alloc_bytes=5779056
gc_disabled=true
EXITCODE=0
```

#### RUN 2
```
---RUN2---
frames=300
warmup=30
p50_us=15.5
p95_us=18.3
p99_us=21.2
mean_us=15.6
min_us=11.2
max_us=22.1
alloc_bytes=5779056
gc_disabled=true
EXITCODE=0
```

#### RUN 3
```
---RUN3---
frames=300
warmup=30
p50_us=18.2
p95_us=23.0
p99_us=28.8
mean_us=18.5
min_us=14.9
max_us=33.2
alloc_bytes=5779056
gc_disabled=true
EXITCODE=0
```

> 注：task-12 版本输出未含 `scenario=`/`gc_stable_start=` token；task-19 后 default 单次冒烟输出为 `scenario=default, alloc_bytes=5776576, gc_stable_start=collected`（alloc 数值与 GC/实现细节相关，非 0 属性与判据口径不变：**default 场景不得用于 M1-WP5 零分配判据**）。

### 3.2 steady 场景 3 次（task-19，stderr 为空）

#### STEADY RUN 1
```
---STEADY_RUN1---
scenario=steady
frames=300
warmup=30
p50_us=14.3
p95_us=17.2
p99_us=22.8
mean_us=14.6
min_us=11.6
max_us=34.8
alloc_bytes=0
alloc_bytes_steady=0
alloc_delta_zero=true
gc_disabled=true
gc_stable_start=collected
EXITCODE=0
```

#### STEADY RUN 2
```
---STEADY_RUN2---
scenario=steady
frames=300
warmup=30
p50_us=14.6
p95_us=17.0
p99_us=21.0
mean_us=15.0
min_us=14.0
max_us=29.1
alloc_bytes=0
alloc_bytes_steady=0
alloc_delta_zero=true
gc_disabled=true
gc_stable_start=collected
EXITCODE=0
```

#### STEADY RUN 3
```
---STEADY_RUN3---
scenario=steady
frames=300
warmup=30
p50_us=17.8
p95_us=17.9
p99_us=22.4
mean_us=17.5
min_us=14.1
max_us=29.0
alloc_bytes=0
alloc_bytes_steady=0
alloc_delta_zero=true
gc_disabled=true
gc_stable_start=collected
EXITCODE=0
```

### 3.3 json 输出验证（task-19）

#### default --json（EXITCODE=0）
```json
{"scenario":"default","frames":300,"warmup":30,"p50_us":16.2,"p95_us":19.1,"p99_us":22.9,"mean_us":16.3,"min_us":11.9,"max_us":30.7,"alloc_bytes":5776576,"gc_disabled":true,"gc_stable_start":"collected"}
```

#### steady --json（EXITCODE=0）
```json
{"scenario":"steady","frames":300,"warmup":30,"p50_us":20.2,"p95_us":22.9,"p99_us":26.9,"mean_us":20.4,"min_us":18.4,"max_us":30.6,"alloc_bytes":0,"alloc_bytes_steady":0,"alloc_delta_zero":true,"gc_disabled":true,"gc_stable_start":"collected"}
```

default/steady 均输出独立 JSON 行且可解析（字段完整，steady 包含 `alloc_bytes_steady`/`alloc_delta_zero`）。

## 4) 中位数表（3 次取中位数）

取中位数而非平均：对少量样本更抗单次 OS 调度/定时器抖动/缓存热度等离群噪声，避免均值被偶发尖峰拉偏。

### 4.1 default 场景（task-12）

| 指标 | RUN1 | RUN2 | RUN3 | 中位数 |
|---|---:|---:|---:|---:|
| p50_us | 17.5 | 15.5 | 18.2 | **17.5** |
| p95_us | 30.8 | 18.3 | 23.0 | **23.0** |
| p99_us | 39.5 | 21.2 | 28.8 | **28.8** |
| mean_us | 19.2 | 15.6 | 18.5 | 18.5 (参考) |
| alloc_bytes | 5779056 | 5779056 | 5779056 | **5779056** |

3 次 `EXITCODE=0`，token 可 grep 解析。

### 4.2 steady 场景（task-19）

| 指标 | STEADY_RUN1 | STEADY_RUN2 | STEADY_RUN3 | 中位数 |
|---|---:|---:|---:|---:|
| p50_us | 14.3 | 14.6 | 17.8 | **14.6** |
| p95_us | 17.2 | 17.0 | 17.9 | **17.2** |
| p99_us | 22.8 | 21.0 | 22.4 | **22.4** |
| mean_us | 14.6 | 15.0 | 17.5 | 15.0 (参考) |
| alloc_bytes | 0 | 0 | 0 | **0** |
| alloc_bytes_steady | 0 | 0 | 0 | **0** |
| alloc_delta_zero | true | true | true | **true（3/3）** |

3 次 `EXITCODE=0`，`scenario=steady`，`gc_stable_start=collected`，token 可 grep 解析；300 帧总耗时远 < 30s。

## 5) 采样协议与 alloc 口径（M1-WP5 判据映射，task-19）

**协议（两场景统一实现并打印）：**
1. warmup（W 帧）完成后
2. `GC.collect`（输出 `gc_stable_start=collected`）
3. `GC.disable`
4. `before = GC.stats.bytes_since_gc`
5. 跑 N 帧采样
6. `after = GC.stats.bytes_since_gc`
7. `GC.enable`

`alloc_bytes = after - before`（after>=before）；steady 场景额外输出 `alloc_bytes_steady`（同值）与 `alloc_delta_zero=(alloc_bytes==0)`。

**场景语义与判据映射：**
- **default（scenario=default）**：每帧分配（`Array(DrawCmd).new` + push），用于观察“有分配路径”的体量基线。task-12 实测 alloc_bytes=5779056（非 0），task-19 冒烟 5776576（非 0）。**明确：default 场景不得用于 M1-WP5「稳态差值=0」判据**（verify-W2-ime-metrics.md D1 指出误用风险，已按此修正）。
- **steady（scenario=steady）**：预分配全部缓冲，循环内仅索引写入，演示零分配稳态。3 次实测 `alloc_bytes_steady=0`、`alloc_delta_zero=true`（3/3），`gc_stable_start=collected`。本环境下 M1-WP5 “稳态 alloc delta == 0” 判据在 steady 场景可满足；若后续环境/编译器/运行时出现隐式分配导致非 0，必须如实记录来源，不得伪造 0。
- `GC.disable` 期间 `bytes_since_gc` 计数器随分配增长，可用于窗口内差值观测；本次 default/steady 观测均符合预期（default 非 0、steady 为 0）。[未验证：所有 GC 后端/版本下语义一致性]

## 6) 噪声说明

- 纯逻辑、无窗口/渲染/IO，主要噪声来自 OS 调度、CPU 频率波动/热状态、缓存命中与计时器分辨率；RUN1 尾部分位（p95/p99/max）明显高于 RUN2/RUN3，符合偶发抖动特征。
- 采用固定 `--frames=300 --warmup=30`、同机同环境连续 3 次并取中位数降低单次波动影响；后续作为门禁基线时需在受控环境多次采样并记录硬件/负载。

## 7) 与真实窗口探针衔接说明（不实现，仅伪代码）

在 `examples/m0_window_probe.cr` 的 `SwapBuffers` 前后嵌入采样点（3 行伪代码示意）：

```crystal
t0 = Time.instant
LibGdi32.SwapBuffers(hdc)
frame_us = (Time.instant - t0).total_microseconds; durations << frame_us
```

> 说明：将 `t0/durations` 置于帧循环外初始化（含 warmup/alloc 采样窗口的 `GC.collect/GC.disable` 配对），循环结束后按本工具同样逻辑计算 P50/P95/P99 与 `alloc_bytes` 并输出 token。实际嵌入点可按需扩展到“渲染提交+交换”整帧区间（`glFlush/glFinish` 前后至 `SwapBuffers` 后）。

## 8) [未验证] 清单

- `GC.disable` 期间 `GC.stats.bytes_since_gc` 在所有 Crystal/GC 后端与负载下的精确语义与一致性（本次仅在当前 ucrt64 Crystal 1.22.1/Windows 环境、固定 workload 下实测；default/steady 均符合预期）。**[未验证]**
- steady 场景在不同编译器优化级别、Crystal/GC 后端版本、或更复杂 workload 下是否仍 `alloc_bytes_steady==0`（本次 3/3 为 0；若出现隐式分配需溯源）。**[未验证]**
- 将采样点嵌入 `examples/m0_window_probe.cr`（含真实 SwapBuffers/GL 路径）后的分位数与分配量表现。**[未验证]**
- 不同硬件、不同系统负载、长时间运行下的稳定性与分布漂移。**[未验证]**
- `--json` 输出在下游自动化解析器中的兼容性（本次已人工/格式验证 default 与 steady 各 1 次可解析；未接入外部 CI 解析器）。**[未验证]**
- node_count/场景参数对分位数与 alloc_bytes 的敏感性（本次固定 200 nodes）。**[未验证]**

## 9) 结论

- 度量工具链 spike 可用：default 与 steady 场景均 `EXITCODE=0`，token 可 grep 解析，`--json` 两场景可解析。
- default 场景（task-12，3 次中位数）：`scenario=default`，`p50_us=17.5`，`p95_us=23.0`，`p99_us=28.8`，`alloc_bytes=5779056`，`gc_disabled=true`。**该场景含每帧分配，不得用于 M1-WP5 零分配判据。**
- steady 场景（task-19，3 次）：`scenario=steady`，`gc_stable_start=collected`，`alloc_bytes_steady=0`，`alloc_delta_zero=true`（3/3），`gc_disabled=true`；中位数 `p50_us=14.6`，`p95_us=17.2`，`p99_us=22.4`。在本环境下满足 M1-WP5 协议化的“稳态 alloc delta == 0”观测（非声称全环境恒成立；若非 0 须如实记录）。
- M-3 目标“建立可复用采集工具链 spike + M1-WP5 判据协议”已达成（纯逻辑）；与真实窗口帧集成待后续嵌入验证（见 §7/§8）。

## 10) task-23（W3-3）P2-2 补证：`GC.enable` ensure + 重跑（2026-11-12 18:11:27 +08:00）

- 目标：保证采样窗口内异常路径也能恢复 GC（`GC.disable` 后必定 `GC.enable`）。
- 代码改动：`tools/bench_frame_time.cr` 将采样循环包裹 `begin ... ensure GC.enable end`，`after_bytes` 初始化为 `before_bytes`，在循环成功后更新；`GC.collect/GC.disable/before` 仍在 `begin` 前按协议执行（warmup→collect→disable→before→N frames→after→enable）。

命令（PATH 含 `C:\msys64\ucrt64\bin`，CWD tessell）：

```powershell
& "C:\msys64\ucrt64\bin\crystal.exe" run tools/bench_frame_time.cr -- --frames=120 --steady 2>&1; "EXIT=$LASTEXITCODE"
& "C:\msys64\ucrt64\bin\crystal.exe" run tools/bench_frame_time.cr -- --frames=120 2>&1; "EXIT=$LASTEXITCODE"
```

### 重跑输出（steady, --frames=120）

```text
scenario=steady
frames=120
warmup=30
p50_us=17.7
p95_us=26.5
p99_us=29.4
mean_us=20.0
min_us=14.3
max_us=34.7
alloc_bytes=0
alloc_bytes_steady=0
alloc_delta_zero=true
gc_disabled=true
gc_stable_start=collected
EXIT=0
```

### 重跑输出（default, --frames=120）

```text
scenario=default
frames=120
warmup=30
p50_us=22.6
p95_us=36.4
p99_us=45.8
mean_us=24.1
min_us=17.2
max_us=48.4
alloc_bytes=2313632
gc_disabled=true
gc_stable_start=collected
EXIT=0
```

- 结论：改后 steady/default 各 1 次均 EXITCODE=0；steady 仍 `alloc_bytes_steady=0`、`alloc_delta_zero=true`、`gc_stable_start=collected`（与改前判据 token 一致）；default 仍为分配场景（本次 120 帧实测 `alloc_bytes=2313632`，非 0）。
- 补充说明：default alloc 字节数随 revision/场景微差（5776576–5779056），steady=0 稳定。前述区间对应 task-12/task-19 300 帧观测（5779056/5776576）；本次 `--frames=120` 因帧数减半，alloc 体量按比例缩小（2313632），属预期的场景/帧数相关差异，**default 场景仍不得用于 M1-WP5「稳态差值=0」判据**。
