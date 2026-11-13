# verify M3-C8 GL 万行滚动脏区上屏（task-116）
- 核验时间 2026-11-13T18:55:24+08:00；HEAD `1f238b273990300382e946ef43e4a28715850769`；只读重跑，未改被核验文件/未 commit。
- 行数（ReadAllLines）：`examples/m3_scroll_window.cr` 867（与声称一致），`docs/evidence/M3-C8-gl-scroll.md` 310（声称 222，原样记录差异），`src/tessell/render/gl/gl_backend.cr` 470。

## 逐项结论
| 项 | 结论 | 证据（原始） |
|---|---|---|
|1 像素等价非空|通过|dy=20 5/5：`diff_pixels=0 diff_A_vs_C=3101 quads_dirty=5 quads_full=141 culled=136 ... alloc_windows=[0,0,0] retried=false attempt=1 verify=pass` EXIT=0；steady 3/3 同上+`STEADY ... windows=[0,0,0] max=0 retried=false attempt=1 scroll_y=36000`。dy=40：`diff_pixels=0 diff_A_vs_C=3285 quads_dirty=10 quads_full=142 culled=132` EXIT=0（A-vs-C/脏提交随 dy 变化）。dy=600(≥视口)：`diff_pixels=0 diff_A_vs_C=3415 quads_dirty=150 quads_full=150 culled=0` verify=fail EXIT=1（退化整窗，像素仍等价；c2 严格 `<` 见缺陷）。|
|2 判据实现审查|通过|像素真读回：`m3s_capture_pixels` glReadPixels+glFinish `examples/m3_scroll_window.cr:220-225`，`m3s_pixel_diff` 逐字节 RGBA `:228-240`，`diff_pixels/diff_A_vs_C` 计算 `:620-621`，无硬编码（grep 无 `"diff_pixels=0"`）。3窗max `:742-786`；`GC.enable` in ensure `:726,:780`；N=200 alloc 窗 `:685,:765`；重试≤1 且打印 attempt1 原始窗 `:735-805,:802,:803-805`；阈值 A<1000 B<=256 `:792,:796,:817` 未篡改。|
|3 blit 方向|通过|dy>0 exposed 底部条带 `m3s_build_scroll_dirty` `:285-306`（`(0,h-d,w,d)` at :299）；blit 用 GL 窗口坐标 `m3s_scroll_blit :311-343`（dy>0 `glRasterPos2i(0,d); glCopyPixels(0,0,w,h-d)` :326-329）。dy=20/40 连续 diff_pixels=0 且 quads_dirty 5/10 随条带变化、dy=600 无 blit(|dy|>=vh :312)仍等价，排除方向反转恰好抵消。|
|4 回归|通过|`m3_dirty_window --frames=20 --verify` EXIT=0：`diff_pixels=0 diff_A_vs_C=889 submitted_quads_dirty=4 submitted_quads_full=57 culled_quads=53 verify=pass`。`m2_text_window --frames=60 --verify` EXIT=0：`text_pixels_nonbg=2801 ratio=1.0617892342683852 pixel_match=true`。`--emoji --frames=30 --verify` EXIT=0：`emoji_pixels_nonbg=1171 ratio=0.9629934210526315 pixel_match=true`。|
|5 源码审计|通过|`git diff -- src/tessell/render/gl/gl_backend.cr` 两阶段 dirty：pass1 全 rect clear+pass2 逐 rect 绘制所有相交 quad（移除 `intersects_any_previous`）并抽 `scissor_params` `:367-388`，均在 dirty 路径；无判据常量/硬编码 diff_pixels。`git diff --stat src/`: `src/tessell.cr +1`, `gl_backend.cr +73/-28`。|
|6 全量/构建|通过|`crystal spec` **221 examples, 0 failures, 0 errors, 0 pending** EXIT=0；`crystal build src/tessell.cr` EXIT=0（产物已删）；`git status --short` 含 M `docs/evidence/M3-iteration-log.md, src/tessell.cr, src/tessell/render/gl/gl_backend.cr` 及未跟踪 C8/ui 等。|

## 缺陷清单
| 级别 | 位置 | 复现 | 影响 |
|---|---|---|---|
|P3|`examples/m3_scroll_window.cr:816`|`--frames=120 --dy=600 --verify` → `quads_dirty=150 quads_full=150 culled=0 diff_pixels=0 diff_A_vs_C=3415 alloc_windows=[0,0,0] verify=fail` EXIT=1|dy>=视口退化整窗时像素等价且 alloc 合格，但 c2 要求 `quads_dirty < quads_full`(严格)致误判 fail；不影响渲染正确性/小步滚动验收。|
|P3(信息)|`docs/evidence/M3-C8-gl-scroll.md`|声称 222 行，ReadAllLines 实测 310 行|证据文档行数口径不符（原样记录，无功能影响）。|

## 裁定
**PASS-WITH-DEFECTS**（dy=20/40 及 steady 像素等价、提交下降、零分配与回归/全量均通过；dy>=视口边界脚本验收判定过严 P3；自报 dy=20/steady 数值与实测一致）。

## 增量复核（task-118 修复）
- 2026-11-13T19:18:11+08:00，只读未改。行数(ReadAllLines)：`examples/m3_scroll_window.cr` 884，`docs/evidence/M3-C8-gl-scroll.md` 377。
**1 dy=600（修复前 task-116：`verify=fail EXIT=1`，`quads_dirty=150 quads_full=150 culled=0 diff_pixels=0 diff_A_vs_C=3415 alloc=[0,0,0]`，无 full_redraw token；c2 严格 `<` 误判）** 现 raw：
`ALLOC_ATTEMPT1 alloc_windows=[96,80,0] delta_max=96 attempt1=1 pass=true fail_reason=none`
`rows=10000 viewport=800x600 row_h=20 dy=600 visible_avg=30.0000 pool_size=32 quads_full=150 quads_dirty=150 culled=0 batches=30 diff_pixels=0 diff_A_vs_C=3415 full_redraw=true dirty_area=480000 viewport_area=480000 scroll_offset=104400 label_bytes_total=78890 frame_full_p50_us=309 frame_full_p95_us=677 frame_full_p99_us=4447 frame_dirty_p50_us=343 frame_dirty_p95_us=666 frame_dirty_p99_us=4638 alloc_windows=[96,80,0] retried=false attempt=1 frames=120 verify=pass GL_SCROLL_WINDOW=done` **EXIT=0**
**2 --blit-off 反证**（执行者报 diff_pixels=2911，实测一致，EXIT=1）：
`ALLOC_ATTEMPT1 alloc_windows=[64,3984,0] delta_max=3984 attempt1=1 pass=false fail_reason=delta>=1000`
`ALLOC_ATTEMPT2 alloc_windows=[0,0,0] delta_max=0 retried=true attempt=2 fail_reason=none`
`rows=10000 viewport=800x600 row_h=20 dy=20 visible_avg=30.0000 pool_size=32 quads_full=141 quads_dirty=5 culled=136 batches=30 diff_pixels=2911 diff_A_vs_C=3101 full_redraw=false dirty_area=16000 viewport_area=480000 scroll_offset=33600 label_bytes_total=78890 frame_full_p50_us=342 frame_full_p95_us=1305 frame_full_p99_us=5559 frame_dirty_p50_us=329 frame_dirty_p95_us=1273 frame_dirty_p99_us=5395 alloc_windows=[0,0,0] retried=true attempt=2 frames=120 verify=fail GL_SCROLL_WINDOW=done`
代码：仅关 glCopyPixels — `m3s_scroll_blit` `enabled:Bool=true` :312，`return false unless enabled` :313（跳过内部拷贝），:314 仍做 dy==0/|dy|>=vh 早退；解析/传参 :404,:418-419,:580,:613,:665,:706,:724,:760,:778。未放松判据（c1/c2/c3/full_redraw 与 blit_off 无耦合，:820-832）。
**3 判据不可空转**：`full_redraw = dirty_area_i >= viewport_area_i`，`dirty_h_i` 由实际 eff_dy 计算 `:820-823`（非写死）；c1 含 `diff_pixels==0 && diff_A_vs_C>0` `:825`；c2 full_redraw→`quads_dirty==quads_full && culled==0` 否则 `quads_dirty<quads_full` `:826-830`；`pass_verify=verify&&c1&&c2&&c3` `:832`。`--blit-off` 不改 dirty_area/full_redraw/c1/c2。
**4 重试率**（非 steady, `--frames=120 --dy=20 --verify`，10 次）：attempt1 即 pass **10/10 (100%)**，失败窗 **0/30**。未复现执行者自报 `[0,2832,0]@w2`（重试通过）— 原样记录。
`R1: ALLOC_ATTEMPT1 alloc_windows=[0,0,0] delta_max=0 attempt1=1 pass=true, retried=false attempt=1 EXIT=0`
`R2: ALLOC_ATTEMPT1 alloc_windows=[0,0,0] delta_max=0 attempt1=1 pass=true, retried=false attempt=1 EXIT=0`
`R3: ALLOC_ATTEMPT1 alloc_windows=[0,0,0] delta_max=0 attempt1=1 pass=true, retried=false attempt=1 EXIT=0`
`R4: ALLOC_ATTEMPT1 alloc_windows=[0,0,0] delta_max=0 attempt1=1 pass=true, retried=false attempt=1 EXIT=0`
`R5: ALLOC_ATTEMPT1 alloc_windows=[0,0,0] delta_max=0 attempt1=1 pass=true, retried=false attempt=1 EXIT=0`
`R6: ALLOC_ATTEMPT1 alloc_windows=[0,0,0] delta_max=0 attempt1=1 pass=true, retried=false attempt=1 EXIT=0`
`R7: ALLOC_ATTEMPT1 alloc_windows=[0,0,0] delta_max=0 attempt1=1 pass=true, retried=false attempt=1 EXIT=0`
`R8: ALLOC_ATTEMPT1 alloc_windows=[0,0,0] delta_max=0 attempt1=1 pass=true, retried=false attempt=1 EXIT=0`
`R9: ALLOC_ATTEMPT1 alloc_windows=[0,0,0] delta_max=0 attempt1=1 pass=true, retried=false attempt=1 EXIT=0`
`R10: ALLOC_ATTEMPT1 alloc_windows=[0,0,0] delta_max=0 attempt1=1 pass=true, retried=false attempt=1 EXIT=0`
**回归/全量**：`m3_dirty_window --frames=20 --verify` EXIT=0 `diff_pixels=0 diff_A_vs_C=889 submitted_quads_dirty=4 submitted_quads_full=57 culled_quads=53 verify=pass`；`m2_text_window --frames=60 --verify` EXIT=0 `text_pixels_nonbg=2801 ratio=1.0617892342683852 pixel_match=true`；`--emoji --frames=30 --verify` EXIT=0 `emoji_pixels_nonbg=1171 ratio=0.9629934210526315 pixel_match=true`；`crystal spec` **221 examples,0 failures** EXIT=0；`crystal build src/tessell.cr` EXIT=0（删产物）。
`git status --short`: `M docs/evidence/M3-iteration-log.md src/tessell.cr src/tessell/render/gl/gl_backend.cr; ?? dist/ docs/evidence/M3-C8-gl-scroll.md docs/evidence/M4-WP2-packaging.md docs/evidence/verify-M3-C8-scroll.md docs/evidence/verify-M4-WP1-S1-r2.md docs/evidence/verify-M4-WP1-S1.md docs/research/dsl-state-api.md examples/m3_scroll_window.cr spec/ui_builder_spec.cr src/tessell/ui/ tools/package.ps1`
**裁定**：PASS-WITH-DEFECTS（P3-1 dy>=视口判据误判已修复并独立验证；`--blit-off` 反证有效；本样本重试率 10/10 attempt1-pass，但执行者曾遇 `[0,2832,0]@w2` 需重试，零分配稳定性宜持续观察 [未复现]）。