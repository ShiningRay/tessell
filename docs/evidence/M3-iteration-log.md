# M3 迭代 1 收口日志（M3-iter1）

## 迭代概览
- 迭代：M3-iter1（M3-WP1 后端抽象与脏矩形提交巩固）
- 日期：2026-11-13
- 仓库：C:\Users\ShiningRay\projects\ShiningRay\tessell（HEAD=ef8903a）
- 执行：gongbu-shangshu-3（工部尚书副手）
- 核验：dalisi-qing-2（大理寺卿）
- 收口任务：task-97「编写 M3 迭代 1 迭代记录」
- 提交位置：ef8903a（M3-iter1）；M3-WP4 feat `98360f2` / docs `26dddf5`

## 本机环境
- Crystal：1.22.1 [23828b0a40]
- LLVM：23.1.3
- 平台：Windows 11（ucrt64）
- PATH：需 C:\msys64\ucrt64\bin（执行前设置 $env:PATH）

## 任务与裁定
| 任务 | 状态 | 说明/产出 |
|---|---|---|
| T92（M3-WP1 实现） | 完成 | 后端抽象 + GL 后端 + TextRenderer 重构 + 脏区示例 |
| T94（独立核验） | 完成（核验） | verify-M3-WP1.md（37 行），PASS-WITH-DEFECTS |
| T95（缺陷补齐） | 完成 | P2 关闭；P3 残余如实记录 |

## 交付物（行数实跑口径）
| 路径 | 行数 |
|---|---|
| src/tessell/render/backend.cr | 33 |
| src/tessell/render/gl/gl_backend.cr | 430 |
| src/tessell/render/gl/gl_renderer.cr | 58 |
| src/tessell/render/text_renderer.cr | 243 |
| src/tessell.cr | 33 |
| spec/backend_protocol_spec.cr | 396 |
| spec/text_renderer_spec.cr | 239 |
| examples/m3_dirty_window.cr | 499 |
| docs/evidence/M3-WP1-backend-dirty.md | 126 |
| docs/evidence/verify-M3-WP1.md | 37 |

- 注：gongbu 自报 M3-WP1-backend-dirty.md 62 行，
  实跑 126 行（.NET ReadAllLines 口径），以实跑为准。

## 实测证据
- crystal spec（全量，T95 后）：194 examples, 0 failures,
  0 errors, 0 pending（EXIT=0，429.4 ms）
- m3_dirty_window --frames=20 --verify（EXIT=0）：
  - diff_pixels=0 diff_A_vs_C=889 dirty_area_ratio=0.012568
  - submitted_quads_dirty=4 submitted_quads_full=57
  - culled_quads=53 no_move=false verify=pass
- --no-move 反例：diff_A_vs_C=0 verify=fail（EXIT=1；
  不动画时脏区提交不产生像素差异，反例成立）
- 探针 backend_protocol_spec.cr 单文件：12/12 全绿
- warmup 后无 4464B 首窗；偶发 16B 噪声窗
  - RUN1 [0,0,16]、RUN3 [0,16,0]、RUN6 [16,0,0] 等
- 三方帧时间对照（dirty/full，µs，p50/p95/p99）：
  - 工部：288/943/1217 vs 273/1633/4162
  - 首辅：392/1124/1851 vs 286/881/1610
  - 核验：239/744/1289 vs 228/672/1334
- 结论：四边形提交数下降可证（4 vs 57，culled 53）
- 帧时间在本机噪声内无结论

## 缺陷与关闭
| 缺陷 | 状态 | 说明 |
|---|---|---|
| P2（example 缺 diff_A_vs_C） | 已关闭 | T95 补上 |
| P3-1（探针首窗 4464B 来源未定位） | 未关闭/降级为残余风险 | warmup 前置吸收，来源未定位，不算关闭 |
| P3-2（3 窗 max + ≤1 次重试） | 未关闭 | 非绝对零分配证明，判据强度限制 |

## 未验证清单
- 脏矩形在多批次/多脏区下的像素等价
  验证所需：多脏区场景构造 + readback 逐像素 diff
- scissor 面积占比阈值
  验证所需：多场景 dirty_area_ratio 分布统计
- 真实 GPU 帧时间（当前 CPU 侧 + swap 计时）
  验证所需：GPU timestamp query 或 Present 计数
- macOS/Linux 后端（引 docs/research/m3-platform-matrix.md）
  验证所需：mac 主机或 macOS CI + Linux WSLg/真机

## 门禁关联
- M2 残余条件：C5（性能区间）、C7（真实键盘 IME 手测）、
  C8（UIA + GL 滚动）、C9（OFL 许可）
- C6 waiver 见 docs/evidence/M2-summary.md §3.1

## 提交信息（M3-iter1）
- 提交 1（feat）hash：e4ed14b354ba15b832a755568fc36c968856d91e
- 提交 1（feat）短 hash：e4ed14b
- 提交 2（docs）hash：7ea94594d04fd06258372f2408aebcfa68ce76d3
- 提交 2（docs）短 hash：7ea9459
- 提交 3（docs）hash：本提交

# M3 迭代 2 收口日志（M3-iter2）

## 迭代概览
- 迭代：M3-iter2（M3-WP5 DPI 缩放与主题 token、C5 性能区间）
- 日期：2026-11-13
- 仓库：C:\Users\ShiningRay\projects\ShiningRay\tessell
- 执行：gongbu-shangshu-3（工部尚书副手）
- 核验：dalisi-qing-2（大理寺卿）
- 收口任务：task-106
- 提交 1（feat）hash：a57a2f4d5658f6ffcd232c12385009d1c8e3112f
- 提交 1（feat）短 hash：a57a2f4
- 提交 2（docs）hash：d5eadd48a30ac7989dbbeafe42a851ccb769f74f
- 提交 2（docs）短 hash：d5eadd4
- 提交 3（docs）hash：本提交

## 任务与裁定
| 任务 | 状态 | 说明/产出 |
|---|---|---|
| T99 | completed | dpi-theme 设计草案（hanlin） |
| T100 | completed | C5 性能区间（gongbu） |
| T101 | completed | M3-WP5 实现（gongbu） |
| T103 | completed | 混合缺陷修复（gongbu） |
| T104 | PASS-WITH-DEFECTS | 独立核验（dalisi），P1/P2 无、P3×3 |
| T105 | A-recheck=PASS | 合成覆盖度梯度补充验证（dalisi） |

## 交付物（行数实跑口径）
| 路径 | 行数 |
|---|---|
| src/tessell/render/theme.cr | 42 |
| src/tessell/render/dpi.cr | 25 |
| src/tessell/render/backend.cr | 34 |
| src/tessell/render/gl/gl_backend.cr | 453 |
| src/tessell/render/gl/gl_renderer.cr | 73 |
| src/tessell/render/text_renderer.cr | 243 |
| src/tessell.cr | 35 |
| spec/theme_spec.cr | 87 |
| spec/dpi_spec.cr | 41 |
| spec/backend_protocol_spec.cr | 396 |
| examples/m3_dpi_theme.cr | 724 |
| examples/m2_text_window.cr | 505 |
| docs/research/dpi-theme.md | 150 |
| docs/evidence/M3-WP5-dpi-theme.md | 186 |
| docs/evidence/M3-perf-band.md | 202 |
| docs/evidence/verify-M3-WP5.md | 89 |

## 实测证据
- crystal spec（全量，T95 后）：207 examples, 0 failures, 0 errors, 0 pending
  （EXIT=0，455.18 ms）
- m3_dpi_theme --verify：px10=1605 px15=3079 px20=5094
  r15=1.918380 r20=3.173832 j1_pass=true
  corner_pixel_rgba=0xffffffff expected_bg=0xffffffff；alloc_windows 最大 112
- --dpi=1.5 --theme=dark --verify：J5 diff_pixels=0 diff_A_vs_C=1180
  submitted_quads_dirty=4 < submitted_quads_full=31 culled_quads=27
  corner_pixel_rgba=0x1e1e1eff expected_bg=0x1e1e1eff j5_j3_pass=true
- C5：bench_scroll alloc ∈[128,176]（5 次）；m3_dirty_window 5 次全
  diff_pixels=0 diff_A_vs_C=889 verify=pass；zero_alloc_frame alloc∈{0,16}
  criterion_ok=true → C5 关闭
- 回归：m2_text_window text_pixels_nonbg=2801 ratio=1.061789；
  emoji 1171 match=true，与基线一致

## 缺陷与关闭
| 缺陷 | 状态 | 说明 |
|---|---|---|
| D1 I² 双重乘 coverage | 已关闭 | P1；改 GL_ONE,GL_ONE_MINUS_SRC_ALPHA |
| D1 补充（复现） | 已关闭 | §3A 合成梯度 Δ_linear≤1, Δ_i²=48/64 |
| P3-2 默认 rgba 0xffffffff→0x000000ff | 记录不关闭 | 无仓内破坏、外部期望风险 |
| P3-3 close 未显式 disable BLEND | 记录不关闭 | end_frame 已 disable |

## 未验证清单
- 每显示器 DPI 无法单屏真测
  验证所需：WM_DPICHANGED 不可编程触发
- 真实 GPU 帧时间
  验证所需：GPU timestamp query 或 Present 计数
- macOS/Linux 后端
  验证所需：mac 主机或 macOS CI + Linux WSLg/真机
- UIA 未实现
  验证所需：UIA COM 输出/读屏器验证

## 门禁关联
- C5 关闭
- C6 waiver 仍适用（M3-WP5 验收侧：字面 [0,0,0] 未达，A/B 通过）
- C7/C8/C9 未动

# M3 迭代 3 收口日志（M3-iter3）

## 迭代概览
- 迭代：M3-iter3（C8 真实 GL 万行滚动 + M4-WP1 S1 声明层）
- 日期：2026-11-13（Asia/Shanghai）
- 仓库：C:\Users\ShiningRay\projects\ShiningRay\tessell
- HEAD 基线：1f238b273990300382e946ef43e4a28715850769
- 提交：2397dc3（C8/M4-WP1 S1）、4a3e9d7（M4-WP2）、f498099（docs/证据）
- 执行/收口：gongbu-shangshu-4；task-117（仅改本文件，禁 commit）

## A. C8 真实 GL 万行滚动
- 产物：`examples/m3_scroll_window.cr`、`docs/evidence/M3-C8-gl-scroll.md`、
  `src/tessell/render/gl/gl_backend.cr`。场景 10000 行 × 行高 20 × 800×600。
- 修复后 verify：`diff_pixels=0 diff_A_vs_C=3101 quads_dirty=5 quads_full=141`
  `culled=136 visible_avg=30`，`alloc_windows=[0,0,0] retried=false attempt=1`
  （frames=20/120，verify=pass，EXIT 0）。
- `--steady` 连续滚动：`STEADY mode=steady_continuous windows=[0,0,0] max=0`
  `retried=false attempt=1 scroll_y=36000`；5 连跑 5/5 pass；
  `label_bytes_total=78890`（init 一次性）。
- 根因链：①脏区仅重绘 exposed strips、无 interior 像素平移 →
  `diff_pixels=2798`（`DIAG_DIFF_BC bbox=(45,25)-(64,576)` 覆盖全高）；
  ②`gl_backend` 逐 rect clear→draw 顺序问题 → 两阶段（先全 clear，再逐
  rect scissor 画相交 quad）；③run cache 默认 256 条不足 10000 行 → 每帧
  miss 分配 → 原位归因 `rdirty=92576/200帧`；④首窗 3984B 一次性分配
  （`ALLOC_ATTEMPT1 alloc_windows=[3984,0,0] fail_reason=delta>=1000`）靠
  prime measured-probe pass 吸收 → 修复后到 0。

## B. M4-WP1 S1 声明层
- 产物：`docs/research/dsl-state-api.md`（145 行）、
  `src/tessell/ui/{key,builder,apply}.cr`、`spec/ui_builder_spec.cr`。
- 实证：`UiKey{parent,local}` 非字符串 key；复用为对象身份
  （`same_object=true id_stable=true`）；脏集最小
  （`LAYOUT_LEAF_CHANGE count=3` 链上三节点、`PAINT_ONLY_CHANGE count=1`）；
  幂等按完整帧：`apply → collect_dirty → consume → 同输入 apply → 空`。

## C. 缺陷台账（本轮 P1×2）
| 缺陷 | 裁断与修复 | 结果 |
|---|---|---|
| P1-apply 吞外部脏 | apply 只标脏、清脏归调用方；新增 `UI.consume` | 复核通过 |
| P1-C8 像素不等价 | blit interior + 仅 exposed strip 重绘 | 像素等价 |
- P1-apply：`apply.cr:102-111` 帧起始无条件 clean；
  `P1_EXTERNAL ... swallowed=true`。新增 `UI.consume`（`apply.cr:199-206`），
  全文唯一 `clean!` 在 `:203`。复核 `swallowed=false`、
  `CONSUME_PARTIAL n1_cleared=true n2_kept=true`、
  `IDEMPOTENT empty=true`；加回 clean 反证 `REGRESS_PROBE_EXIT=1`。
- P1-C8：`diff_pixels=2798`（`DIAG_DIFF_BC bbox=(45,25)-(64,576)` 覆盖全高）；
  修复后 `diff_pixels=0 diff_A_vs_C=3101`。

## D. 零分配判据现状
- 判据：A `delta < 1000`、B `delta <= 256`、三窗取 max、`GC.enable` 在 `ensure`、
  ≤1 次重试且必须打印 `attempt=1`。
- 本轮 ui_apply/ui_consume/ui_builder 三探针全 `[0,0,0]`（偶发 `[0,0,16]` 仍在
  判据内）；负例对抗 `NEG_RESULT=CAUGHT`（两轮）。
- 口径声明（task-125 增补）：「零分配」在本仓库的唯一合法口径是判据 A `delta_work < N(=1000)` 与 B `delta_work <= 256`（定义见 `docs/evidence/M2-WP2c-zero-alloc-criterion.md`），**不是** `delta == 0`。
- 本机实测存在 16B（偶发 64–96B）级 GC/allocator 簿记噪声，可落入任意测量窗；任何文档不得把单次 `[0,0,0]` 写成普适保证。
- C6 waiver 只覆盖 M3-WP5 自身主张，不覆盖 M3 全域（引 `docs/evidence/M2-summary.md:52`）。

## E. 门禁条件台账（逐条）
| 条件 | 状态 | 说明 |
|---|---|---|
| C5 | 已关闭 | 性能区间三档已给出（M3-iter2） |
| C6 | 书面 waiver | `[0,0,0]`未达、A/B通过；阻断 M3-WP5 不阻断其余 |
| C7 | 未关闭 | 真实键盘 IME 手测需人工（`ime_injection=blocked`） |
| C8 | 部分/范围缩减 | GL 万行滚动已实现；UIA provider 未实现（lead 裁断缩减） |
| C9 | 未关闭 | 字体许可待决：Noto 可分发 / Windows 字体不可分发 |
- C6：见 `docs/evidence/M2-summary.md` §3.1。
- C8：M3/M4 计划无 UIA 项（`docs/plan.md:263-266`）；M2-WP5 已交付 A11yNode
  最小树 + J1–J9；UIA 需 COM vtable/线程模型，成本收益不匹配。
  结论：UIA 明确不在 M3/M4 范围、延后待真实场景评估，属 lead 裁断范围缩减，
  非已完成。

## F. 未验证清单
- 真实 GPU 帧时间不可由 CPU 侧外推；需 GPU timestamp query 或 Present 计数。
- 跨机器/跨驱动不可外推；需多 GPU/驱动矩阵实测。
- 进程 RSS 未采样（`label_bytes_total` 仅为字符串字节和）；需进程级采样。
- UIA 未实现，a11y 与屏幕阅读器端到端未验证；需 UIA COM provider + 读屏器。

## G. M4-WP2 打包与 DLL 依赖清单（同迭代并行）
- `tools/package.ps1`：build → 复制 DLL → 写 `MANIFEST.txt`
  （名/字节/SHA256），绝对路径调 crystal/objdump；
  `dist/tessell/` 裸 PATH 验收 EXIT=0。
- 导入表 20 个 DLL；裸 PATH（`C:\Windows\System32;C:\Windows`）
  跑未打包 exe → `EXIT=-1073741515`（STATUS_DLL_NOT_FOUND）。
- 补齐传递闭包后最小 msys2 运行时集 **16 个 DLL**，与 exe 同目录裸 PATH
  `verify=pass`、`j1_pass=true`、`j5_pass=true j5_j3_pass=true`、EXIT=0。
- 删测 3 次（`libintl-8.dll`/`libgraphite2.dll`/`libiconv-2.dll`）
  每次均 `-1073741515`。
- 许可：freetype FTL/GPLv2+、harfbuzz MIT、Noto OFL 1.1 可随包；
  Windows 系统字体不可分发（`docs/research/font-fallback.md`）。
- 证据：`docs/evidence/M4-WP2-packaging.md`（173 行，含 8 条 [未验证]）。

# M3 迭代 4 收口日志（M3-WP4 路径 stencil/cover）

## 1. 任务表

| 任务 | 内容 | 状态 |
|---|---|---|
| task-141 | 实现：Polygon CPU 参考 + GL stencil/cover + 窗口验证（阶段 A/B） | 已完成（待提交） |
| task-142 | 独立核验：stencil 反证 + CPU 参考独立性 + 判据审计 | PASS-WITH-DEFECTS（P3×3） |
| task-143 | 收尾文字：注释事实修正 + 本日志 + README/终审 r3 | 本节 |

## 2. 交付物行数表（ReadAllLines 口径）

| 文件 | 行数 |
|---|---|
| `src/tessell/render/polygon.cr` | 151 |
| `src/tessell/render/backend.cr` | 51 |
| `src/tessell/render/gl/gl_backend.cr` | 668 |
| `src/tessell.cr` | 38 |
| `spec/polygon_spec.cr` | 361 |
| `spec/path_gl_spec.cr` | 209 |
| `spec/backend_protocol_spec.cr` | 443 |
| `examples/m3_path_window.cr` | 575 |
| `tools/gate.ps1` | 250 |
| `docs/evidence/M3-WP4-stencil-cover.md` | 71 |
| `docs/evidence/verify-M3-WP4.md` | 78 |

## 3. 实测原始 token 照录（三行；折行处内容照录）

- 正例：`mode=stencil_cover stencil_bits=8 fill_pixels_gl=7794
  fill_pixels_cpu=7794 star_pixels=7794 diff_pixels=0 star_offset_x=0.13
  star_offset_y=0.29 star_vertices=5 frames=20 alloc_windows=[64,64,64]
  retried=false attempt=1 negative_holds=true verify=pass`
- 负例：`mode=fan_no_stencil stencil_bits=8 fill_pixels_gl=16244
  fill_pixels_cpu=7794 star_pixels=7794 diff_pixels=8450 ... verify=fail`
- 核验反证：`GL_INVERT→GL_KEEP` 后 `fill_pixels_gl=0 fill_pixels_cpu=7794
  diff_pixels=7794 verify=fail`（已恢复，`git diff --stat` 仍 +111/−6）。

## 4. 判据与口径

- 四条：`stencil_bits>=8`、`diff_pixels==0`、`fill_pixels_gl==fill_pixels_cpu`、
  `fill_pixels_gl>0`；未放宽。
- 零分配：A `delta_work<1000`、B `<=256`、三窗 max、`GC.enable` 在 ensure。

## 5. P3 台账（核验 PASS-WITH-DEFECTS，P0/P1/P2 无）

- P3-1 注释偏移陈旧：本轮已修（400.13/300.29，并补 0.37/0.61 曾得 diff=1）。
- P3-2 `diff==0` 仅对当前 5 角/偏移几何成立；radius 80 时 `diff=1`，属边界
  fill convention，记录不视作缺陷。
- P3-3 零分配 probe 数字跨运行差 16B（64 vs 80）；A/B 均过，非阻断。

## 6. 未验证（≥4）

- 多显卡/驱动 stencil 行为差异；MSAA 下像素一致性。
- cover 仅 bounds quad 的极端形状覆盖质量。
- stencil 与 dirty/scissor/多 polygon 复用交互。
- `even_odd=false`（nonzero）未实现。

## 7. 门禁关联

- **M3-WP4 关闭（带限定：even-odd only、单几何像素对拍）**；C8 已关闭；
  C7/C9 未动。
- 措辞禁写：通用/跨平台/生产就绪/严格零分配。
