# verify-M2-WP2c（M2-WP2c 合并核验：光栅写入/advance/复用零分配 + atlas P3 修复 + 零分配探针加固）

- 任务：task-55（合并核验，范围含 task-54/56 结果）
- 核验人：dalisi-qing-2（只读核验 + 重跑 + 本报告；未修改 src/spec/docs 其它文件，未 commit）
- 时间：2026-11-13（Asia/Shanghai，会话内执行）
- 环境：Windows, Crystal 1.22.1 [23828b0a40] (2026-10-23), MSYS2 ucrt64 gcc (Rev6) 16.2.0；运行前 `$env:PATH="C:\msys64\ucrt64\bin;$env:PATH"`；字体 `C:/Windows/Fonts/msyh.ttc`
- 对象：`src/tessell/text/rasterizer.cr`、`spec/rasterizer_spec.cr`；task-54 atlas P3 修复（`src/tessell/text/glyph_atlas.cr`、`spec/glyph_atlas_spec.cr`）；task-56 零分配探针双窗口加固（`spec/core_node_zero_alloc_spec.cr`、`spec/text_ft_zero_alloc_spec.cr`、`tools/zero_alloc_frame.cr`）
- 元信息：最终行数 88（read/UTF-8 行数口径）；本报告由 dalisi-qing-2 在 76ef5d6 基线核验

## A. rasterizer（光栅真实性/负 pitch/offset/advance/复用/零分配）

### A1 光栅真实性（FT_Load_Glyph 标志 / pixel_mode / 逐字节来源）
- 代码事实：`src/tessell/text/rasterizer.cr:142-144` `# FT_LOAD_RENDER... pixel_mode=2`，`err = FT::Lib.load_glyph(face, gid, FT::Lib::LOAD_RENDER)`；`copy_bitmap_to_atlas`（:160-188）逐行逐字节拷贝 `src_row[col] -> dst_page[(slot.y+row)*page_size + (slot.x+col)]`。
- 独立实测（`bin/_vb.cr`，`crystal run`，EXIT=0，脚本已删）："A" 24px：`A24 w=17 h=18 pixel_mode=2 pitch=17 byte_match=true mismatch=0 coverage_api=142 coverage_manual=142 used_pixels=306 slot=page0@0,0`
  - 结论：8bpp gray（pixel_mode==2），图集字节与 FT bitmap 源逐字节一致，coverage 与独立非零计数一致；非硬编码/空白。

### A2 负 pitch 证据与公式
- 代码事实（`src/tessell/text/rasterizer.cr:171-179`）：`if pitch >= 0` 用 `src + row*pitch`，否则 `src + (h - 1 - row) * (-pitch)`（与注释 :171-172 FT 正/负 pitch 语义一致）。
- 独立实测（msyh.ttc, 24px）：`PITCH_SAMPLE ch="g" gid=77 w=13 h=19 pitch=13`，`ch="j" gid=80 w=8 h=25 pitch=8`，`ch="y" gid=95 w=13 h=19 pitch=13`，`ch="p" gid=86 w=13 h=19 pitch=13`，`ch="Q" gid=55 w=19 h=20 pitch=19`，`ch="A" gid=39 w=17 h=18 pitch=17`；`NEG_PITCH_FOUND=false`。
- 结论：抽样未见负 pitch，`pitch<0` 分支**本次未在运行时触达**（[未验证] 真实负 pitch 位图路径）；代码公式与 FT 语义一致，正 pitch 路径已逐字节验证。`spec/rasterizer_spec.cr:96-145` 用同公式做行匹配（`rows_match`）为公式级证据。

### A3 offset 符号（'A','g','j'）与绘制推导
- 代码事实：`src/tessell/text/rasterizer.cr:152-157` 取 `bitmap_left/bitmap_top` 存入 slot；:200-201 透出为 `GlyphPlacement.offset_x/offset_y`。
- 独立实测（24px）：`OFF ch=A off_x=0 off_y=18 bitmap_left=0 bitmap_top=18 w=17 h=18 adv=16.886719`；`OFF ch=g off_x=1 off_y=13 bitmap_left=1 bitmap_top=13 w=13 h=19 adv=15.3515625`；`OFF ch=j off_x=-3 off_y=19 bitmap_left=-3 bitmap_top=19 w=8 h=25 adv=6.4101562`。
- 符号/推导：`offset_x == bitmap_left`（自 pen 向右为正），`offset_y == bitmap_top`（FT: baseline 到 bitmap 顶边的向上距离；'g' 下伸部较小 13，'j' 顶高 19 且左伸 bitmap_left=-3）。绘制（y 向下屏幕坐标）：`glyph_left = pen_x + offset_x`，`glyph_top = baseline_y - offset_y`（y 向上则 `baseline_y + offset_y`）。

### A4 advance 三方一致（HB 26.6 定点/64、rasterize advance_px、FtMeasurer.measure）
- 独立实测：`ADV txt="Hello" hb=40.140625 rast=40.140625 meas=40.140625 maxdiff=0.0`；`ADV txt="你好世界" hb=64.0 rast=64.0 meas=64.0 maxdiff=0.0`（|差值| ≤0.5px，均 0.0）。
- `ADV txt="لا" count=0 hb=22.3125 rast=0.0 meas=22.3125 maxdiff=22.3125`：HB 与 `FtMeasurer#measure` 一致，但 `rasterize` 返回 0 placements、advance 累计 0.0，**该样例三方不一致**（rasterize 侧缺失，msyh.ttc/处理路径下未产出 placement）。
- 结论：Hello/你好世界 三方一致；`لا` 不满足“三处必须一致”。

### A5 复用与不同 size
- 二次 rasterize 同字符：`REUSE hits=0->1 misses=1->1 rasters=1->1 pages=1->1 used=144->144`（hits 增、rasters 不变、atlas 不新页、used_pixels 不增）。
- 不同 size 同 glyph：`DIFFSIZE key_eq=false size16=16 size24=24 same_slot=false w16=12 w24=17`（key 含 size_px，新槽）。

### A6 coverage 与空白字形
- 'A' 24px：`COV_A api=142 manual=142 diff=0`（逐字节复核，差异 0）。
- 空白字形（空格）：`COV_SPACE ex=ArgumentError msg="GlyphAtlas.insert: glyph size must be > 0 (got 0x0)"`。空格位图 w/h 可为 0，`src/tessell/text/rasterizer.cr:155` 直接 insert，task-54 后 `src/tessell/text/glyph_atlas.cr:187-189` 拒绝 0 尺寸并抛 ArgumentError；**空白字形未返回 coverage=0，而是异常**（交互回归/未适配）。

### A7 资源与错误
- 坏字体：`BADFONT ex=Exception msg="FtMeasurer.open: font file not found: C:/Windows/Fonts/DOES_NOT_EXIST.ttf"`（明确）。
- glyph_id=0 (.notdef)：`GID0 count=0`，与 `src/tessell/text/rasterizer.cr:140` “gid==0 … skip (return nil)” 一致。
- 100 次同字符串：`LOOP100 pages=0->1 handles=186->186 delta=0 hits=496 rasters=4`（`atlas.page_count` 稳定为 1，句柄差 0）。

### A8 零分配（`rasterize_into` 命中路径，双窗口）
- 独立探针（sink 复用、全部字形已缓存，prime 1000 次后 steady 1000 次，各自 GC.collect/disable/enable）：`ZEROALLOC rasterize_into N=1000 delta_prime=0 delta_steady=16 delta_1000=16`
- 判据：缓存命中路径 1000 次 delta 必须 0。**实测 delta_steady=16（非 0）**，未满足（本次未定位首个分配点）。

## B. glyph_atlas P3 修复（task-54）
- 代码事实：`src/tessell/text/glyph_atlas.cr:187-189` 0/负尺寸抛 `ArgumentError("GlyphAtlas.insert: glyph size must be > 0 (got #{w}x#{h})")`；:193-198 重复 key 刷新 tick 返回原 slot（忽略新参数）；:303-305 oversized 在 `acquire_page` 前预检并 raise 固定消息，避免遗留空页（修复 P3-1）。
- 独立复跑（`bin/_vb.cr`）：`OVERSIZE raised_class=Exception msg="Glyph (100x100) does not fit in empty page of size 64" pages_before=1 pages_after=1 used_before=100 used_after=100 old_intact=true`；`ZERO raised_class=ArgumentError msg="GlyphAtlas.insert: glyph size must be > 0 (got 0x8)" pages=0 used=0`；`DUP first_wins=true w1=6 w2=6`。
- `crystal spec spec/glyph_atlas_spec.cr`：`13 examples, 0 failures, 0 errors, 0 pending`（Finished 9.52ms, EXIT=0），符合 10+3=13。

## C. 零分配探针加固（task-56）与全量稳定性

### C1 双窗口实现审查
- `spec/core_node_zero_alloc_spec.cr:79-116`：warmup 10 次后 prime 窗口（collect/disable → `1000.times { Node.collect_dirty(root, sink) }` → enable，记 `delta_prime`），再 steady 窗口同参 1000 次记 `delta_steady`；断言 `delta_steady.should eq 0` 且 `delta_prime.should be < 1000_i64`，失败输出三数。`GC.enable` 显式调用但**不在 ensure** 中（异常时窗口内 GC 可能保持 disabled）。
- `spec/text_ft_zero_alloc_spec.cr:20-47`：同构双窗口（`1000.times { c.measure("Hello", 1, 16.0_f32, 0.0_f32) }`，同参数/同 N），`delta_steady==0` 且 `delta_prime < 1000_i64`；`GC.enable` 同样非 ensure，外层仅 `ensure ft.close`。
- `tools/zero_alloc_frame.cr:72-106`：单窗口探针（warmup 10 帧，collect/disable → N 帧 → enable in ensure），报告 `alloc_bytes/delta_zero`；实测两场景 0。
- 强度判断：prime 与 steady 同参数可检出“每次调用都分配且累计 ≥1000B”的情况，但 `delta_prime < 1000` **不能必然捕获所有 per-call 分配**（例如累计 <1000B 的分配、或分布使某窗口偶发漏检）；稳态强约束仍为 `delta_steady==0`。整体属“分离一次性初始化噪声”的加固，未取消 steady==0，但 prime 阈值相对宽松且 GC.enable 无 ensure 保护（健壮性瑕疵）。**未降低 steady 强度，prime 侧非充分必然。**

### C2 独立连跑 5 次全量 `crystal spec`（稳定性）
`$env:PATH="C:\msys64\ucrt64\bin;$env:PATH"; crystal spec`，5 次：
- run1：`138 examples, 1 failure, 0 errors, 0 pending`，`EXIT=1`；失败：`crystal spec spec\text_ft_zero_alloc_spec.cr:12 # Tessell::Text::FtMeasurer zero-alloc via CachingMeasurer CachingMeasurer(FtMeasurer) 1000 cache-hit measures have delta bytes_since_gc == 0`
- run2：`138 examples, 0 failures, 0 errors, 0 pending`（Finished 109.07ms），`EXIT=0`
- run3：`138 examples, 0 failures, 0 errors, 0 pending`（Finished 85.53ms），`EXIT=0`
- run4：`138 examples, 0 failures, 0 errors, 0 pending`（Finished 86.45ms），`EXIT=0`
- run5：`138 examples, 0 failures, 0 errors, 0 pending`（Finished 105.99ms），`EXIT=0`
- 结论：4/5 通过，存在 1 次 flake（text_ft zero-alloc 探针），与“8/8 稳定性宣称”不符。

补充观察：单独 `crystal spec spec/rasterizer_spec.cr` 编译失败 `undefined constant FT::Lib` at `spec\rasterizer_spec.cr:108:5`（EXIT=1）；全量 spec 多数运行计 138 examples（与该现象的交互未进一步定位）。

## 重跑（全量 spec / build / zero_alloc_frame）
- `crystal spec`（全量 5 次）：见 C2（run1 138/1f/EXIT=1；run2-5 138/0f/EXIT=0）。
- `crystal build src\tessell.cr`：`BUILD_EXIT=0`；产物已删除（`deleted_tessell.exe=yes`）。
- `crystal run tools/zero_alloc_frame.cr`：`scenario=static frames=200 nodes=205 alloc_bytes=0 delta_zero=true`；`scenario=paint1 frames=200 nodes=205 alloc_bytes=0 delta_zero=true`；`EXIT=0`。

## 缺陷清单
- **P1**：`rasterize_into` 全缓存命中路径稳态非零分配。`src/tessell/text/rasterizer.cr:85-123,128-131` 热路径在 "Hello"/16 全缓存+sink 复用下实测 `ZEROALLOC rasterize_into N=1000 delta_prime=0 delta_steady=16 delta_1000=16`，违反“1000 次 delta 必须 0”。复现：预热后 GC.collect/disable → 1000 次 `rasterize_into("Hello",16,sink)` → 计 delta。
- **P2**：零分配探针稳定性不足（task-56 目标未达成）。全量 `crystal spec` 5 次 run1 失败 `spec\text_ft_zero_alloc_spec.cr:12`（138 examples, 1 failure, EXIT=1），run2-5 通过（4/5）。
- **P3-1**：空白/零尺寸字形异常。`src/tessell/text/rasterizer.cr:155` 未对 w==0||h==0 分支处理即 `@atlas.insert`，与 `src/tessell/text/glyph_atlas.cr:187-189`（task-54）冲突；空格实测 `ArgumentError "GlyphAtlas.insert: glyph size must be > 0 (got 0x0)"`，非 coverage=0。
- **P3-2**：`"لا"`（msyh.ttc,16）rasterize 返回 0 placements（advance 累计 0.0），而 HB/meas 为 22.3125，三方一致性不成立（样例相关，原因未深挖）。
- **P3-3**：负 pitch 分支 `src/tessell/text/rasterizer.cr:175-179` 本次抽样未触达（`NEG_PITCH_FOUND=false`），运行时正确性 [未验证]。
- **P3-4（观察）**：`spec/rasterizer_spec.cr:108` 单独运行触发 `undefined constant FT::Lib` 编译失败（EXIT=1），与全量运行行为存在差异，需关注。

## 裁定
- **FAIL**
- 理由：A8 `rasterize_into` 命中路径 `delta_steady=16`（N=1000）违反关键零分配判据（P1）；全量 spec 5 次出现 1 次探针失败、稳定性未达宣称（P2）；空白字形触发异常及 `"لا"` advance 三方不一致等问题存在（P3）。通过项：A1 光栅逐字节一致（pixel_mode=2，byte_match/mismatch=0，coverage 142==142）、A3 offset 与 bitmap_left/bitmap_top 符号关系正确、A5 复用与不同 size 新槽正确、Hello/你好世界 advance 三方一致、坏字体/GID0/100 次句柄与页稳定；B atlas P3 修复行为与 `glyph_atlas_spec` 13/0 通过；build 与 `tools/zero_alloc_frame.cr` 两场景 alloc 0。综合判定 **FAIL**。
