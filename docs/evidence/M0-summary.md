# M0 证据汇总与 Go/No-Go 建议（EX-W1-07 / W3-1，W3-2 修订）

> 状态：**证据汇总与 Go/No-Go 建议（非门禁“已通过”宣告）**。本文仅汇总既有证据与核验结论，供 M0 门禁验收与 W3 收口裁断使用；“Go（条件）”表示在满足所列条件/补证前提下可推进，不等同于无条件通过。[来源: 任务书 task-16/task-22; `docs/evidence/M0-gate.md`]
> 仓库：`C:\Users\ShiningRay\projects\ShiningRay\tessell`（Windows, PowerShell, Crystal 1.22.1, `C:\msys64\ucrt64\bin\crystal.exe`）。
> 证据采集于 1b0d832/602a525（分阶段）：M0-WP1/2/3 基线与探针采集于 `981e7a9`（`docs/evidence/M0-WP1-baseline.md:12-17`，`M0-WP2-isolated.md:6`，`M0-WP3-window.md:6`）；M0-WP4 deps/text/IME、M0-WP5m 等 W1-W2 证据采集/verify 基线为 `1b0d832`（`M0-WP4-text-deps.md:4`，`M0-WP4-text.md:4`，`M0-WP4-ime.md:4`，`M0-WP5m-metrics.md:4`，各 `verify-W2-*.md`）。门禁独立重跑于 `602a52533592a12db6a8b1058768003be604e1ca` 进行，且 `git diff --stat 1b0d832..HEAD` 仅 `docs/evidence/`、`docs/research/`、`examples/`、`tools/` 变更、**无 `src/`、无 `spec/`** → 代码等价，602a525 上独立重跑关键 token 一致（引 `docs/evidence/M0-gate.md:30-45,50-62`）。不得将任一原始证据误表述为“在 602a525 采集”。
> 采集/汇总/修订时间：2026-11-12（Asia/Shanghai）；各 WP 采集时间与 HEAD 以对应证据文件为准。
> 约束：仅本文件与 `docs/evidence/M0-WP4-text.md` 由 task-22 修订；所有断言引证据文件/命令/核验报告/门禁报告；未实测项显式标 `[未验证]`；不得把建议写成已通过。

## 1) 证据索引表

| WP/交付 | 证据文件路径 | 关键命令（摘要） | 关键结果/验收结论（与证据一致） | 核验方裁定（verify/门禁） |
|---|---|---|---|---|
| M0-WP1 本机基线 | `docs/evidence/M0-WP1-baseline.md` | `crystal --version`; `crystal spec`; 环境查询 | Crystal 1.22.1 [23828b0a40] (2026-10-23), LLVM 23.1.3, x86_64-w64-windows-gnu; `crystal spec` **6 examples, 0 failures, 0 errors, 0 pending, EXITCODE 0**（`M0-WP1-baseline.md:37-42,97-102`）；OS Win NT 10.0.26300.0 AMD64。 | `verify-W1.md`：**PASS**（`verify-W1.md:21,28-31`）；`M0-gate.md:53,79-84` 重跑一致。 |
| M0-WP2 Isolated+Channel | `docs/evidence/M0-WP2-isolated.md` + `examples/m0_isolated.cr` + `examples/m0_parallel_block_neg.cr` + `examples/m0_parallel_migrate.cr` | `crystal run examples/m0_isolated.cr`；`crystal build examples/m0_parallel_block_neg.cr`；`crystal run examples/m0_parallel_migrate.cr` | 核心探针：`same_fiber=true same_tid=true diff_from_main=true cross_iso=42 mutex_val=4`，EXITCODE 0（`M0-WP2-isolated.md:27-36,49-51`）。**C1 补证（task-23，`M0-WP2-isolated.md`“负例与迁移观测”节）**：`Parallel.new(name,size,&)` 编译期负例 `crystal build` **EXITCODE=1**，错误原文 `Error: 'Fiber::ExecutionContext::Parallel.new' is not expected to be invoked with a block, but a block was given`（`examples/m0_parallel_block_neg.cr:5:41`）。迁移样本 8 fibers×3 yields：逐 fiber `migrated=true`，汇总 `migrated_any=true fibers=8 migrated_fibers=8 yields=3`，EXIT 0。**迁移行为仅单次样本，不得断言“不会迁移”或“总会迁移”**（与旧 24 样本 `migrated_any=false` 不同，印证不确定性）。 | `verify-W1.md`：**PASS**（核心）；`M0-gate.md:87-92` 指出原负例/迁移未闭环（C1/P2-1）→ task-23 已补证；门禁重跑核心 token 一致（`M0-gate.md:54`）。 |
| M0-WP3 WGL 窗口提交 | `docs/evidence/M0-WP3-window.md` + `examples/m0_window_probe.cr` | `crystal build ...`; `bin/m0_window_probe.exe --frames=120` | P-WIN-2 user32/gdi32/opengl32+WGL；`gl_version=4.6.0_-_Build_32.0.101.7092` `gl_renderer=Intel(R)_Iris(R)_Xe_Graphics` `frames=120` `swapbuffers=120` `pixel_match=true`，EXITCODE 0（`M0-WP3-window.md:48-76,91-94`）。 | `verify-W1.md`：**PASS**；`M0-gate.md:55,95-100` 重跑一致（60 帧变体）。 |
| M0-WP4 依赖/FFI 加载 | `docs/evidence/M0-WP4-text-deps.md` + `examples/m0_ffi_load.cr` | `pacman -S --noconfirm mingw-w64-ucrt-x86_64-freetype mingw-w64-ucrt-x86_64-harfbuzz`；`crystal run examples/m0_ffi_load.cr` | 安装 **freetype 2.15.0-1 / harfbuzz 15.1.0-1**（ucrt64），探针 `ft_init_ok=true ft_library_version=2.15.0 hb_version_string=15.1.0 hb_version=15.1.0 EXITCODE=0`（`M0-WP4-text-deps.md:111-113,185-198,215-219`）。 | `verify-W2-text.md` PASS-WITH-DEFECTS（FFI/deps 复跑一致）；`M0-gate.md:61,102-108` 复跑一致。 |
| M0-WP4 文本 FFI 探针 | `docs/evidence/M0-WP4-text.md` + `examples/m0_text_probe.cr` | `crystal run/build examples/m0_text_probe.cr` | **FT 2.15.0 / HB 15.1.0**；中文 `zh_glyphs=10 zh_advance=1536`，"你" 光栅 `render_px=410`（32x30）；`"سلام"`(segoeui) `ar_glyphs=4 ar_codepoints=4`。task-17 后 D1：`ft_bitmap_sizeof=40 ft_slot_bitmap_left_at144=true ft_slot_bitmap_top_at148=true ft_layout_assert=pass`。D2 lam-alef `"لا"`：tahoma/arial/times **glyph_count=1**，segoeui **glyph_count=2**，4 字体均 `ids_differ_from_isolated=true`。计时样本 `shape_us_avg=0.503 render_us_avg=7.191`（task-17）/ 0.387-5.116（task-9 历史已归档）；量级 **shape≈0.4-0.5µs, render≈5-10µs**（单机样本，环境波动）。 | `verify-W2-text.md` **PASS-WITH-DEFECTS** → D1/D2 修复 → `verify-W2-text-fix.md` **PASS**；`M0-gate.md:56,102-108`。task-22 按 P3/D5 去除 `M0-WP4-text.md` 重复历史段，数据结论不变。 |
| M0-WP4-IME (M-1) | `docs/evidence/M0-WP4-ime.md` + `examples/m0_ime_probe.cr` | `crystal run examples/m0_ime_probe.cr -- --frames=60`；`... --ime-test` | `imm_available=true imm_open_status=1`，基线 `ime_messages=4`（setcontext=1, notify=3），`--ime-test` 合成注入 `ime_messages=5 ime_test_injected=1`，`ime_composition=0`，`imm_error=none`，EXITCODE 0（`M0-WP4-ime.md:38-59,62-67`）。**真实 IME 组合输入 START/COMPOSITION/END [未验证]**（需人工手测，`M0-WP4-ime.md:72,84-95`）。 | `verify-W2-ime-metrics.md`：**PASS**（D2 缺口已声明）；`M0-gate.md:57,110-116` 判定“部分关闭”。 |
| M0-WP5m 度量工具链 (M-3) | `docs/evidence/M0-WP5m-metrics.md` + `tools/bench_frame_time.cr` + `tools/bench_frame_time.ps1` | `crystal run tools/bench_frame_time.cr -- --frames=300 --warmup=30`；`--steady`；`--json` | **default 场景**：分配体量样本 `alloc_bytes=5779056/5776576/2313632`（随 revision/帧数微差，**区间 5776576–5779056** 见 300 帧样本；120 帧重跑 2313632），非 0——**不得用于 M1-WP5 零分配判据**。**steady 场景**（`warmup→GC.collect(gc_stable_start=collected)→GC.disable→采样→GC.enable`，task-23/C3 已将采样包裹 `begin...ensure GC.enable` 并重跑）：稳态 `alloc_bytes_steady=0`，`alloc_delta_zero=true`（多次样本一致）；分位数样本 **p50 14.3–20.8µs**、p95 16-27.4µs、p99 17.5-41.3µs（跨会话/帧数/负载波动，**单机单驱动非泛化**，`M0-WP5m-metrics.md`，`M0-gate.md:58-60,118-126,154`）。 | `verify-W2-ime-metrics.md` **PASS**+D1 → 修复 → `verify-W2-metrics-fix.md` **PASS**；`M0-gate.md:118-126`（C3 ensure 已由 task-23 补证并回填 WP5m）。 |
| EX-W1-08 布局预研 | `docs/research/layout-two-pass.md` | 文档审阅（只读调研产出） | **205 行**（实测 `(Get-Content).Count`，task-22 复核）设计草案（未实现）：两遍 measure/arrange；Crystal 接口草案；缓存键+父链 dirty 失效+arrange 仅 dirty 子树；零分配口径与 3 个易破功点；**9 条**单测计划；6 条风险 `[未验证]/[推断]`（`layout-two-pass.md:1-205`）。 | 设计评审证据；内容含 `docs/plan.md` 行号引用与 `[推断]/[未验证]` 标注。 |
| M0 门禁终审 | `docs/evidence/M0-gate.md` | 门禁独立重跑与审计 | **PASS-WITH-CONDITIONS**，M1-WP1 **GO**（条件见 C1-C6，`M0-gate.md:10-20,177-211`）。 | 左都御史终审（task-21）。 |

## 2) 覆盖矩阵：`docs/plan.md` M0-WP1..WP5 与 `docs/plan-execution.md` D.1

| WP/条目（plan） | 是否关闭 | 证据 | 核验/状态 | 剩余缺口 |
|---|---|---|---|---|
| M0-WP1 本机基线（`docs/plan.md` B.1 M0-WP1） | **已关闭（本机证据）** | `M0-WP1-baseline.md`（spec 6/0/0, EXITCODE 0） | `verify-W1.md` PASS；`M0-gate.md` 重跑一致 | 未来 HEAD/环境变更需重跑 `[未验证: 持续性]` |
| M0-WP2 Isolated UI 可行性（M0-WP2） | **核心通过 + C1 补证完成（负例已证、迁移已观测到 true 样本；不能断言不迁移）** | `M0-WP2-isolated.md`（核心 token +“负例与迁移观测”task-23 节）、`examples/m0_isolated.cr`、`m0_parallel_block_neg.cr`、`m0_parallel_migrate.cr` | `verify-W1.md` PASS（核心）；`M0-gate.md` C1/P2-1 补证已落实（task-23）；门禁核心 token 重跑一致 | **迁移行为仅单次样本**（本样本 `migrated_any=true fibers=8 migrated_fibers=8 yields=3`；与旧样本 `migrated_any=false` 不同），需 M1/M2 更多样本/多负载观测 `[未验证]`；重载穷举未复测 `[未验证]` |
| M0-WP3 窗口+WGL 提交（M0-WP3） | **已关闭（本机会话）** | `M0-WP3-window.md`（GL 4.6.0 Intel Iris Xe, `pixel_match=true`, 120 帧） | `verify-W1.md` PASS；`M0-gate.md` 重跑一致 | 人工点击关闭 `[未验证]`；多 DPI/多显示器/长稳/跨平台 `[未验证]` |
| M0-WP4 文本 FFI 最小可行（M0-WP4） | **已关闭（最小探针实证，附条件）** | `M0-WP4-text-deps.md`, `M0-WP4-text.md`（FT 2.15.0/HB 15.1.0, `zh_glyphs=10 render_px=410`, lam-alef tahoma/arial/times=1、segoeui=2；task-22 去重） | `verify-W2-text.md` PASS-WITH-DEFECTS → D1/D2 修复 → `verify-W2-text-fix.md` PASS | 更细粒度 GSUB/复杂脚本覆盖、hb_ft 集成、干净环境 DLL 分发 `[未验证]`；字体分发许可限制（§3,§4） |
| M0-WP4-IME (M-1) 前置探针（M0-WP4-IME） | **部分关闭（自动化路径；真实组合未验证）** | `M0-WP4-ime.md`（`imm_available=true`, `ime_messages=4/5` 合成注入，`ime_composition=0`） | `verify-W2-ime-metrics.md` PASS（D2 缺口已声明）；`M0-gate.md:110-116` | **真实 IME 组合输入 START/COMPOSITION/END [未验证]**；TSF/候选窗实际效果/多 IME 多 DPI/窗口线程模型差异 `[未验证]`（M2-WP3 前须补测或 No-Go） |
| M0-WP5m (M-3) 度量工具链 spike（M0-WP5m） | **已关闭（spike+协议，C3 ensure 已补证）** | `M0-WP5m-metrics.md`, `tools/bench_frame_time.cr`（steady `alloc_bytes_steady=0`, `alloc_delta_zero=true`；default 非 0 体量区间；task-23 ensure 重跑） | `verify-W2-ime-metrics.md` PASS+D1 → 修复 → `verify-W2-metrics-fix.md` PASS；`M0-gate.md` C3 | **真实窗口 SwapBuffers 集成度量 [未验证]**；GC 语义边界/后端差异 `[未验证]`；分位数与 default alloc **单机单驱动非泛化** |
| M0-WP5 证据与 Go/No-Go 输入（M0-WP5） | **本汇总文档提供建议输入（待门禁裁决）** | 本文件 + WP 证据 + verify 链 + `M0-gate.md` | 门禁 **PASS-WITH-CONDITIONS** | 最终 Go/No-Go 由首辅/验收裁决；本文仅“Go（条件）”建议 |
| EX-W1-07（plan-execution D.1）M0 证据汇总 | **已产出（本文件，task-22 修订）** | `docs/evidence/M0-summary.md` | `M0-gate.md` C4/P2/P3 已落实 | — |
| EX-W1-08（D.1）布局预研 | **已产出** | `docs/research/layout-two-pass.md`（205 行实测，9 条用例） | 任务完成回报 | 实现与单测落地 `[未验证]`（设计草案） |

## 3) 未验证/已知缺口与处置状态（不隐瞒）

### 3.1 IME 真实输入缺口（部分关闭）
- `WM_IME_STARTCOMPOSITION` / `WM_IME_COMPOSITION` / `WM_IME_ENDCOMPOSITION` 在真实中文/日文等 IME 输入下的计数与内容 **[未验证]**（`M0-WP4-ime.md:72,84-85`）。
- `ImmSetCompositionWindow` 对候选窗/组合窗位置的实际生效效果 **[未验证]**（`M0-WP4-ime.md:86`）。
- TSF 路径行为（现代 Windows IME 多走 TSF，IMM32 为兼容层）**[未验证]**（`M0-WP4-ime.md:87`）。
- 不同输入法、不同 DPI/多显示器、非 Isolated/主线程窗口的 IMM32 行为差异 **[未验证]**（`M0-WP4-ime.md:88-89`）。

### 3.2 M-3 真实窗口集成与 GC 语义缺口
- 真实窗口 `SwapBuffers` 集成采样下的分位数与分配量 **[未验证]**（`M0-WP5m-metrics.md:250-260`；`M0-gate.md` C3）。
- `GC.disable` 期间 `GC.stats.bytes_since_gc` 在所有 Crystal/GC 后端与负载下的精确语义与一致性 **[未验证]**（`M0-WP5m-metrics.md:262-263`）。
- steady 场景在不同编译器优化级别、GC 后端版本或更复杂 workload 下是否仍 `alloc_bytes_steady==0` **[未验证]**（`M0-WP5m-metrics.md:264`）。
- 不同硬件/系统负载/长时间运行下的稳定性与分布漂移 **[未验证]**（`M0-WP5m-metrics.md:266`）；当前 p50/default alloc **单机单驱动非泛化**。
- `--json` 下游解析器兼容性、node_count/场景参数敏感性 **[未验证]**（`M0-WP5m-metrics.md:267-268`）。

### 3.3 WP2 迁移行为缺口（C1 已补证，样本有限）
- `Parallel.new(name,size,&)` 编译期负例已证（EXITCODE=1，错误原文如 `M0-WP2-isolated.md` 记录；`M0-gate.md` C1）。
- 迁移样本已证：8 fibers×3 yields → 逐 fiber `migrated=true`，`migrated_any=true fibers=8 migrated_fibers=8 yields=3`，EXIT 0（单次样本，task-23）。
- **迁移行为仅单次样本，需 M1/M2 更多样本/多负载观测；不得断言“不会迁移”或“总会迁移”** `[未验证: 泛化]`。重载穷举未复测 `[未验证]`。

### 3.4 阿拉伯文连字细粒度缺口
- lam-alef：tahoma/arial/times 1 glyph、segoeui 2 glyph，4 字体 `ids_differ_from_isolated=true`；**更细粒度 GSUB feature 逐项比对 [未验证]**（`M0-WP4-text.md:163`；`verify-W2-text-fix.md:176-177`）。
- 其他复杂脚本（Devanagari/Thai/emoji ZWJ 等）未覆盖 **[未验证]**（`M0-WP4-text.md:164`）。
- `hb_ft_font_create` 集成未尝试 **[未验证]**（`M0-WP4-text.md:165`）。

### 3.5 GC.enable ensure 与文档卫生（task-22/task-23 处置状态）
- **GC.enable ensure（C3/P2-3）**：`tools/bench_frame_time.cr` 已改为采样窗 `begin...ensure GC.enable`，并按协议重跑（steady 120 帧 `alloc_bytes_steady=0 alloc_delta_zero=true`，EXIT 0；default 120 帧 `alloc_bytes=2313632`，EXIT 0），证据回填 `docs/evidence/M0-WP5m-metrics.md`“GC.enable ensure 修复与补跑（task-23 / W3-3，C3 补证）”节。**状态：已修复并补证。**
- **文档卫生（P3/D5, C4）**：`docs/evidence/M0-WP4-text.md` 已删除重复历史段（原 :177,179-314 task-9 旧版），保留 task-17 事实段与关键 token，并追加历史版本说明；`docs/evidence/M0-summary.md` 已按 gate C4 修正 HEAD 表述/布局行数实数/IME 部分关闭/缺口与处置状态/区间与非泛化标注。**状态：本轮已修正。**

### 3.6 字体分发许可与依赖/分发完整性缺口
- `C:\Windows\Fonts` 系统字体不可随应用再分发；开源替代（Noto Sans CJK / Noto Color Emoji 等）可用性与许可 **[未验证]**（`M0-WP4-deps.md`）。
- `objdump -p` 仅直接依赖；传递闭包、干净环境（无 ucrt64 PATH）运行/分发最小 DLL 集、静态链接可行性 **[未验证]**（`M0-WP4-text-deps.md:164-165,203-213`）。

### 3.7 可持续性/环境漂移
- 当前证据绑定特定 HEAD/机器/驱动（Intel Iris Xe, GL 4.6.0 build 32.0.101.7092）；跨 GPU/驱动/显示器与后续提交后的回归 **[未验证]**。

## 4) 依赖与分发结论

### 4.1 运行时原生库需求
- 需 `C:\msys64\ucrt64\bin` 在 `PATH` 或与可执行文件同目录提供 `libfreetype-6.dll`、`libharfbuzz-0.dll` 及其直接依赖（`M0-WP4-text-deps.md:115-165,201-205`）。**实测（PATH 方式）**；完整传递闭包/最小集 **[未验证]**。

### 4.2 分发路径选项（推演/未验证）

| 选项 | 说明 | 优点 | 缺点/风险 | 标注 |
|---|---|---|---|---|
| (A) 随包分发 DLL | 复制 ucrt64 DLL 集与应用同目录 | 部署可控、环境门槛低 | 体积与维护成本；传递闭包未完整确认 | `[推断]/[未验证]` |
| (B) 动态链接+安装指引 | 要求用户安装 MSYS2 ucrt64 或提供运行时 | 包小 | 环境门槛高、用户体验差 | `[推断]/[未验证]` |
| (C) 静态链接 | 减少运行时 DLL 依赖 | 部署更简单 | 可行性、许可与构建复杂度需评估 | `[未验证]` |

### 4.3 字体分发
- Windows 系统字体可用于本机探针验证，但不可随应用再分发。M2 需确定可再分发字体（Noto 等）与回退链并确认许可。**[未验证]**。

### 4.4 构建产物
- `bin/` 为 gitignored 构建产物；`crystal build` + 运行需同上 DLL 可解析（`M0-WP3/M0-WP4` 证据）。

## 5) Go/No-Go 建议（逐条“Go（条件）”）

> 以下为**建议**，非“已通过”裁定。任一条件未满足或证据失效时，对应条目应降级为 **No-Go（待补齐）**。

### 5.1 M0-WP1/2/3：Go（条件）
- **WP1**：以 `981e7a9` 采集证据 + `verify-W1.md` PASS + `602a525` 门禁重跑一致（代码等价）为准；后续改动/环境变更需重跑。
- **WP2**：**核心通过 + C1 补证完成**（负例已证、迁移已观测到 true 样本；不能断言不迁移）；**迁移行为仅单次样本**，需 M1/M2 更多样本观测作为持续风险跟踪（`M0-WP2-isolated.md` task-23 节；`M0-gate.md` C1）。
- **WP3**：本机/本会话证据与重跑一致；多环境/交互关闭 `[未验证]`。

### 5.2 M0-WP4（deps + 文本 FFI）：Go（条件）
- 接受 `verify-W2-text-fix.md` PASS（D1/D2 关闭）与 P3/D5 文档去重为当前可信度基础；后续绑定保持 `sizeof/offsetof` 断言门禁；分发与字体许可见 §4。

### 5.3 M0-WP4-IME (M-1)：Go（条件，附并行补证）— **部分关闭**
- 允许 M1-WP1 开工以 **IMM32 挂接与合成消息路径可用**（`imm_available=true, ime_messages=4/5`, `ime_test_injected=1`）为输入；**并行补证**真实 IME 组合输入（按 `M0-WP4-ime.md:76-82` 人工步骤）与候选窗/TSF 行为，回填 `[未验证]` 状态。M2-WP3 前未补证则不得宣称 IME 已验证。

### 5.4 M0-WP5m (M-3)：Go（条件，附并行补证）
- 接受 spike 工具与协议（steady `alloc_bytes_steady=0`, `alloc_delta_zero=true`；C3 ensure 已修复）作为**离线采集能力与方法学**输入；分位数 **p50 14.3–20.8µs**、default alloc 体量 **5776576–5779056**（300 帧样本区间；帧数/场景不同可变）属**单机单驱动非泛化**观测。并行补证真实窗口 `SwapBuffers` 集成与 GC 语义；M1-WP5 判据必须使用 steady/等价零分配 workload + 同协议，**不得**使用 default 场景 alloc。

### 5.5 EX-W1-08 布局预研：Go（条件）
- 作为 M1-WP1 接口/单测设计输入可用（205 行实测，9 条用例、缓存/失效/零分配口径已草拟）；实现阶段以 `crystal spec` 与实测收敛，不得视为已实现。

### 5.6 M0 总体（EX-W1-07 门禁输入）：Go（条件）
- `M0-gate.md` 裁定 **PASS-WITH-CONDITIONS**，M1-WP1 **GO**（`M0-gate.md:10-20,177-211`）。在接受并行补证计划（IME 真实组合、M-3 窗口集成与 GC 语义、WP2 迁移多样本）且不将其误报为已关闭的前提下，可推进 M1-WP1 开工；M1-WP5 依赖 M-3 口径固化与稳态验证。

## 6) 与 M1 的衔接

### 6.1 M1-WP1 两遍布局内核（纯函数）
- 输入来源：`docs/research/layout-two-pass.md`（205 行实测，`layout-two-pass.md:1-205`）。
- 关键输入点：Pass A measure / Pass B arrange；接口草案 `Measureable/Node/layout`、`Constraints/Size/Rect`；9 条单测计划（固定尺寸、文本单行/换行、百分比/弹性、嵌套 Padding、约束冲突 clamp、失效重算与缓存复用、稳态零分配、浮点确定性/epsilon，`layout-two-pass.md:181-228`）。
- 证据/备注：设计草案未实现 `[未验证]`；开工可先行。

### 6.2 M1-WP2 文本测量接口与缓存
- 输入来源：`docs/evidence/M0-WP4-text.md`（task-17 事实段，182 行实测，已去重），`docs/evidence/M0-WP4-text-deps.md`。
- 关键输入点：`TextMeasurer` 抽象与缓存键 `(font_id,size,text_hash,max_width)`；shape/render 量级 **shape≈0.4-0.5µs / render≈5-10µs**（`zh_glyphs=10 render_px=410`，单机样本波动）；需缓存 face/font/buffer 与 script/direction（`M0-WP4-text.md:151-157`）。
- 证据/备注：复杂脚本/cluster/BiDi、`hb_ft` 与干净环境分发 `[未验证]`；字体许可待决策。

### 6.3 M1-WP5 稳态零分配/零重绘验证
- 输入来源：`docs/evidence/M0-WP5m-metrics.md`，`docs/research/layout-two-pass.md`。
- 关键输入点：判据协议 `GC.collect→GC.disable→GC.stats.bytes_since_gc` 前后差值 0（`layout-two-pass.md:155-161,220-223`；`M0-WP5m-metrics.md`）；**必须使用 steady/等价零分配 workload**（default 非 0，体量区间 5776576–5779056 为 300 帧样本，帧数相关，**不得**作零分配判据）。steady spike 多样本 `alloc_bytes_steady=0`，p50 **14.3–20.8µs**（跨会话/帧数波动，单机单驱动非泛化）。
- 证据/备注：真实窗口集成与 GC 语义 `[未验证]`；M1-WP5 验收前须按协议在目标场景复测。

### 6.4 IME 后续（M2 关联）
- 输入来源：`docs/evidence/M0-WP4-ime.md`。IMM32 挂接可用 + 人工补测步骤（`:76-82`）；真实组合与 TSF 行为为 M2 输入风险项（**部分关闭**）。

## 7) 缺陷→修复→关闭/处置链条（摘要，含 P2/P3）

### 7.1 W2-text 缺陷链（D1/D2）
- 原始裁定：`docs/evidence/verify-W2-text.md` **PASS-WITH-DEFECTS**（D1 FT_Bitmap/slot 布局偏差；D2 lam-alef 证据不足）。
- 修复：task-17 修正 `examples/m0_text_probe.cr` 与 `docs/evidence/M0-WP4-text.md`。
- 复验：`docs/evidence/verify-W2-text-fix.md` **PASS**（D1/D2 关闭）。**状态：已关闭**。

### 7.2 W2-metrics 缺陷链（D1 关闭；GC.ensure/C3 补证）
- 原始裁定：`docs/evidence/verify-W2-ime-metrics.md` **PASS**（附 D1：default 非零易误用；D2：IME 真实组合未验证）。
- 修复：task-19 增 `--steady` 与协议 token；task-23 按 C3 将采样加 `begin...ensure GC.enable` 并重跑（`M0-WP5m-metrics.md` §10），`M0-gate.md` P2-3 处置。
- 复验：`docs/evidence/verify-W2-metrics-fix.md` **PASS**（D1 关闭）。**状态：D1 已关闭；C3/ensure 已补证；D2(IME) 未关闭（`[未验证]`）**。

### 7.3 门禁 P2/P3 处置状态（C1/C3/C4，`M0-gate.md`）
- **P2-1/C1（WP2 负例/迁移未闭环）**：task-23 已补证负例 EXITCODE=1（错误原文）与迁移样本 `migrated_any=true fibers=8 migrated_fibers=8 yields=3`（单次）；`M0-summary.md` 已改为“核心通过 + C1 补证完成（负例已证、迁移已观测到 true 样本；不能断言不迁移）”，§3 记“迁移行为仅单次样本、需 M1/M2 更多样本”。**状态：C1 补证完成；迁移泛化待续证。**
- **P2-2/C2（IME 真实组合）**：仍 **[未验证]**，本文与 `M0-gate.md` 标“部分关闭”，M2-WP3 前须补测或 No-Go。**状态：未闭环（条件）。**
- **P2-3/C3（GC.enable ensure）**：task-23 已修复并重跑回填（`M0-WP5m-metrics.md` §10）。**状态：已关闭。**
- **P3/D3,D4,D5,D7/C4（文档）**：HEAD/采集时点与门禁重跑表述已修正；布局草案行数改为实测 **205 行**（task-22 复核，不沿用 205 旧断言而是重验确认）；`M0-WP4-text.md` 重复历史段已删除并加历史说明；p50 改为区间 **14.3–20.8µs**、default alloc 标 **5776576–5779056**（300 帧样本）并注明单机单驱动非泛化；§7 补 P2/P3 处置。**状态：本轮已修正（D6/D8/D9 等未在本文件范围内变更，依 gate 跟踪）。**

## 8) 逐 WP 关键命令/输出原文（可审计锚点）

> 以下锚点摘自对应证据文件；数值区间/波动说明见 §3、§5（p50 14.3–20.8µs，default alloc 5776576–5779056 等为跨会话观测，单机单驱动非泛化）。

### 8.1 M0-WP1（`M0-WP1-baseline.md:23-42`）
```text
Crystal 1.22.1 [23828b0a40] (2026-10-23)

LLVM: 23.1.3
Default target: x86_64-w64-windows-gnu
EXITCODE:0
......

Finished in 222 microseconds
6 examples, 0 failures, 0 errors, 0 pending
EXITCODE:0
```

### 8.2 M0-WP2（`M0-WP2-isolated.md:28` + task-23 补证节）
```text
main_fid=2061926027008 main_tid=2061926022816 iso_fid=2061926026208 iso_tid=2061926022192 same_fiber=true same_tid=true diff_from_main=true cross_iso=42 mutex_val=4
```
```text
Error: 'Fiber::ExecutionContext::Parallel.new' is not expected to be invoked with a block, but a block was given  (examples\m0_parallel_block_neg.cr:5:41)  BUILD_EXIT=1
migrated_any=true fibers=8 migrated_fibers=8 yields=3  EXIT=0  (单次样本)
```

### 8.3 M0-WP3（`M0-WP3-window.md:73-74`）
```text
hwnd=20712404 pixel_format=5 gl_version=4.6.0_-_Build_32.0.101.7092 gl_renderer=Intel(R)_Iris(R)_Xe_Graphics frames=120 swapbuffers=120 pixel_match=true iso_tid=2212314627120 main_tid=2212314627744 elapsed_ms=188 pixel_rgba=204,51,51,255 expected_rgb=204,51,51
EXITCODE=0
```

### 8.4 M0-WP4 deps/FFI（`M0-WP4-text-deps.md:186-190`）
```text
ft_init_ok=true
ft_library_version=2.15.0
hb_version_string=15.1.0
hb_version=15.1.0
EXITCODE=0
```

### 8.5 M0-WP4 text（`M0-WP4-text.md` task-17 事实段）
```text
ft_bitmap_sizeof=40
ft_slot_bitmap_left_at144=true
ft_slot_bitmap_top_at148=true
ft_layout_assert=pass
zh_glyphs=10
zh_advance=1536
render_px=410
ar_lam_alef_min_glyphs=1
ar_lam_alef_ligature_font=C:\Windows\Fonts\times.ttf
shape_us_avg=0.503
render_us_avg=7.191
EXITCODE=0
```

### 8.6 M0-WP4-IME（`M0-WP4-ime.md:38-40,56-58`）
```text
ime_start=0 ime_composition=0 ime_end=0 ime_setcontext=1 ime_notify=3 ime_test_injected=0
imm_available=true imm_open_status=1 ime_messages=4 imm_error=none ...
EXITCODE=0
```
```text
ime_start=0 ime_composition=0 ime_end=0 ime_setcontext=2 ime_notify=3 ime_test_injected=1
imm_available=true imm_open_status=1 ime_messages=5 imm_error=none ...
EXITCODE=0
```

### 8.7 M0-WP5m steady（`M0-WP5m-metrics.md` 示例/补跑）
```text
scenario=steady
alloc_bytes_steady=0
alloc_delta_zero=true
gc_disabled=true
gc_stable_start=collected
EXITCODE=0
```
> p50 跨会话样本 14.3–20.8µs；default alloc 300 帧样本 5776576–5779056（帧数/场景相关）；单机单驱动非泛化。

## 9) 后续行动清单（供 W3/W4 决策，非本文裁决）

| # | 行动 | 责任方 | 前置/依赖 | 完成判据 |
|---|---|---|---|---|
| A1 | IME 真实组合人工手测（记录 START/COMPOSITION/END、候选窗、IME 版本） | 工部尚书 + 翰林院回填 | `M0-WP4-ime.md:76-82` | `[未验证]` 转实测/明确不可行；M2-WP3 前闭环或 No-Go |
| A2 | 度量工具嵌入真实窗口 SwapBuffers 采样（C3 ensure 已完成，仍需窗口集成） | 工部尚书 | M0-WP3 探针 | 3 次中位分位数+alloc 可复现，协议同 steady |
| A3 | M1-WP1 按 `layout-two-pass.md` 9 条用例实现布局内核与 spec | 工部尚书 | EX-W1-08 草案（205 行） | `crystal spec` 布局用例通过 |
| A4 | M1-WP2 `TextMeasurer` 抽象+缓存实现 | 工部尚书 | M1-WP1；M0-WP4 证据 | 缓存命中/失效单测通过 |
| A5 | M1-WP5 稳态零分配判据按协议在目标场景复测（steady workload） | 工部尚书+大理寺卿 | A2/M1-WP1 | `alloc_delta_zero=true` 且证据诚实；不外推泛化 |
| A6 | WP2 迁移行为多样本/多负载观测 | 工部尚书+大理寺卿 | task-23 单次样本 | 多样本证据，结论仍不得绝对化 |
| A7 | 字体分发许可与分发路径决策（DLL/安装/静态） | 翰林院+首辅 | M2 前置 | 许可与决策记录 |

## 10) 本汇总自身边界

- 本文仅汇总既有证据与核验/门禁结论，不新增实测；数值可在对应证据文件/命令输出中复核。
- 本轮写入范围仅 `docs/evidence/M0-summary.md` 与 `docs/evidence/M0-WP4-text.md`（未 commit；未修改 src/spec/examples/tools 其他源码/证据逻辑，未触碰他人未归属改动）。
- 若后续证据更新，本文相关章节需同步回填，避免“建议”与“新证据”漂移。
- **M1-WP1 GO ≠ M0 全面关闭**（`M0-gate.md:198-199`）。

---
*本文件为 EX-W1-07 汇总建议（含 task-22 W3-2 修订）；最终 M0 门禁裁决由首辅/验收流程确定。*
