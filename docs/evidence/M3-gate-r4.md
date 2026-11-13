# M3 收口门禁终审（r4，重建）

> 本报告于 19:51 首写、20:09 被并行 agent 的破坏性 git 命令删除后按原结论重建；
> 重跑数字以首跑为准（本轮未全部重跑）。

## 0. 结论

- 裁定：**Go-with-conditions（S1 范围）**。
- M3 可标“M3-S1 收口（含 No-Go/未验证记录）”，不得标“M3 全量完成”。
- M4-WP1 可开工；M4 完成受 C7/C9、M3-WP3（及可选 WP4）阻断。
- P1：无。P2：2 项。P3：3 项。

## 1. 核验环境

- 仓库：`C:\Users\ShiningRay\projects\ShiningRay\tessell`。
- HEAD：`1161e53af06a04a047737761d8588b55ac34ae99`（=origin/main）。
- 时间：2026-11-13 19:37–19:51 +08:00；重建 20:09。
- 工作区：报告丢失前仅本报告未跟踪；重建时有 `?? examples/app_demo.cr`、
  `?? tools/gate.ps1`（均非本报告创建，未触碰）。
- 只写本报告；未 commit；未执行 git clean/checkout/stash/reset。

## 2. 必跑结果（首跑 EXIT 与关键 token）

| 检查 | EXIT | 关键结果 |
|---|---|---|
| crystal spec | 0 | 221 examples, 0 failures, 0 errors, 0 pending |
| crystal build | 0 | 2,278,930B；产物已删 |
| scroll dy20 | 0 | alloc [0,0,0] delta=0 diff=0 verify=pass |
| scroll dy600 | 0 | alloc [80,80,80] delta=80 diff=0 verify=pass |
| scroll steady | 0 | alloc [0,0,0] max=0 diff=0 verify=pass |
| dirty 20f | 0 | diff=0 4<57 ratio=.012568 verify=pass |
| dpi light/dark | 0 | px 1605/3079/5094 alloc 64–96 pass |
| m2 text 60f | 0 | 2801 ratio=1.061789 pixel_match=true |
| emoji 30f | 0 | 1171 ratio=.962993 pixel_match=true |
| zero_alloc | 0 | static 16B paint 0 criterion_ok=true |
| atlas_raster | 0 | 8/8 项过；RANDOM200 pages=1；page_reuse same_page |

- 零分配探针非全零：text_renderer 64B、ui_apply/ui_builder 16B；均在 A/B 内。
- 探针：ui_consume 0、virtual_list 0；text_ft 16B。

## 3. 口径审计

- A/B 判据：A `delta<1000`、B `delta<=256`；不是严格 0。
- dy600：文档 `M3-C8-gl-scroll.md:333` 写 `[0,0,0]`，实测 `[80,80,80]`；不实。
- C6 waiver 仅覆盖 M3-WP5（`M2-summary.md:52`、`M3-iteration-log.md:231`），
  不覆盖 M3 全域。
- M4-WP1 幂等按完整帧：`apply→collect_dirty→consume→同输入 apply→空`
  （`M3-iteration-log.md:206`），不是“重复 apply 不标脏”。
- C8 已写 lead 裁断缩减 + UIA 未实现（`M3-iteration-log.md:233,236-239`），
  不得读成“已完成”。
- `M3-WP1-backend-dirty.md:65` 称 12/12 均 `[0,0,0]`；同文件 `:106` 记 max 16B
  （RUN1 `[0,0,16]`）→ 自相矛盾。
- C8 帧时间与首跑差异大（626/3745/21468µs vs 232/414/1211µs），仅记录。

## 4. C5–C9 条件台账

| 条件 | 状态 | 判据/来源 |
|---|---|---|
| C5 | 关闭 | `M3-perf-band.md:180-186` A/B 达标；`:188-196` 不写“更快” |
| C6 | waiver | 仅 M3-WP5；`M2-summary.md:52`；`M3-iteration-log.md:231` |
| C7 | 开放 | 真实键盘 IME 人工；`M2-gate-r3.md:41`（M3-WP3 前） |
| C8 | 部分/缩减 | lead 裁断 UIA 未实现；`M3-iteration-log.md:233` |
| C9 | 开放 | OFL 文本/哈希未逐包核对；`M4-WP2-packaging.md:122-123` |

- C5 关闭；C6 仅 WP5；C7/C9 未关闭；C8 为部分/范围缩减，不是完成。

## 5. M3 完成判定与 M4 阻断

- M3-S1：WP1 后端/脏矩形、WP5 DPI/主题、C8 GL 滚动可收口。
- M3-WP2 macOS：本机 No-Go（`m3-platform-matrix.md:48`）。
- M3-WP3 Linux：未做；M3-WP4 可选：未做；阻断“全量/跨平台”声明。
- M3 不得标全量完成；只能标 S1 收口并附 No-Go/未验证记录。
- M4-WP1 可开工；M4 完成阻断：C7、C9、M3-WP3（及 WP4）、
  M4-WP2 干净 VM/安装器/签名未验证。
- C8 UIA 为范围外（lead 裁断），不计入“已完成”。

## 6. 缺陷清单

### P1（阻断）

- 无。

### P2（须修）

- P2-1 `M3-C8-gl-scroll.md:333`：dy600 写 `[0,0,0]`，实测 `[80,80,80]`。
  复现：`crystal run examples/m3_scroll_window.cr -- --frames=120 --dy=600 --verify`。
  影响：C8 证据可信度；功能上 80 在 A/B 内，仍 pass。
- P2-2 `M3-WP1-backend-dirty.md:65` 称 12/12 均 `[0,0,0]`；
  同文件 `:106` 记 max 16B、RUN1 `[0,0,16]`，自相矛盾。
  影响：零分配声明的边界被抹平，须改为“A/B 内、含 16B 噪声”。

### P3（记录）

- P3-1 `M3-C8-gl-scroll.md:309-310` “不可清零项/waiver 未提出”未覆盖 dy600 80B。
- P3-2 `M3-C8-gl-scroll.md:216` 首窗失败未打印，复现性弱。
- P3-3 C8 帧时间与首跑差异大（626/3745/21468µs vs 232/414/1211µs）。

## 7. 限制与重建

- 本轮按 lead 指示未全部重跑；数字来自 19:37–19:51 首跑记录。
- 重建不改变裁定；需复核时按上表命令重跑。
- 未验证：M3-WP2 macOS/真实 DPI/多显示器、M3-WP3 Linux、M3-WP4、
  UIA、C7 IME 手测、M4 打包。
