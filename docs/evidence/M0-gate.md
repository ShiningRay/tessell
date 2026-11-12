# M0 门禁终审报告（左都御史 / task-21）

> **裁定：PASS-WITH-CONDITIONS（有条件通过）。**
> **M1-WP1：可开工（GO）**，但不得把本报告读作“M0 已全面关闭”。
> 审计对象：`docs/evidence/M0-summary.md` 及其索引的全部原始证据、4 份 verify 报告、布局预研。
> 仓库：`C:\Users\ShiningRay\projects\ShiningRay\tessell`；审计时 `HEAD=602a52533592a12db6a8b1058768003be604e1ca`，`origin/main` 同值；`git status --porcelain` 仅 `?? docs/evidence/M0-summary.md`。
> 环境：Windows NT 10.0.26300.0 AMD64；Crystal 1.22.1 [23828b0a40] (2026-10-23)，LLVM 23.1.3，`x86_64-w64-windows-gnu`；PATH 前置 `C:\msys64\ucrt64\bin`；GPU 报告为 Intel Iris Xe / GL 4.6.0 Build 32.0.101.7092。
> 写入范围：**仅本文件** `docs/evidence/M0-gate.md`。未修改 `src/spec/examples/tools/docs` 其他文件，未执行 commit/checkout/reset 等改变 git 历史的操作。

---

## 0. 结论摘要

1. **独立重跑：任务书 7 条命令全部 `EXITCODE=0`；另加 8 次补充重跑也全部 `EXITCODE=0`。** 核心 token（spec 6/0/0、`cross_iso=42 mutex_val=4`、`pixel_match=true`、`zh_glyphs=10 render_px=410`、lam-alef 1/1/2/1、IME 4/5、steady `alloc_bytes_steady=0`、FFI 2.15.0/15.1.0）均复现。
2. **无 P1 阻断项。** 但存在 **2 项 P2**：M0-WP2 的验收负例未入证据却写成“已关闭”；度量工具的 `GC.enable` 未置于 ensure（异常路径可能留下 GC 关闭状态）。
3. **M0-WP4-IME 只能判“部分关闭”**：`imm_available=true` 与合成注入 4/5 条消息可复现，但真实 IME 组合（START/COMPOSITION/END）仍为 `[未验证]`，`ime_composition=0`。该缺口已声明，不构成隐瞒，但不能写成 M-1 已关闭。
4. **M0-WP5m 作为“工具链 spike”通过**：steady 协议可执行且 3/3 零分配；但真实窗口 `SwapBuffers` 集成、GC 语义边界仍未验证，属于 M1-WP5 前置条件，不是 M0 阻断。
5. **M1-WP1 可开工**：`docs/plan.md:232` 中 M1-WP1 的唯一依赖是 M0-WP1；M0-WP1 已独立重跑通过（6/0/0）。M1-WP1 不依赖 IME 真机组合，也不依赖窗口度量集成。
6. **M0-summary 总体没有把“建议”写成“门禁已通过”**（`M0-summary.md:3,97,119,294` 多次自我限定）；但局部存在过度声明（WP2“已关闭”）与文档内部不一致（布局文档 205 行 vs 实际 240 行）。

---

## 1. 审计方法与边界

- 只读核对 `docs/evidence/` 全部输入证据、verify 报告与 `docs/research/layout-two-pass.md`；唯一写入本文件。
- 以任务书命令在**当前 HEAD** 独立重跑；记录 `EXITCODE` 与关键 token，不引用旧输出冒充本次结果。
- 对每条结论标注路径+行号；无法实测的项标 `[未验证]`；不删除、不篡改他人证据。
- 预算：≤50 次工具调用；本次实际约 20 次（含读取、重跑、写入）。同一失败未重试超过 2 次。

### 1.1 先确认“证据采集 HEAD”与当前 HEAD 的关系

| 证据 | 记录 HEAD | 锚点 |
|---|---|---|
| M0-WP1 基线 | `981e7a9f0d401170472eb1e52d90b8338dc4d577` | `docs/evidence/M0-WP1-baseline.md:12-17` |
| M0-WP2 Isolated | `981e7a9` | `docs/evidence/M0-WP2-isolated.md:6` |
| M0-WP3 窗口 | `981e7a9` | `docs/evidence/M0-WP3-window.md:6` |
| M0-WP4 deps/text/IME、WP5m | `1b0d832220f3017e9efd6f42d59b5d7fab6b09f3` | `M0-WP4-text-deps.md:4`、`M0-WP4-text.md:4`、`M0-WP4-ime.md:4`、`M0-WP5m-metrics.md:4` |
| verify-W1 | `981e7a9` | `docs/evidence/verify-W1.md:6` |
| verify-W2-* | `1b0d832` | `verify-W2-text.md:12`、`verify-W2-text-fix.md:9`、`verify-W2-ime-metrics.md:7`、`verify-W2-metrics-fix.md:9` |

`git diff --stat 1b0d832..HEAD` 显示 15 个文件、3372 行新增，**全部位于 `docs/evidence/`、`docs/research/`、`examples/`、`tools/`，没有 `src/` 或 `spec/` 变更**。因此：

- 以 `981e7a9`/`1b0d832` 采集的**代码行为**在 `602a525` 上仍适用；本次独立重跑也证实了这一点。
- 但 `M0-summary.md:4,100` 的“以 HEAD=602a525 对应证据”表述不精确：**没有任何一份证据是在 602a525 采集的**；602a525 只是 `564cb17` 之后的文档 hash 回填。此项列为 P3 文档缺陷，不构成阻断。
- `M0-summary.md` 本身在审计时是 untracked（`?? docs/evidence/M0-summary.md`），因此 `HEAD=602a525` 并不包含这份汇总；归档前需提交（见 §5 条件 C4）。

---

## 2. 独立重跑结果

### 2.1 任务书 7 条命令

| # | 命令 | EXITCODE | 关键输出（本次） | 与证据对比 |
|---|---|---|---|---|
| 1 | `crystal spec` | 0 | `6 examples, 0 failures, 0 errors, 0 pending`（Finished in 189 microseconds） | 与 `M0-WP1-baseline.md:37-41` 一致 |
| 2 | `crystal run examples/m0_isolated.cr` | 0 | `same_fiber=true same_tid=true diff_from_main=true cross_iso=42 mutex_val=4`；`iso_tid=1749935930416 main_tid=1749935931040` | 与 `M0-WP2-isolated.md:28` 一致；fiber/线程 id 因进程而异属正常 |
| 3 | `crystal run examples/m0_window_probe.cr -- --frames=60` | 0 | `gl_version=4.6.0_-_Build_32.0.101.7092`、`gl_renderer=Intel(R)_Iris(R)_Xe_Graphics`、`frames=60 swapbuffers=60 pixel_match=true`、`pixel_rgba=204,51,51,255`、`iso_tid=2204601170992 main_tid=2204601171616`、`elapsed_ms=110` | GL/像素/线程隔离与 `M0-WP3-window.md:73-74` 一致；帧数按任务书用 60（证据为 120） |
| 4 | `crystal run examples/m0_text_probe.cr` | 0 | `zh_glyphs=10 zh_advance=1536 render_px=410`；`ft_bitmap_sizeof=40 ft_slot_bitmap_left_at144=true ft_slot_bitmap_top_at148=true ft_layout_assert=pass`；lam-alef tahoma/arial/times `glyph_count=1`、segoeui `glyph_count=2`；`ar_shaping_diff=false`；`shape_us_avg=0.536 render_us_avg=7.346` | 关键 token 与 `M0-WP4-text.md:78-126` 一致；计时较证据 `0.503/7.191` 高约 6.6%/2.2%（环境波动） |
| 5 | `crystal run examples/m0_ime_probe.cr` | 0 | `ime_messages=4`（`ime_setcontext=1 ime_notify=3`）、`imm_available=true imm_open_status=1 imm_error=none`、`ime_composition=0`、`ime_start=0 ime_end=0` | 与 `M0-WP4-ime.md:38-40` 一致；真实组合仍未触发 |
| 6 | `crystal run tools/bench_frame_time.cr -- --frames=120 --warmup=15 --steady` | 0 | 3 次均 `alloc_bytes=0 alloc_bytes_steady=0 alloc_delta_zero=true`；p50 分别为 20.6/20.8/19.3µs；p95 20.7/27.4/19.7µs；p99 31.2/28.7/41.3µs | 零分配 3/3 与 `M0-WP5m-metrics.md:120-180` 一致；分位数本次整体偏高（见 §4 D7） |
| 7 | `crystal run examples/m0_ffi_load.cr` | 0 | `ft_init_ok=true ft_library_version=2.15.0 hb_version_string=15.1.0 hb_version=15.1.0` | 与 `M0-WP4-text-deps.md:184-191` 一致 |

### 2.2 补充重跑

| 命令 | EXITCODE | 关键输出 | 用途 |
|---|---|---|---|
| `crystal run examples/m0_ime_probe.cr -- --frames=60 --ime-test` | 0 | `ime_messages=5`（setcontext=2）、`ime_test_injected=1`、`imm_error=none`、`ime_composition=0` | 复核 IME 5 条计数来自合成注入，不是真实组合 |
| `crystal run tools/bench_frame_time.cr -- --frames=300 --warmup=30` | 0 | `scenario=default`、`alloc_bytes=5776576`、p50 23.0µs | 复核 default 非零分配；当前 HEAD 稳定为 5776576 |
| `crystal run tools/bench_frame_time.cr -- --frames=300 --warmup=30 --json` | 0 | 合法 JSON 行：`"alloc_bytes":5776576`、p50 22.4µs | 复核 JSON 场景数值 |
| `crystal run tools/bench_frame_time.cr -- --frames=300 --warmup=30 --steady` | 0 | `alloc_bytes_steady=0`、`alloc_delta_zero=true`、p50 20.6µs | 300 帧下零分配仍成立 |
| `crystal run tools/bench_frame_time.cr -- --frames=120 --warmup=15`（default） | 0 | `alloc_bytes=2313600`（=19,280×120） | 证明 default 分配随帧数线性增长，非零 |

> 说明：`--json` 的 JSON 行经目检为合法 JSON；对下游解析器的兼容性仍为 `[未验证]`（与 `M0-WP5m-metrics.md:267` 的自我声明一致）。

---

## 3. 逐项对账

### 3.1 M0-WP1 本机基线

- 计划验收：`crystal --version` 可执行并记录；`crystal spec` 通过现有 geometry 用例或记录失败证据（`docs/plan.md:220`）。
- 原始证据：Crystal 1.22.1 / LLVM 23.1.3 / x86_64-w64-windows-gnu；spec `6 examples, 0 failures, 0 errors, 0 pending`、`EXITCODE:0`（`M0-WP1-baseline.md:23-28,37-41,96-103`）。
- 独立重跑：完全一致（§2.1 #1）。
- **判定：通过（关闭）。** 唯一保留是“未来 HEAD/环境变更需重跑”的持续性风险，属正常门禁语义，不是缺陷。

### 3.2 M0-WP2 Isolated UI 执行上下文

- 计划验收：可执行；观测 `Isolated.new(name,&)`、`diff_from_main=true`、`cross_iso=42`、`mutex_val=4`；**记录 `Parallel.new(name,size,&)` 编译期报错；`migrated_any=false` 仅样本**（`docs/plan-execution.md:22`）。
- 原始证据：核心 token 齐全，`EXITCODE 0`（`M0-WP2-isolated.md:28,34`）；但负例与迁移采样明确标 `[未验证]`：`Parallel.new(name,size,&)` 编译期报错“本轮未复测该负例”（`:44`），`migrated_any=false` 仅样本“本轮未做迁移采样”（`:45`），重载穷举也未复测（`:46`）。
- 独立重跑：`cross_iso=42 mutex_val=4 diff_from_main=true same_tid=true`，`EXITCODE 0`（§2.1 #2）。
- **过度声明判定：** `M0-WP2-isolated.md:50` 写“输出含全部要求 token”，就“token”而言成立；但 `M0-summary.md:26` 把 WP2 写成“**已关闭（样本实证）**”，而验收明确要求的编译期负例与迁移样本并未进入本轮证据。按 `plan-execution.md:22` 的验收口径，WP2 应表述为“**核心探针通过、负例/迁移记录待补**”，不能写“已关闭”。列为 **P2-1**。
- **判定：核心通过，验收未完全闭环（条件关闭）。**

### 3.3 M0-WP3 Windows 窗口 + WGL 最小提交

- 计划验收：窗口显示/可关闭/至少 1 帧提交；UI 在 Isolated 线程运行；P-WIN-2 选型与依赖（`docs/plan.md:222`；`docs/plan-execution.md:23-24`；`roadmap.md:50,55`）。
- 原始证据：P-WIN-2 纯 FFI；`frames=120 swapbuffers=120 pixel_match=true`、GL 4.6.0、Isolated 线程与主线程 tid 不同、`elapsed_ms=188`（`M0-WP3-window.md:73-74,79-85,91-93`）。
- 独立重跑：60 帧、`swapbuffers=60`、`pixel_match=true`、GL/线程隔离一致（§2.1 #3）。
- “可关闭”：代码存在 `WM_CLOSE → DestroyWindow → WM_DESTROY → PostQuitMessage` 路径（`examples/m0_window_probe.cr:190-194`），但本次未做人工点击关闭测试，探针是自然退出；交互关闭仍为 `[未验证]`。多 DPI/多显示器/长稳/跨平台也已由证据自我声明未验证（`M0-WP3-window.md:93-94`）。
- **判定：通过（本机会话）；交互关闭与多显示器为保留项。**

### 3.4 M0-WP4 依赖/FFI 加载 + 文本探针

- 计划验收：库可定位或记录阻塞；文本探针可观测度量/字形/位图；ASCII 最小集，CJK 目标（`docs/plan.md:223`；`plan-execution.md:26-27`）。
- 依赖证据：正确包名 `mingw-w64-ucrt-x86_64-*`（任务书原包名 `ucrt64` 不存在，`EXITCODE=1`，`M0-WP4-text-deps.md:28-87`）；freetype 2.15.0-1 / harfbuzz 15.1.0-1（`:111-113`）；FFI 加载 `ft_init_ok=true`、`hb_version=15.1.0`、`EXITCODE 0`（`:184-191`）。
- 文本证据：`zh_glyphs=10 render_px=410`、lam-alef tahoma/arial/times=1、segoeui=2、`ft_bitmap_sizeof=40`、offset 断言 pass、`ar_shaping_diff=false`（`M0-WP4-text.md:78-126`）。D1/D2 经 `verify-W2-text.md:246-257` 发现，`verify-W2-text-fix.md:96-99,157-166,194-211` 关闭。
- 独立重跑：依赖与文本关键 token 全部一致（§2.1 #4、#7）；计时略高但同量级。
- **判定：通过。** GSUB 细粒度、其他复杂脚本、`hb_ft`、干净环境 DLL 分发、字体许可仍为 `[未验证]`，已在 `M0-summary.md:52-66` 声明，属 M2 前置，不是 M0 阻断。

### 3.5 M0-WP4-IME（M-1）

- 计划验收：记录 Windows IME 可否触发、预编辑（composition）可否获取；不可行须写为 M2 No-Go 输入并给出替代/降级（`docs/plan.md:224`；`plan-execution.md:28`）。
- 原始证据：`imm_available=true imm_open_status=1`；基线 `ime_messages=4`（setcontext=1, notify=3）；`--ime-test` 后 `ime_messages=5`、`ime_test_injected=1`；但 `ime_start=0 ime_composition=0 ime_end=0`，真实 IME 组合 `[未验证]`（`M0-WP4-ime.md:38-40,56-58,72,84-89`）。
- 独立重跑：4/5 计数、`imm_available`、`imm_error=none` 均一致；`ime_composition=0` 也一致（§2.1 #5、§2.2）。
- **过度声明判定：** `M0-summary.md:29` 写“**部分关闭（自动化路径）**”，并在 `:108` 明确要求并行补证真实组合，**没有**把 M-1 写成完全关闭；这一点是诚实的。但 M-1 的验收问题是“可否触发/预编辑可否获取”，目前答案是“IMM32 挂接与合成消息可用，真实组合未验证”，因此**仍不能关闭 M-1**。列为 **P2-2**（条件，不是阻断；M1-WP1 不依赖它）。
- **判定：部分关闭。** 在 M2-WP3 之前必须完成真实组合手测，或按 `docs/plan.md:224` 写成 M2 No-Go 输入。

### 3.6 M0-WP5m（M-3）帧时间/分配工具链

- 计划验收：给出可执行采集方式，覆盖帧时间分位数与分配计数；无工具则 M1 门禁不可判定（`docs/plan.md:225`；`plan-execution.md:30`）。
- 原始证据：协议 `warmup → GC.collect(gc_stable_start=collected) → GC.disable → before=bytes_since_gc → N 帧 → after → GC.enable`（`M0-WP5m-metrics.md:226-237`，代码 `tools/bench_frame_time.cr:144-184`）；steady 3/3 `alloc_bytes_steady=0`、`alloc_delta_zero=true`（`:120-180`）；default 非零（`:68-116,184-187`）。
- 独立重跑：steady 3/3 零分配（120 帧）与 300 帧零分配均复现；default 300 帧 `alloc_bytes=5776576`（§2.1 #6、§2.2）。
- **重要限定：** default 场景每帧 `Array(DrawCmd).new` + push（`tools/bench_frame_time.cr:130-138,166-177`），其非零分配**不得**作为 M1-WP5 零分配判据；摘要 `M0-summary.md:18,30,112` 已明确此点，verify D1 也明确（`verify-W2-ime-metrics.md:195-199,221`）。未发现把 default 当零分配判据的过度声明。
- **缺陷：** `GC.enable` 在 `tools/bench_frame_time.cr:184` 直接调用，**未包在 ensure/begin-ensure 中**；若 `GC.disable`（:146）与 `GC.enable`（:184）之间抛异常，GC 可能保持关闭。`W2-iteration-log.md:44-46` 已记录该遗留并建议 M3 改进，但 `M0-summary.md:44-50` 的 §3.2 未列入。列为 **P2-3**（工具健壮性；当前正常路径输出不受影响）。
- **判定：作为“工具链 spike”通过；真实窗口集成与 GC 语义边界为 M1-WP5 前置条件。**

### 3.7 M0-WP5 证据汇总（EX-W1-07）

- 计划验收：各 WP 有通过/失败/阻塞/未验证状态与命令摘要；引用 research 行号；未执行项显式 `[未验证]`（`plan-execution.md:31`）。
- 实际：`M0-summary.md` 结构完整，含证据索引、覆盖矩阵、未验证清单、逐条 Go（条件）、M1 衔接、缺陷链、原文锚点；多处自我限定“建议、非已通过”（`:3,97,119,294`）。
- 但：汇总本身在审计时为 untracked；个别数字/表述不精确（见 §4）。**判定：有条件接受。**

### 3.8 EX-W1-08 布局预研

- 计划验收：设计草案（文本）、接口可单测、与 Constraints/Rect 对齐、零分配口径、**草案不落库代码**（`plan-execution.md:32`）。
- 实际：`docs/research/layout-two-pass.md` 为 **240 行**（`read` 工具显示 total 240；文件字节统计 239 个 LF；末尾 `（文末）` 在第 240 行），含两遍 measure/arrange、Crystal 接口草案、缓存/失效、零分配口径、**9 条单测计划**（`:181-228`）与 6 条风险（`:230-237`）；未落 `src/`。
- **文档缺陷：** `M0-summary.md:19,33,116` 写“205 行”，且 `:19` 引 `layout-two-pass.md:1-205`；实际为 240 行。`M0-summary.md:126,130` 的 `:1-240` 与 `:181-228` 才是正确的。列为 **P3-2**（不影响设计内容，但引用不可审计）。
- **判定：作为预研产出通过；实现与单测落地 `[未验证]`（设计草案）。**

---

## 4. 缺陷清单（按严重度）

> 分级：P1=阻断门禁；P2=必须带条件处理，影响结论可信度；P3=文档/可审计性/低风险。

| ID | 级别 | 缺陷 | 位置/证据 | 修法 |
|---|---|---|---|---|
| D1 | **P2** | WP2 写成“已关闭”，但 `plan-execution.md:22` 要求的 `Parallel.new(name,size,&)` 编译期负例与 `migrated_any=false` 迁移样本未入本轮证据；WP2 文件自身也标 `[未验证]` | `M0-summary.md:26`；`M0-WP2-isolated.md:44-46,50`；`docs/plan-execution.md:22` | 二选一：补编译期报错与迁移采样记录；或把 WP2 改为“核心通过、负例待补”，并在汇总 §2/§5 同步 |
| D2 | **P2** | `GC.enable` 未在 ensure 中；异常路径可能留下 GC 关闭状态；汇总 §3.2 未列该遗留 | `tools/bench_frame_time.cr:146,184`；`W2-iteration-log.md:44-46`；`M0-summary.md:44-50` | 改为 `begin ... ensure GC.enable end`，补一次异常路径自测；在汇总 §3.2/§9 增列 |
| D3 | **P3** | “以 HEAD=602a525 对应证据”不精确：所有证据采集于 `981e7a9`/`1b0d832`；602a525 仅为文档 hash 回填 | `M0-summary.md:4,100`；`verify-W1.md:6`；`M0-WP1-baseline.md:12-17`；`M0-WP4-text.md:4` | 改为“证据采集于 981e7a9/1b0d832；1b0d832..602a525 仅文档/探针新增，无 src/spec 变更；602a525 上独立重跑一致” |
| D4 | **P3** | 布局文档行数写成 205，实际 240；`:1-205` 引用越界 | `M0-summary.md:19,33,116`；`docs/research/layout-two-pass.md`（240 行） | 统一改为“240 行 / `:1-240`”；保留正确的 `:181-228` |
| D5 | **P3** | `M0-WP4-text.md` 尾部保留 task-9 历史重复段（旧 `0.387/5.116` 与旧结论），与当前 task-17 结果同文件并存，易误读 | `M0-WP4-text.md:177,179-314`；`verify-W2-text-fix.md:182` | 删除重复段，或加“历史存档，非当前结论”标题并移到附录 |
| D6 | **P3** | verify 报告 JSON 示例有笔误：`"p99_us=17.5"`（应为 `"p99_us":17.5`） | `verify-W2-metrics-fix.md:149`；合法输出见 `M0-WP5m-metrics.md:189-192` | 修正引文；重跑 `--json` 并贴合法行 |
| D7 | **P3** | 分位数与 default alloc 的“固定值”表述未标注环境/版本：本次 p50 19.3–20.8µs，高于证据 14.3–17.8µs；default 本次稳定 5,776,576，task-12 的 5,779,056 未复现 | `M0-summary.md:18`；`M0-WP5m-metrics.md:68-180,184-187`；本次重跑输出 | 在汇总中注明“分位数环境相关，不作固定阈值；default 字节数随 probe revision 略有差异，判据只用 steady 零分配” |
| D8 | **P3** | `M0-summary.md` 与本次 `M0-gate.md` 均 untracked，`HEAD=602a525` 不包含汇总/终审；归档不可审计 | `git status --porcelain`（`?? docs/evidence/M0-summary.md`；写入后另有 `?? docs/evidence/M0-gate.md`） | 门禁归档时一并提交，commit message 注明 M0 gate evidence |
| D9 | **P3** | WP3 “可关闭”只有代码路径（`WM_CLOSE→DestroyWindow→WM_DESTROY→PostQuitMessage`），未做人工交互关闭测试；证据只证自然退出 | `examples/m0_window_probe.cr:190-194`；`M0-WP3-window.md:81,93` | 补一次人工点击关闭/`WM_CLOSE` 注入测试，或在证据中明确标 `[未验证]` |

**P1：无。** 未发现探针失败、token 造假、把失败写成通过、或删除失败证据的情况。

---

## 5. 过度声明与隐瞒审查（逐项回答任务书第 3 点）

| 审查项 | 结论 | 锚点 |
|---|---|---|
| 是否把“建议”写成“已通过” | **总体没有**。标题、§5 开头、§5.6、文末均写“建议/非已通过”。但 WP2 的“已关闭”属于局部过度声明（D1）。 | `M0-summary.md:3,97,119,294`；`M0-summary.md:26` |
| 是否隐瞒 IME 真实组合未验证 | **没有隐瞒**。§3.1、§5.3、行动 A1 均明确 `[未验证]`；`--ime-test` 只证明合成注入。 | `M0-summary.md:17,29,37-42,107-109,279`；`M0-WP4-ime.md:72,84-89` |
| 是否隐瞒 M-3 窗口集成/GC 语义 | **没有隐瞒**。§3.2 列 6 项未验证；§5.4 明确要求并行补证。 | `M0-summary.md:44-50,111-113`；`M0-WP5m-metrics.md:250-268` |
| 是否隐瞒 GSUB 深度 | **没有隐瞒**。§3.3 明确“更细粒度 GSUB feature 逐项比对未验证”。 | `M0-summary.md:52-55`；`M0-WP4-text.md:161-168` |
| 是否隐瞒字体分发/许可 | **没有隐瞒**。§3.5、§4.3、A6 均标 `[未验证]`，并明确系统字体不可再分发。 | `M0-summary.md:61-63,86-89,284` |
| 是否隐瞒 `GC.enable` ensure 遗留 | **汇总遗漏，但不构成隐瞒**：`W2-iteration-log.md:44-46` 已记录，`verify-W2-metrics-fix.md:33,177` 也提示；但 `M0-summary.md` §3.2/§9 未列。按 D2 处理。 | `W2-iteration-log.md:44-46`；`verify-W2-metrics-fix.md:33,177` |
| 是否把 default 场景 alloc 当零分配判据 | **没有**。摘要与 verify 均明确 default 不得作为 M1-WP5 判据；本次重跑也验证 default 非零。 | `M0-summary.md:18,30,112`；`verify-W2-ime-metrics.md:195-199,221`；`tools/bench_frame_time.cr:4-8` |
| 是否编造数据/删除他人证据 | **未发现**。所有关键数字均能在原始证据或本次命令输出中找到；本次未改动他人文件。 | —— |

---

## 6. 门禁裁定与 M1 入口建议

### 6.1 裁定

**PASS-WITH-CONDITIONS。**

理由：
- 任务书 7 条命令全部 `EXITCODE=0`，核心 token 与证据一致；没有探针失败或伪造。
- M0-WP1/WP3/WP4/WP5m 的验收目标已达到（WP5m 作为工具链 spike；WP4 文本达到 CJK 目标）。
- M0-WP2 核心通过但负例验收未闭环；M0-WP4-IME 仍为部分关闭；这两项都已被证据显式标注，不是隐瞒，但也不能写成完全关闭。
- 因此不能给无条件 PASS；也不构成 FAIL（无关键路径不可行、无替代方案缺失的证据）。

### 6.2 M1-WP1 是否可开工

**可开工（GO）。**

依据：
1. `docs/plan.md:232` 明确 M1-WP1 的依赖只有 **M0-WP1**；M0-WP1 已独立重跑通过（6/0/0）。
2. M1-WP1 是纯布局内核，不依赖 IME 真机组合、不依赖窗口 `SwapBuffers` 度量集成；这两项分别是 M2-WP3 与 M1-WP5 的前置。
3. `docs/research/layout-two-pass.md:181-228` 已给出 9 条可落地单测计划，满足“可先行”的设计输入条件。

但必须同时声明：
- **M1-WP1 GO ≠ M0 全面关闭。** M0 仍带 §6.3 条件；M1-WP5 不得在 M-3 真实窗口集成/GC 语义补证前宣称“零分配已验证”；M2-WP3 不得在 IME 真实组合补证前宣称“IME 已验证”。

### 6.3 条件列表（按关闭时点排序）

| 条件 | 内容 | 关闭时点 | 责任建议 |
|---|---|---|---|
| C1 | 补 WP2 负例：`Parallel.new(name,size,&)` 编译期报错记录 + `migrated_any=false` 迁移采样；或把 WP2 状态改为“核心通过、负例待补”并同步汇总 | M0 最终归档前 | 工部尚书 + 大理寺卿复核 |
| C2 | 真实 IME 组合手测（微软拼音输入“你好”，记录 START/COMPOSITION/END 计数、候选窗位置、IME 版本）；不可行则按 `plan.md:224` 写成 M2 No-Go 输入 | M2-WP3 开工前（可与 M1 并行） | 工部尚书 + 翰林院回填 |
| C3 | 把度量采样嵌入真实窗口 `SwapBuffers` 路径，3 次取中位；明确 `GC.disable/bytes_since_gc` 语义边界；修复 `GC.enable` ensure | M1-WP5 判据固化前 | 工部尚书 + 大理寺卿 |
| C4 | 文档修正：D3 HEAD 表述、D4 布局行数、D5 重复段、D6 JSON 笔误、D7 分位数/default 标注；提交 `M0-summary.md` 与本报告 | M0 归档前 | 翰林院 + 首辅 |
| C5 | 字体分发/许可决策（Noto 等可再分发替代 + 回退链）；GSUB 细粒度与复杂脚本覆盖 | M2-WP2F / M2-WP3 前 | 翰林院 + 首辅 |
| C6 | 明确 M1-WP5 判据只用 steady/等价零分配 workload + 同协议，不得用 default alloc；结论不得外推为“全环境恒成立” | M1-WP5 设计时 | 工部尚书 + 大理寺卿 |

---

## 7. 审计限制与未验证项

以下均为本次**未实测**，不作为已通过结论：

- 真实 IME 组合输入、候选窗位置、TSF 路径、多输入法/多 DPI：`[未验证]`（`M0-WP4-ime.md:72,84-89`）。
- 真实窗口 `SwapBuffers` 集成下的分位数/分配量；`GC.disable` 在全部 Crystal/GC 后端与负载下的语义：`[未验证]`（`M0-WP5m-metrics.md:250-268`）。
- 更细粒度 GSUB feature 逐项比对、Devanagari/Thai/emoji ZWJ 等复杂脚本、`hb_ft`：`[未验证]`（`M0-WP4-text.md:161-168`）。
- 干净环境（无 ucrt64 PATH）DLL 分发、传递闭包、静态链接、字体再分发许可：`[未验证]`（`M0-WP4-text-deps.md:164-165,203-213`；`M0-summary.md:61-66,86-89`）。
- 多 DPI/多显示器、长时间稳定性、macOS/Linux、跨 GPU/驱动：`[未验证]`（`M0-WP3-window.md:93-94`；`M0-summary.md:69`）。
- `--json` 下游解析器兼容性、node_count/场景参数敏感性：`[未验证]`（`M0-WP5m-metrics.md:267-268`）。
- WP3 人工点击关闭：`[未验证]`（仅有代码路径 `examples/m0_window_probe.cr:190-194`）。
- 本次重跑只覆盖当前机器/当前 HEAD；不证明其他环境、其他 Crystal/LLVM 版本或后续提交的等价性。

---

## 8. 附：关键原始输出摘录

```text
# crystal spec
6 examples, 0 failures, 0 errors, 0 pending
EXITCODE=0

# m0_isolated
main_fid=1749935935232 main_tid=1749935931040 iso_fid=1749935934432 iso_tid=1749935930416
same_fiber=true same_tid=true diff_from_main=true cross_iso=42 mutex_val=4
EXITCODE=0

# m0_window_probe --frames=60
hwnd=19335738 pixel_format=5 gl_version=4.6.0_-_Build_32.0.101.7092
gl_renderer=Intel(R)_Iris(R)_Xe_Graphics frames=60 swapbuffers=60 pixel_match=true
iso_tid=2204601170992 main_tid=2204601171616 elapsed_ms=110
pixel_rgba=204,51,51,255 expected_rgb=204,51,51
EXITCODE=0

# m0_text_probe（关键行）
zh_glyphs=10
zh_advance=1536
render_px=410
ft_bitmap_sizeof=40
ft_slot_bitmap_left_at144=true
ft_slot_bitmap_top_at148=true
ft_layout_assert=pass
ar_lam_alef[...tahoma.ttf].glyph_count=1
ar_lam_alef[...arial.ttf].glyph_count=1
ar_lam_alef[...segoeui.ttf].glyph_count=2
ar_lam_alef[...times.ttf].glyph_count=1
ar_shaping_diff=false
shape_us_avg=0.536 render_us_avg=7.346
EXITCODE=0

# m0_ime_probe（基线）
ime_start=0 ime_composition=0 ime_end=0 ime_setcontext=1 ime_notify=3 ime_test_injected=0
imm_available=true imm_open_status=1 ime_messages=4 imm_error=none
EXITCODE=0

# m0_ime_probe --ime-test
ime_start=0 ime_composition=0 ime_end=0 ime_setcontext=2 ime_notify=3 ime_test_injected=1
imm_available=true imm_open_status=1 ime_messages=5 imm_error=none
EXITCODE=0

# bench steady（3 次，节选）
scenario=steady frames=120 warmup=15
p50_us=20.6 p95_us=20.7 p99_us=31.2 mean_us=19.9
alloc_bytes=0 alloc_bytes_steady=0 alloc_delta_zero=true
gc_disabled=true gc_stable_start=collected
EXITCODE=0

# bench default 300 帧（节选）
scenario=default frames=300 warmup=30
p50_us=23.0 p95_us=41.9 p99_us=49.0
alloc_bytes=5776576
gc_disabled=true gc_stable_start=collected
EXITCODE=0

# m0_ffi_load
ft_init_ok=true
ft_library_version=2.15.0
hb_version_string=15.1.0
hb_version=15.1.0
EXITCODE=0
```

---

*本报告为 task-21 左都御史终审产出；仅写入 `docs/evidence/M0-gate.md`。最终 Go/No-Go 与发布动作由首辅/用户裁断。*
