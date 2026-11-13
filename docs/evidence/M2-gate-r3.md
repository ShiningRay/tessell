# M2 门禁终裁（task-91）

- 复核起点 HEAD=`4cc928a`；复核期间 `991b663`（C2/C3 整改）与 `b4f91fb`（hash 回填）已提交，末态 HEAD=`b4f91fb`，`origin/main` 同值。
- `git diff 4cc928a..HEAD -- src` 为空；C2/C3 只改 docs/tools。工作区仅 `?? docs/research/m3-platform-matrix.md`（他人产物，未碰）；本报告仅新增。
- 只读核验 + 独立重跑；一次性 `bin/_g3.cr` 用后已删；未 commit。

## 0. 三句结论

1. **C2：未完全关闭（部分）**。8/8 探针齐全、EXIT 0；但 `page_reuse` 只断言 `page_count` 不增，不能证明“空闲页被复用”，已构造反证。
2. **C3：关闭**。§4.2 九行与原文 9/9 逐字节一致；§3.1 waiver 满足；第 22 行旧数已标注；P1-1 已恢复原文。
3. **M2 最终裁定：Go-with-conditions**。C2 的 `page_reuse` 断言/契约修正后放行 M3；C5/C7/C8/C9 按 WP 关闭。

## 1. 独立重跑（HEAD b4f91fb）

- `crystal run tools/atlas_raster_verify.cr`：EXIT 0；9 行输出与 WP2b §3.1 一致（frame_eviction、invalidate_font、lru_tick、RANDOM200、UV_STABLE、page_reuse、lookup、shaped_run）。
- 全量 `crystal spec`：EXIT 0；`186 examples, 0 failures, 0 errors, 0 pending`；text_ft `delta_work=16`、text_renderer `48 [32,32,48]`、virtual_list `0 [0,0,0]`。
- 反证 A（RANDOM200）：改用 256 页宽，`COUNTER_RANDOM200 pages=8 count=200 overlap_ok=true check_would_pass=true`。探针的 check 只算 `ok && count==200`（`:127`），`pages=1` 只是输出、不是判据。
- 反证 B（page_reuse）：page 0 留 100x100 活 glyph，page 1 放 40x40 后整页释放，再插 20x20；输出 `COUNTER_PAGE_REUSE page1_before=1 after_free=2 after=2 new_page=0 check_would_pass=true reused_label=true`。新 glyph 落回活着的 page 0，freed page 1 未被复用，但 `ok = pc_after <= pc_before`（`:195`）仍为 true，`reused=true` 标签失真。

## 2. C2：8 项存在，page_reuse 断言不成立

- 通过项：8 个 verify 函数齐全（`tools/atlas_raster_verify.cr:36-271`）；`placements_equal?` 覆盖 12 字段（`:20-33`）；失败汇总 exit 1（`:287-294`）；全量 186/0。
- 证据列可重跑：§4 指向 §3.1 输出/代码锚点；`76ef5d6` 已降为历史参照（`M2-WP2b.md:4,107,121`）；grep `代码路径未变` 无命中。
- 源码抽查 6/6 相符：`glyph_atlas.cr:85-86`（FrameEvictionError）、`:158-168`（begin/end/in_frame）、`:215-224`（invalidate_font）、`:288-304`（place + 超大预检）；`rasterizer.cr:168-190`（shape_run_into）、`:332-360`（正负 pitch 复制）。
- 缺口：`M2-WP2b.md:98` 写“整页空闲后复用，page_count 不增 | 已验证”，但 `verify_page_reuse` 只证后半句；反证 B 证明前半句可为假而检查仍过。**C2 关闭前必须**：把 `ok` 改为同时断言新 slot 的 page 是被释放页，或把契约收窄为“page_count 不增（不承诺具体页复用）”并删除 `reused=true`。
- 附带：`RANDOM200` 的 `pages=1` 未参与断言（P3）；`page_reuse` 实际场景中 page0 也被释放并复用，所以输出本身不是伪造，问题在“断言强度/标签”。

## 3. C3：关闭

- `Compare-Object` 独立比较 `M2-gate.md` 与 `M2-summary.md` 的 9 行 `^| C[1-9] `：9/9 逐字节一致，`C_ROWS_IDENTICAL=true`。
- §3.1 waiver（`:47-53`）含事实（`alloc_windows=[0,0,0]` 未达、112–160B/1000）、判据（A<1000、B<=256）、机制（7–8 次×16B，Boehm 簿记噪声）、结论（C6 waiver，阻断 M3-WP5）、责任人。
- `:22` 已写新数 112/112B、p50 110/112µs，并把旧 3728/4016B、1199/1195µs 标注“缓存之前，已不适用”；`:16/:35/:41/:42` 已换 112–160B/A/B；`:55` P1-1 已恢复“Emoji 样例未实现、完成度放大”。
- 仅 P3：`:85` 仍写“C1/C2/C3/C4 已交付”，C2 尚未完全关闭；C2 修好后一并改为“C2 待复核/关闭”。

## 4. M3 前残余（Go 的附带条件）

| 条件 | 关闭时点 | 责任人 |
|---|---|---|
| C2 page_reuse 断言/契约 | **M3 开工前** | M2-WP2b / 工部 |
| C5 3 次分位区间 | M3-WP4 前 | M2-WP4 |
| C7 真实键盘 IME | M3-WP3 前 | M2-WP3 |
| C8 UIA / GL 滚动 | M3-WP5 / M3-WP4 对应验收前 | M2-WP5 / M2-WP4 |
| C9 WP2F OFL 文本/哈希 | M3 打包前 | M2-WP2F |

## 5. 本轮新缺陷

- **P2-1（C2，阻断 M3）**：`tools/atlas_raster_verify.cr:195` 的 `ok = pc_after <= pc_before` 不证 page 复用；反证 B 可过。`M2-WP2b.md:98` 的“已验证”超出断言能力。
- **P3-1**：`tools/atlas_raster_verify.cr:127` 的 RANDOM200 未断言 `pages=1`，`pages` 仅输出。
- **P3-2**：`M2-summary.md:85` 的“C1/C2/C3/C4 已交付”与 C2 未完全关闭不一致。
- **P3-3**：`M2-WP2b.md` 的 `read` 计 124 行、`Get-Content` 计 99 行（行尾混用），不影响内容但影响行号引用一致性。
