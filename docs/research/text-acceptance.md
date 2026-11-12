# M2-WP2/WP3 文本样例集与验收口径（text-acceptance.md）

> 状态：纯调研草案（未实现/未改码）。事实锚定 `文件:行` 或探针/命令输出 token；不可验证标 `[未验证]`；禁编造 API/数值。
> 任务：task-46「M2-WP2/WP3 样例集与验收口径文档」，HEAD=78ee3af（任务书）；采集 2026-11-13 00:38:45 +08:00（会话 time context）。
> 必读锚点：`docs/plan.md:238-247,167,182,224,244-245`；`docs/evidence/M0-WP4-text.md`；`docs/evidence/M0-WP4-ime.md`；`docs/evidence/M1-WP5-zero-alloc.md`；`docs/research/glyph-atlas.md`；`docs/research/font-fallback.md`；`src/tessell/text/measurer.cr:12-41,78-112`。
> 写入范围：仅本文件；未改 `src/`/`spec/`/`tools/`/`examples/`/其他 docs。

## 0) 约束与依据（可执行边界）

- 口径禁止“正确显示”类不可测表述；每条判据须可命令化（token/计数/序列/差值阈值/协议标志）或可明确观测（`docs/plan.md:167,244-245`）。
- 稳态零分配按 M1-WP5：`warmup→GC.collect→before=GC.stats.bytes_since_gc→GC.disable→N帧→after→GC.enable(ensure)`，`alloc_bytes==after-before`，`delta_zero==true`（`docs/evidence/M1-WP5-zero-alloc.md:3-4,26-34,39-51`）；**不得**以 default/首帧/冷启动/扩页/首次 shaping 路径判“通过”（`docs/evidence/M1-WP5-zero-alloc.md:54,57-59`；`docs/research/glyph-atlas.md:51-56,80`；`docs/plan.md:167`）。
- 测量缓存键锚点：`MeasureKey(font_id,size,text_hash,max_width)`，FNV-1a `text_hash`（`src/tessell/text/measurer.cr:12-41`）；失效/命中统计 `hits/misses/evictions`、`invalidate_font/clear`（`src/tessell/text/measurer.cr:78-112`）。glyph/atlas 侧键与失效分层见 `docs/research/glyph-atlas.md:38-45,83-85`。
- 字体/回退：`FontRef{path,ttc_index,...}`、逐字符 `FT_Get_Char_Index>0` 回退与 `font_set_version` 缓存失效提案（`docs/research/font-fallback.md:72-77,81-84`）；开发/发布字体来源与许可边界（`docs/research/font-fallback.md:10-17,47-61,98-103`）。

## 1) 样例集（每条：字符串/字体/期望/可自动断言）

### 1.1 Latin："Hello" 与 "AV" kerning
- 字符串：`"Hello"`（U+0048,0065,006C,006C,006F）；kerning 对照 `"AV"` vs `"A"+"V"`（U+0041,0056）。
- 字体：Latin 基线（如 segoeui.ttf/tahoma.ttf/arial.ttf，固定 `font_id,size`，同一 FontRef/face；来源 `docs/research/font-fallback.md:10-17,22-39`）。M0 探针使用 msyh/segoeui/arial/tahoma/times 等 face 进行 shaping（`docs/evidence/M0-WP4-text.md:8,16-18,111`）。
- 期望字形/序列：glyph_count 与 `glyph_id(HB codepoint)+advance` 序列对同一 `(text,font,face,size,script,dir,lang)` 稳定可复现（模式参照 zh 样本：`zh_glyphs=10`、逐 glyph codepoint/advance 输出，`docs/evidence/M0-WP4-text.md:17,50-69,108-109`）。
- 期望宽度：`measured_width ≈ Σ(HB x_advance_px)`（26.6 定点换算，见 `ft_advance_x26=2048`、`zh_glyph[0].advance=1536` 模式，`docs/evidence/M0-WP4-text.md:51,103,137,152`）；kerning 生效时 `width("AV") != width("A")+width("V")`（方向/幅度与 font/feature 相关）。
- 可自动断言点：glyph 序列快照一致；`|measured_width - sum_advances_px| <= 0.5px`（容差）；`"AV"` 与 `"A"+"V"` 宽度差非零/符号按探针结果记录。
- `[未验证]` "Hello"/"AV" 的具体 glyph id、advance、kerning 差值未实测；需按 `examples/m0_text_probe.cr` 探针模式输出 token 实测。

### 1.2 CJK："你好世界" 与 扩展 B "𠀀"
- 字符串：`"你好世界"`（U+4F60,U+597D,U+4E16,U+754C）；`"𠀀"`（U+20000，CJK Unified Ideographs Extension B）。
- 字体：开发 msyh（`C:\Windows\Fonts\msyh.ttc`），发布 OFL Noto Sans SC（`docs/research/font-fallback.md:13,24,37,57-58,72-77`）。M0 已实测 zh 串 shaping/光栅基础能力（`zh_glyphs=10 zh_advance=1536`，`docs/evidence/M0-WP4-text.md:17,50-51,108-109,136-137`）。
- 期望字形：`"你好世界"` 4 个 codepoint → 4 glyph（不换行约束下）；"你" 光栅先例 `ft_glyph_index=1154 ft_bitmap_w=32 ft_bitmap_rows=30 render_px=410 ft_bitmap_left=0 ft_bitmap_top=26`（`docs/evidence/M0-WP4-text.md:102-106,119-120,137-138`）。`"𠀀"` 字体覆盖未知：命中则 1 glyph，未命中则按回退链查找或 tofu。
- 期望宽度：4 glyph advance 之和（px）；`"𠀀"` 命中时为该 face advance，未命中/tofu 时为回退或 tofu advance `[未验证]`。
- 可自动断言点：glyph_count==4 且序列稳定（S-CJK-1）；`resolve(U+20000)` 逐字符 `FT_Get_Char_Index>0` 命中/回退层级可观测，未命中记录缺失 codepoint/font_id/chain_pos 与 tofu 告警策略（`docs/research/font-fallback.md:68,75-77,103`）。
- `[未验证]` "你好世界" 在目标 face/size 的具体 glyph id 序列与总宽；U+20000 在 msyh/NotoSansSC 的 cmap 覆盖与最终命中字体/tofu 行为。

### 1.3 Emoji："😀"（分三档）
- 字符串：`"😀"`（U+1F600）。
- 字体：系统 `seguiemj.ttf`（`GSUB+GPOS true color=COLR,CPAL`，`docs/research/font-fallback.md:31,43`）；发布替代 Noto Color Emoji `[未验证 可获取/表结构]`（`docs/research/font-fallback.md:40,90,100`）。`seguiemj` 不可分发（`docs/research/font-fallback.md:49`）。
- 三档验收：
  - **(a) 测量**：HB shape 返回 glyph_count/advance 可得，宽度可纳入 layout（最小可测）。
  - **(b) 落图（灰阶/单色）**：若 M2-WP2 仅支持 R8 主图集，可降级为 mask/单色或占位落图 `[未验证 具体降级实现]`。
  - **(c) 彩色渲染**：COLR/CPAL（seguiemj）或 CBDT/CBLC（候选 Noto Color Emoji）路径是否支持取决于 M2-WP2 实现与 FreeType/渲染管线 `[未验证]`（`docs/research/glyph-atlas.md:11,15-17,91`）。
- 期望宽度：同一 face/size 下三档测量宽度目标一致（以 advance 为准）`[未验证]`。
- 可自动断言点：档 a 输出 glyph_count/advance token；档 b/c 记录 `atlas_id`/format 分派（R8 vs RGBA8 双图集建议，`docs/research/glyph-atlas.md:11,16-17,64-65`）与页增长。
- `[未验证]` "😀" 的 glyph id/advance、R8 降级效果、COLR/CPAL/CBDT 实际渲染支持与 Noto Color Emoji 本机可获取性。

### 1.4 复杂脚本：阿拉伯文 "لا"（lam-alef，已测字体差异）
- 字符串：`"لا"`（U+0644 LAM + U+0627 ALEF）；对照 `"سلام"`（U+0633,0644,0627,0645，4 codepoints，segoeui 形如 4 glyphs，`ar_glyphs=4 ar_codepoints=4 ar_shaping_diff=false`，`docs/evidence/M0-WP4-text.md:71-77,110-114,139`）。
- 字体（已实测）：tahoma.ttf / arial.ttf / segoeui.ttf / times.ttf（`docs/evidence/M0-WP4-text.md:78-97,122-123,140-147`）。
- 期望字形（按字体差异断言，不跨字体强制一致）：
  - tahoma/arial/times：`glyph_count=1`，`glyph_ids=1019`，`isolated_lam_alef_ids=989,909`，`ids_differ_from_isolated=true`，`ligature_candidate=true`（`docs/evidence/M0-WP4-text.md:78-87,93-97,141-142,144-145`）。
  - segoeui：`glyph_count=2`，`glyph_ids=3941,3980`，`isolated_lam_alef_ids=2341,2317`，`ids_differ_from_isolated=true`，`ligature_candidate=false`（`docs/evidence/M0-WP4-text.md:88-92,143,146`）。
  - 汇总 token：`ar_lam_alef_fonts_tested=4`，`ar_lam_alef_min_glyphs=1`，`ar_lam_alef_ligature_font=C:\Windows\Fonts\times.ttf`（`docs/evidence/M0-WP4-text.md:121-123`）。
- 期望宽度：Σ glyph x_advance（face 绑定）；`ar_shaping_diff=false` 仅指 `"سلام"` 样本 glyph 数==codepoint 数，不表示未 shaping（`docs/evidence/M0-WP4-text.md:114,139,147`）。
- 可自动断言点：同 face/size 下 glyph_count、glyph_ids、`ids_differ_from_isolated=true` 与探针结果一致；不得写成“所有字体 lam-alef 必为 1 glyph”（`docs/research/glyph-atlas.md:40,82`）。
- 可选脚本（P2）：天城文/泰文（如 "नमस्ते"/"สวัสดี"）需对应脚本字体与 hb script/dir 配置 `[未验证，无字体确认]`（`docs/evidence/M0-WP4-text.md:164`；`docs/plan.md:182,245`）。

### 1.5 组合字符序列：e + U+0301
- 字符串：`e` (U+0065) + COMBINING ACUTE ACCENT (U+0301)，分解形 `é`；对照预组 `é` (U+00E9) `[未验证 等价性]`。
- 字体：Latin 字体且需支持组合标记/GSUB/GPOS mark attachment `[未验证 覆盖]`。
- 期望字形/cluster：**1 cluster**；glyph 结果 **1 glyph 或 2 glyph 取决于字体与 shaping**（`docs/evidence/M0-WP4-text.md:15,154` cluster 映射未验证）。不可编造固定 glyph 数。
- 期望宽度：Σ advance；与预组形式视觉/度量等价性 `[未验证]`。
- 可自动断言点：cluster 数可观测（或按 HB cluster 序列稳定）；glyph 序列对同 face 稳定；光标/命中应按 cluster 语义而非裸 codepoint `[未验证 需实现与探针]`。
- `[未验证]` 实际 glyph 数、advance、cluster id、预组/分解等价与 mark 定位。

## 2) 验收口径（可命令化）

| 口径 | 输入/前提 | 判据 | 来源 |
|---|---|---|---|
| 测量宽度与 HB advance 一致 | 固定 `text,font_id,size,max_width`，shape 后得 glyph advances | `|measured_width_px - Σ(advance_px)| <= 0.5px`（26.6→px；取整策略 `[未验证]`） | `src/tessell/text/measurer.cr:12-41`；`docs/evidence/M0-WP4-text.md:51,103,137,152`；`docs/plan.md:85,155` |
| 换行行数 | 固定 `max_width` 约束与文本 | layout 结果行数 == 预期（预期值由样例定义时给出） | `src/tessell/text/measurer.cr:14,18-24`；`docs/plan.md:232-233` |
| 字形数与 glyph id 序列 | 固定 `(text,FontRef/font_id,size,script,dir,lang)` | `glyph_count`、`glyph_id` 序列、advance 序列与基线快照/探针 token 一致；lam-alef 按字体分支断言 | `docs/evidence/M0-WP4-text.md:15,50-97,108-114,140-147`；`docs/research/glyph-atlas.md:40,82` |
| atlas 复用后内存不增 | 预热固定 glyph 集，重复绘制 N 帧 | `atlas_page_count` 增长==0 且 `used_pixels`（或等价占用计数）增长==0 `[未实现 计数接口]` | `docs/research/glyph-atlas.md:43,53,80-81,83-85` |
| 稳态零分配 | M1-WP5 协议；推荐场景 `glyph_reuse` 预填后 N≥200 帧 `[未实现]` | `alloc_bytes==0 && delta_zero==true`；静态/paint1 基线 200 帧 205 节点 alloc_bytes=0（`docs/evidence/M1-WP5-zero-alloc.md:39-51`） | `docs/evidence/M1-WP5-zero-alloc.md:3-4,26-34,39-51,54,57-59`；`docs/research/glyph-atlas.md:51-56,80,96`；`docs/plan.md:167` |
| IME 预编辑串不丢字（C2） | IMM32 路径窗口 + 真实 IME 输入（微软拼音等） | `STARTCOMPOSITION/COMPOSITION/ENDCOMPOSITION` 可观测且组合→预编辑→上屏串完整、不丢字；候选窗位置策略按实现验证 `[未验证]`。自动基线：`imm_available=true imm_open_status=1 imm_error=none`，系统/合成消息可计数（`docs/evidence/M0-WP4-ime.md:38-42,44-59,62-67`） | `docs/evidence/M0-WP4-ime.md:38-42,44-59,62-73,76-82,85-95`；`docs/plan.md:224,245`（C2：真实 IME 手测须在 M2-WP3 前完成） |

## 3) 分级：P0 / P1 / P2 与最小实现范围

| 级别 | 目标 | 覆盖样例/口径 | 最小实现范围 |
|---|---|---|---|
| P0（M2-WP2 必须） | Latin+CJK 基本可测可绘制，稳态路径合规 | S-LAT-1、S-CJK-1、S-AR-LA；宽度±0.5px、序列稳定、零分配协议（非 default/冷启动） | **R8 单灰阶图集**；FT 光栅+HB shaping 基本链路；`MeasureKey`/`CachingMeasurer` 接入；最小 `FontRef` 回退（开发字体）；emoji 不要求彩色渲染（`docs/research/glyph-atlas.md:11,15,70-75`；`docs/plan.md:244`） |
| P1（应通过） | 回退/组合字符可观测，emoji 测量+灰阶落图，缓存/批次纪律 | S-CJK-EXTB、S-EMOJI-1(a/b)、S-COMB-1；atlas 复用不增、失效一致、批次正确 | R8 单图集 + 逐字符 fallback 与缺失告警（`docs/research/font-fallback.md:75-77`）；glyph/measure 失效对齐（`docs/research/glyph-atlas.md:44-45,84-85`；`src/tessell/text/measurer.cr:104-112`）；emoji 可降级 mask `[未验证]` |
| P2（可延后） | 彩色 emoji、复杂脚本扩展、IME 真实闭环 | S-EMOJI-1(c)、S-OPT-DEV、IME C2 手测闭环、COLR/CBDT 路径 | **R8+RGBA8 双图集**（`docs/research/glyph-atlas.md:16-17,64-65,91`）；COLR/CPAL 或 CBDT/CBLC 支持 `[未验证]`；hinting/LCD/竖排/BiDi cluster/多 face/逐字形混排延后 `[未验证]`（`docs/research/glyph-atlas.md:75,92,95,98`；`docs/evidence/M0-WP4-text.md:154,163-165`） |

## 4) 与计划映射表

| 计划条目 | 样例 | 验收判据 | 依赖/条件 |
|---|---|---|---|
| M2-WP2 文本栈集成（`docs/plan.md:244`） | S-LAT-1,S-CJK-1,S-EMOJI-1(a-c),S-AR-LA | shaping/栅格/atlas/测量可用；glyph 序列与宽度一致（±0.5px）；atlas 复用与稳态零分配口径可判（glyph_reuse 场景待工具扩展 `[未实现]`） | 依赖 M0-WP4,M1-WP2,M1-WP4,M2-WP2F（`docs/plan.md:244`）；字体按 `docs/research/font-fallback.md`；atlas/DrawList 按 `docs/research/glyph-atlas.md`、`src/tessell/render/draw_list.cr:18-35,89-118` |
| M2-WP3 IME 与复杂文本（`docs/plan.md:245`） | S-AR-LA,S-COMB-1,S-OPT-DEV(可选), IME 真实输入 | RTL/连字/组合字符序列稳定；预编辑串不丢字、组合消息完整 | **C2**：真实 IME 手测须在 M2-WP3 前完成（引用 M0-WP4-IME M-1 证据：IMM32 路径/消息可达已证，真实组合 `[未验证]`，`docs/evidence/M0-WP4-ime.md:62-73,76-82,85-95`；`docs/plan.md:224,245`） |

## 5) 未验证清单

- `[未验证]` Latin "Hello"/"AV" 具体 glyph id、advance、kerning 差值与探针 token（需固定 face/size 实测）。
- `[未验证]` "你好世界" 在目标 face/size 的 glyph id 序列与总宽；U+20000 (Ext B) cmap 覆盖、回退命中层级与 tofu 告警实际输出。
- `[未验证]` "😀" 的 shape 结果、R8 降级落图、COLR/CPAL（seguiemj）与 CBDT/CBLC（Noto Color Emoji）彩色渲染支持及 Noto Color Emoji 可获取性/OFL 获取与校验（`docs/research/font-fallback.md:40,43,90-92,100`）。
- `[未验证]` e+U+0301 cluster→glyph 数（1/2）、与 U+00E9 等价性、mark attachment/光标命中（`docs/evidence/M0-WP4-text.md:154`）。
- `[未验证]` 天城文/泰文等复杂脚本字体、hb script/dir/lang 配置与序列断言（`docs/evidence/M0-WP4-text.md:164`）。
- `[未验证]` 真实 IME 组合：`WM_IME_STARTCOMPOSITION/COMPOSITION/ENDCOMPOSITION` 计数、预编辑/候选窗/上屏不丢字；TSF 路径；不同 IME/DPI/显示器（`docs/evidence/M0-WP4-ime.md:72-82,85-89`）。
- `[未验证]` `tools/zero_alloc_frame.cr` 的 `glyph_reuse` 场景与输出 token 扩展；GPU 纹理上传/GL 调用是否可纳入 GC 窗口（`docs/research/glyph-atlas.md:54,80,96`；`docs/evidence/M1-WP5-zero-alloc.md:54`）。
- `[未验证]` atlas 2048² R8 页可容纳 16px 汉字数量 X、浪费率/碎片率、`GL_MAX_TEXTURE_SIZE`/显存与纹理上传带宽（`docs/research/glyph-atlas.md:30-31,81,90,93`）。
- `[未验证]` 宽度容差 ±0.5px 在 hinting/亚像素/不同 DPI 与 26.6→px 取整策略下的适用性。
- `[未验证]` 字体工具链（fc-query/otfinfo/ttx/fontTools）本机缺失，语言/字符覆盖与表细节无法离线自动核验（`docs/research/font-fallback.md:20,116`）。