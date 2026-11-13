# verify-M2-WP4（M2-WP4 虚拟列表核验）

- 任务：task-70（lead m00704 指派）
- 核验人：dalisi-qing-2（只读核验 + 独立脚本/对抗 + 本报告；禁改源码、禁 commit）
- 仓库：`C:\Users\ShiningRay\projects\ShiningRay\tessell`
- HEAD：`7cfb44f65bed89e4cc3a92eac0f45542edcd4ab2`（short 7cfb44f）
- 时间：2026-11-13 10:44:01 +08:00（Asia/Shanghai）
- 环境：Windows；Crystal 1.22.1；`$env:PATH="C:\msys64\ucrt64\bin;$env:PATH"`；工作区含未提交新增/修改 `src/tessell/widgets/virtual_list.cr`、`spec/virtual_list_spec.cr`、`tools/bench_scroll.cr`、`docs/evidence/M2-WP4-virtual-list.md`、`M src/tessell.cr`（本次仅只读与写本报告）
- 元信息：最终行数 86（read/UTF-8 行数口径，实测）

## 裁定
- **PASS-WITH-DEFECTS**
- 理由：核心硬指标成立——可见区间/绑定仅遍历可见行（10000 vs 100000 行 fetched/耗时比 ≈1，无全表扫描/每帧前缀和重建）、固定/非整除/clamp 边界与手算一致、变高前缀和与 offset 正确且稳态不重建、回收池有界、`spec/virtual_list_spec.cr` 零分配探针（A/B、3 窗 max、ensure GC.enable、≤1 次整窗重试）在滚动簿记路径上为 0 且对抗注入 `Bytes.new(8)` 可 CAUGHT、全量 spec 2/2 绿（161/0）。存在 **P2**：`dirty_rects` 对小步滚动总是产出“新露出边 + 对侧同厚边”两条带（覆盖新露出区、无漏绘，但包含非必要对侧带，语义/面积偏保守）且实现/注释未精确区分；帧时间口径曾为簿记 0µs（已在证据/bench 中纠正为 CPU 帧但历史声称易误导）；gongbu 消息所称“两场景 alloc_bytes=0…”与 `docs/evidence/M2-WP4-virtual-list.md:56-57,65` 及 `tools/bench_scroll.cr` 真实 CPU 帧路径实测不符（真实帧路径有分配，spec 窄探针为 0）。未发现 P0/P1。

## 1. 不物化（10k vs 100k）— 通过
- 代码（`src/tessell/widgets/virtual_list.cr`）：`bind_visible` 仅对 `[@visible_first,@visible_last]` while 循环取数并回调（:296-362，`@fetch.call(i)` 每可见行一次 :356-360）；无 `row_count.times`/全表遍历。`recompute_visible` fixed 算术求 first/last（:188-220），variable 用前缀和 + 二分 `lower_bound_row/upper_bound_row*`（:221-284）。`build_prefix` 仅在构造(variable :97)、`!@prefix_valid`（:151,221,287）或 `invalidate_heights`（:449-457）调用，`invalidate_row` 仅 variable 失效（:441-447）；稳态 scroll/查询不重建前缀（`bin/_v70_var_rebuild.cr`：init=1，100 次 offset/range 查询后=1，scroll+100 次查询后=1，invalidate_heights 后=2，invalidate_row 后=3）。
- 独立实测（`crystal run bin/_v70_main.cr`，500 帧 scroll_by(1) wrap，viewport 600/row_h 20）：

| rows | frames | us_total | us_per_frame | fetched_last | visible_last | fetch_calls_window | avg_fetch_per_frame |
|---:|---:|---:|---:|---:|---:|---:|---:|
| 10,000 | 500 | 305 | 0.61 | 30 | 30 | 15475 | 30.95 |
| 100,000 | 500 | 308 | 0.616 | 30 | 30 | 15475 | 30.95 |

- **10k/100k 耗时比值**：`308/305 ≈ 1.010`（us/frame 0.616/0.61 ≈ 1.010），**≈1**；fetched/visible/call 数完全一致。未见随行数线性增长（非 ≈10），**无隐藏线性扫描/物化迹象**。

## 2. 边界手算对照（fixed / 非整除 / clamp）— 通过
### 2.1 Fixed：10000 行, row_h=20, viewport_h=600, max_scroll=199400
手算：`count = 30`（整齐）或 `31`（非 20 对齐时上下各露出部分行）；`first=floor(sy/20)` clamp；`last=floor((sy+599)/20)` 并裁剪 `<sy+600`；`node_offset(first)=first*20-sy`；`scroll_to` clamp 到 `[0,199400]`。

| req scroll_y | exp scroll_y | exp first | exp last | exp count | exp node_offset(first) | 实测 scroll_y | 实测 first | 实测 last | 实测 count | 实测 node_offset_first | 结论 |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|:---:|
| 0 | 0 | 0 | 29 | 30 | 0 | 0 | 0 | 29 | 30 | 0 | ✓ |
| 1 | 1 | 0 | 30 | 31 | -1 | 1 | 0 | 30 | 31 | -1 | ✓ |
| 19 | 19 | 0 | 30 | 31 | -19 | 19 | 0 | 30 | 31 | -19 | ✓ |
| 20 | 20 | 1 | 30 | 30 | 0 | 20 | 1 | 30 | 30 | 0 | ✓ |
| 599 | 599 | 29 | 59 | 31 | -19 | 599 | 29 | 59 | 31 | -19 | ✓ |
| 600 | 600 | 30 | 59 | 30 | 0 | 600 | 30 | 59 | 30 | 0 | ✓ |
| 198000 | 198000 | 9900 | 9929 | 30 | 0 | 198000 | 9900 | 9929 | 30 | 0 | ✓ |
| -50 (clamp) | 0 | 0 | 29 | 30 | 0 | 0 | 0 | 29 | 30 | 0 | ✓ |
| 1000000 (clamp) | 199400 | 9970 | 9999 | 30 | 0 | 199400 | 9970 | 9999 | 30 | 0 | ✓ |

### 2.2 非整除：viewport=601/row_h=20 与 viewport=600/row_h=17
独立逐点期望 `exp_first=floor(sy/h)`、`exp_last=floor((sy+vp-1)/h)` 并裁剪末行 top `< sy+vp`，与实测比较并检查 `miss_top/miss_bot`（相邻行是否仍与视口相交却未计入）：

| case | sy | first | last | count | exp_first | exp_last | exp_count | ok | miss_top | miss_bot |
|---|---:|---:|---:|---:|---:|---:|---:|:---:|:---:|:---:|
| vp601_rh20 | 0 | 0 | 30 | 31 | 0 | 30 | 31 | true | false | false |
| vp601_rh20 | 1 | 0 | 30 | 31 | 0 | 30 | 31 | true | false | false |
| vp601_rh20 | 19 | 0 | 30 | 31 | 0 | 30 | 31 | true | false | false |
| vp601_rh20 | 20 | 1 | 31 | 31 | 1 | 31 | 31 | true | false | false |
| vp601_rh20 | 600 | 30 | 60 | 31 | 30 | 60 | 31 | true | false | false |
| vp601_rh20 | 601 | 30 | 60 | 31 | 30 | 60 | 31 | true | false | false |
| vp601_rh20 | 1000 | 50 | 80 | 31 | 50 | 80 | 31 | true | false | false |
| vp600_rh17 | 0 | 0 | 35 | 36 | 0 | 35 | 36 | true | false | false |
| vp600_rh17 | 1 | 0 | 35 | 36 | 0 | 35 | 36 | true | false | false |
| vp600_rh17 | 16 | 0 | 36 | 37 | 0 | 36 | 37 | true | false | false |
| vp600_rh17 | 17 | 1 | 36 | 36 | 1 | 36 | 36 | true | false | false |
| vp600_rh17 | 33 | 1 | 37 | 37 | 1 | 37 | 37 | true | false | false |
| vp600_rh17 | 599 | 35 | 70 | 36 | 35 | 70 | 36 | true | false | false |
| vp600_rh17 | 600 | 35 | 70 | 36 | 35 | 70 | 36 | true | false | false |
| vp600_rh17 | 1000 | 58 | 94 | 37 | 58 | 94 | 37 | true | false | false |

无漏行/重行。

### 2.3 变高行高（`src/tessell/widgets/virtual_list.cr:441-458` 重建语义）
proc：`i<100 ? 40 : 20`，row_count=200，viewport=600：`total_height=6000`，`node_offset(150)=prefix[150]-scroll_y=5000`(@0)、`4000`(@1000)，与 spec `spec/virtual_list_spec.cr:75-85` 一致。前缀和仅 init/invalidate 重建（§1）。

## 3. 脏区覆盖（scroll_by(10) 是否两条带且覆盖新露出区）
- 代码 `dirty_rects`（`src/tessell/widgets/virtual_list.cr:394-439`）：累计 `@dirty_accum` 后，`dy==0` 空（:402-403）；`|dy|>=viewport_h` 全窗 1 条 `(0,0,w,vh)`（:405）；`0<|dy|<viewport_h` **生成 2 条带**（:407-421）：`dy>0` 时 `(0,vh-d,w,d)`（底部，新露出边）+ `(0,0,w,d)`（顶部，对侧同厚带）（:413-415），`dy<0` 对称（:417-419），再经 `Render::Dirty.merge_into`。
- 独立几何探测（重开暴露 `@dirty_output` 快照）：

| 场景 | count | area | rect0 (x,y,w,h) | rect1 (x,y,w,h) |
|---|---:|---:|---|---|
| scroll_to(5000) 后 scroll_by(+10) | 2 | 16000 | (0.0,590.0,800.0,10.0) | (0.0,0.0,800.0,10.0) |
| scroll_to(5000) 后 scroll_by(-10) | 2 | 16000 | (0.0,590.0,800.0,10.0) | (0.0,0.0,800.0,10.0) |
| scroll_to(5000) 后 scroll_by(+1) | 2 | 1600 | (0.0,599.0,800.0,1.0) | (0.0,0.0,800.0,1.0) |
| scroll_by(0) | 0 | 0 | - | - |
| scroll_by(1200) (≥viewport) | 1 | 480000 | (0.0,0.0,800.0,600.0) | - |

- 结论：**非“只给一条”**，每次小步滚动均产出 2 条带；**新露出边始终包含**（向下滚在底部 y=vh-d，向上滚在顶部 y=0），故不会留下新露出区域未重绘（非 P1 漏绘）。但两条带固定为“两端各 d 高”（另一端为对侧同厚带，注释称 counterpart/old exposed），并非仅对真实内容变化区域最小化；对向下滚动而言顶部带为保守重绘。计为 **P2（语义/保守过绘，非覆盖缺失）**。

## 4. 零分配真实性与对抗
- `spec/virtual_list_spec.cr:133-214`：探针覆盖 `scroll_by(1)+scroll_to wrap+dirty_rects` 循环；warmup、prime/calib、3 窗 max、`GC.enable` in ensure（:150,161,171,178,200,202）、失败同一 it 内整窗重试 ≤1 次（:185-212）、打印 `delta_prime/delta_calib/delta_work/N/windows/retried/attempt`、判据 `delta_work < n && delta_work <= 256`（:206,213）。符合现行判据形态。
- 运行 `crystal spec spec/virtual_list_spec.cr`：`12 examples, 0 failures, 0 errors, 0 pending` EXIT=0；探针输出 `zero-alloc probe(virtual_list): delta_prime=0 delta_calib=0 delta_work=0 N=1000 windows=[0,0,0] retried=false attempt=1`。
- 对抗（`bin/_v70_alloc_bad_spec.cr`，复制探针逻辑并 reopen `scroll_by` 注入 `Bytes.new(8)` 每次调用，临时脚本已删）：`delta_prime=16272 delta_calib=0 delta_work=16000 N=1000 windows=[12176,16000,16000] retried=false attempt=1` → 重试 `windows=[16000,16000,16000] retried=true attempt=2` → **FAIL**（1 example, 1 failure, EXIT=1，`crystal spec bin\_v70_alloc_bad_spec.cr:17`）。**CAUGHT**，判据未放水（对该滚动簿记路径）。
- 备注：lead 引述 gongbu 声称“两场景 alloc_bytes=0 alloc_windows=[0,0,0]”；但当前 `docs/evidence/M2-WP4-virtual-list.md:56-57,65` 与 `tools/bench_scroll.cr` 真实 CPU 帧路径（含 `rasterize_into/build_text/build_batches`，:44-68,118-123,158-162）记录 `alloc_bytes≈131-132KB`、windows 非零、`retried=true attempt=2` 且“不满足 A/B”。本次未重跑 bench_scroll（耗时/非强制），结论限于：**spec 窄路径（scroll/dirty）零分配成立且探针有效；真实帧路径分配性按现有证据为非零，与“alloc_bytes=0”口头声称冲突**。

## 5. 回收池与其它
- 1000 次滚动+`bind_visible`：`RECY pool=32 created=32 acquired=173 released=142 reused=30569 invariant_acq_eq_rel_plus_active=true active=31 created_le_pool_plus1=true`（pool=ceil(600/20)+2=32，created 有界无泄漏迹象）。`src/tessell/widgets/virtual_list.cr:368-389` 计数与 created cap 逻辑与实测一致。
- 可见行数：10k×20/viewport600 下 avg 30.95、count 30/31，≤32（与声称一致）。
- `src/tessell.cr` 仅新增 `require "./tessell/widgets/virtual_list"`（git diff 确认）。

## 6. 帧时间口径（代码证据，非性能成绩）
- `tools/bench_scroll.cr` 当前 `run_frame`（:44-68）执行真实 CPU 帧：`scroll`(:44)→`dirty_rects`(:45)→`DrawList.clear`(:46)→每可见行 push 背景/分隔 `DrawCmd`(:51-58)→`tr.build_text(...)` 生成文本四边形(:61)→累计 quads(:62)→`bind_visible`(:48)→`dl.build_batches`(:64)；计时包裹该路径（`measure_frames` :82-85）。因此 **当前 bench_scroll 非“仅簿记”**，其输出以 `frame_cpu_p50_us/p95/p99` 记录（见 `docs/evidence/M2-WP4-virtual-list.md:49-66`，p50≈1765µs）。
- 历史“`frame_p50_us=0 p95=1`”属早期簿记口径缺陷，已在 `docs/evidence/M2-WP4-virtual-list.md:27-29` 纠正说明；本报告不将其视为性能成绩（lead 已判定）。**P2（文档/沟通口径）**：对外声称仍易混淆（含 alloc_bytes=0 表述与现有真实帧证据矛盾，见 §4）。

## 7. 全量 spec（2 次）
- Run1：`161 examples, 0 failures, 0 errors, 0 pending`（379.4ms）`EXIT1=0`
- Run2：`161 examples, 0 failures, 0 errors, 0 pending`（353.71ms）`EXIT2=0`

## 缺陷清单（P0–P3，file:line）
| 级别 | 位置 | 缺陷 | 证据/影响 |
|---|---|---|---|
| P2 | `src/tessell/widgets/virtual_list.cr:407-421`（另注释 :409-411） | 小步滚动 `dirty_rects` 固定产出“新露出边 + 对侧同厚边”两条带：新露出区已覆盖（无漏绘），但对侧带为保守重绘且命名/注释（“old exposed + new exposed”/counterpart）与实际几何语义不够精确。 | 实测 down10/up10 均为 `(y=590,h=10)` 与 `(y=0,h=10)` 两条，count=2；功能正确但过绘/语义含糊。 |
| P2 | `docs/evidence/M2-WP4-virtual-list.md:27-29,56-57,65`；`tools/bench_scroll.cr:44-68,107-175,235,256`；(沟通声称) | 帧时间/分配口径表述易误导：早期 `frame_p50_us=0/p95=1` 为簿记缺陷已纠正为 CPU 帧（p50≈1.77ms），但 lead 引述“两场景 alloc_bytes=0 alloc_windows=[0,0,0]”与证据文件及 bench 真实帧路径实测（`alloc_bytes≈132416/131904`，windows 非零，`retried=true attempt=2`，不满足 A/B）冲突；spec 窄探针为 0 二者需明确区分。 | 读者可能误判整体滚动路径零分配/性能；建议分列“簿记/dirty 探针”与“含 text+drawlist 真实帧”两组口径。 |
| P3 | `tools/bench_scroll.cr:117-123,155-162`（观察） | alloc_probe/帧循环包含 warm glyph 后的 `build_text/rasterize_into` 路径，真实帧稳态分配未清零（按既有证据 ~132B/帧级聚合），与“滚动稳态零分配”目标存在差距（可能源于 text/render 路径，非本次改动范围内定位）。 | `[未验证归因]`：未在本次单独剖析分配点。 |

- **P0**：无。**P1**：无。

## 未验证清单
- 未亲自重跑 `tools/bench_scroll.cr`（2000 帧×2 场景+探针）；采信/对照其源码与 `docs/evidence/M2-WP4-virtual-list.md` 记录。
- 未做 `--window` GL 滚动上屏、`glReadPixels` 首末行像素校验（可选，未实现）。
- 未将 `spec/virtual_list_spec.cr` 探针扩展到含 `bind_visible` 回调内重绑定真实节点/DrawList/TextRenderer 的端到端滚动帧（当前探针覆盖 scroll+wrap+dirty）。
- 真实帧路径分配根因未归因（text renderer/rasterizer/drawlist 等）；计时分辨率未校准。
- 10k/100k 比值为微基准单次采样（305µs/308µs），受环境噪声影响但量级与 fetch 计数足以支持“≈1 非 ≈10”结论。

## 关键原始输出摘要
- `crystal spec spec/virtual_list_spec.cr`：`12 examples, 0 failures, 0 errors, 0 pending`；`zero-alloc probe(virtual_list): delta_prime=0 delta_calib=0 delta_work=0 N=1000 windows=[0,0,0] retried=false attempt=1`；EXIT=0。
- 对抗（bin 副本，`Bytes.new(8)`/call）：`delta_work=16000 windows=[12176,16000,16000] retried=false attempt=1` → `windows=[16000,16000,16000] retried=true attempt=2` → `1 examples, 1 failures` EXIT=1（CAUGHT）。
- `crystal spec`×2：`161 examples, 0 failures, 0 errors, 0 pending` EXIT=0/0。
- `git diff -- src/tessell.cr`：仅 `+require "./tessell/widgets/virtual_list"`。

（报告完）