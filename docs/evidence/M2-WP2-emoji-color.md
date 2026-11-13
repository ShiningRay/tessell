# M2-WP2 Emoji 彩色上屏（COLR/CPAL → RGBA atlas 页）证据

HEAD `595802b` + task-134 工作区改动（未 commit）。日期 2026-11-14。阶段：task-133 纯逻辑/测量之后的上屏收口。

## 1. 范围（六项目标）

1. `GlyphAtlas` 增 RGBA 页（1024²、预乘 4B/px），与 R8 页独立计数；`page_count` 语义不变（R8 专用），新增 `rgba_page_count` / `rgba_page_data` / `insert_rgba` / `lookup(key, color)`。
2. `GlyphPlacement` 加 `color : Bool`（默认 false，向后兼容）。
3. `TextBatch` 加 `color : Bool`（默认 false）；`TextRenderer` 仅在「同页 + 同色型」合并。
4. `GLBackend#sync_atlas`：R8 仍 `GL_INTENSITY`+顶点调制；RGBA 页 `glTexImage2D(..., GL_RGBA, ...)` 原样上传预乘；色批次 `glColor4f(1,1,1,1)` 不再二次乘；`resolved_texture(page, color)` 双形态。
5. `examples/m2_text_window.cr` 增 `--emoji-color`（旧 `--emoji` 不动）。
6. 彩色稳态零分配判据 A/B 同口径。

## 2. 结构（改动文件）

| 文件 | 改动 |
| --- | --- |
| `src/tessell/text/glyph_atlas.cr` | `Page` bpp（1/4）；`@rgba_pages`/`@rgba_cache`/`@rgba_free_page_indices`；`insert_rgba`/`place_rgba`/`acquire_rgba_page`；`try_place_in_page(..., color)`；`GlyphSlot.color`；evict/invalidate/remove 跨双 cache；R8 断言与阈值未动 |
| `src/tessell/text/rasterizer.cr` | `GlyphPlacement.color`；`Rasterizer.new(..., color_enabled=false)` opt-in；`rasterize_glyph` 彩色分支（COLR/CPAL → `ColorRasterizer` → `insert_rgba` → `copy_rgba_to_atlas`）；`coverage` 按色型分派 |
| `src/tessell/render/text_renderer.cr` | `TextBatch.color`；flush 条件 `page != cur || color != cur_color` |
| `src/tessell/render/backend.cr` | 具体 `resolved_texture(page, color)` 默认回落 R8（abstract 不破） |
| `src/tessell/render/gl/gl_backend.cr` | `@rgba_page_texture_ids_arr`；`sync_atlas` R8+RGBA 双上传；绘制按 `b.color` 选纹理与 `glColor4f`；`delete_textures` 双数组 |
| `examples/m2_text_window.cr` | `--emoji-color` 分支 + `count_color_stats` + `compute_cpu_coverage_sum` 色型分派 |
| `spec/text_emoji_color_spec.cr` | 新建 7 例（含稳态零分配探针） |

## 3. 实测原始行

- `crystal spec spec/text_emoji_color_spec.cr`（2026-11-14 03:32 CST，gongbu-shangshu-3）→ `7 examples, 0 failures, 0 errors, 0 pending` EXIT 0；输出 `ZERO_ALLOC_COLOR windows=[0, 0, 0] n=200`（典型观测）。核验方 3 次重跑 `windows` 为 `[0,0,0]`/`[16,0,0]`/`[16,0,0]`（max∈{0,16}），均在判据 A(`<N`) B(`<=256`) 内。16B 级偶发增量为 Boehm `GC.stats.bytes_since_gc` 簿记噪声，可落任意测量窗（见 `docs/evidence/M2-WP2c-zero-alloc-criterion.md`），不得声称严格 0。探针：shape_run_into 彩命中 + TextRenderer 稳态循环，warmup 40 + 2 prime 窗丢弃 + 3 测量窗 + GC.enable in ensure。
- `crystal spec` → `246 examples, 0 failures, 0 errors, 0 pending` EXIT 0（基线 239 + 新 7）。
- `bin/m2_text_window.exe --emoji-color --frames=30 --verify` EXIT 0（2026-11-14 03:32 CST 复跑）：
  `emoji_color_quads=2 emoji_color_pixels=1347 emoji_color_pixels_colored=1257 emoji_color_dominant_rgb=255,176,46 emoji_color_batches=1 emoji_color_verify=true a_opaque_ratio=1.0 emoji_color_ratio=0.9302486187845304 cpu_cov=1448 mixed_pixels_nonbg=3115 frames=30 swapbuffers=30 pen_after_emoji_x=127.875 text_quads=7 frame_p50_ms=3.0027 frame_p95_ms=4.5045 frame_p99_ms=17.457`
- 旧 `--emoji` 不回归：`emoji_quads=2 emoji_pixels_nonbg=1171 emoji_pixel_match=true ... emoji_cpu_coverage_sum=1216 emoji_ratio=0.9629934210526315` EXIT 0。
- `tools/zero_alloc_frame.cr --frames=200`：static `alloc_bytes=16 windows=[0,16,0] criterion_ok=true retried=false attempt=1`；paint1 `alloc_bytes=0 windows=[0,0,0] criterion_ok=true retried=false attempt=1`。
- 回归：`examples/m3_dpi_theme.cr -- --frames=20 --verify` 三档 verify=pass（J1 r15=1.918380 r20=3.173832；J5 diff_pixels=0 diff_A_vs_C=1180）EXIT 0。核验方补跑（`docs/evidence/verify-M2-WP2-emoji-color.md`）`m3_dirty_window --frames=20 --verify`、`m3_scroll_window --frames=60 --dy=20 --verify` 均 EXIT 0 / verify=pass。
- `crystal build src/tessell.cr` BUILD_EXIT=0，产物已删。

## 4. 判据对照

- ① RGBA 页独立：`rgba_page_count` 单调增长、`page_count` 不变（`glyph_atlas_spec` 12 例全绿，含 UV 稳定/RANDOM200/帧内禁淘汰）。
- ②③ 色型字段默认 false：旧 `--emoji` 像素数 1171 与基线逐字节一致。
- ④ 色批次不二次乘：`glColor4f(1,1,1,1)` + 预乘纹理；主色 `255,176,46` 与 CPAL 调色板层色一致（task-132/133 探针同值）。
- 通路图：COLR 层（`FT_Get_Color_Glyph_Layer` 灰度 mask + CPAL 颜色）→ 逐层 tint 预乘 → source-over 合成 `ColorBitmap`（预乘 RGBA）→ `insert_rgba` 写 RGBA 页 → `glTexImage2D(GL_RGBA)` 原样上传 → `glBlendFunc(GL_ONE, GL_ONE_MINUS_SRC_ALPHA)`。
- 混合只乘一次推导：合成阶段片元 `f=(c·a, a)`（`color_glyph.cr` 已乘 a）；纹理原样上传不再乘；blend src=GL_ONE ⇒ 输出 `c·a + b·(1−a)`，a 仅参与一次乘法；对照 task-103 前 INTENSITY+SRC_ALPHA 的 I² 双乘已修。
- ⑤ `--emoji-color` token 全字段；判据 `color_pixels>0 && colored>0 && a_opaque_ratio>0.5 && ratio∈[0.5,1.5]` 全过。
- ⑥ 零分配：两场景 `criterion_ok=true`（A `delta<1000` B `<=256`）；彩路径直接证据 spec it7 典型观测 `windows=[0, 0, 0] n=200`，核验 3 次波动 `[0,0,0]`/`[16,0,0]`/`[16,0,0]`（max∈{0,16}，均 A/B 内）；16B 偶发为 Boehm `GC.stats.bytes_since_gc` 簿记噪声，可落任意窗（`docs/evidence/M2-WP2c-zero-alloc-criterion.md`），不声称严格 0。

## 5. 灰彩混排串色结论

不串色。机制：placement.color → TextRenderer 按 (page, color) flush → GLBackend 按 b.color 选纹理数组；色批次 `glColor4f(1,1,1,1)`、灰批次逐顶点色调制，两条路径纹理目标不同。spec it4 断言 `"A😀"` ≥2 批、灰批永不排在彩批之后且顺序灰→彩。例：mixed 帧 3115 非背景像素由两张独立纹理各自贡献，emoji_color_ratio=0.930 与旧 emoji_ratio=0.963 分开核算。

## 6. 未验证（需要什么才能验证）

- 真实窗口人工目视：需带显示器的交互会话；本机仅 glReadPixels 数值。
- COLRv1/SVG 字形：需对应字体与 FreeType 版本支持；seguiemj.ttf 为 COLRv0+CPAL。
- 非 Segoe 彩色字体（如 Noto Color Emoji）：未在本机出现，未测。
- 128px 大尺寸上屏：spec 覆盖光栅不崩，上屏未跑。

## 7. 已知副作用（非缺陷）

`a_opaque_ratio=1.0`：预乘混合下画布不透明（alpha 恒 1），与 task-103 裁断一致，已文档化。
- 多层同色叠加 alpha 误差：同色多层 source-over `a_out = a1 + a2·(1−a1)`，边缘抗锯齿可产生 ±1 通道级舍入；实现逐层 mask 精确合成、未做层间去重，误差上限为单层 1/255 累积。判据 max-min>30 不受影响（实测 colored=1257）。[未验证] 精确误差上界未逐像素测量，需对多层同色字形做逐通道 diff 才可量化。
