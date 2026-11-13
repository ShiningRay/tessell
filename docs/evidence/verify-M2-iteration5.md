# verify-M2-iteration5.md — M2 迭代 5 变更集独立核验（dalisi-qing-2, task-75）
- 元信息：报告行数 **61 行**（read/UTF-8, Get-Content | Measure-Object -Line 实测）；HEAD `7cfb44f` + 未提交工作区（代码冻结）；核验时点 2026-11-13（Asia/Shanghai）；只读核验，**未改源码/证据文档、未 commit**；`verify-M2-WP4.md` 未改，`docs/evidence/M2-WP4-virtual-list.md` 未碰。
- 范围/约束：`src/tessell/a11y/tree.cr`、`src/tessell/text/glyph_atlas.cr`、`src/tessell/text/rasterizer.cr`、`src/tessell/render/draw_list.cr`、`src/tessell/render/text_renderer.cr`、`src/tessell/widgets/virtual_list.cr` 及对应 spec/diff/证据文档；临时脚本 `bin/_v75_verify.cr`、`bin/_v75_j9_bad.cr` 已用完并删除。
- 裁定：**PASS-WITH-DEFECTS**（P0 无，P1 无；P3 语义/泄漏风险与契约观察见 §5；未发现伪造）。

## 1. 声称 vs 实测对照
| 项目 | 声称/期望（任务书/实现意图） | 独立实测/证据 | 结论 |
|---|---|---|---|
| ① a11y 焦点 | `focused` 实时取自 `FocusManager#focused?`，非旁挂缓存 | `bin/_v75_verify.cr`：build→无焦点→focus(a)→focus(b) 三次 build 得 `FOCUSED_SEQ empty=true after_focus_a=true after_focus_b=true`；源码 `src/tessell/a11y/tree.cr:105` | 一致 |
| ① a11y 万行 emit 节点数 | 10000 行 `VirtualWindow#emit` 节点数 ≤ 窗口上限（非物化全量） | 独立计数：`A11Y_10K emit_size=31 container_children=10000 container_scroll=0 visible_count=30 expected=31`；滚动后 `A11Y_10K_SCROLL emit_size=31 container_children=10000 container_scroll=12340 visible_count=30 expected=31`；`spec/a11y_tree_spec.cr` J5/J5b 通过 | 一致（31=1容器+30可见） |
| ① a11y DFS 稳定 | DFS 先序稳定，重排子节点序列随之改变 | `DFS_REORDER changed=true preorder_ok_before=true preorder_ok_after=true`（两树不同子序得不同先序 id 序列） | 一致 |
| ① a11y sink.clear 语义 | `build/emit` 复用 sink（先 clear） | `SINK_CLEAR_BUILD swallowed=true size=3`，`SINK_CLEAR_EMIT swallowed=true size=31`（预填充被丢弃）→ 语义为**覆盖/清空后写入**，非追加；源码 `src/tessell/a11y/tree.cr:88,94,145` | 一致（语义=清空覆写） |
| ① a11y Meta 旁挂泄漏 | set_meta 后删/脱离节点的残留风险 | `META_LEAK set_before=true after_detach=true set_before_y=true after_remove_y=true`；`set_meta` 写 `@meta`（`:75-79`）无删除/修剪 API | **存在残留风险（不等价于自动回收）** |
| ② atlas Entry/lookup/LRU | `struct→class`、lookup 不回写 Hash，LRU tick/evict/定向驱逐正确，无别名 bug | `LRU_ORDER evicted=1 k1_present=true k2_present=true k3_present=false expect_k3_evicted=true`；`INVALIDATE_FONT evicted=2 fa1_nil=true fa2_nil=true fb1_present=true`；`ALIAS_SLOT slot_copy_page=0 w=12 h=14 x=0 y=0`（返回 `GlyphSlot` 值拷贝，`Entry` 私有类引用不外泄）；源码 `:119-126,174-180,206-216,227`；`spec/glyph_atlas_spec.cr` 13/0f | 一致，LRU/驱逐正确，未见别名 bug |
| ③ rasterizer page/去 union | glyph 数==placement 数（.notdef/空白/零尺寸），page 与 slot 一致，可分组等价旧 lookup | `PLACEMENT_COUNT space 1==1`、`tabnl 2==2`、`notdef 1==1 w0=true page_neg=true`；`PAGE_MATCH drawable_and_zero=true`；跨页 64×64+48px CJK：`CROSS_PAGE atlas_pages=2 placements=2 drawable=2 placement_pages=[0,1] old_lookup_pages=[0,1] eq_per_glyph=true batch_count=2 batch_textures=[101,202]`；`spec/rasterizer_spec.cr`、`spec/text_renderer_spec.cr` 通过 | **等价**（计数/page/跨页分组与旧逐字形 lookup 一致） |
| ④ draw_list build_batches_into | 与 `build_batches` 逐字段等价；batch_count 一致；sink 已含内容时覆盖非追加 | `DL_EMPTY eq=true`；`DL_ONE arr=1 into_n=1 eq=true`；`DL_MULTI arr=["0:2","2:1","3:2"] into_n=3 bc=3 fields_eq=true`；`DL_PREFILL logical_n=1 pref_size=3 idx0=0:1 idx1_tail_residual=88:88 idx2_tail_residual=77:77 logical_prefix_overwritten=true` → **逻辑前缀覆写、返回逻辑计数正确，但尾部物理残留未清**（非追加；消费者须按返回 count 消费） | 逻辑批次/字段**等价**；sink 语义=按 count 覆写前缀（尾残留） |
| ⑤ text_renderer 分组 | 无 `@atlas.lookup`，按 `placement.page` 分组 | diff 去 lookup；与③跨页实测同：`eq_per_glyph=true`、批次/纹理 `[101,202]` 与 placement.page 序列一致 | **等价** |
| ⑥ virtual_list API/脏区 | `prepare_visible` 与 `bind_visible` fetch 次数一致（不重复/不漏）；dirty_rects 两带语义与 verify-M2-WP4 一致 | `VLIST_FETCH prepare=30 fetched1=30 bind=30 fetched2=30 visible=30 equal=true`；滚动后 `prepare=31 fetched=31`；`DIRTY down10 count=2 area=16000 jump1200 count=1 area=480000`；源码 `:296-382,408-439`；`spec/virtual_list_spec.cr` 12/0f | **等价/一致** |

## 2. 必查项逐项结论（含等价性判断）
1. **a11y `src/tessell/a11y/tree.cr` / `spec/a11y_tree_spec.cr` / `docs/evidence/M2-WP5-a11y-tree.md`**：焦点**实时查询**（`:105` `@focus.try(&.focused?(node))`，非缓存）— **符合**；10000 行 emit 实际 **31 节点**（1+可见30），滚动后仍 31 且 `children_count==10000, scroll_offset==vl.scroll_y` — **符合**；DFS 先序**稳定且随重排改变** — **符合**；`sink.clear` 为**清空覆写**（build `:88,94`、emit `:145`），吞弃调用方已有内容 — **语义明确/覆盖非追加**；Meta 旁挂 Hash（`:75-79`）无删除 API，detach/remove 后条目残留 — **存在泄漏/陈旧风险（P3）**。证据文档 J1-J9/节点数/探针数字与实测及 spec 输出一致，未见弱化。
2. **glyph_atlas `src/tessell/text/glyph_atlas.cr`**：`Entry` `struct→class`（`:119`）且 lookup 命中仅更新 tick 不回写 Hash（`:174-180`）— LRU tick/`evict_lru` 选最旧**正确**（构造 3 项两次 lookup 后淘汰 k3）；`invalidate_font` 定向驱逐**正确**；引用语义**未引入可观测别名 bug**（Entry 私有不外泄，API 返回 `GlyphSlot` 值拷贝，invalidate 后外部持有的 slot 值仍为有效快照；类内可变仅 tick，符合 LRU 意图）。**等价/正确**。
3. **rasterizer `src/tessell/text/rasterizer.cr`**：`GlyphPlacement#page`（默认 -1）与 `GlyphSlot#page` 一致（`:204-215`），返回 `GlyphPlacement` 非 union（`:129`）且无条件 `sink << placement`（`:123`）— glyph 数==placement 数在 notdef/空白/零尺寸**成立**（HB 计数一致，w/h=0 且 page=-1）；跨页分组与旧逐字形 lookup **等价**（`:` 见 ③ 实测）。**等价**。
4. **draw_list `src/tessell/render/draw_list.cr`**：`build_batches_into`（`:92-112`）与 `build_batches`（`:116-119`）对 0/1/多命令、合并/分裂逐字段**等价**；`batch_count`（`:122-124`）与 `build_batches.size` **一致**；sink 预含内容时**非追加**，而是**覆写逻辑前缀并返回逻辑 count，尾部未清理（残留旧元素）** — 消费者须以返回值为界。**等价（逻辑）/尾部物理语义需注意**。
5. **text_renderer `src/tessell/render/text_renderer.cr`**：按 `placement.page` 分组/取纹理（`:123-139`），无 `@atlas.lookup`；与旧逐字形 lookup 分组结果**等价**（跨页实测逐字形 page 序列与批次一致）。
6. **virtual_list `src/tessell/widgets/virtual_list.cr`**：`prepare_visible`（`:296-363`）完成范围计算/fetch 计数，`bind_visible` 包装并 yield（`:366-382`）— fetch 次数**一致且不重复不漏**（等于可见数）；`dirty_rects`（`:408-439`）小步两带、大跳全窗与 verify-M2-WP4 描述**一致**（down10 2/16000，jump1200 1/480000）。**等价/一致**。

## 3. 必跑命令与结果（照录关键行）
- 4 单文件 spec（a11y/render/text）：
  - `crystal spec spec/a11y_tree_spec.cr spec/render_draw_list_spec.cr spec/rasterizer_spec.cr spec/text_renderer_spec.cr` → **44 examples, 0 failures, 0 errors, 0 pending**，EXIT=0。探针：`zero-alloc probe(a11y_build): delta_prime=0 delta_calib=0 delta_work=0 N=1000 windows=[0,0,0] retried=false attempt=1`；`text_renderer ... delta_work=64 windows=[32,32,64] retried=false attempt=1`。
- 全量 spec Run1：`171 examples, 0 failures, 0 errors, 0 pending`（359.03ms）EXIT=0。探针：`a11y_build delta_work=0 windows=[0,0,0]`，`core_node delta_work=16 [16,0,0]`，`glyph_atlas delta_work=0 [0,0,0]`，`render_dirty delta_work=0 [0,0,0]`，`text_ft delta_work=0 [0,0,0]`，`text_renderer delta_work=64 [64,48,16]`，`virtual_list delta_work=0 [0,0,0]`。
- 全量 spec Run2：`171 examples, 0 failures, 0 errors, 0 pending`（398.28ms）EXIT=0。探针：`a11y_build 0 [0,0,0]`，`core_node 16 [0,0,16]`，`glyph_atlas 0 [0,0,0]`，`render_dirty 0 [0,0,0]`，`text_ft 0 [0,0,0]`，`text_renderer 64 [32,64,32]`，`virtual_list 0 [0,0,0]`。
- bench_scroll（`crystal run tools/bench_scroll.cr` 一次，照录两场景原始行，EXIT=0）：
  - `bench_scroll config row_count=10000 row_h=20 viewport_h=600 viewport_w=800 frames=2000 n_alloc=1000 font=C:/Windows/Fonts/msyh.ttc label="row 12345"`
  - `scenario=scroll_plus1px visible_avg=30.95 fetched_per_frame_avg=30.95 cmds_avg=61.9 batches_avg=1.0 quads_avg=247.6 alloc_bytes=3728 frame_cpu_p50_us=1199 frame_cpu_p95_us=1786 frame_cpu_p99_us=2023 frames=2000 alloc_windows=[0,0,3728] delta_prime=0 delta_calib=0 retried=true attempt=2 pool_size=32 created=32`
  - `scenario=jump_fixed_seed seed=12345 visible_avg=30.9555 fetched_per_frame_avg=30.9555 cmds_avg=61.911 batches_avg=1.0 quads_avg=247.644 alloc_bytes=4016 frame_cpu_p50_us=1195 frame_cpu_p95_us=1804 frame_cpu_p99_us=2027 frames=2000 alloc_windows=[0,0,4016] delta_prime=0 delta_calib=0 retried=true attempt=2 pool_size=32 created=32`
  - `GL_SCROLL_WINDOW=not_done reason=optional_not_implemented_in_task70` / `BENCH_SCROLL_EXIT=0`

## 4. 对抗实验（a11y J9 注入）
- 方法：复制 J9 同等 3 窗/≤1 次重试/ensure GC.enable/A+B 判据的探针，在 work 循环内注入 `Bytes.new(8)`（`bin/_v75_j9_bad.cr`，已删）。
- 结果：`delta_prime=0 delta_calib=0 delta_work=16272 N=1000 windows=[16272,12176,15984] retried=false attempt=1` → `delta_work=16000 windows=[16000,16000,16000] retried=true attempt=2` → `CAUGHT: criterion failed as expected (delta_work=16000)`，EXIT=1。**判据未放水，可捕获注入分配。**

## 5. 缺陷/观察清单（P0–P3, file:line）
- **P0**：无。
- **P1**：无。
- **P2**：无。
- **P3-1 语义观察（draw_list）**：`build_batches_into` 覆写 `sink[0, count)` 并返回逻辑 count，但不清理 `sink[count..]` 尾部残留（`src/tessell/render/draw_list.cr:92-112`；实测 `DL_PREFILL logical_n=1` 时 idx1/idx2 仍为旧值 88:88/77:77）。逻辑批次与 `build_batches` 等价，但物理尾部非清空——若调用方误用 `sink.size`/越界读取会得陈旧数据（API 以返回值为准）。
- **P3-2 泄漏/陈旧风险（a11y Meta）**：`Builder#set_meta` 仅写入 `@meta` 无删除/修剪路径（`src/tessell/a11y/tree.cr:75-79`），节点 detach/remove_child 后对应 meta 仍驻留（实测 `META_LEAK after_detach=true after_remove_y=true`）。长生命周期/大量节点 churn 场景存在无界增长与陈旧元数据风险（M2 无 UIA provider 未暴露外部影响，属潜在债）。

## 6. 未验证清单
- Windows UIA/屏幕阅读器端到端、COM/STA、DPI 语义（按设计稿 M2 未做，未验证）。
- a11y Meta 在对象 id 复用极端场景下的陈旧命中影响（未实测）。
- glyph atlas 并发/多线程访问与 Entry class 引用在并发下的安全性（当前单线程语境，未验证）。
- rasterizer 负 pitch/更多字体与复杂脚本的全覆盖（本次覆盖 spec 与独立探针样本，未穷举）。
- bench_scroll CPU 帧 `alloc_bytes`（3728/4016）来源归因与归零可能性（沿用 WP4 观察，非本迭代改动目标，未深挖）。
- GL 上屏/真实像素级文本渲染正确性（CPU 侧与现有 spec/bench 覆盖，GPU 路径未在本次重跑）。

## 7. 伪造检查
- 未发现断言弱化、数字与实测不符或凭空证据：a11y J1-J9 仍为强断言（含 10k≤32、焦点同源、DFS、bounds、零分配 probe），独立计数/序列/LRU/跨页/bench 行与源码行为一致；J9 注入对抗 **CAUGHT**。结论：**无伪造证据**。

（报告结束）

