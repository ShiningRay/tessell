# verify-M2-WP4-task73.md — M2-WP4 task-73 shaped-run 缓存独立核验（dalisi-qing-2, task-82）
- 元信息：报告 39 行（read/UTF-8 实测，`ReadAllLines`=39）；HEAD `2a2b620`+未提交；2026-11-13 Asia/Shanghai；只读核验，未改源码/spec/工具、未 commit。探针 `bin/_v73.cr` 已运行并删除。

## 1. 必跑命令与原始结果
- `crystal spec`：**186 examples, 0 failures, 0 errors, 0 pending** EXIT=0（352.29ms）。
- `crystal spec spec/shaped_run_spec.cr`：**4 examples, 0 failures** EXIT=0。`crystal spec spec/rasterizer_spec.cr`：**11 examples, 0 failures** EXIT=0。
- `crystal run tools/bench_scroll.cr`（BENCH_SCROLL_EXIT=0）：
  - `scroll_plus1px visible_avg=30.95 fetched_per_frame_avg=30.95 cmds_avg=61.9 batches_avg=1.0 quads_avg=247.6 alloc_bytes=112 frame_cpu_p50_us=105 frame_cpu_p95_us=188 frame_cpu_p99_us=211 frames=2000 alloc_windows=[112,112,96] delta_prime=112 delta_calib=0 retried=false attempt=1 pool_size=32 created=32`
  - `jump_fixed_seed seed=12345 visible_avg=30.9555 fetched_per_frame_avg=30.9555 cmds_avg=61.911 batches_avg=1.0 quads_avg=247.644 alloc_bytes=112 frame_cpu_p50_us=108 frame_cpu_p95_us=198 frame_cpu_p99_us=305 frames=2000 alloc_windows=[112,112,96] delta_prime=112 delta_calib=0 retried=false attempt=1 pool_size=32 created=32`；`GL_SCROLL_WINDOW=not_done`

## 2. 等价性（关键）
- 独立探针（同 atlas/measurer，cached miss/hit vs `build_text` 基线，逐字段比对）：`EQUIV cached_miss_vs_build_text ok=true pen=88.33594 vcount=32 bcount=1 bad_v=0 bad_b=0 run_cache=1`；`EQUIV cached_hit_vs_build_text ok=true ... bad_v=0 bad_b=0 run_cache=1`；`EQUIV cached_hit_case2 ok=true pen=135.3125 vcount=28 bcount=1 bad_v=0`（含 CJK/不同位置字号）。**顶点/批次/pen 逐字段相等，功能未降级。**
- stats/per-glyph 语义：`rasterize_into` 仍走 `shape_and_rasterize_into`（`src/tessell/text/rasterizer.cr:195-198`，HB/FT 逐字形路径 :200-238,:287-330），缓存未改写其语义（探针：`rasterize_into first hits=0 misses=9 rasters=9 second hits=8 misses=10 rasters=10`，每次调用继续更新统计）。`shape_run_into` 命中为设计上的跳过整形拷贝缓存（:168-184），命中不改 stats（`hit_changed=false`），与 `build_text_cached` 语义一致；`rasterizer_spec` 所覆盖的 `rasterize/rasterize_into` 行为未变。

## 3. 性能下降 17× 真实性（非空转）
- p50 **105/108µs**（对照 task-73 前 ~1765/1775µs 量级，~16-17×），解释成立：命中路径 `shape_run_into` 跳过 HB reset/shape/FT 整形（`rasterizer.cr:168-184,216-219,306-307`），`build_text_cached` 仍执行 placement→顶点/批次生成（`text_renderer.cr:115-125,127-179,190-203`）。
- 稳态仍做真实工作：`cmds_avg=61.9/61.911`、`quads_avg=247.6/247.644`、`visible_avg=30.95/30.9555`、`batches_avg=1.0`、`fetched_per_frame_avg` 同步，`pool_size=32 created=32`。**非空转，P1 不成立。**

## 4. 零分配判据与噪声结论
- `tools/bench_scroll.cr` 判据实现：A `delta_work < N_ALLOC`、B `<=256`，3 窗 max（:235-276, :447-488）、`GC.enable` in ensure（:210-212,:226-228,:268-270,:420-422,:436-438,:480-482）、重试 ≤1（:277-281,:489-493）、打印 `alloc_windows/delta_prime/delta_calib/retried/attempt`（:284,:496）。符合。
- 独立 1000 帧真实路径（scroll+DrawList+`build_text_cached`+批次，预热后 cache hit）逐帧 delta：`ALLOC_REAL nonzero=7 total=112 first20_idx=[86,214,346,548,655,844,969] first20_vals=[16,16,16,16,16,16,16,16]`（稀疏、非每帧固定）。
- 反例探针（每帧 `Bytes.new(16)`×200 帧）：`ALLOC_FIXED16 nonzero=81 total=8064 frames=200 first_vals=[32,32,32,32,32,32,32,32,32,32] every_frame_nonzero=false`。非逐帧等量可见受 GC 计数粒度影响，但 **总量/密度(8064B,81/200)** 与真实路径(112B,7/1000)差异悬殊，未构成“每帧固定 16B 应用分配”反例；与簿记噪声/非 per-frame 结论一致（未被推翻）。

## 5. 帧内禁淘汰与容量（cap=3）
- `FRAME cap3 sz_before=3 sz_after_out=3 raised=true ex=shaped-run LRU eviction during frame is forbidden in_frame=true after_end=false evicted=1 sz_after_evict=2`。cap=3 硬约束、帧内插入触发驱逐必抛 `FrameEvictionError`（`rasterizer.cr:256-259,262-267,128-138`）、end_frame 后恢复并可淘汰。符合。

## 6. 文档对账
- `docs/evidence/M2-WP4-virtual-list.md` **113 行**、`docs/evidence/M2-iteration-log.md` **272 行**（`ReadAllLines` 实测）。两文档结论写为“机制性不可清零（至严格 [0,0,0]）+ 证据/簿记噪声”，非含糊；bench 记录为早次实测（如 102/101µs、alloc 112/144、windows [112,112,112]/[96,128,144]）与本次 105/108µs、112/112、[112,112,96] 属同量级 run-to-run 波动；p50 下降原因在文档中有解释（shaped-run 命中跳过 HB/FT）。

## 7. 缺陷清单
- P1：无。P2：无。
- P3-1：bench 原始数字存在 run-to-run 小幅波动，文档记录值与任一单次复跑不必逐位相同（量级/判据结论一致）。P3-2：`shape_run_into` 命中不更新 hits/misses/rasters（设计使然，`rasterizer.cr:168-184`），与 `rasterize_into` 每次统计不同；属 API 语义差异，非 `rasterize_into` 退化。

## 8. 未验证清单
- 严格 `[0,0,0]` 在本机/GC 下不可得（簿记噪声）；多机/多 GC 实现复现；GPU present/GL 上屏帧（`GL_SCROLL_WINDOW=not_done`）；不同字体/多文本 key 混合压力下 run cache 淘汰与性能；长时运行与 run_cache 容量饱和后 miss 分配形态。

## 9. 裁定
**PASS-WITH-DEFECTS**（P1/P2 无，P3×2；等价性/真实性/禁淘汰与判据实现均成立，噪声结论未被推翻）。