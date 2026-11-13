# verify-M2-WP2b（M2 字形图集装箱/UV 稳定性/淘汰契约/零分配核验）

- 任务：task-52 核验 M2-WP2b
- 核验人：dalisi-qing-2（只读核验 + 重跑 + 本报告；未修改 src/spec/其它 docs）
- 时间：2026-11-13（Asia/Shanghai，会话内执行）
- 环境：Windows, Crystal 1.22.1, MSYS2 ucrt64 gcc (Rev6) 16.2.0；运行前 `$env:PATH="C:\msys64\ucrt64\bin;$env:PATH"`
- 对象：`src/tessell/text/glyph_atlas.cr`、`spec/glyph_atlas_spec.cr`（HEAD=76ef5d6 基线核验，工作区含未跟踪 glyph_atlas 相关文件按仓库现状核验）
- 元信息：最终行数见本报告末尾（read 工具口径）；本报告由 dalisi-qing-2 在 76ef5d6 基线核验

## 1) 契约真实性（帧内禁止淘汰 / invalidate_font / lookup LRU tick）
**代码事实**（`src/tessell/text/glyph_atlas.cr`）：`begin_frame`/`end_frame` 维护 `@in_frame` 计数（:158-168）；`evict_lru` 在帧内直接 `raise FrameEvictionError`（:220）；`ensure_capacity_for_insert` 在满且帧内 raise（:248-250），帧外调用 `evict_lru(1)`（:251）；`invalidate_font` 遍历 cache 收集 `font_id` 匹配 key 后逐个 `remove_key` 并返回数量（:208-217）；`lookup` 命中时更新 `e.tick=@tick; @tick+=1` 并写回（:174-181）；`insert` 命中已有 key 同样刷新 tick 并返回原 slot，不重分配（:185-190）。

**独立脚本 `bin/_va.cr`（crystal run，EXIT=0，脚本已删除）**：
- 帧内 `evict_lru(1)`：`FRAME_EVICT_LRU=FrameEvictionError msg="evict_lru called inside frame"`，`FRAME_EVICT_LRU_RAISED=true`
- 帧内容量触发淘汰（capacity=2，已满再 insert）：`FRAME_EVICT_CAP=FrameEvictionError msg="LRU eviction during frame is forbidden"`，`FRAME_EVICT_CAP_RAISED=true`；`end_frame` 后 `IN_FRAME_AFTER_END=false`
- `invalidate_font(1)`（font1 两条 + font2 一条）：`INVALIDATE_FONT_EVICTED=2 l1_1_nil=true l1_2_nil=true l2_1_nil=false ev_total=2`
- `lookup` 更新 LRU tick（capacity=2，插入 k1/k2，`lookup(k1)`，再插入 k3 触发淘汰）：`LOOKUP_TICK k1_nil=false k2_nil=true k3_nil=false`（最少使用的 k2 被淘汰，证明 lookup 刷新了 k1 的 tick）

结论：帧内禁止淘汰契约真实生效（主动/容量触发均抛 `FrameEvictionError`）；`invalidate_font` 定向清理且计数正确；`lookup` 确实更新 LRU tick。

## 2) 装箱独立性（200 随机尺寸）
**独立脚本 `bin/_va.cr`**：`GlyphAtlas.new(1024)`，Random seed 67890，插入 200 个随机字形 `w,h ∈ [4,120]`，独立验证：
- 两两不重叠（同页内矩形不相交）
- 不越界（`x>=0,y>=0,x+w<=1024,y+h<=1024`）
- shelf 条带检查：同页 y 范围重叠处 x 必须不相交（与矩形不重叠一致；不同字形高度可同 shelf y 不同 h，非错误）
结果：`RANDOM200 ok count=200 pages=2`（EXIT=0）

与项目 `spec/glyph_atlas_spec.cr` 的 50 个用例独立（另 seed/实现）。结论：通过。

## 3) UV 稳定性（扩容后旧槽逐字节不变）
**独立脚本 `bin/_va.cr`**：page_size=256，先插入 30 个基准字形并向各槽矩形写入确定性字节图案并快照；随后插入 80 个新字形触发新 shelf/新页扩容（`pages_before=2 pages_after=6 base=30`），逐字节比对旧槽 (page,x,y,w,h) 与内容。
结果：`UV_STABLE=true mismatch=0 pages_before=2 pages_after=6 base=30`
结论：扩容/新增 shelf/新增页后旧槽坐标与字节内容稳定不变。

## 4) 剔除正确性（容量 8，淘汰顺序，page_count 不增/页复用）
**代码事实**：`remove_key` 淘汰后 `page.live_count -= 1`，当 `live_count <= 0` 时 `page.reset!` 并将页索引加入 `@free_page_indices` 以供复用（:266-279）；`acquire_page` 优先 pop 空闲页复用（:302-311）；容量触发仅 `evict_lru(1)`（:251）。

**独立脚本 `bin/_va.cr`**：
- capacity=8，插入 k0..k7，touch k1..k7（k0 成为 LRU），插入 k8：`EVICT8 k0_nil=true k1_nil=false k8_nil=false page_count=1 evicted_total=1`（淘汰最少使用项 k0）
- 全部 evict 后插入新 key：`PAGE_REUSE page_before=1 page_after=1 evicted_total=9`（`page_count` 不增长，页字节复用生效）
- capacity=3，小图集场景：插入3个，touch k1/k2（k0 为 LRU），插入 k3：`EVICT3 victim0_nil=true page_count_before=1 page_count_after=1`

结论：帧外按 LRU 淘汰顺序正确；淘汰后页可复用、`page_count` 不增长。满足“容量 8…淘汰顺序正确且淘汰后 page_count 不增（页字节复用）”。

## 5) 零分配（spec 5 次 + lookup 命中探针 3×1000）
- `crystal spec spec/glyph_atlas_spec.cr` 连跑 5 次（`$env:PATH="C:\msys64\ucrt64\bin;$env:PATH"`），取末行：
  - run1: `Finished in 5.33 milliseconds` / `10 examples, 0 failures, 0 errors, 0 pending` EXIT=0
  - run2: `Finished in 6.04 milliseconds` / `10 examples, 0 failures, 0 errors, 0 pending` EXIT=0
  - run3: `Finished in 6.09 milliseconds` / `10 examples, 0 failures, 0 errors, 0 pending` EXIT=0
  - run4: `Finished in 5.83 milliseconds` / `10 examples, 0 failures, 0 errors, 0 pending` EXIT=0
  - run5: `Finished in 5.87 milliseconds` / `10 examples, 0 failures, 0 errors, 0 pending` EXIT=0
  统计：5/5 通过，未见 GC flake / 非 0 delta 失败。
- 独立 GC 探针（`bin/_va.cr`，预热+GC.collect，GC.disable 下 3 次各 1000 次 lookup 命中）：`PROBE run=0 delta=0`，`PROBE run=1 delta=0`，`PROBE run=2 delta=0`（EXIT=0）

结论：lookup 命中路径在探针口径下 0 分配，稳定。

## 6) 边界（w=0/h=0、超大字形、负 subpixel、重复 key 不同尺寸）
**独立脚本 `bin/_va.cr`**（page_size=64）：
- `w=0,h=0` insert：`ZERO_00 ok page=0 x=0 y=0 w=0 h=0 used=0 pc=1`
- `w=0,h=10`：`ZERO_0H ok page=0 x=0 y=0 w=0 h=10`
- `w=10,h=0`：`ZERO_W0 ok page=0 x=0 y=0 w=10 h=0`
  行为：可插入、占用像素计数 0，坐标有效；不破坏已有槽（后续操作正常）。实现未显式拒绝 0 尺寸（由 shelf 放置逻辑接受）。
- 重复 key 不同尺寸：同一 key 先 insert(8,8) 再 insert(20,20)，`DUPKEY same=true w1=8 h1=8 w2=8 h2=8`（命中已有 key 时刷新 tick 并返回原 slot，忽略新尺寸，符合 UV/稳定性语义）。
- 负 subpixel：`GlyphKey` 参数类型为 `UInt8`，Crystal 类型系统在编译期强制（脚本记录 `SUBPIXEL_NEG type_enforced=UInt8_param`）；运行期传入 255_u8 可正常：`SUBPIXEL_255 ok sp=255 x=8`。
- 超大字形（> page_size）：w=65 `OVERSIZE_W ex=Exception msg="Glyph (65x10) does not fit in empty page of size 64"`；h=65 `OVERSIZE_H ex=Exception msg="Glyph (10x65) does not fit in empty page of size 64"`（`place` 在新空页仍放不下时 raise，:296-299）。
- 超大失败后已有槽完整性：先插入 pre(10,10)，再插入 100x100 触发异常；`OVERSIZE_INTACT pre_nil=false same=true pc_before=1 pc_after=2`（异常抛出，但实现已 `acquire_page` 追加空页使 `page_count` 增长至 2；旧槽坐标与可查询性未破坏）。

结论：行为总体明确；超大字形通过异常拒绝且不破坏已有槽，但失败路径会遗留一个已分配空页（见 P3-1）。

## 7) 重跑（crystal spec / build / zero_alloc_frame）
- `crystal spec`（PATH 含 `C:\msys64\ucrt64\bin`）：`127 examples, 0 failures, 0 errors, 0 pending`，`Finished in 67.4 milliseconds`，EXITCODE=0（与预期 127 一致，未见 GC flake）
- `crystal build src\tessell.cr`：EXITCODE=0；`tessell.exe` 已删除（cleanup 记录 `deleted tessell.exe`）
- `crystal run tools/zero_alloc_frame.cr`：`scenario=static frames=200 nodes=205 alloc_bytes=0 delta_zero=true`，`scenario=paint1 frames=200 nodes=205 alloc_bytes=0 delta_zero=true`，EXITCODE=0

## 8) 断言有效性
逐条评估 `spec/glyph_atlas_spec.cr`（10 examples）：
1. **50 随机尺寸不重叠/不越界**：强（pairwise 重叠+边界全检，seed 固定）；但样本 50、尺寸 8..96，覆盖有限。
2. **同 key lookup/insert 幂等且 used_pixels 不增**：较强（验证坐标、页、used_pixels）；未验证 tick 行为。
3. **扩容后旧槽坐标稳定**：中等（只比对 page/x/y/w/h，未验证字节内容未被改写；本核验 step 3 补了逐字节校验）。
4. **GlyphKey 相等/hash 与不同 subpixel/flags/font_id 区分**：较强（==/hash 一致性 + cache 区分存储）。
5. **invalidate_font 仅清目标 font 且计数**：较强（计数+他 font 仍在）；未验证被清页复用细节。
6. **帧内 evict_lru/容量触发均抛 FrameEvictionError**：强（契约关键路径覆盖）。
7. **zero-alloc lookup 命中 1000 次 delta==0**：强但环境敏感（GC 探针），本次 5 次 spec + 独立 3×1000 均稳定。
8. **dense 小字形 waste_ratio < 0.5**：中等偏弱（阈值宽松，仅测 >/<0.5，未测紧凑度上界/具体比率）。
9. **page_data/slot_rect API 暴露**：弱（只测 size==page_size 与 rect 字段回显，未验证数据读写正确性）。
10. **帧外 LRU 淘汰与页复用 page_count 不增**：较强（访问序决定 victim，且验证 evict 后再插入 page_count 不变）；但 page_size=128、容量 2 场景单一。

未覆盖/依赖实现细节：未测 w/h=0、超大字形、负/边界 subpixel 类型、插入不同尺寸同 key 时的尺寸参数忽略语义、超大失败后的空页残留；capacity=8 明确访问序淘汰在 spec 中间接覆盖较少（本核验 step 4 补充）。

## 缺陷清单
- P1: 无
- P2: 无
- P3-1（低/健壮性）：超大字形插入失败路径可能遗留空页。`place` 在所有现有页放不下时先 `acquire_page` 分配并 append 新页（`src/tessell/text/glyph_atlas.cr:293,302-311`），若新空页仍无法容纳则直接 `raise`（:296-299），未回滚该空页或将其归还 `@free_page_indices`。复现：`GlyphAtlas.new(64); insert(10,10); insert(100,100) rescue` → `page_count` 由 1 变 2 且旧槽完好（本核验 step 6: `OVERSIZE_INTACT pre_nil=false same=true pc_before=1 pc_after=2`）。影响：异常输入可造成 `page_count`/内存单调增长（非静默破坏已有槽）；正常尺寸不触发。
- P3-2（观察）：`w=0`/`h=0` 可被接受并进入 cache/shelf（used_pixels 计数 0），行为未在 spec/注释中约束；当前不破坏既有槽但语义可再明确。`insert` 命中已有 key 时忽略新传入的 w/h/bearing/advance（返回旧 slot，:185-190），调用方若期望更新尺寸会被静默忽略（与 key 语义一致，但可文档化）。

## 裁定
- **PASS-WITH-DEFECTS**（P1 无，P2 无，P3 两项见上）
- 理由：帧内淘汰契约（主动与容量触发）真实抛 `FrameEvictionError`；`invalidate_font` 定向且计数正确；`lookup` 更新 LRU tick 决定淘汰顺序；200 随机尺寸独立装箱无重叠/无越界；UV 在扩容/新页（2→6 页，30 基准槽）后逐字节稳定；容量 8 与容量 3 场景淘汰最少使用项且页复用使 `page_count` 不增；lookup 命中 3×1000 次 delta=0 且 glyph_atlas_spec 5/5 通过；全量 spec 127/0、build 与 zero_alloc_frame 两场景 0 分配均通过。P3 为超大字形失败遗留空页及 0 尺寸/重复 key 尺寸忽略等边界语义问题，未致静默破坏既有槽。
- 复现命令索引：`$env:PATH="C:\msys64\ucrt64\bin;$env:PATH"; crystal spec spec/glyph_atlas_spec.cr`；`crystal spec`；`crystal build src\tessell.cr`；`crystal run tools/zero_alloc_frame.cr`；独立验证见本报告所述 `bin/_va.cr`（已按纪律删除，可按各 step 逻辑重建）。
