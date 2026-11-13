# M2 阶段汇总（Tessell 文本/IME/虚拟列表/无障碍最小树）

- 仓库：`C:\Users\ShiningRay\projects\ShiningRay\tessell`
- 基线 HEAD：`7cfb44f65bed89e4cc3a92eac0f45542edcd4ab2`（`docs: 回填 M2 迭代 4 提交 hash`，origin/main 同步）
- 本汇总对应范围：迭代 1–4 已提交（HEAD）；迭代 5（WP4/WP5，task-68/70/71/72）代码与证据已在工作区落地并通过本地 spec，**尚未提交**，待 dalisi `verify-M2-iteration5.md` 裁断与首辅放行。
- 平台/工具链：Windows (ucrt64)，Crystal 1.22.1；PATH 需 `C:\msys64\ucrt64\bin`。
- 生成时间：2026-11-13（Asia/Shanghai，提交准备稿）。

## 1. 五个 WP 完成度

| WP | 内容 | 完成度 | 主要交付/证据 |
|---|---|---|---|
| M2-WP1 | 输入/命中/焦点/路由（含 PointerUp 清 pressed） | 已完成并提交 | `src/tessell/input/*`，`spec/input_*_spec.cr`，`docs/research/font-fallback.md`、`glyph-atlas.md`，`docs/evidence/verify-M2-WP1.md`；迭代 1 提交 `17814ca/78ee3af` |
| M2-WP2（2a/2b/2c/2d） | 真实文本测量(FT/HB)、字形图集、光栅化写入、CPU 四边形+GL1.1 上屏与像素回读 | 已完成并提交；存在核验缺陷项/后续项 | `src/tessell/text/{ft_measurer,ffi/*,glyph_atlas,rasterizer}.cr`，`src/tessell/render/{text_renderer,gl/gl_renderer}.cr`，`examples/m2_text_window.cr`，`spec/text_* / glyph_atlas / rasterizer / text_renderer`，`docs/evidence/verify-M2-WP2a/b/c/c-fix/WP2d.md`，`M2-WP2c-zero-alloc-criterion.md`；迭代 2–4 提交 `1025373/76ef5d6`、`77f42d8/fdb797c`、`6520dca/7cfb44f` |
| M2-WP3 | IME 探针与证据（程序化注入/渲染管线关联） | 部分完成（探针+证据落地，真实键盘手测未闭合 C2 开放） | `examples/m2_ime_probe.cr`，`docs/evidence/M2-WP3-ime.md`、`M2-WP3-p3-arabic-msyh.md`；迭代 4 提交 |
| M2-WP4 | 万行虚拟列表（簿记/脏条带/池化/bench） | 实现与簿记指标达标；真实 CPU 帧零分配未达标（残余证据化，task-73 承接） | `src/tessell/widgets/virtual_list.cr`，`spec/virtual_list_spec.cr`，`tools/bench_scroll.cr`，`docs/evidence/M2-WP4-virtual-list.md`；迭代 5 工作区（未提交） |
| M2-WP5 | 无障碍最小树（平台无关镜像 + 虚拟窗口） | M2 最小目标达成（J1–J9）；UIA provider 未做 | `src/tessell/a11y/tree.cr`，`spec/a11y_tree_spec.cr`，`docs/evidence/M2-WP5-a11y-tree.md`；迭代 5 工作区（未提交） |

## 2. 关键数字（实测/提交口径）

- **Spec 规模**：110 (iter1) → 117 (iter2) → 141 (iter3) → 149 (iter4, HEAD) → **171 examples, 0 failures, 0 errors, 0 pending**（iter5 工作区，全量 `crystal spec` EXIT=0）。
- **文本上屏（M2-WP2d, GL1.1 R8→GL_ALPHA, `glPixelStorei(GL_UNPACK_ALIGNMENT,1)`）**：`text_pixels_nonbg=2801 cpu_coverage_sum=2638 ratio=1.0618 pixel_match=true frames=60 swapbuffers=60 p50=1.81 p95=8.16 p99=9.00 quads=14 batches=1`（核验/证据记录，`m2_text_window --frames=60 --verify`）。
- **IME（M2-WP3）**：程序化注入 **不可用/被拒**（非伪造）`ime_injection=blocked ime_injection_reason=imm_set_composition_rejected ime_injection_available=false imm_set_str_ret=0 preedit_roundtrip=false result_roundtrip=false ... IMM_ERR=ImmSetCompositionStringW_rejected_preedit_ret=0_result_ret=0_win32_error=0 IME_PROBE_EXIT=0`；KL `kl_count=2 0x8040804,0x4090409`；候选 `candidate_list_bytes=144 candidate_list_entries=0`；渲染管线 CPU 侧关联 `nihao→5 quads, 你好→2 quads`。
- **万行虚拟列表（10000×20px, viewport 600, 2000 帧 CPU bench）**：`visible_avg=30.95/30.9555 fetched_per_frame_avg≤32 pool_size=32 created=32`；scroll `frame_cpu_p50_us=1269 p95=2031 p99=2688`、jump `p50=1775 p95=3669 p99=4421`（`cmds_avg~61.9 batches_avg=1.0 quads_avg~247.6`）；簿记/emit 硬指标达标，A11y 窗口节点 **≤32**。
- **零分配判据与盲区**：判据 A `delta_work < N` (N=1000)、B `delta_work <= 256`，3 窗 max、`GC.enable` in ensure、失败整套重试 1 次并打印 `retried/attempt`。能证“无 per-call（1B/次×1000 必抓）”，**不能证绝对零分配**（≤256B 稀疏分配可放过；dalisi PASSED_BLIND 1次/1000→`delta_work=32 windows=[32,0,0]`、5次/1000→`160 windows=[160,0,0]`）；1536B 级 GC/簿记尖峰可落窗致 flake，重试缓解但 A 门不放大。VirtualList 簿记路径与 A11y build 探针观测 `delta_work=0 windows=[0,0,0]`。

## 3. 核验结论（摘要）
- WP1：PASS（verify-M2-WP1）。WP2a：PASS-WITH-DEFECTS（verify-M2-WP2a）。WP2b：PASS-WITH-DEFECTS；WP2c 首轮 FAIL → 修复后 PASS（verify-M2-WP2c / fix）。WP2d：PASS-WITH-DEFECTS（verify-M2-WP2d）；迭代 4 证据集 PASS-WITH-DEFECTS（verify-M2-iteration4，未发现伪造）。WP4：PASS-WITH-DEFECTS（verify-M2-WP4）。迭代 5 全覆盖：**待 dalisi `verify-M2-iteration5.md` 裁断**（冻结等待中）。

## 4. 明确未达成项（必须保留，不得表述为已完成）

- **真实 CPU 帧路径零分配未达成**：M2-WP4 bench 真实帧 `alloc_bytes=3920/4000` 为 1000 帧合计（~3.9 B/帧均摊，集中个别窗口 `[3920,0,3712]/[0,4000,0]`），定性为**低频重复分配事件**（约每几百帧一次 ~4KB），非每帧固定分配；A 门未通过（3920>1000）。零分配主张仅覆盖 VirtualList 簿记路径（`delta_work=0`），真实帧路径「未达零分配，残余 ~4KB/1000 帧，根因定位 text 整形/build_text 命中路径」——由 **task-73** 承接。
- **真实键盘 IME 手测未完成（C2 开放）**：程序化 `ImmSetCompositionStringW` 注入本机被拒，`WM_IME_STARTCOMPOSITION→COMPOSITION(GCS_COMPSTR)×n 不丢字→COMPOSITION(GCS_RESULTSTR)→ENDCOMPOSITION`、候选窗真实定位、多 IME 切换均未在真实键盘路径验证闭合。
- **UIA 未实现**：M2 仅平台无关最小无障碍树与判据（J1–J9）；Windows UIA COM provider、屏幕阅读器端到端、COM/线程/导出形状未实测与落地。
- **GL 滚动上屏未做**：`tools/bench_scroll.cr` 的 `--window`/`GL_SCROLL_WINDOW` 未实现（`reason=optional_not_implemented`），真实帧 bench 为 CPU 侧，不含 GPU present。
- 其他未达/未验证：Emoji COLR/CPAL 彩色、GL 着色器路径、`GlRenderer#delete_textures` 生命周期/泄漏深验、`ratio` 非逐像素等价、S-AR-LA 仅 arial 样例、glyph atlas/GPU 上传未纳入 GC 窗口等（详见各迭代未验证清单与证据文档）。

## 5. 备注
- 禁止将“簿记路径零分配”表述为“真实帧已零分配”；禁止将稀疏窗口分配表述为“每帧 4B”。判据 B 存在已证实盲区（≤256B 稀疏放过），引用零分配结论时须同时引用判据能力边界与对抗证据。
- 迭代 5 提交待 verify-M2-iteration5 裁断后按两支提交（feat + hash 回填）落地，提交前不得改源码。
