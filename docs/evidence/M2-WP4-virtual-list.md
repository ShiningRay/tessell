# M2-WP4 虚拟列表 — 证据报告

- 任务：task-68（M2-WP4 虚拟列表实现与实测）/ task-71（稳态分配查清与修复）
- 实现：`src/tessell/widgets/virtual_list.cr`，`spec/virtual_list_spec.cr`，`tools/bench_scroll.cr`
- 根入口：`src/tessell.cr` 末尾 `require "./tessell/widgets/virtual_list"`
- 约束遵守：未改 `src/tessell/input/*`、`src/tessell/render/*` 以外仅为 task-71 零分配修复所需的 `src/tessell/render/draw_list.cr`、`src/tessell/render/text_renderer.cr`、`src/tessell/text/glyph_atlas.cr`、`src/tessell/text/rasterizer.cr`（见下）；未 commit；未引入 FFI。

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

## 5. Bench（C+D，真实 CPU 帧，task-71 最终）

帧内容：每帧 `scroll/dirty` + `prepare_visible` + 逐可见行无块构建 `DrawList`（行背景 + 1px 分隔线 `Rect` Cmd）+ `Rasterizer#rasterize_into` + `TextRenderer#build_text` 绘制固定标签 `"row 12345"`（16px，`C:/Windows/Fonts/msyh.ttc`，预热后 glyph/atlas/page/缓冲稳定）+ `DrawList#build_batches_into`。无 `String` 插值/`Array#each` 新建/块闭包捕获于帧循环内。

`crystal run tools/bench_scroll.cr` 原始输出：

```
bench_scroll config row_count=10000 row_h=20 viewport_h=600 viewport_w=800 frames=2000 n_alloc=1000 font=C:/Windows/Fonts/msyh.ttc label="row 12345"
scenario=scroll_plus1px visible_avg=30.95 fetched_per_frame_avg=30.95 cmds_avg=61.9 batches_avg=1.0 quads_avg=247.6 alloc_bytes=3920 frame_cpu_p50_us=1269 frame_cpu_p95_us=2031 frame_cpu_p99_us=2688 frames=2000 alloc_windows=[3920,0,3712] delta_prime=0 delta_calib=0 retried=true attempt=2 pool_size=32 created=32
scenario=jump_fixed_seed seed=12345 visible_avg=30.9555 fetched_per_frame_avg=30.9555 cmds_avg=61.911 batches_avg=1.0 quads_avg=247.644 alloc_bytes=4000 frame_cpu_p50_us=1775 frame_cpu_p95_us=3669 frame_cpu_p99_us=4421 frames=2000 alloc_windows=[0,4000,0] delta_prime=3888 delta_calib=0 retried=true attempt=2 pool_size=32 created=32
GL_SCROLL_WINDOW=not_done reason=optional_not_implemented_in_task70
BENCH_SCROLL_EXIT=0
```

## 6. “稳态分配”最终措辞（结论，按 lead task-71 裁断）

- **已清零/显著改善部分（有证据）**：批数组每帧分配由 `build_batches_into(sink)` 复用消除（初始 e `delta_work=64064` → 修复后 e `delta_work=0`）；bench 块闭包/`Range#each` 热路径遍历消除；`build_text` 逐字形 `atlas.lookup` 改走 `GlyphPlacement.page`；`GlyphAtlas` 命中不回写 Hash 且 `Entry` struct→class 去装箱/值写回；`Rasterizer` 热路径 union 装箱消除；`VirtualList` 提供无块 API（`visible_first/visible_last`、`prepare_visible`、`node_offset`）。帧时间 p50 1765→1269µs（scroll）可解释且无性能倒退；`visible/fetched/pool/created` 达标。
- **量级定性（必须写清）**：`alloc_bytes=3920/4000` 是 **1000 帧合计**，即 ~3.9 B/帧均摊、且集中在个别窗口（`[3920,0,3712]` / `[0,4000,0]`），**不是每帧固定分配**（若是每帧 31 行分配，量级应是 MB）。因此正确定性是「**低频重复分配事件**（约每几百帧一次 ~4KB）」，而非「每帧分配未清零」。
- **判据裁定（不可混同）**：**A 门**（`delta_work < N`）在真实 CPU 帧路径**未通过**（3920>1000），所以 M2-WP4 的零分配主张**只覆盖 VirtualList 簿记路径**（`delta_work=0 windows=[0,0,0]`，有对抗 CAUGHT 证据）；真实 CPU 帧路径标注「**未达零分配，残余 ~4KB/1000 帧，根因定位 text 整形/build_text 命中路径，后续专项**」。两者不混为一句，禁止写「已零分配」，禁止写「每帧 4B」。
- **根因与证据**：bisect 定位残余落在 `rasterize_into`/`build_text` 文本整形与顶点生成的缓存命中路径（修复后 c/d/f 段 `delta_work≈2.9–4.0KB/1000帧` 窗口仍出现，e 已归零）。已排除 draw list 批构建分配、bench 块闭包/遍历分配、atlas 命中回写与 build_text 内显式 atlas 查找；剩余疑为 `FtMeasurer/Rasterizer` 每帧重复 `FT_Set_Pixel_Sizes`+HB reset/shape+逐 glyph 组装及/或 HB/FT/FFI+GC 交互下的簇状分配（证据不足断言单一来源），在不改变 `text/*` 契约与不引入更深原生剖析的范围内未稳定清零。M2-WP4 真实帧残余由 task-73（shaped-run 跨帧缓存，专门清理）承接，不在本轮处理。

## 7. 未验证 / 备注

- `GL_SCROLL_WINDOW=not_done reason=optional_not_implemented_in_task70`（可选项未做）。
- 帧时间为 CPU 侧（含整形/光栅缓存命中/顶点与批构建），不含实际 GPU present；环境依赖本机 `C:/Windows/Fonts/msyh.ttc` 与 msys64 Crystal 工具链。
- task-71 bisect/探针临时脚本已删除（`_bench_scroll_bisect.cr`、`_bisect2.cr`、`_probe_*`）。