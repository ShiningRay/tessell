# M2-WP2 彩色 Emoji 独立核验（COLR/CPAL → RGBA → GL_RGBA）

行数：80（实测）
HEAD：`595802b`；工作区 13 个待提交文件（9 M + 4 ??）；未 commit。
方法：只读 + 独立重跑 + 一次性探针；未改被核验文件；临时 `bin/_v_color_neg.cr` 已删。

## 0. 裁定

**PASS-WITH-DEFECTS（P1 无；P2 一项；P3 三项）**。
彩色路径真实、混合只乘一次、批次不串色、R8 未破坏、三项 M3 回归通过。
P2 为证据文档的零分配窗口值与实测不完全一致，不影响彩色功能。

## 1. 独立重跑

| 项 | EXIT | 关键结果 |
|---|---:|---|
| `crystal spec` | 0 | 246 examples, 0 failures, 0 errors, 0 pending |
| `crystal build src/tessell.cr` | 0 | 2,280,466B；产物已删 |
| `--emoji-color --frames=30 --verify` | 0 | 1347/1257；dominant 255,176,46；batches=1；ratio .9302486 |
| `--emoji --frames=30 --verify` | 0 | pixels=1171；ratio .9629934；match=true |
| `spec/text_emoji_color_spec.cr` | 0 | 7/0/0/0；`ZERO_ALLOC_COLOR` 见 §3 |
| 三个 R8 spec | 0 | 32 examples, 0 failures |
| `tools/zero_alloc_frame.cr` | 0 | static 16B；paint1 0；criterion_ok=true |
| M3 dpi/dirty/scroll | 0 | 三项均 `verify=pass` |

## 2. 八项必核

1. **彩色真实性：通过。** `count_color_stats` 用读回像素 `max-min>30`，读的是
   `--emoji-color` 绘制后的 `glReadPixels`（`examples/m2_text_window.cr:170-191,420-428`）。
   独立反证：灰度 `rasterize` 同一串 `😀👍` → `colored=0`；彩色路径同串 → `colored=1256`。
2. **颜色来源：通过。** `color_glyph.cr:150` 逐层 `resolve_color`，`:212-217` 取
   CPAL `pal[color_index]`；`FT_COLOR_FOREGROUND` 才回退 `fg`。`src/` 硬编码
   `255,176`/`0xFFB02E` 扫描 **0 命中**；`color_glyph_spec` 输出 `dominant_rgb=(255,176,46)`。
3. **混合只乘一次：通过。** RGBA 页 `glTexImage2D(... GL_RGBA, GL_RGBA ...)`
   （`gl_backend.cr:238-241`）；色批次 `glColor4f(1,1,1,1)`（`:301`）；R8 仍
   `GL_INTENSITY` + 顶点调制（`:213-216`）。全文件 `glBlendFunc` 实调用仅 1 处
   （`:179`，`ONE, ONE_MINUS_SRC_ALPHA`；`:71` 是 FFI 声明）。
4. **不串色：通过。** `text_renderer.cr:182-196` 在 `page` 或 `color` 变化时 flush；
   `TextBatch.color` 区分纹理/色调。`spec it4` 断言 `"A😀"` ≥2 批且灰批不在彩批之后。
5. **R8 旧语义：通过。** R8/ RGBA 计数器、cache、page 数组分离
   （`glyph_atlas.cr:143-156,188-194,223-249`）；`page_count`/`used_pixels` 仍 R8-only。
   `glyph_atlas`/`rasterizer`/`text_renderer` 32/0；旧 `--emoji` 1171 与基线一致。
6. **零分配口径：通过，文档有偏差。** `text_emoji_color_spec.cr:94-135` 有 3 窗、
   `GC.enable` 在 `ensure`、打印 `windows`；无重试（≤1，允许）。
   `tools/zero_alloc_frame.cr` 两场景与自报一致。
7. **M3 回归：通过。** DPI J1 1605/3079/5094、J5 diff=0；dirty diff=0/4<57；
   scroll `[0,0,0]`/diff=0，均 `verify=pass`。
8. **文档一致性：部分。** 61 行、246/7、1171、1347/1257、dominant、DPI 数值均对；
   唯一不符见 P2-1。

## 3. 缺陷

**P2-1** `docs/evidence/M2-WP2-emoji-color.md:28` 写
`ZERO_ALLOC_COLOR windows=[0,0,0] max=0`。本轮 3 次重跑为
`[16,0,0]`、`[16,0,0]`、`[0,0,0]`（max 16/16/0）；A/B 仍过（16<1000、≤256）。
文档应记录“单次观测/窗口波动”，不能把一次全零写成固定结果。
**P3-1** 同文档 `:34` 回归只列 DPI；dirty/scroll 未列（本轮已补跑，均 pass）。
**P3-2** `examples/m2_text_window.cr:193` 的 `a_opaque_ratio` 用硬编码白色背景
判定 non-bg；当前白底成立，换底色会失真。
**P3-3** 真实窗口人工目视未做（`M2-WP2-emoji-color.md:53` 已列为 `[未验证]`）；本轮仅数值回读。

## 4. 独立探针原始输出

```text
NEG_GRAY placements=2 nonbg=1216 colored=0 rgba_pages=0
POS_COLOR placements=2 nonbg=1448 colored=1256 rgba_pages=1
NEG_PASS=true
```

## 5. 结论

彩色 Emoji **可以**写进 README/终审报告为“已完成”，但必须带限定：
**Windows + seguiemj.ttf 单一样例 + COLRv0/CPAL + glReadPixels 数值验证**；
R8 灰度路径保留，旧 `--emoji` 1171 不回退。不得写成“Emoji 全域支持”、
“跨平台彩色”或“严格零分配”。P2-1 修文档后，彩色项可作为已完成交付。

## 6. 限制

仅本机 Windows/WGL/GL1.1、单驱动、单字体；未做真实窗口人工目视、
COLRv1/SVG、非 Segoe 彩色字体、128px 上屏。上述均属文档已列 `[未验证]`。
