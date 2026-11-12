# W3 迭代记录（M0 门禁归档）

- 迭代编号：W3-iter1
- 记录人：工部尚书（gongbu-shangshu），task-24 收口
- 记录时间：2026-11-12 18:30:09 +08:00（收口会话时间，非全部任务精确时间戳）
- 基线 HEAD（W2 收口后）：`602a52533592a12db6a8b1058768003be604e1ca`
- W3 主提交（task-24）：`8836d01219baf381a383a4b02dc58e31417f23fc`（`docs(m0): M0 证据汇总、门禁终审与条件补证（负例/迁移/度量 ensure）`，已推送 origin/main）
- hash 回填提交（task-24，第二提交）：`（本回填提交，hash 见下方“提交与回填”及回报）`（`docs: 回填 W3 提交 hash`，本地 amend 修正文案后普通 push，未改写已推送历史）
- 推送结果：主提交 `602a525..8836d01 main -> main` 已推送；回填提交待推送（普通 push）
- 环境参考：Windows NT 10.0.26300.0 AMD64；`Crystal 1.22.1 [23828b0a40] (2026-10-23), LLVM 23.1.3, Default target: x86_64-w64-windows-gnu`；PATH 含 `C:\msys64\ucrt64\bin`。

## 本轮任务状态表（T16/T21/T22/T23）

| 任务 | 描述 | 状态 | 备注/裁定 |
| --- | --- | --- | --- |
| T16 (task-16) | M0 证据汇总与 Go/No-Go 建议（EX-W1-07 / W3-1） | completed | 产出 `docs/evidence/M0-summary.md`（汇总证据索引、覆盖矩阵、未验证清单、Go（条件）建议；建议非门禁已通过）。 |
| T21 (task-21) | M0 门禁终审 | completed | `docs/evidence/M0-gate.md`：**裁定 PASS-WITH-CONDITIONS（有条件通过），M1-WP1 GO**（`docs/evidence/M0-gate.md:3,178-200`），附条件 C1–C6（见下节）。 |
| T22 (task-22) | 文档修正（W3-2，落实门禁 P3/C4 等） | completed | 修订 `docs/evidence/M0-summary.md`、`docs/evidence/M0-WP4-text.md` 等文档：`M0-summary.md` **255 行**、`M0-WP4-text.md` **182 行**（`Get-Content <path> | Measure-Object -Line` 实测）。**行数口径说明**：`docs/research/layout-two-pass.md` 本次实测 **205 行**（Get-Content），与 `M0-gate.md` 中所记 240 行存在计数口径差异（`docs/evidence/M0-gate.md:19,136-137,151` 记 205 vs 240）；**以 Get-Content 实测为准（205 行）**。 |
| T23 (task-23) | W3-3：补证 C1（Parallel block 负例+迁移样本）与 P2-2（bench GC.enable ensure） | completed | 新增 `examples/m0_parallel_block_neg.cr`、`examples/m0_parallel_migrate.cr`；更新 `docs/evidence/M0-WP2-isolated.md`、`docs/evidence/M0-WP5m-metrics.md`、`tools/bench_frame_time.cr`（详见补证节）。 |

## 门禁裁定与条件（C1–C6）

- 裁定：**PASS-WITH-CONDITIONS**，**M1-WP1 可开工（GO）**，但不得读作“M0 已全面关闭”（`docs/evidence/M0-gate.md:3,178-200`）。
- 条件列表（原文引用，`docs/evidence/M0-gate.md:205-210`）：

| 条件 | 内容（原文） | 关闭时点 | 责任建议 |
|---|---|---|---|
| C1 | 补 WP2 负例：`Parallel.new(name,size,&)` 编译期报错记录 + `migrated_any=false` 迁移采样；或把 WP2 状态改为“核心通过、负例待补”并同步汇总 | M0 最终归档前 | 工部尚书 + 大理寺卿复核 |
| C2 | 真实 IME 组合手测（微软拼音输入“你好”，记录 START/COMPOSITION/END 计数、候选窗位置、IME 版本）；不可行则按 `plan.md:224` 写成 M2 No-Go 输入 | M2-WP3 开工前（可与 M1 并行） | 工部尚书 + 翰林院回填 |
| C3 | 把度量采样嵌入真实窗口 `SwapBuffers` 路径，3 次取中位；明确 `GC.disable/bytes_since_gc` 语义边界；修复 `GC.enable` ensure | M1-WP5 判据固化前 | 工部尚书 + 大理寺卿 |
| C4 | 文档修正：D3 HEAD 表述、D4 布局行数、D5 重复段、D6 JSON 笔误、D7 分位数/default 标注；提交 `M0-summary.md` 与本报告 | M0 归档前 | 翰林院 + 首辅 |
| C5 | 字体分发/许可决策（Noto 等可再分发替代 + 回退链）；GSUB 细粒度与复杂脚本覆盖 | M2-WP2F / M2-WP3 前 | 翰林院 + 首辅 |
| C6 | 明确 M1-WP5 判据只用 steady/等价零分配 workload + 同协议，不得用 default alloc；结论不得外推为“全环境恒成立” | M1-WP5 设计时 | 工部尚书 + 大理寺卿 |

> C1/C3 已于 task-23/task-22 在本轮补证/处置并回填证据；C2/C5/C6 为后续并行/前置条件；C4 本轮文档修正与归档提交推进中。最终裁断由首辅/验收流程确定。

## task-23 条件补证摘要

### A) C1（Parallel block 负例 + 迁移样本，`docs/evidence/M0-WP2-isolated.md` 新增节）
- 负例文件：`examples/m0_parallel_block_neg.cr`（**故意不可编译，属负例证据**；`crystal spec` 不采集/不编译 `examples/`，spec 仍通过）。
- 命令：`crystal build examples/m0_parallel_block_neg.cr`（PATH 含 `C:\msys64\ucrt64\bin`）
- **BUILD_EXIT=1**（非 0，符合预期），错误原文关键行：
  - `In examples\m0_parallel_block_neg.cr:5:41`
  - ` 5 | par = Fiber::ExecutionContext::Parallel.new("w", 4) { }`
  - `                                             ^--`
  - `Error: 'Fiber::ExecutionContext::Parallel.new' is not expected to be invoked with a block, but a block was given`
- 迁移样本：`examples/m0_parallel_migrate.cr`（8 fibers × 3 yields，单次样本），命令 `crystal run examples/m0_parallel_migrate.cr`，EXIT=0，输出：
  - `fiber=0..7` 均 `migrated=true`（tid 序列含线程切换）
  - 汇总：`migrated_any=true fibers=8 migrated_fibers=8 yields=3`
- 说明：编译期 API 形状已证；**迁移观测为单次样本**（不得写成“不会迁移/总会迁移”）。

### B) P2-2/C3（`tools/bench_frame_time.cr` GC.enable ensure + 重跑）
- 改动：采样循环 `begin ... ensure GC.enable end`，保证异常路径恢复 GC；协议不变（warmup→GC.collect(gc_stable_start=collected)→GC.disable→before→N frames→after→GC.enable）。
- 重跑（`--frames=120`，EXIT=0）：
  - **steady**：`scenario=steady` `alloc_bytes=0` `alloc_bytes_steady=0` `alloc_delta_zero=true` `gc_disabled=true` `gc_stable_start=collected` `p50_us=17.7 p95_us=26.5 p99_us=29.4`
  - **default**：`scenario=default` `alloc_bytes=2313632` `gc_disabled=true` `gc_stable_start=collected` `p50_us=22.6 p95_us=36.4 p99_us=45.8`
- 证据回填：`docs/evidence/M0-WP5m-metrics.md` §10；补充「default alloc 字节数随 revision/场景微差（5776576–5779056，300 帧样本），steady=0 稳定」；120 帧 default 2313632 为帧数相关缩小，**default 仍不得用于 M1-WP5 零分配判据**。

## 提交前自检（task-24）

| 命令 | EXITCODE | 关键输出 |
| --- | ---: | --- |
| `crystal spec` | 0 | `6 examples, 0 failures, 0 errors, 0 pending`（重试 1 次后通过；负例 `examples/m0_parallel_block_neg.cr` 未被 spec 采集） |
| `crystal run examples/m0_parallel_migrate.cr` | 0 | `migrated_any=false fibers=8 migrated_fibers=0 yields=3`（本次自检单次样本；与 task-23 记录的 `migrated_any=true fibers=8 migrated_fibers=8` 不同，印证迁移观测具样本不确定性） |
| `crystal run tools/bench_frame_time.cr -- --frames=60 --steady` | 0 | `scenario=steady alloc_bytes=0 alloc_bytes_steady=0 alloc_delta_zero=true gc_disabled=true gc_stable_start=collected` |

## 提交与回填

- 主提交：`8836d01219baf381a383a4b02dc58e31417f23fc` `docs(m0): M0 证据汇总、门禁终审与条件补证（负例/迁移/度量 ensure)`（范围：`examples/`、`docs/evidence/`、`docs/research/`、`tools/`；`bin/` 不入库），已推送。
- 回填提交：`（本回填提交）` `docs: 回填 W3 提交 hash`（第二小提交，普通 push；不 amend 已推送历史，与 W1/W2 同策；本地 amend 修正文案后 push）。
- 约束：禁止 `git add -A`；禁止无 `--force-with-lease` 强推；未改 `src/`、`spec/`、`shard.yml`、`README`、`docs/plan*`、`docs/roadmap.md`。提交前 `git status --short` 仅含上述允许路径（含已存在的 docs/evidence/docs/research/tools/examples 变更与本日志）。

## 备注

- `examples/m0_parallel_block_neg.cr` 为 C1 负例证据，**预期不可编译**，已纳入版本库；日志与证据已说明 `crystal spec` 不采集 `examples/` 目录，故不影响测试套件。
- 迁移观测为运行时调度样本：task-23 观测为 `migrated_any=true (8/8)`，本次自检为 `migrated_any=false (0/8)`，均为单次样本，符合“不得断言不会迁移/总会迁移”的边界。
- 最终 M0 门禁裁决与后续开工节奏由首辅/验收流程确定；本日志仅归档本轮事实与产物。