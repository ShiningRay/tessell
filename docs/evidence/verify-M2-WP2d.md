# verify-M2-WP2d（M2-WP2d 文本上屏真实性、零分配判据强度与 GL 路径正确性）

- 任务：task-64
- 核验人：dalisi-qing-2（只读核验 + 重跑 + 本报告；禁改源码、禁 commit）
- 仓库：`C:\Users\ShiningRay\projects\ShiningRay\tessell`（HEAD fdb797c，工作区有未提交改动：含 `src/tessell/render/text_renderer.cr`、`src/tessell/render/gl/gl_renderer.cr`、`examples/m2_text_window.cr`、5 个 GC 探针 spec、`tools/zero_alloc_frame.cr`、`docs/evidence/M2-WP2c-zero-alloc-criterion.md` 等）
- 时间：2026-11-13（Asia/Shanghai，会话内执行）
- 环境：Windows, Crystal 1.22.1；`$env:PATH="C:\msys64\ucrt64\bin;$env:PATH"`；字体 `C:/Windows/Fonts/msyh.ttc`
- 元信息：最终行数 78（read/UTF-8 行数口径）

## 1. 判据升格审查（B 64→256）与分布复跑

### 1.1 代码/文档现状审查
- 现行判据（独立读码一致）：
  - `spec/text_ft_zero_alloc_spec.cr:71-76`、`spec/core_node_zero_alloc_spec.cr:139-144`、`spec/render_dirty_into_spec.cr:120-125`、`spec/glyph_atlas_spec.cr:192-197`、`spec/text_renderer_spec.cr:215-231`（逻辑为 `loop` 内 break/失败后 `:231` 断言 `delta_work`；见第 7 节编译问题）、`tools/zero_alloc_frame.cr:194-196,205-211`：均 `delta_work < N && delta_work <= 256`（工具侧 `< frames && <=256`，N=frames=200），`delta_work = max(3 work windows)`。
  - `GC.enable` 在 ensure：specs `:34-36,:52-54,:68-70`（text_ft）/对应模式一致；`tools/zero_alloc_frame.cr:101-103,:119-121,:142-144`。
  - prime/calib 仅诊断打印，不参与断言。
- `docs/evidence/M2-WP2c-zero-alloc-criterion.md`（30 行，实读）：B 记为 `delta_work <= 256`（:6）、记录 task-63 build_text 20 窗 `[32,48,48,48,48,48,48,48,32,64,32,48,48,48,48,48,32,64,32,48]` max=64 非零 20/20（:11-13）、空循环基线 `[0,1536,0,...]` max=1536 非零 1/20（:14-16）、对比与“B 上限按实测聚合抬升以避免 flake”解释（:16,27）、残余风险“单次噪声若 >256B 会误报失败…”（:30）。**A `delta_work < N` 硬门保留**（:6,25,27,30）——文档如实记录尖峰风险与 A/B 含义。

### 1.2 独立分布复跑（20 窗，N=1000，同协议 warmup+GC.collect/disable 窗口，临时脚本 `bin/_v64.cr` 已删）
- build_text 稳态（`"Hello World"` 16px, 800x600, sink/tex_id 预热+reserve，`TextRenderer#build_text`）：`deltas=[48,32,48,48,48,48,48,32,64,48,48,48,48,48,32,48,64,32,48,48] max=64 nonzero=20`（与 gongbu 序列值域/最大值一致模式：32/48/64 聚合，max=64）。
- 空循环基线（空迭代+可观测累加，不调 build_text）：`deltas=[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,16,0] max=16 nonzero=1 sink=11989000`（本次未复现 1536B 尖峰；GC 簿记尖峰具有偶发性）。

### 1.3 结论（B=256 与 1536 级尖峰；A 硬门）
- **B=256 会被 1536 级 GC 尖峰击穿的场景是存在的且在风险面内**：文档已记录空循环基线曾观测 `max=1536` 单窗尖峰（:14-16），本次独立 20 窗未再现但属偶发噪声；若同量级尖峰落入被测 work 窗，则 `delta_work <= 256` 失败 → **误报失败（flake/假阳性），判据仍可 flake**。按当前 build_text 实测分布（32-64B）B=256 有 4×余量，但对 1536B 级偶发簿记无抵抗。
- **明确结论：可接受残余风险，但必须在报告/文档中持续明示且不得视为“判据永不 flake”**。理由：尖峰来自运行时/GC 簿记而非 per-call 分配，表现为保守方向误报（非漏报）；A 门 `delta_work < N`（per-call ≥1B ⇒ ≥1000B）仍为硬检出门，核心安全性未因 B 放宽至 256 而丧失（见第 2 节）。**不建议“再改 B 常数”来追 1536**（会显著削弱对聚合分配的检出）；若后续反复因 >256 尖峰误报，应升级判据方法（扣除 calib/多窗分位/统计去噪/重试策略已在部分 probe 体现但未统一）而非单纯抬 B。该风险属“可接受残余风险（需明示）”而非“可忽略”。

## 2. 对抗实验（A 门负例 + B 门盲区）

> 独立临时脚本 `bin/_v64.cr`、`bin/_v64_fix.cr`（均已删），同探针协议：prime/calib/3 work 取 max，判据 `delta_work < N && delta_work <= 256`（N=1000）。

| 实验 | 设定 | 结果 | 结论 |
|---|---|---|---|
| A 门负例 | 每次迭代分配 1 个小对象 `AByte`×1000（per-call 分配） | `NEG_A delta_prime=32640 delta_calib=0 delta_work=32000 windows=[28000,31968,32000] N=1000 criterion_ok=false RESULT=CAUGHT` | **A 门有效：CAUGHT**（delta_work>=N） |
| B 盲区样例 1 | 每 100 次分配 16B 对象，共 10 次/窗（总 ≤200B 量级事件） | `BLIND_B delta_prime=0 delta_calib=0 delta_work=3968 windows=[3968,0,0] N=1000 criterion_ok=false RESULT=CAUGHT alloc_events_per_window=10` | 本例被窗口噪声/计量放大至 3968B，**未**落入 B 盲区（CAUGHT），说明“10 次分配”不等同“≤200B delta_work” |
| B 盲区样例 2 | 每 200 次分配 1 次，共 5 次/窗 | `BLIND5 delta_prime=160 delta_calib=0 delta_work=160 windows=[160,160,160] N=1000 criterion_ok=true RESULT=PASSED_BLIND events=5` | **B 盲区实证：PASSED_BLIND**（160B < N 且 ≤256，判据通过） |
| B 盲区样例 3 | 1000 次仅 1 次分配（事件 1） | `BLIND1 delta_prime=32 delta_calib=1536 delta_work=32 windows=[32,32,32] N=1000 criterion_ok=true RESULT=PASSED_BLIND events=1` | **B 盲区实证：PASSED_BLIND**（32B 通过） |

- **盲区结论（不得隐瞒）**：B 门 `<=256` 与 A 门 `<N` 联合下，**稀疏/少量分配事件（本实验 1~5 次/1000 迭代）且累计 bytes_since_gc 增量落在 ≤256B 时可被放过**（PASSED_BLIND），即存在“累计小、非逐次 per-call”的盲区；同时 A 门仍保证 **每次迭代 ≥1B 的稳定 per-call 分配必 CAUGHT**。此盲区与文档“>256B 且 <N 的固定分配可能被 B 误放行（仍受 A 约束）”方向一致，但实验表明在 Boehm 计量下即便名义总量小也可能因聚合表现为不同 delta，需以 `delta_work` 实测为准。

## 3. CPU 侧语义独立复核（`src/tessell/render/text_renderer.cr`）

- 读码复核（`text_renderer.cr:100-193`）：
  - `left = pen_x + p.offset_x.to_f32`，`top = pen_y - p.offset_y.to_f32`（:142-143），`right=left+p.w`，`bottom=top+p.h`（:144-145）；四顶点顺序 (l,t),(r,t),(r,b),(l,b) UV 对应 (u0,v0),(u1,v0),(u1,v1),(u0,v1)（:172-184）——与 y-down + baseline/top 约定一致。
  - `p.w>0 && p.h>0` 才产 quad，否则仅推进 pen（:123,152）；零位图不推 quad。
  - `slot` 取自 `@atlas.lookup(p.key)`（:124），宽高用 placement `p.w/p.h`（:144-145），UV 用 placement `p.u0..v1`（:147），与 atlas/placement 语义一致。
  - 页切换 flush batch（:129-141,156-170），批次数 == 绘制过程中出现的 page 段数；`page_texture_ids[page]` 取纹理（:127）。
  - `reserve_quads`/`reserve_batches` 仅在不足时扩容（:82-93）；`build_text` 复用 `@vertices/@batches` 原位写并以 `@vertex_count/@batch_count` 截断逻辑视图（:105-106,164-168,188-192）。
- 独立脚本复核（`bin/_v64.cr`，文本 `"Hello 你好"` 24px baseline(10,50)）：
  - 逐字形几何（按 **每 glyph 前 pen_x** 修正校验，`bin/_v64_geom.cr`）：`GEOM_CORRECT ok=true pen_end=125.3125 pen_x_final=125.3125 quads=7 batches=1`（初版脚本误用固定起点导致 `ok=false`，经修正为 `left=pen_x_i+offset_x` 后一致）。
  - `size_w_h_eq_slot=true`（drawable glyph 的 placement w/h 与 slot w/h 一致）、`uv_ok=true` 且 UV∈[0,1]（逐顶点）、`zero_bitmap=1 zero_no_quad=true`（空格不产 quad）、`pen_ok=true`。
  - 批次：`batches=1 unique_pages=1 match=true`。
  - `reserve_quads` 后 1000 次 build_text：`verts_size_before=40 verts_size_after=40 verts_oid_same=true batches_size_before=1 batches_size_after=1 batches_oid_same=true quad_cap=10`（缓冲对象与 size 未增长，稳态复用成立）。

## 4. 真实上屏复核（`examples/m2_text_window.cr -- --frames=60 --verify`）

- 独立重跑（EXIT=0）输出：
  - `text_pixels_nonbg=2801 cpu_coverage_sum=2638 ratio=1.0617892342683852 pixel_match=true frames=60 swapbuffers=60 frame_p50_ms=2.1705 frame_p95_ms=5.3527 frame_p99_ms=5.8367 pen_end_x=300.96875 quads=14 batches=1`
  - `gl_path=GL1.1_compat R8->GL_ALPHA glPixelStorei(GL_UNPACK_ALIGNMENT,1) glTexCoord2f/glVertex2f`
  - criterion_note：non-bg=RGB delta>8（对白底），cpu_coverage_sum=渲染字形矩形内非零 R8 atlas 字节计数，ratio 容差 [0.5,1.5]。
- **ratio=1.06 是否巧合（独立口径复算，`bin/_v64_fix.cr`，同文本 `"Hello 你好 Tessell"` 32px）**：
  - `cpu_count_v_gt0=2638`、`cpu_count_v_gt8=2567`、`cpu_count_v_gt32=2473`、`cpu_count_v_gt64=2364`、`cpu_count_v_gt128=1937`；对 readback `text_pixels_nonbg_claim=2801`：
  - `ratio_gt0=1.0617892342683852`、`ratio_gt8=1.0911569925983637`、`ratio_gt32=1.132632430246664`、`ratio_gt64=1.1848561759729273`、`ratio_gt128=1.4460505937016004`。
  - 结论：**1.06 并非单一巧合，属于多口径下的稳定偏高区间（~1.06-1.45）**。原因与 criterion_note 一致：GL_LINEAR 采样+边缘混合+顶点/像素中心与光栅化差异会使 readback 变暗像素数多于“严格源 bitmap 覆盖阈值”像素数；阈值越高（>128）分母越小 ratio 上升至 ~1.45。pixel_match 采用 [0.5,1.5] 容差可覆盖该范围，但**ratio 不能单独证明逐字形精确一致性**，仅证明“有可观文本像素且量级匹配”。

## 5. GL 路径正确性（`src/tessell/render/gl/gl_renderer.cr`）

- `glPixelStorei(GL_UNPACK_ALIGNMENT, 1)`：在 `sync_atlas_textures` 每页上传前显式设置（`gl_renderer.cr:137`，紧随 `glBindTexture :134`、先于 `glTexImage2D :143-146`）——**每次上传都设**，满足 R8 紧密行要求。
- 纹理尺寸/上传：`glTexImage2D` 使用 `size=@atlas.page_size` 宽高、`internalformat/format=GL_ALPHA`、`type=GL_UNSIGNED_BYTE`、pixels=`atlas.page_data(i)`（:130,143-146），与 atlas 页一致；遍历 `pc=@atlas.page_count`（:120,129-148）。
- `glOrtho(0,w,h,0,-1,1)`（:162）与 begin_frame y-down 投影一致；CPU 侧 `top=pen_y-offset_y`（`text_renderer.cr:143`）同向（y 向下增大，offset_y 为 baseline 上方距离，故 top 上移=数值更小）。**上下不对称样本验证**：
  - CPU 几何（`bin/_v64.cr`，baseline=100, 32px）："gy" 两字形均 `off_y=18 top=82 bottom=108 above=18 below=8`（有下伸）；"AV" `off_y=25 top=75 bottom=100 above=25 below=0`（全在基线之上）。
  - 屏幕回读分布（`bin/_v64_vis.cr`，baseline=150, 48px，GL 回读转 y-down 统计）："gy" `total=939 above_baseline=714 below_or_on=225 cpu_min_top=123 cpu_max_bottom=162`；"AV" `total=960 above_baseline=960 below_or_on=0 cpu_min_top=113 cpu_max_bottom=150`。**"AV" 基线下方为 0，"gy" 基线下方显著 >0**，与 CPU extents 同向，未见 y 翻转。
- `delete_textures`：非空时 `glDeleteTextures` 全量删除并 clear id 数组（`gl_renderer.cr:202-207`）——释放路径存在；本次未做 GL 对象存活的底层探针（见未验证）。
- 绘制：`glBegin(GL_QUADS)`/`glTexCoord2f/glVertex2f` 按批次纹理绑定（:173-194），`begin_frame` 设 viewport/清屏/正交/纹理+混合/黑色（:153-170），`end_frame` 禁用并 flush（:196-200）。

## 6. CJK/Latin/Arabic 样例验证

- CPU 侧四边形/advance 一致性（`bin/_v64.cr`，msyh 16px）：
  - `"你好世界"`：placements=4 hb=4 drawable=4 quads=4 batches=1 sum_adv=64.0 meas=64.0 diff=0.0 uv_finite=true pages=1。
  - `"Hello"`：placements=5 hb=5 drawable=5 quads=5 batches=1 sum_adv=40.140625 meas=40.140625 diff=0.0 uv_finite=true pages=1。
  - `"لا"`：placements=2 hb=2 drawable=0 quads=0 batches=0 sum_adv=22.3125 meas=22.3125 diff=0.0 uv_finite=true pages=1（HB/测量/advance 一致，但 **msyh 下无可绘制位图 quad**——与已知 msyh 对该串形状/覆盖行为一致，非几何生成错误；上屏“可见像素”在 msyh 上不可得）。
- 真实上屏：示例 `m2_text_window.cr` 文本为 `"Hello 你好 Tessell"`（含 CJK+Latin）verify 通过、`quads=14 batches=1`；`"لا"` 在 msyh 16px 下 CPU 侧 drawable=0，未能产生可见像素（上屏无意义且无法由该字体验证）。

## 7. 全量 spec 稳定性（≥3 次）

- Run 1（全量 `crystal spec`）：**EXIT=1，编译失败** — `spec\text_renderer_spec.cr:231:6 Error: undefined local variable or method 'delta_work' for top-level`（工作区未提交改动；`delta_work` 在 `loop do` 内赋值 `:223`，`:231` 断言位于 loop 之后同一 it 块但超出该局部变量可见作用域）。
- Run 2（全量）：同上 **EXIT=1，编译失败**（确定性，非 runtime flake）。
- Run 3（全量）：同上 **EXIT=1，编译失败**。
- 补充定向回归（探针/渲染相关 5 spec 合跑）：`crystal spec spec/render_dirty_into_spec.cr spec/glyph_atlas_spec.cr spec/core_node_zero_alloc_spec.cr spec/text_ft_zero_alloc_spec.cr spec/text_renderer_spec.cr` → **38 examples, 0 failures, 0 errors, 0 pending, EXIT=0**（含 `text_renderer_spec` 自身 8 examples 通过，表明其在该编译/运行上下文可过；但全量编译路径触发 :231 作用域错误需以源码为准报告）。
- 其它已跑：`spec/glyph_atlas_spec.cr` 13/0f（task-60 证据链/本次读码上下文一致），`tools/zero_alloc_frame.cr` 本次未单独重跑（第 1 节判据口径已由 specs/文档确认）。
- **稳定性结论**：全量 3 次均因同一编译错误失败 → **不存在 runtime flake 证据，但全量套件在当前工作区不可绿（确定性编译阻塞）**。

## 声称数字 vs 独立复核对照

| 项目 | gongbu 声称 | 独立复核 |
|---|---|---|
| `m2_text_window.cr --frames=60 --verify` | `text_pixels_nonbg=2801 cpu_coverage_sum=2638 ratio=1.0618 pixel_match=true frames=60 swapbuffers=60 frame_p50=1.85/p95=10.95/p99=12.88ms quads=14 batches=1` | `text_pixels_nonbg=2801 cpu_coverage_sum=2638 ratio=1.0617892342683852 pixel_match=true frames=60 swapbuffers=60 frame_p50_ms=2.1705 frame_p95_ms=5.3527 frame_p99_ms=5.8367 pen_end_x=300.96875 quads=14 batches=1 gl_path=GL1.1_compat...`（像素/计数/比例/通过性一致；**帧时不同**，属运行环境波动） |
| build_text 20 窗分布 | `[32,48,48,48,48,48,48,48,32,64,32,48,48,48,48,48,32,64,32,48]` max=64 非零 20/20 | `[48,32,48,48,48,48,48,32,64,48,48,48,48,48,32,48,64,32,48,48]` max=64 非零 20/20（值域/最大值一致） |
| 空循环基线尖峰 | `[0,1536,0,...]` max=1536 非零 1/20 | `[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,16,0]` max=16 非零 1/20（本次未复现 1536，偶发） |
| 判据 B | 64→256，A `delta_work<N` 保留 | 代码/文档确为 `<=256` 且保留 `delta_work<N`（:6 等） |
| CJK/Latin/Arabic `"你好世界","Hello","لا"` | 三串真实上屏或 CPU 侧四边形正确 | CPU：前两者 drawable/quads/uv/advance 正确；`"لا"` msyh 16px placements=2 hb=2 **drawable=0 quads=0** 但 advance/meas 一致。上屏示例含 CJK+Latin 通过；`"لا"` msyh 无可见位图输出 |

## 缺陷清单（P0–P3，file:line）

| 级别 | 位置 | 缺陷/风险 | 证据 |
|---|---|---|---|
| P1 | `spec/text_renderer_spec.cr:223,231` | **工作区全量 spec 编译失败（确定性）**：`delta_work` 在 `loop do` 内赋值，loop 后 `:231` 处 `(delta_work < n && delta_work <= 256).should be_true` 引用导致 `Error: undefined local variable or method 'delta_work' for top-level`；3 次全量 `crystal spec` 均 EXIT=1。 | Run1-3 全量均同错；定向 5-spec 合跑 38/0f 通过但全量受阻。 |
| P2 | 判据实现（`spec/text_*zero_alloc_spec.cr:71-76` 等 5 probe + `tools/zero_alloc_frame.cr:194-196`）/ `docs/evidence/M2-WP2c-zero-alloc-criterion.md:14-16,30` | **B=256 可被 1536 级 GC 簿记尖峰击穿导致误报 flake（残余风险）**；空循环基线历史 max=1536；A 门仍有效但 B 侧非“绝对不 flake”。 | 文档记录+本次未复现（偶发）；1.3 节结论为可接受残余风险（需明示/方法升级而非盲目抬 B）。 |
| P2 | 判据盲区（A+B 联合） | **稀疏小分配可被放过**：1~5 次/1000 迭代分配实测 `delta_work=32/160` → `criterion_ok=true RESULT=PASSED_BLIND`（仍满足 A<N, B<=256）。每次迭代稳定分配仍被 A 抓住（32000 CAUGHT）。 | 第 2 节对抗实验。 |
| P3 | `examples/m2_text_window.cr:347-373` / 指标口径 | **ratio≈1.06 非逐像素等价证明**：多阈值口径 ratio 1.06~1.45（GL_LINEAR/混合/光栅差异），容差 [0.5,1.5] 通过但不能证明字形级精确一致，仅量级/存在性。 | 第 4 节复算。 |
| P3 | 样例/字体覆盖 | `"لا"`（msyh 16px）CPU 侧 drawable=0/quads=0，无法形成可见上屏像素验证（advance/meas 正确）。 | 第 6 节。 |
| P3 | GL 资源释放验证 | `delete_textures` 逻辑存在（`gl_renderer.cr:202-207`）但未做 GL 对象泄漏/存活的底层计数验证。 | 未验证。 |

## 未验证清单

- GL 纹理对象删除后是否无泄漏（需 GL 查询/长跑计数工具，本次未测）。
- `"لا"` 在具备该字形位图覆盖的其它字体下的真实上屏像素（仅测 msyh）。
- 1536B 基线尖峰在当前环境下的可复现频率（本次 20 窗未命中，属偶发）。
- `spec/text_renderer_spec.cr` 在“全量一次性编译”与“定向子集编译”间行为差异的根因（均为工作区未提交态；源码级已定位 :231 作用域问题）。
- 跨 GPU/驱动/软件 GL 实现的上屏像素与帧时一致性（仅本机一次运行）。

## 裁定

- **裁定：PASS-WITH-DEFECTS**
- 理由：文本上屏链路在本次独立复核中功能与几何正确（CPU 四边形/UV/批次/复用正确；`m2_text_window.cr --verify` EXIT=0 且像素计数与声称核心指标一致；gy/AV 方向验证未见 y 翻转；CJK/Latin CPU 与上屏一致，`"لا"` 为字体覆盖导致 drawable=0 而非渲染器几何错误）；A 硬门有效（CAUGHT），但存在 P1（全量 spec 编译阻塞于工作区 `spec/text_renderer_spec.cr:231`）、P2（B=256 对 1536 级偶发簿记可误报 flake 的可接受残余风险，且存在稀疏分配 B 盲区）、P3（ratio 口径非精确证明/字体覆盖/GL 释放未深验）等缺陷，未达无缺陷 PASS。

## 增量补记（task-64 follow-up，响应 lead m00610，2026-11-13 Asia/Shanghai）

> 只读核验；未改源码/未 commit。临时脚本 `bin/_v64_ar.cr` 已删除。

### 1) P1 时点竞态复核（全量 spec 3 次）
- 命令：`$env:PATH="C:\msys64\ucrt64\bin;$env:PATH"; crystal spec` ×3。
- Run1：`149 examples, 0 failures, 0 errors, 0 pending` EXIT=0（370.14ms）；探针：`render_dirty delta_work=16 windows=[0,16,0] retried=false attempt=1`，`text_ft delta_work=16 windows=[0,0,16] retried=false attempt=1`，`text_renderer delta_work=64 windows=[64,48,48] retried=false attempt=1`。
- Run2：`149 examples, 0 failures, 0 errors, 0 pending` EXIT=0（376.56ms）；`render_dirty 16 [0,0,16]`，`text_ft 0 [0,0,0]`，`text_renderer 64 [64,64,48]`，均 `retried=false attempt=1`。
- Run3：`149 examples, 0 failures, 0 errors, 0 pending` EXIT=0（340.84ms）；`render_dirty 0 [0,0,0]`，`text_ft 16 [0,16,0]`，`text_renderer 48 [48,48,48]`，均 `retried=false attempt=1`。
- 结论：**3/3 绿，未复现 `undefined local variable or method 'delta_work'`**。现行 `spec/text_renderer_spec.cr:209` 已于 it 作用域初始化 `delta_work`，`:224` 赋值，`:233` 断言可见；先前 b7 记录的 `:231` 编译阻塞在当前工作区状态下不再出现，确认为**时点竞态/中途编辑态**，非现行源码缺陷。

### 2) GC 探针重试实现合法性审查（防放水）
- 审查对象：`spec/text_ft_zero_alloc_spec.cr`、`spec/core_node_zero_alloc_spec.cr`、`spec/render_dirty_into_spec.cr`、`spec/glyph_atlas_spec.cr`、`spec/text_renderer_spec.cr`、`tools/zero_alloc_frame.cr`。
- 逐项核对：
  - **同一 it/同次调用内整窗重测**：prime/calib 仅诊断且仅执行一次；重试 `loop` 每轮重新执行**完整 3-work-window** 集合（每窗独立 `GC.collect`/`GC.disable`→测 N 次→记 delta）并取 `delta_work=max` 后判定（`spec/text_ft_zero_alloc_spec.cr:58-83`，`spec/core_node_zero_alloc_spec.cr:127-152`，`spec/render_dirty_into_spec.cr:107-132`，`spec/glyph_atlas_spec.cr:175-204`，`spec/text_renderer_spec.cr:211-232`，`tools/zero_alloc_frame.cr:128-159`）。
  - **最多 1 次重试**：`attempt=1` 起，首轮失败且 `attempt<2` 时置 `retried=true, attempt=2` 再测一轮；再次失败走 `attempt>=2` 失败分支（`...:78-82`/`:147-151`/`:127-131`/`:199-203`/`:227-231`/`:153-157`）。
  - **`GC.enable` 在 ensure**：各 work 窗（及 prime/calib）均 `ensure GC.enable`（如 `spec/text_ft_zero_alloc_spec.cr:34-36,52-54,70-72`；其它 spec 同模式；`tools/zero_alloc_frame.cr:101-103,119-121,146-148`）。
  - **第二次仍失败必须 fail**：spec 探针显式 `fail "..."`；`spec/text_renderer_spec.cr:233` 另有 `(delta_work < n && delta_work <= 256).should be_true` 兜底断言；tool 返回失败结果并由调用方判 `criterion_ok`/exit 1（`:205-223`）。
  - **诊断打印 `retried/attempt`**：各 spec `puts ... retried=#{retried} attempt=#{attempt}`；tool JSON/文本均输出且失败 note 带 `retried/attempt`（`:211-222`）。
  - **未缩短 N、未跳过断言/判据**：spec `n=1000` 常量全程不变；tool `frames` 固定用于 `delta_work < frames && delta_work <= 256`；通过才 `break`，失败不放行。
- 结论：**重试实现合法，未见放水路径**（仅对 GC 簿记噪声做 1 次整窗去噪，判据阈值/N/断言与 ensure 语义均保留）。

### 3) P3 定性：`"لا"` (U+0644 U+0627) 在 msyh 16px `drawable=0`
- 独立实测（只读脚本，HB shape + 独立 FT face `LOAD_RENDER` + rasterizer placements，对照 arial/times）：
  - **msyh 16px**：`glyph_ids=[0,0] advances_px=[11.15625,11.15625] meas_w=22.3125 meas_h=21.0 placements=2 drawable=0 sum_adv=22.3125`；逐字形 `gid=0 hb_adv=11.15625 ft=SKIP bitmap_w=0 bitmap_h=0`（两字形均为 gid 0 / .notdef，无可栅格化轮廓）。
  - **msyh 24px**：`glyph_ids=[0,0] advances_px=[16.734375,16.734375] meas=33.46875x32.0 placements=2 drawable=0`，gid 0×2。
  - **msyh 32px**：`glyph_ids=[0,0] advances_px=[22.3125,22.3125] meas=44.625x42.0 placements=2 drawable=0`，gid 0×2。
  - **arial 16px**：`glyph_ids=[1019]`（合字为单形）`advances_px=[8.703125] meas=8.703125x18.0 placements=1 drawable=1`；`gid=1019 ft_err=0 bitmap_w=9 bitmap_h=10 pitch=9 pixel_mode=2 bitmap_left=0 bitmap_top=11 slot_adv26_x=576`。
  - **arial 24px**：gid 1019，bitmap 13x16 pitch13 bl0 bt17 slot_adv26_x=832 hb_adv 13.0546875，drawable=1。
  - **arial 32px**：gid 1019，bitmap 16x21 pitch16 bl1 bt23 slot_adv26_x=1088 hb_adv 17.40625，drawable=1。
  - **times 16/24/32px**：与 arial 同 gid/bitmap/advance/位移（16: 9x10, 24: 13x16, 32: 16x21，均 drawable=1）。
- 结论：**msyh 在 16/24/32px 下将 “لا” 整形为 `glyph_id=0`（无有效字形映射/.notdef），故无 FT 位图、drawable=0；属字体覆盖/整形映射缺失，非光栅化 bug**。同串在 arial/times 下整形得有效 gid 且 `FT_Load_Glyph(..., LOAD_RENDER)` 产出有效 bitmap（w/h>0）并可绘制，advance/placement 链路正确。

### 增量结论（三点）
1. 全量 `crystal spec` 3/3 绿（149/0f，EXIT=0，`retried=false attempt=1`），未复现 `delta_work` 编译错误；P1 确认为时点竞态。
2. 5 探针 + `tools/zero_alloc_frame.cr` 重试实现合法（同 it 整 3 窗重测、≤1 次、ensure GC.enable、二次失败必 fail、打印 retried/attempt、N/判据/断言未放水）。
3. `"لا"` msyh 16/24/32 `gid=0` 无位图（drawable=0、advance 正常）；arial/times 16/24/32 `gid=1019` 有有效位图且 drawable=1——**字体缺字形映射，非光栅化 bug**。
