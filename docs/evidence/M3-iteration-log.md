# M3 迭代 1 收口日志（M3-iter1）

## 迭代概览
- 迭代：M3-iter1（M3-WP1 后端抽象与脏矩形提交巩固）
- 日期：2026-11-13
- 仓库：C:\Users\ShiningRay\projects\ShiningRay\tessell（HEAD=ef8903a）
- 执行：gongbu-shangshu-3（工部尚书副手）
- 核验：dalisi-qing-2（大理寺卿）
- 收口任务：task-97「编写 M3 迭代 1 迭代记录」
- 提交位置：提交待回填

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
