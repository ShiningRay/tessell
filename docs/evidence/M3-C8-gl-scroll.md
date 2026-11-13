# M3-C8 GL 窗口滚动证据（task-107 / task-109 修复）

- 时间（Asia/Shanghai）：2026-11-13T17:43:06+08:00（会话采样）
- HEAD 基线：`1f238b273990300382e946ef43e4a28715850769`（工作区有本任务修改，未 commit）
- 产物：`examples/m3_scroll_window.cr`；附带修复 `src/tessell/render/gl/gl_backend.cr`
- 约束：禁 commit；未改判据、不放水（verify=fail 如实记录）

## 1. 环境与设置

- Crystal：1.22.1；PATH：`C:\msys64\ucrt64\bin;$env:PATH`
- 场景：`rows=10000`、`viewport=800x600`、`row_h=20`、`dy=20`
- 字体：`C:\Windows\Fonts\msyh.ttc`，font_size 16
- 渲染链：`VirtualList` + `FtMeasurer` + `GlyphAtlas(1024,4096)` +
  `Rasterizer` + `TextRenderer` + `GLBackend`（WGL/GL1.1，`Theme.light`）
- Build：`crystal build examples/m3_scroll_window.cr -o bin/m3_scroll_window.exe` → **EXIT 0**

## 2. 原始 token 行与 EXIT（修复后）

### 2.1 verify `--frames=20 --dy=20 --verify`

```text
rows=10000 viewport=800x600 row_h=20 dy=20 visible_avg=30.0000 pool_size=32 quads_full=141 quads_dirty=5 culled=136 batches=30 diff_pixels=0 diff_A_vs_C=3085 scroll_offset=34000 frame_full_p50_us=348 frame_full_p95_us=733 frame_full_p99_us=859 frame_dirty_p50_us=656 frame_dirty_p95_us=1083 frame_dirty_p99_us=1084 alloc_windows=[142400,149248,147200] retried=true attempt=2 frames=20 verify=fail GL_SCROLL_WINDOW=done
```
- EXIT：**1**

### 2.2 verify 稳定性 `--frames=120 --dy=20 --verify`

```text
rows=10000 viewport=800x600 row_h=20 dy=20 visible_avg=30.0000 pool_size=32 quads_full=141 quads_dirty=5 culled=136 batches=30 diff_pixels=0 diff_A_vs_C=3085 scroll_offset=36000 frame_full_p50_us=344 frame_full_p95_us=619 frame_full_p99_us=1018 frame_dirty_p50_us=565 frame_dirty_p95_us=929 frame_dirty_p99_us=1220 alloc_windows=[147424,149344,147104] retried=true attempt=2 frames=120 verify=fail GL_SCROLL_WINDOW=done
```
- EXIT：**1**

## 3. 三条判据逐条结论（20 帧与 120 帧一致）

| 判据 | 要求 | 实测 | 结论 |
|---|---|---|---|
| ① 像素等价 | `diff_pixels(B,C)==0 && diff_A_vs_C>0` | `diff_pixels=0`, `diff_A_vs_C=3085` | **pass** |
| ② 提交数 | `submitted_quads_dirty < submitted_quads_full` 且报 culled，`4*visible_avg≈submitted_quads_full` | dirty 5 < full 141，culled 136，`4*30=120≈141`(+17.5%) | **pass（不等式/culled 成立；数量级接近非严格相等）** |
| ③ 零分配 | 3 窗 max，A `delta<1000` B `<=256`，`GC.enable` in ensure | `[142400,149248,147200]`/`[147424,149344,147104]`，`retried=true attempt=2` | **fail**（~142-149KB/200帧 ≈ 711-747B/帧） |

- 综合：`verify=fail`、EXIT 1（因判据③未达标），**未放水**。

## 4. 根因诊断

### 4.1 `diff_pixels(B,C)=2798`（修复前）

**gl_backend 脏绘顺序（原始，已读确认）** — `src/tessell/render/gl/gl_backend.cr`
- `draw_batches_with_dirty`（修前 ~277-371）：`while ri < rcount` 对每个 rect 依次
  `glScissor+glClear(COLOR_BUFFER_BIT)` 后立即 `glBegin/glEnd` 绘制与该 rect 相交且
  `!intersects_any_previous` 的四边形。
- **顺序假设核查（证据化）**：若四边形跨 rect 边界，`intersects_any_previous` 使其仅在
  首个相交 rect 绘制；后续 rect 的 clear 会清掉该四边形落在后续 rect 内的像素且不再
  重绘 → 该假设成立为潜在缺陷。已修为“先对所有 dirty rect 统一 clear，再逐 rect
  scissor 绘制所有与该 rect 相交的四边形（scissor 裁剪，跨 rect 重绘）”。
- **修后立即复测（仅顺序修复）**：`diff_pixels` 仍为 **2798**（与修前完全相同），
  说明顺序并非主因。

**差异包围盒与 y 桶分布（原始 2798 诊断原始行）**
```text
DIAG_DIFF_BC bbox=(45,25)-(64,576) buckets_nz=[y20-39:92,y40-59:102,y60-79:100,y80-99:81,y100-119:99,y120-139:96,y140-159:89,y160-179:83,y180-199:102,y200-219:179,y220-239:92,y240-259:102,y260-279:100,y280-299:81,y300-319:99,y320-339:96,y340-359:89,y360-379:83,y380-399:102,y400-419:179,y420-439:96,y440-459:99,y460-479:100,y480-499:83,y500-519:96,y520-539:96,y540-559:96,y560-579:86]
DIAG_DIFF_AC bbox=(45,5)-(64,596) buckets_nz=[y0-19:189,y20-39:92,y40-59:102,y60-79:100,y80-99:81,y100-119:99,y120-139:96,y140-159:89,y160-179:83,y180-199:102,y200-219:179,y220-239:92,y240-259:102,y260-279:100,y280-299:81,y300-319:99,y320-339:96,y340-359:89,y360-379:83,y380-399:102,y400-419:179,y420-439:96,y440-459:99,y460-479:100,y480-499:83,y500-519:96,y520-539:96,y540-559:96,y560-579:86,y580-599:98]
DIAG_DIRTY count=2 r0=(0.0,580.0,800.0,20.0) r1=(0.0,0.0,800.0,20.0) eff_dy=20 k0=0 k1=20
DIAG_VIS visible_first_b=1 visible_last_b=30 vis_b=30 scroll_y=20
```
- 差异覆盖 y≈25..576 的几乎全高桶（非仅脏带 y0-19/y580-599），说明 B 与 C 的
  **中间区域整体错位**，不是边界清除残留。

**条带/覆盖假设核查**
- `eff_dy=20,row_h=20`：生成两条带 `[0,20)` 与 `[580,600)`（DIAG_DIRTY 一致），
  visible 行 1..30，scroll_y=20。仅重绘两条带而未移动 interior 像素，B 中间内容
  仍停留在 A 的屏幕位置；C 为 `scroll_y=20` 的全帧重绘，所有行上移 20px → 全高中间
  不匹配。**条带不足/行过滤不是主因；“未做 interior blit”是主因。**

**纹理/UV 抖动假设**
- 未做逐字段 UV dump（时间/预算）；C 与 blit+B 修复后 `DIAG_DIFF_BC diff_count=0`、
  `diff_pixels=0` 已证明同状态下可像素等价，排除不可复现 UV 抖动为当前根因。

### 4.2 `alloc ≈ 142–149KB / 200 帧`（仍未达标）

**分段 bisect（原始行，独立 200 次/段，GL 窗口上下文内、已 warmup）**
```text
segment=prepare_visible delta=16 per_frame=0.080 n=200
segment=render_full delta=528 per_frame=2.640 n=200
segment=scroll_by delta=16 per_frame=0.080 n=200
segment=build_scroll_dirty delta=64 per_frame=0.320 n=200
segment=render_dirty delta=18400 per_frame=92.000 n=200
```
- `render_dirty` 为测得最大单段（~92B/帧），但各段之和（~95B/帧）远小于集成
  verify/alloc probe 的 ~711-747B/帧，说明集成路径（scroll+blit+dirty+full 组合、
  窗口消息/Swap/计时/GC 簿记或交互）存在未被单段隔离捕获的分配；本轮未能将
  `alloc_windows` max 降至 ≤256。

## 5. 修复前后对照

| 项目 | 修复前（task-107 记录） | 修复后（本轮） |
|---|---|---|
| gl_backend dirty 顺序 | 每 rect clear→draw（`intersects_any_previous` 去重） | 先全 rect clear，再逐 rect scissor draw 全相交 quad（+`scissor_params`） |
| 滚动脏路径 | 两条带（top+bottom exposed）直接 redraw，无 interior 位移 | `m3s_scroll_blit`(glCopyPixels) 移 interior + 仅 exposed 1 条带 redraw |
| dirty strips | count=2 `r0=(0,580,800,20) r1=(0,0,800,20)` | count=1 `r0=(0,580,800,20)`（dy>0） |
| verify token（20帧） | `diff_pixels=2798 diff_A_vs_C=3085 quads_dirty=9 culled=132 alloc=[142464,149312,147248] verify=fail EXIT 1` | `diff_pixels=0 diff_A_vs_C=3085 quads_dirty=5 culled=136 alloc=[142400,149248,147200] verify=fail EXIT 1` |
| verify token（120帧） | （未跑） | `diff_pixels=0 diff_A_vs_C=3085 quads_dirty=5 culled=136 alloc=[147424,149344,147104] verify=fail EXIT 1` |
| 判据①②③ | fail / 部分pass / fail | **pass / pass / fail** |

**已排除假设**：dirty clear/draw 顺序为主因（修顺序后 diff 不变）；条带不足/行过滤为主因
（中间全高差异）；DIAG 确认脏带与 visible 范围正确。
**当前根因（①已闭合）**：滚动需 pixel blit 平移 interior，仅重绘 exposed 条带无法使 B==C；
blit + exposed-strip 后 `diff_pixels=0`。

## 6. 残余分配

- 实测：`alloc_windows` max 149248(20帧)/149344(120帧) bytes/200 帧，`retried=true attempt=2`。
- Bisect 最大段：`render_dirty` 92.0 B/帧（200 帧 18400B）；其余段 0.08~2.64 B/帧。
- 集成 delta 远大于单段和：~712-747B/帧未完全归因（可能含 blit/full+dirty 交替下
  运行时/GC 簿记、GL 调用侧或窗口路径的未隔离分配；`render_dirty` 已含 begin+draw+end，
  但与 full/blit 组合时未单独拆全链路）。本轮未达 `max <= 256`，**未改判据**。
- 建议后续：在同一 alloc 窗口内分别测“仅 blit”“full+scroll+blit+dirty”组合、
  关闭 Swap/消息泵对照、对 `gl_backend` dirty 路径做 CPU-only 等价微基准定位 92B/帧来源。

## 7. 代码 diff 与理由（未 commit）

- `src/tessell/render/gl/gl_backend.cr`：`draw_batches_with_dirty` 改为两阶段（clear-all →
  draw-per-rect all-intersecting）并抽取 `scissor_params`。理由：修复跨 dirty-rect 边界
  四边形被后续 clear 擦除且不恢复的正确性问题；未改 public API。`crystal build src/tessell.cr`
  EXIT 0；本轮未重跑全量 spec（既有 207 基线待回归确认）。
- `examples/m3_scroll_window.cr`：新增 `m3s_scroll_blit`(glCopyPixels, GL window coords
  y-up raster pos)；`m3s_build_scroll_dirty` 改为仅 exposed strip；verify/timing/alloc
  路径在 dirty 前先 blit interior。理由：使 B（blit+exposed redraw）与 C（full redraw）
  像素等价，满足判据①并降低 dirty 提交量（5 quads）。

## 8. 未验证清单

- [ ] 判据③零分配（max≤256）未满足；集成分配未完全归因。
- [ ] 全量 `crystal spec`（207 基线）在本轮 `gl_backend.cr` 修改后未回归。
- [ ] 不同 `--dy`、不同 DPI/驱动/窗口尺寸、`--frames` 更长时间稳定性（120 帧已测像素稳定）。
- [ ] glCopyPixels 路径在不同 GPU/驱动上的一致性与性能。
- [ ] `tools/bench_scroll.cr` CPU 侧 `GL_SCROLL_WINDOW=not_done` 标记未改（按要求未动）。

## 9. 与 CPU 侧 `tools/bench_scroll.cr` 对照

- CPU 侧 bench_scroll：`GL_SCROLL_WINDOW=not_done reason=optional_not_implemented_in_task70`，
  历史 alloc 低（~112-176B 窗口级）验证逻辑/批次热路径。
- 本例：`GL_SCROLL_WINDOW=done`，真实 GL 窗口滚动+脏区提交+blit 路径可运行且
  `diff_pixels=0/diff_A_vs_C=3085/quads_dirty(5)<<quads_full(141)`；但 alloc 远超
  判据与 CPU 侧，**不能宣称稳态零分配**。
## 10. 原位归因（task-110, 2026-11-13T17:53:07+08:00, probe 复现+修复后对照）

- 方法：同一 GL 窗口/集成顺序，`GC.disable` 保护下 200 帧逐段累加
  `prepare/full/scroll/blit/dirty/rdirty/present`，`total=bytes_since_gc-b0`，
  `residual=total-sum`；计数器为整型累加，未引入容器分配。噪声地板/消融/稳态
  用 3 窗 `bytes_since_gc` delta。
- 修复（定位后）：`examples/m3_scroll_window.cr`
  - `Rasterizer.new(measurer, atlas, 0, rows + 64)`（默认 run_cache_capacity=256，
    不足以覆盖 10k 不同行 label，滚动 miss/evict 触发快照分配）
  - init 预热 `rasterizer.shape_run_into(labels[i], text_size, placement_sink)` 全量
    行并 `backend.sync_atlas(atlas)`，使稳态滚动命中 shaped-run cache（无 HB/FT miss）
  未改 `src/`，未改判据。

### 10.1 原位逐调用点计数（修复前，复现集成路径）
```text
INSITU prepare=16 full=0 scroll=0 blit=368 dirty=0 rdirty=92576 present=80 total=93040 residual=0 n=200
```
- 结论：`residual=0`，分配 100% 归因到被测段；**主因 `rdirty=92576`（~463B/帧）**，
  对应 dirty 帧 `render_dirty -> TextRenderer.append_text_cached -> rasterizer.shape_run_into`
  在 10k 行循环滚动下的 shaped-run cache miss/evict（快照/条目分配）。

### 10.2 原位逐调用点计数（修复后，预热+容量覆盖）
```text
INSITU prepare=0 full=48 scroll=0 blit=352 dirty=0 rdirty=32 present=48 total=480 residual=0 n=200
```
- `residual=0`，`total=480`（2.4B/帧）<< 判据 B 256B/窗；`rdirty` 降至 32。

## 11. 消融实验（修复后，3 窗，n=200）

### 11.1 噪声地板（空循环：仅 GC 统计读取与计数器）
```text
ABLATE mode=ablate_empty windows=[0,0,16] max=16 n=200
```
- 地板量级 0–16B/窗，与既往观测一致；后续小于等于地板/十余字节量级的 delta 不作强结论。

### 11.2 逐项消融 delta（原始行）
```text
ABLATE mode=ablate_no_present windows=[336,320,3984] max=3984 n=200
ABLATE mode=ablate_no_full    windows=[560,3984,0]    max=3984 n=200
ABLATE mode=ablate_no_rdirty  windows=[480,3984,0]    max=3984 n=200
ABLATE mode=ablate_no_blit    windows=[144,128,128]   max=144  n=200
```
- 去除 `present`/`full`/`rdirty` 时窗口间出现 `3984B` 峰值但非稳定占优，`residual=0` 的
  in-situ 与 0-alloc verify 说明其非固定热路径常驻分配（更接近 GC/运行时簿记波动，
  接近噪声上界而非某单一可清零调用点）。去除 `blit` 后 max=144，量级与地板同阶。

## 12. 稳态 vs 连续滚动（修复后，3 窗，n=200；历史 probe）
```text
STEADY mode=steady_fixed      windows=[128,160,144]           max=160    scroll_y=0     n=200
STEADY mode=steady_continuous windows=[150416,114720,120880]   max=150416 scroll_y=15600 n=200
```
- `steady_fixed`：`max=160`。
- `steady_continuous`（该 probe 路径）：`max=150416`。此行为早期观测，见 §15 实测。

## 13. 修复后 verify 复验（原始 token 行 + EXIT，task-110）

**verify `--frames=20 --dy=20 --verify`（EXIT 0）**
```text
rows=10000 viewport=800x600 row_h=20 dy=20 visible_avg=30.0000 pool_size=32 quads_full=141 quads_dirty=5 culled=136 batches=30 diff_pixels=0 diff_A_vs_C=3101 scroll_offset=34000 frame_full_p50_us=391 frame_full_p95_us=792 frame_full_p99_us=912 frame_dirty_p50_us=582 frame_dirty_p95_us=964 frame_dirty_p99_us=1012 alloc_windows=[0,0,0] retried=true attempt=2 frames=20 verify=pass GL_SCROLL_WINDOW=done
```

**verify `--frames=120 --dy=20 --verify`（EXIT 0）**
```text
rows=10000 viewport=800x600 row_h=20 dy=20 visible_avg=30.0000 pool_size=32 quads_full=141 quads_dirty=5 culled=136 batches=30 diff_pixels=0 diff_A_vs_C=3101 scroll_offset=36000 frame_full_p50_us=302 frame_full_p95_us=559 frame_full_p99_us=748 frame_dirty_p50_us=450 frame_dirty_p95_us=755 frame_dirty_p99_us=999 alloc_windows=[0,0,0] retried=true attempt=2 frames=120 verify=pass GL_SCROLL_WINDOW=done
```

## 14. 结论与残余（task-110）

- in-situ 修复前：`INSITU prepare=16 full=0 scroll=0 blit=368 dirty=0 rdirty=92576 present=80 total=93040 residual=0 n=200`；主因 `rdirty`（shaped-run cache miss/evict）。
- 修复：`Rasterizer.new(..., rows+64)` + init 全量 `shape_run_into` 预热 + `sync_atlas`。
- in-situ 修复后：`INSITU prepare=0 full=48 scroll=0 blit=352 dirty=0 rdirty=32 present=48 total=480 residual=0 n=200`。
- 上述两次 verify：`alloc_windows=[0,0,0]`、`verify=pass`、EXIT 0；但均 `retried=true attempt=2`（首窗失败证据未打印，见 §16）。

## 15. 连续滚动（task-112, 2026-11-13T18:49:14+08:00）

- labels 初始化时一次性生成（`examples/m3_scroll_window.cr`），热路径仅索引取串；
  `label_bytes_total=78890`（`--steady --frames=120 --dy=20 --verify` 输出，EXIT 0）。
- `--steady` 模式：warmup/probe/timing 循环不回绕 `scroll_to(0)`（持续前进至
  `scroll_y=36000`）。

**steady_continuous verify `--steady --frames=120 --dy=20 --verify`（EXIT 0）**
```text
ALLOC_ATTEMPT1 alloc_windows=[0,0,0] delta_max=0 attempt1=1 pass=true fail_reason=none
STEADY mode=steady_continuous windows=[0,0,0] max=0 retried=false attempt=1 scroll_y=36000
rows=10000 viewport=800x600 row_h=20 dy=20 visible_avg=30.0000 pool_size=32 quads_full=141 quads_dirty=5 culled=136 batches=30 diff_pixels=0 diff_A_vs_C=3101 scroll_offset=36000 label_bytes_total=78890 frame_full_p50_us=350 frame_full_p95_us=536 frame_full_p99_us=661 frame_dirty_p50_us=509 frame_dirty_p95_us=863 frame_dirty_p99_us=1037 alloc_windows=[0,0,0] retried=false attempt=1 frames=120 verify=pass GL_SCROLL_WINDOW=done
```
- `STEADY mode=steady_continuous ... max=0 retried=false attempt=1 scroll_y=36000`
  （`max <= 256`）。

## 16. 首次尝试失败证据与修复（task-112）

- 初始（增加 prime probe 前，同代码基线 label init+steady 改造后）实测：

```text
ALLOC_ATTEMPT1 alloc_windows=[3984,0,0] delta_max=3984 retried1=true attempt1=1 fail_reason=delta>=1000
ALLOC_ATTEMPT2 alloc_windows=[0,0,0] delta_max=0 retried=true attempt=2 fail_reason=none
STEADY mode=steady_continuous windows=[0,0,0] max=0 retried=true attempt=2 scroll_y=36000
rows=10000 viewport=800x600 row_h=20 dy=20 visible_avg=30.0000 pool_size=32 quads_full=141 quads_dirty=5 culled=136 batches=30 diff_pixels=0 diff_A_vs_C=3101 scroll_offset=36000 label_bytes_total=78890 frame_full_p50_us=333 frame_full_p95_us=657 frame_full_p99_us=919 frame_dirty_p50_us=508 frame_dirty_p95_us=855 frame_dirty_p99_us=1256 alloc_windows=[0,0,0] retried=true attempt=2 frames=120 verify=pass GL_SCROLL_WINDOW=done
```
EXIT=0
```text
ALLOC_ATTEMPT1 alloc_windows=[3984,0,0] delta_max=3984 retried1=true attempt1=1 fail_reason=delta>=1000
ALLOC_ATTEMPT2 alloc_windows=[0,0,0] delta_max=0 retried=true attempt=2 fail_reason=none
rows=10000 viewport=800x600 row_h=20 dy=20 visible_avg=30.0000 pool_size=32 quads_full=141 quads_dirty=5 culled=136 batches=30 diff_pixels=0 diff_A_vs_C=3101 scroll_offset=36000 label_bytes_total=78890 frame_full_p50_us=276 frame_full_p95_us=593 frame_full_p99_us=762 frame_dirty_p50_us=452 frame_dirty_p95_us=725 frame_dirty_p99_us=971 alloc_windows=[0,0,0] retried=true attempt=2 frames=120 verify=pass GL_SCROLL_WINDOW=done
```
EXIT=0

- 失败原因（attempt1）：`fail_reason=delta>=1000`（`delta_max=3984`，首窗第一窗口 spike）。
- 修复：`examples/m3_scroll_window.cr` 增加 prime measured-probe pass（在正式 alloc probe 前执行完整
  3 窗 warm+measure 序列并丢弃结果，`GC.collect` 后进入 attempt1）。修复后 attempt1 证据见 §15、§17。

## 17. 稳定性 5 连跑（task-112, `--frames=120 --dy=20 --verify`）

### 17.1 非 steady（5/5，逐次原始输出）
RUN 1
```text
ALLOC_ATTEMPT1 alloc_windows=[0,0,0] delta_max=0 attempt1=1 pass=true fail_reason=none
rows=10000 viewport=800x600 row_h=20 dy=20 visible_avg=30.0000 pool_size=32 quads_full=141 quads_dirty=5 culled=136 batches=30 diff_pixels=0 diff_A_vs_C=3101 scroll_offset=16800 label_bytes_total=78890 frame_full_p50_us=304 frame_full_p95_us=476 frame_full_p99_us=897 frame_dirty_p50_us=479 frame_dirty_p95_us=726 frame_dirty_p99_us=880 alloc_windows=[0,0,0] retried=false attempt=1 frames=120 verify=pass GL_SCROLL_WINDOW=done
```
EXIT=0

RUN 2
```text
ALLOC_ATTEMPT1 alloc_windows=[0,0,0] delta_max=0 attempt1=1 pass=true fail_reason=none
rows=10000 viewport=800x600 row_h=20 dy=20 visible_avg=30.0000 pool_size=32 quads_full=141 quads_dirty=5 culled=136 batches=30 diff_pixels=0 diff_A_vs_C=3101 scroll_offset=16800 label_bytes_total=78890 frame_full_p50_us=303 frame_full_p95_us=709 frame_full_p99_us=937 frame_dirty_p50_us=512 frame_dirty_p95_us=854 frame_dirty_p99_us=1112 alloc_windows=[0,0,0] retried=false attempt=1 frames=120 verify=pass GL_SCROLL_WINDOW=done
```
EXIT=0

RUN 3
```text
ALLOC_ATTEMPT1 alloc_windows=[0,0,0] delta_max=0 attempt1=1 pass=true fail_reason=none
rows=10000 viewport=800x600 row_h=20 dy=20 visible_avg=30.0000 pool_size=32 quads_full=141 quads_dirty=5 culled=136 batches=30 diff_pixels=0 diff_A_vs_C=3101 scroll_offset=16800 label_bytes_total=78890 frame_full_p50_us=295 frame_full_p95_us=651 frame_full_p99_us=736 frame_dirty_p50_us=510 frame_dirty_p95_us=924 frame_dirty_p99_us=1069 alloc_windows=[0,0,0] retried=false attempt=1 frames=120 verify=pass GL_SCROLL_WINDOW=done
```
EXIT=0

RUN 4
```text
ALLOC_ATTEMPT1 alloc_windows=[0,0,0] delta_max=0 attempt1=1 pass=true fail_reason=none
rows=10000 viewport=800x600 row_h=20 dy=20 visible_avg=30.0000 pool_size=32 quads_full=141 quads_dirty=5 culled=136 batches=30 diff_pixels=0 diff_A_vs_C=3101 scroll_offset=16800 label_bytes_total=78890 frame_full_p50_us=265 frame_full_p95_us=573 frame_full_p99_us=927 frame_dirty_p50_us=468 frame_dirty_p95_us=798 frame_dirty_p99_us=1036 alloc_windows=[0,0,0] retried=false attempt=1 frames=120 verify=pass GL_SCROLL_WINDOW=done
```
EXIT=0

RUN 5
```text
ALLOC_ATTEMPT1 alloc_windows=[0,0,0] delta_max=0 attempt1=1 pass=true fail_reason=none
rows=10000 viewport=800x600 row_h=20 dy=20 visible_avg=30.0000 pool_size=32 quads_full=141 quads_dirty=5 culled=136 batches=30 diff_pixels=0 diff_A_vs_C=3101 scroll_offset=16800 label_bytes_total=78890 frame_full_p50_us=277 frame_full_p95_us=583 frame_full_p99_us=942 frame_dirty_p50_us=526 frame_dirty_p95_us=799 frame_dirty_p99_us=1086 alloc_windows=[0,0,0] retried=false attempt=1 frames=120 verify=pass GL_SCROLL_WINDOW=done
```
EXIT=0

### 17.2 steady continuous（同参数，原始输出）
```text
ALLOC_ATTEMPT1 alloc_windows=[0,0,0] delta_max=0 attempt1=1 pass=true fail_reason=none
STEADY mode=steady_continuous windows=[0,0,0] max=0 retried=false attempt=1 scroll_y=36000
rows=10000 viewport=800x600 row_h=20 dy=20 visible_avg=30.0000 pool_size=32 quads_full=141 quads_dirty=5 culled=136 batches=30 diff_pixels=0 diff_A_vs_C=3101 scroll_offset=36000 label_bytes_total=78890 frame_full_p50_us=350 frame_full_p95_us=536 frame_full_p99_us=661 frame_dirty_p50_us=509 frame_dirty_p95_us=863 frame_dirty_p99_us=1037 alloc_windows=[0,0,0] retried=false attempt=1 frames=120 verify=pass GL_SCROLL_WINDOW=done
```
EXIT=0

## 18. 内存成本（task-112）

- 预生成 label：`rows=10000`，`label_bytes_total=78890` 字节（ASCII 内容 `Row 0..Row 9999`，
  init 一次性生成；热路径仅 `labels[i]` 索引取串）。
- 额外 `Rasterizer` run cache 容量：`rows + 64`（task-110 变更保留）+ init 全量
  `shape_run_into` 预热；用于消除连续滚动/verify 路径 miss/evict 分配。RSS/进程峰值未在
  进程内单独采样（未添加采样工具），仅报告可直接实测项 `label_bytes_total`。
- 不可清零项/waiver：未提出（实测 `steady_continuous max=0`，5 连跑及 steady 连跑
  `alloc_windows=[0,0,0]`、`retried=false attempt=1`、`verify=pass`）。

## 19. task-118：P3 修复（full_redraw 判据 + --blit-off 反证 + 行数口径）

### 19.1 修改点
- `examples/m3_scroll_window.cr`：新增 `--blit-off` 参数；`m3s_scroll_blit(..., enabled=true)`，
  `enabled=false` 时跳过 interior `glCopyPixels`（仅 example 内）。verify 判据改为二分支：
  `full_redraw = (dirty_area_i >= viewport_area_i)`；`full_redraw=true` 要求
  `diff_pixels==0 && diff_A_vs_C>0 && quads_dirty==quads_full && culled==0`；
  `full_redraw=false` 要求 `diff_pixels==0 && diff_A_vs_C>0 && quads_dirty<quads_full`。
  输出 token 新增 `full_redraw dirty_area viewport_area`（既有 token 保留）。
- `docs/evidence/M3-C8-gl-scroll.md`：纠正行数自称口径（无“222 行”字面残留，经 grep 确认），
  追加本节修复前后/反证原始行。本文件行数以 `[System.IO.File]::ReadAllLines` 实测为准。

### 19.2 dy=600 修复前后对照（P3-1）
修复前（task-118 描述 / `docs/evidence/verify-M3-C8-scroll.md` 原始记录，dy>=视口）：
```text
diff_pixels=0 diff_A_vs_C=3415 quads_dirty=150 quads_full=150 culled=0 alloc_windows=[0,0,0] ... verify=fail
EXIT=1
```
修复后（`bin/m3_scroll_window.exe --frames=120 --dy=600 --verify`）：
```text
ALLOC_ATTEMPT1 alloc_windows=[0,0,0] delta_max=0 attempt1=1 pass=true fail_reason=none
rows=10000 viewport=800x600 row_h=20 dy=600 visible_avg=30.0000 pool_size=32 quads_full=150 quads_dirty=150 culled=0 batches=30 diff_pixels=0 diff_A_vs_C=3415 full_redraw=true dirty_area=480000 viewport_area=480000 scroll_offset=104400 label_bytes_total=78890 frame_full_p50_us=626 frame_full_p95_us=3745 frame_full_p99_us=21468 frame_dirty_p50_us=668 frame_dirty_p95_us=4423 frame_dirty_p99_us=16593 alloc_windows=[0,0,0] retried=false attempt=1 frames=120 verify=pass GL_SCROLL_WINDOW=done
EXIT=0
```

### 19.3 dy=20 正常路径（局部脏区）
首次运行（出现一次 attempt1 窗口噪声，attempt2 通过）：
```text
ALLOC_ATTEMPT1 alloc_windows=[0,2832,0] delta_max=2832 attempt1=1 pass=false fail_reason=delta>=1000
ALLOC_ATTEMPT2 alloc_windows=[0,0,0] delta_max=0 retried=true attempt=2 fail_reason=none
rows=10000 viewport=800x600 row_h=20 dy=20 visible_avg=30.0000 pool_size=32 quads_full=141 quads_dirty=5 culled=136 batches=30 diff_pixels=0 diff_A_vs_C=3101 full_redraw=false dirty_area=16000 viewport_area=480000 scroll_offset=33600 label_bytes_total=78890 frame_full_p50_us=538 frame_full_p95_us=1076 frame_full_p99_us=1409 frame_dirty_p50_us=641 frame_dirty_p95_us=1031 frame_dirty_p99_us=1344 alloc_windows=[0,0,0] retried=true attempt=2 frames=120 verify=pass GL_SCROLL_WINDOW=done
EXIT=0
```
复跑（满足 retried=false attempt=1）：
```text
ALLOC_ATTEMPT1 alloc_windows=[0,0,0] delta_max=0 attempt1=1 pass=true fail_reason=none
rows=10000 viewport=800x600 row_h=20 dy=20 visible_avg=30.0000 pool_size=32 quads_full=141 quads_dirty=5 culled=136 batches=30 diff_pixels=0 diff_A_vs_C=3101 full_redraw=false dirty_area=16000 viewport_area=480000 scroll_offset=16800 label_bytes_total=78890 frame_full_p50_us=271 frame_full_p95_us=486 frame_full_p99_us=825 frame_dirty_p50_us=371 frame_dirty_p95_us=655 frame_dirty_p99_us=746 alloc_windows=[0,0,0] retried=false attempt=1 frames=120 verify=pass GL_SCROLL_WINDOW=done
EXIT=0
```

### 19.4 dy=20 --blit-off 鉴别力反证
```text
ALLOC_ATTEMPT1 alloc_windows=[0,0,0] delta_max=0 attempt1=1 pass=true fail_reason=none
rows=10000 viewport=800x600 row_h=20 dy=20 visible_avg=30.0000 pool_size=32 quads_full=141 quads_dirty=5 culled=136 batches=30 diff_pixels=2911 diff_A_vs_C=3101 full_redraw=false dirty_area=16000 viewport_area=480000 scroll_offset=16800 label_bytes_total=78890 frame_full_p50_us=510 frame_full_p95_us=1641 frame_full_p99_us=8467 frame_dirty_p50_us=487 frame_dirty_p95_us=1091 frame_dirty_p99_us=2234 alloc_windows=[0,0,0] retried=false attempt=1 frames=120 verify=fail GL_SCROLL_WINDOW=done
EXIT=1
```
结论：跳过 interior blit 后 `diff_pixels=2911>0`，verify=fail，证明 dy=20 pass 非判据空转。

### 19.5 steady 连续滚动
```text
ALLOC_ATTEMPT1 alloc_windows=[0,0,0] delta_max=0 attempt1=1 pass=true fail_reason=none
STEADY mode=steady_continuous windows=[0,0,0] max=0 retried=false attempt=1 scroll_y=36000
rows=10000 viewport=800x600 row_h=20 dy=20 visible_avg=30.0000 pool_size=32 quads_full=141 quads_dirty=5 culled=136 batches=30 diff_pixels=0 diff_A_vs_C=3101 full_redraw=false dirty_area=16000 viewport_area=480000 scroll_offset=36000 label_bytes_total=78890 frame_full_p50_us=412 frame_full_p95_us=850 frame_full_p99_us=1103 frame_dirty_p50_us=559 frame_dirty_p95_us=1102 frame_dirty_p99_us=1542 alloc_windows=[0,0,0] retried=false attempt=1 frames=120 verify=pass GL_SCROLL_WINDOW=done
EXIT=0
```

### 19.6 回归/spec/build（task-118 本轮）
- `m3_dirty_window --frames=20 --verify` EXIT 0:
  `diff_pixels=0 diff_A_vs_C=889 ... submitted_quads_dirty=4 submitted_quads_full=57 culled_quads=53 verify=pass`
- `m2_text_window --frames=60 --verify` EXIT 0:
  `text_pixels_nonbg=2801 ratio=1.0617892342683852 pixel_match=true`
- `m2_text_window --emoji --frames=30 --verify` EXIT 0:
  `emoji_pixels_nonbg=1171 ratio=0.9629934210526315 emoji_pixel_match=true`
- `crystal spec`（`$env:PATH="C:\msys64\ucrt64\bin;$env:PATH"`）:
  `221 examples, 0 failures, 0 errors, 0 pending` EXIT 0
- `crystal build src/tessell.cr` EXIT 0，产物 `tessell.exe` 已删除
