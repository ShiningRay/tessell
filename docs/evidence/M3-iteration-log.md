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
- 提交 1（feat）hash：提交待回填
- 提交 1（feat）短 hash：提交待回填

