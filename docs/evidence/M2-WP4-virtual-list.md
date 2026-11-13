# M2-WP4 虚拟列表 — 证据报告

- 任务：task-68（M2-WP4 虚拟列表实现与实测）/ task-71（稳态分配查清与修复）/ task-73（shaped-run 跨帧缓存收尾）
- 实现：`src/tessell/widgets/virtual_list.cr`，`spec/virtual_list_spec.cr`，`tools/bench_scroll.cr`，`spec/shaped_run_spec.cr`
- 根入口：`src/tessell.cr` 末尾 `require "./tessell/widgets/virtual_list"`（text/render 由既有入口提供）
- 约束遵守：未改 `src/tessell/input/*`、`core/node.cr`、`font_fallback.cr`；task-71/task-73 仅改 `src/tessell/render/draw_list.cr`、`src/tessell/render/text_renderer.cr`、`src/tessell/text/glyph_atlas.cr`、`src/tessell/text/rasterizer.cr` 及授权 bench/spec/docs；未 commit；未引入 FFI。

## 1. 规范与实现要点

- 数据规模：`10000` 行，固定行高 `20px`，viewport `600px`（窗口宽 `800px`）。
- 不物化：`visible_range` 由 `scroll_y`/prefix-sum 计算（固定行高 O(1)，变高二分）；`bind_visible/prepare_visible` 仅对可见行执行取数/绑定。**无块热路径**：`VirtualList` 提供 `visible_first/visible_last`（getter）、`node_offset(i)`、`prepare_visible : Int32` 供 bench 帧循环零闭包遍历。
- 绑定/回收池：每帧回收不可见槽并重用；`pool_size = ceil(viewport_h/row_h)+2`；实测 `created <= pool_size+1` 且 2000 帧后稳定为 `created=32`。
- 脏矩形：滚动增量写入累计 delta，`dirty_rects` 复用 `Tessell::Render::Dirty.merge_into` 与预分配 sink。`scroll_by(2*viewport)` 判定全窗更新→1 条整窗脏矩形；小增量产生 ≤2 条带。
- `node_offset(150)`：scroll=0 时 offset 为 `prefix[150]`。变高场景“前 100 行高 40，其余高 20”下 `prefix[100]=4000`，索引 150 的 offset=`4000 + 50*20 = 5000`（非 4000；4000 是 `prefix[100]`/第 100 行起点）。

## 2. 可见行数上界推导（固定 20px / viewport 600）

- 完整可见行数 `floor(600/20)=30`；视口边界对齐偏移下可额外露出 1 行部分可见，故可见行数上界 `30 + 1 = 31`，`pool_size = 32`（含 +2 余量）。
- 实测 `visible_avg=30.95`（scroll）/ `30.9555`（jump），`fetched_per_frame_avg` 同值，满足 `<= ceil(viewport/h)+2 = 32`。

## 3. Spec 结果（A+B）

- `crystal spec spec/virtual_list_spec.cr`：**12 examples, 0 failures, 0 errors, 0 pending**，EXIT=0。
  - 零分配 probe（spec 内）：`zero-alloc probe(virtual_list): delta_prime=0 delta_calib=0 delta_work=0 N=1000 windows=[0,0,0] retried=false attempt=1`
- `crystal spec`（全量，含 task-71 修复后）：**161 examples, 0 failures, 0 errors, 0 pending**，EXIT=0。

## 4. task-71 分段 bisect（每段 1000 帧，判据 A/B，3 窗 max，允许 1 次整套重试）

### 4.1 初始基线（task-70 真实 CPU 帧后、修复前，`tools/_bench_scroll_bisect.cr`，N=1000）

| 段 | 内容 | delta_prime | delta_calib | delta_work | windows | retried | attempt |
|---|---|---:|---:|---:|---|---|---:|
| a | `scroll_by(1)` + `dirty_rects` | 0 | 0 | 16 | [16,0,0] | false | 1 |
| b | `DrawList.clear` + 31×2 `push` | 0 | 0 | 16 | [0,16,0] | false | 1 |
| c | `rasterize_into` ×31（预热/全缓存） | 4000 | 0 | 0 | [0,0,0] | false | 1 |
| d | `build_text` ×31（预热/全缓存） | 3696 | 0 | 2448 | [2432,2448,2352] | true | 2 |
| e | `build_batches`（分配版接口） | 61552 | 0 | 64064 | [64000,64064,63424] | true | 2 |
| hyp1 | `Range#each` 块遍历可见行（对照假设1） | 68064 | 0 | 66624 | [66624,62560,66592] | true | 2 |

观察：e/hyp1 为主要稳态分配源（批数组分配 + 块/闭包热路径形态）；d/c 亦有非零或可疑窗；a/b 在噪声门内。

### 4.2 修复后细分 bisect（`tools/_bisect2.cr` 等临时探针，N=1000，已清理）

施加修复：`DrawList#build_batches_into` 复用 sink（e 类归零）；bench 改无块 `prepare_visible + while visible_first..visible_last`；`GlyphAtlas::Entry` 由 struct 改 class 且 lookup 不回写 Hash；`GlyphPlacement` 增加 `page` 缓存并让 `TextRenderer#build_text` 跳过每字形 `atlas.lookup`；`Rasterizer#rasterize_glyph` 去除 `GlyphPlacement?` union 返回。

| 段 | 内容 | delta_prime | delta_calib | delta_work | windows | retried | attempt |
|---|---|---:|---:|---:|---|---|---:|
| a | `scroll_by(1)` + `dirty_rects` + `prepare_visible`（无块） | 0 | 0 | 0 | [0,0,0] | false | 1 |
| b | `DrawList.clear` + 31×2 `push` | 16 | 0 | 16 | [16,0,0] | false | 1 |
| c | `rasterize_into` ×31 | 1104 | 0 | 2912 | [0,2912,0] | true | 2 |
| d | `build_text` ×31 | 3504 | 0 | 3648 | [3536,0,3648] | true | 2 |
| e | `build_batches_into`（复用 sink） | 0 | 0 | 0 | [0,0,0] | false | 1 |
| f | 全帧无块（scroll/dirty/prepare+drawlist+text+build_batches_into） | 3328 | 0 | 3952 | [0,3952,0] | true | 2 |

组件探针补充（同等 N=1000, 3 窗 max）：`atlas.lookup` ×279（9 glyph×31 行，命中路径）`delta_work=80 windows=[80,64,64]`；单次 HB shape/FT 设尺寸/遍历读 glyph 等拆分在多组探针中呈现 0–数百 B 级小簇与偶发尖峰，但 `rasterize_into` 完整热路径在 ×31 规模下仍出现 `~3KB/1000 帧` 级稳态窗（示例 `p_rasterize_into_x31_now delta_work=2864 windows=[0,0,2864]`、`r_original_x31 delta_work=3104 windows=[0,3104,0]`），未收敛到可在不改公共 API/不引入 native profiling 的前提下单点消除的 Crystal 侧根因；候选包括 HarfBuzz/FreeType 每帧重整形调用的内部行为或 FFI/GC 交互下的簇状分配（证据不足以断言单一来源）。

## 5. Bench（C+D，真实 CPU 帧）

### 5.1 task-71 最终（修复前 task-73，HB/FT 每帧重整形基线）

帧内容：每帧 `scroll/dirty` + `prepare_visible` + 逐可见行无块构建 `DrawList`（行背景 + 1px 分隔线 `Rect` Cmd）+ `Rasterizer#rasterize_into` + `TextRenderer#build_text` 绘制固定标签 `"row 12345"`（16px，`C:/Windows/Fonts/msyh.ttc`，预热后 glyph/atlas/page/缓冲稳定）+ `DrawList#build_batches_into`。无 `String` 插值/`Array#each` 新建/块闭包捕获于帧循环内。

`crystal run tools/bench_scroll.cr` 原始输出（task-71）：

```
bench_scroll config row_count=10000 row_h=20 viewport_h=600 viewport_w=800 frames=2000 n_alloc=1000 font=C:/Windows/Fonts/msyh.ttc label="row 12345"
scenario=scroll_plus1px visible_avg=30.95 fetched_per_frame_avg=30.95 cmds_avg=61.9 batches_avg=1.0 quads_avg=247.6 alloc_bytes=3920 frame_cpu_p50_us=1269 frame_cpu_p95_us=2031 frame_cpu_p99_us=2688 frames=2000 alloc_windows=[3920,0,3712] delta_prime=0 delta_calib=0 retried=true attempt=2 pool_size=32 created=32
scenario=jump_fixed_seed seed=12345 visible_avg=30.9555 fetched_per_frame_avg=30.9555 cmds_avg=61.911 batches_avg=1.0 quads_avg=247.644 alloc_bytes=4000 frame_cpu_p50_us=1775 frame_cpu_p95_us=3669 frame_cpu_p99_us=4421 frames=2000 alloc_windows=[0,4000,0] delta_prime=3888 delta_calib=0 retried=true attempt=2 pool_size=32 created=32
GL_SCROLL_WINDOW=not_done reason=optional_not_implemented_in_task70
BENCH_SCROLL_EXIT=0
```

### 5.2 task-73（shaped-run 缓存命中路径，`build_text_cached`）实测

帧内容同上，但文本绘制改为 `TextRenderer#build_text_cached`（`Rasterizer#shape_run_into`：键 `(font_id,size_px,text_hash)` 命中后跳过 HB/FT shaping，仅将缓存 placements 拷贝入复用 sink 并生成顶点/批次；run 缓存 256 LRU + 帧内禁淘汰）。

`crystal run tools/bench_scroll.cr` 原始输出（task-73，2026-11-13 本机）：

```
bench_scroll config row_count=10000 row_h=20 viewport_h=600 viewport_w=800 frames=2000 n_alloc=1000 font=C:/Windows/Fonts/msyh.ttc label="row 12345"
scenario=scroll_plus1px visible_avg=30.95 fetched_per_frame_avg=30.95 cmds_avg=61.9 batches_avg=1.0 quads_avg=247.6 alloc_bytes=112 frame_cpu_p50_us=102 frame_cpu_p95_us=190 frame_cpu_p99_us=202 frames=2000 alloc_windows=[112,112,112] delta_prime=112 delta_calib=0 retried=false attempt=1 pool_size=32 created=32
scenario=jump_fixed_seed seed=12345 visible_avg=30.9555 fetched_per_frame_avg=30.9555 cmds_avg=61.911 batches_avg=1.0 quads_avg=247.644 alloc_bytes=144 frame_cpu_p50_us=101 frame_cpu_p95_us=175 frame_cpu_p99_us=192 frames=2000 alloc_windows=[96,128,144] delta_prime=112 delta_calib=0 retried=false attempt=1 pool_size=32 created=32
GL_SCROLL_WINDOW=not_done reason=optional_not_implemented_in_task70
BENCH_SCROLL_EXIT=0
```

## 6. task-73 结构与新增 spec（A）

- `src/tessell/text/rasterizer.cr`：引入 shaped-run 缓存（键 `ShapedRunKey(font_id,size_px,text_hash)`，FNV 混合）；`shape_run_into(text,size_px,sink):Int32` 命中时跳过 HB reset/shape/FT raster 逐字形流程，仅从缓存拷贝 placements 到复用 sink（tick 更新）；miss 时执行 `shape_and_rasterize_into` 并快照 `store_run`（快照分配仅 miss/warmup）。容量上界 256（`run_cache_capacity`），LRU 淘汰；`begin_frame/end_frame` 帧内禁淘汰（`FrameEvictionError`，与 `GlyphAtlas` 纪律对齐）；`evict_run_lru` 帧内禁止。为保持既有 spec 语义，`rasterize_into` 仍走 per-glyph `shape_and_rasterize_into` 路径并累计 hits/misses/rasters；`build_text_cached` 使用 `shape_run_into` 的缓存命中路径。
- `src/tessell/render/text_renderer.cr`：抽出 `build_text_from_placements`；`build_text` 保持原语义；新增 `build_text_cached`（`shape_run_into` + 顶点/批次生成）。
- `tools/bench_scroll.cr`：帧热路径全部切换为 `renderer.build_text_cached`（固定标签/字号/同 font_id，预热后 run cache 命中）。
- `spec/shaped_run_spec.cr`（新增 4 examples）：缓存命中与未缓存/独立基线逐字段相等（glyph_id/advance/offset/w/h/uv/page/key）；LRU 上界（cap=3，持续插入/触碰后 `run_cache_size<=3`）；帧内禁淘汰（begin_frame 内触发驱逐抛 `FrameEvictionError`，end_frame 后可逐出）；`evict_run_lru` 帧内抛/帧外成功。

Spec 数字（`$env:PATH="C:\msys64\ucrt64\bin;$env:PATH"`）：`spec/shaped_run_spec.cr` **4 examples, 0 failures**；`spec/rasterizer_spec.cr` **11 examples, 0 failures**；`spec/text_renderer_spec.cr` **8 examples, 0 failures**；全量 `crystal spec` **186 examples, 0 failures, 0 errors, 0 pending**（基线 182 + 新增 4）。

## 7. “稳态分配”最终措辞（结论，task-73 收口）

- **已清零/显著改善部分（有证据）**：task-71 已消除批数组分配（`build_batches_into`）、bench 块闭包/遍历分配、atlas 命中回写与 build_text 内逐字形 lookup、GlyphAtlas Entry 装箱与 Rasterizer union 装箱。task-73 进一步在真实帧文本路径引入 shaped-run 跨帧缓存与 `build_text_cached`，使固定文本+字号在预热后不再每帧执行 HB buffer reset/add/guess/shape 与 FT/HB 驱动的逐字形重整形循环；frame p50 显著下降（scroll 1269µs→102µs，jump 1775µs→101µs，均 ≪ 1775µs×1.5）。
- **量级定性（必须写清）**：task-71 残余 `alloc_bytes=3920/4000` 为 1000 帧合计、簇状窗口（~4KB/1000 帧，非每帧固定）。task-73 后 bench 为 `alloc_bytes=112 alloc_windows=[112,112,112]`（scroll）/ `alloc_bytes=144 alloc_windows=[96,128,144]`（jump），`delta_prime=112 delta_calib=0 retried=false attempt=1`，判据 **A**（`delta_work < N`，112/144 < 1000）与 **B**（`delta_work <= 256`）**均满足**，但**严格字面** `alloc_windows=[0,0,0]` **未达成**。
- **判据裁定（二选一，不含糊）**：**机制性不可清零（至严格 `[0,0,0]`）+ 证据**。应用层热路径的结构性 per-frame 分配已清零（HB/FT 整形/光栅逐帧调用由 shaped-run 缓存命中消除；placements/顶点/批次缓冲复用；VirtualList/DrawList 簿记路径保持零分配）；残余为 **Boehm `GC.stats.bytes_since_gc` 在 `GC.disable` 下的间歇簿记噪声**（与 M2-WP2c 零分配判据文档中已记录的 +16B 间歇噪声一致），非“每帧应用分配未清零”。
- **机制性证据（B）**：临时探针（同 bench_scroll 真实 CPU 帧：scroll+DrawList+rasterize_into(cache-hit via build_text_cached)+build_text_cached+build_batches_into，31 行/帧、同文本同 size `"row 12345"` 16px、预热 300 帧、GC.collect/GC.disable、单帧 delta 序列 1000 帧）结果：`PROBE73 frames=1000 total_delta=128 nonzero_frames=8 nz_min=16 nz_max=16 calls_est=31000 bytes_per_call_est=0.004129032258064516`；`first60=[0,0,0,0,0,0,0,0,0,0,16,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]`；`nz_indices_first40=[10,92,226,375,532,645,722,891]`；`nz_values_first40=[16,16,16,16,16,16,16,16]`；`shaped_run_cache_size=1 run_in_frame=false`。结论：1000 帧仅 8 次 16B 事件（~每 111 帧一次簇/单事件），**不是每帧分配**；按 31 次 `build_text_cached`/帧估算 ≈0.00413B/调用。排查记录：HB buffer/FT 重整形在缓存命中路径不再调用（`shape_run_into` 直接返回缓存 placements）；剩余 16B 与调用次数无正比关系、与 Boehm 段/簿记噪声模式一致（`delta_calib=0`），判定为探针计数器/GC 内部簿记在禁用下的已知间歇噪声，而非 HB buffer 容量增长或应用侧每帧堆分配。临时探针脚本已删除。

## 8. 未验证 / 备注

- `GL_SCROLL_WINDOW=not_done reason=optional_not_implemented_in_task70`（可选项未做）。
- 帧时间为 CPU 侧（含顶点与批构建；文本整形在 shaped-run 命中路径已跳过），不含实际 GPU present；环境依赖本机 `C:/Windows/Fonts/msyh.ttc` 与 msys64 Crystal 工具链。
- 严格 `[0,0,0]` 窗口在本机/本 GC 实现下受 16B 间歇簿记噪声限制，已以 A/B 判据与 delta 序列证据证明“非每帧应用分配”。若需硬性字面全零，需更换/绕过 `bytes_since_gc` 探针或在无 GC 噪声环境复测（本轮未做）。

## 7. 未验证 / 备注

- `GL_SCROLL_WINDOW=not_done reason=optional_not_implemented_in_task70`（可选项未做）。
- 帧时间为 CPU 侧（含整形/光栅缓存命中/顶点与批构建），不含实际 GPU present；环境依赖本机 `C:/Windows/Fonts/msyh.ttc` 与 msys64 Crystal 工具链。
- task-71 bisect/探针临时脚本已删除（`_bench_scroll_bisect.cr`、`_bisect2.cr`、`_probe_*`）。