# M2-WP2B 字形图集（Glyph Atlas）预研

> 状态：纯调研草案（未实现/未改码）。每条事实标注来源（文件:行或命令输出/会话记录）；不可验证标 `[未验证]`；不编造库 API。
> 任务：task-42「M2-WP2B 预研：字形图集（格式/装箱/键与失效/零分配/与 DrawList 接口）」，HEAD=a74823b（任务书）；采集时间 2026-11-13 00:06:10 +08:00（会话 time context）。
> 锚点：`docs/plan.md:44-45,85,110,155,167,244`；`docs/architecture.md:155`；`docs/research/font-fallback.md:83`。
> 背景阅读：`docs/evidence/M0-WP4-text.md`、`docs/evidence/M1-WP5-zero-alloc.md`、`docs/research/font-fallback.md`、`src/tessell/render/draw_list.cr`、`src/tessell/text/measurer.cr`、`src/tessell/layout.cr`。
> 写入范围：仅本文件；未改 `src/`/`spec/`/`tools/`/`examples/`/其他 docs。

## 1) 图集格式选型（R8 vs RGBA8 vs 双图集、subpixel、sRGB）

**结论**：M2 MVP 以 **R8 灰阶 alpha 主图集** 承载 Latin/CJK；彩色 emoji 预留 **RGBA8 独立页/图集**（双图集按 format 分派）；glyph key 含 `flags/format`，`atlas_id` 可编码页+格式（建议，不改码）。

| 选项 | 适用 | 依据/收益 | 风险/限制 |
|---|---|---|---|
| R8 灰阶 AA | Latin/CJK 主文本 | FT `FT_LOAD_RENDER` 输出单通道 bitmap（`width/rows/pitch/buffer`），"你" `ft_bitmap_w=32 ft_bitmap_rows=30 render_px=410 ft_bitmap_left=0 ft_bitmap_top=26`（`docs/evidence/M0-WP4-text.md:16,104-106,119-120,137-138`）；1 byte/px，带宽/显存最省 | 仅 alpha，着色依赖 shader tint 约定 `[未验证]` |
| RGBA8 | 彩色 emoji/彩色位图字形 | seguiemj.ttf 含 `COLR,CPAL`（`docs/research/font-fallback.md:31,43`）；彩色路径需 bitmap/RGBA 输出 | seguiemj 不可分发（`docs/research/font-fallback.md:49`）；Noto Color Emoji 表结构 CBDT/CBLC 或 COLR 与可获取性 `[未验证]`（`docs/research/font-fallback.md:40,43,90,100`） |
| 双图集 R8+RGBA8（建议） | 混排文本+emoji | 按 glyph `flags/format` 分派页，避免单纹理格式冲突；`DrawCmd.atlas_id:Int32` 可表达页/格式（`src/tessell/render/draw_list.cr:30,33`），同页同 clip 可合批（:11-12,89-118） | 纹理绑定与批次切换增加；format 编码细节 `[未验证]` |

- **subpixel 定位**：FT 26.6 固定点（`FT_Set_Char_Size(...,24*64,96,96)`，`ft_advance_x26=2048`，`docs/evidence/M0-WP4-text.md:16,102-103,137`）。glyph key 建议含 `subpixel_bucket`：M2 MVP 整数像素对齐（bucket=0）优先保证命中；1/4 水平亚像素或 `FT_RENDER_MODE_LCD` 清晰度更好但缓存基数增大 `[未验证]`。
- **字形度量落 atlas**：除 bitmap/UV 外通常需记录 bearing（如 `bitmap_left/top`）、advance、行高指标供排版与绘制 `[未验证，接口未定]`（探针已读出 advance/bitmap 尺寸与位置，`docs/evidence/M0-WP4-text.md:103-106,119-120`）。
- **sRGB/线性**：灰阶 alpha 在 sRGB framebuffer 混合的 gamma 处理影响观感；`GL_FRAMEBUFFER_SRGB`/着色器策略与本机 `GL_MAX_TEXTURE_SIZE` `[未验证]`。
- **风险**：格式/subpixel 晚定将影响纹理创建、shader 约定与 `DrawCmd` 扩展（§5）。

## 2) 装箱算法（shelf/skyline、页大小、浪费率、扩容）

**结论**：MVP 采用 shelf（同字号行高稳定、实现简单）或 skyline（碎片更优）；策略“初始页 + 满页追加新页”，热路径不重排。

- **shelf（行架）**：按行高分层放置，适合同 size 字形高度相近场景；缺点行尾碎片与跨行高差异浪费。
- **skyline**：维护顶部轮廓线，通常优于 shelf；实现复杂度中等。maxrects/guillotine 等收益/复杂度 `[未验证]`。
- **页大小与显存**：1024²=1 MiB(R8)/4 MiB(RGBA8)，2048²=4/16 MiB，4096²=16/64 MiB。建议初始 1024²，按压力追加；2048² 为常用上限候选；上限受 `GL_MAX_TEXTURE_SIZE` 与显存约束 `[未验证，本机未测]`。
- **浪费率目标**：记录 `used_pixels/atlas_pixels`、页数、碎片率；稳态碎片目标 <20%（经验阈值，非实测门限 `[未验证]`）。字形间建议留 1px padding 防采样 bleeding `[未验证]`。
- **page 扩容**：仅追加新 page（稳定 page id），不在热路径全页重排/重打包/迁移旧 glyph；旧 glyph UV 与 `atlas_id(page)` 不变，避免帧内失效。风险：页过小→批次切换增多（`build_batches` 按 `atlas_id` 切批，`src/tessell/render/draw_list.cr:89-118`）；页过大→设备不支持/上传成本高。

## 3) 键与失效（glyph key、MeasureKey 关系、LRU、帧内不淘汰、font invalidation）

**结论**：glyph cache 与 measure cache 分层但通过 `font_id` 对齐；页满可 LRU 但**帧内不淘汰**；字体失效须同步清理两侧缓存。

- **Glyph key（建议）**：`(font_id, glyph_id, size_px, subpixel_bucket, flags)`。
  - `font_id`：由 `FontRef` 派生并与 `MeasureKey.font_id` 对齐（`docs/research/font-fallback.md:72,82-83`；`docs/architecture.md:155`；`src/tessell/text/measurer.cr:13-20` `MeasureKey(font_id,size,text_hash,max_width)`）。
  - `glyph_id`：HB shaping 输出 `hb_glyph_info_t.codepoint`（`docs/evidence/M0-WP4-text.md:15`），**非 Unicode codepoint**；示例 `zh_glyph[0].codepoint=1154 advance=1536`（:50-51,108-109），lam-alef 因字体不同（tahoma/arial/times 1 glyph、segoeui 2 glyph，:71-97,140-147）。
  - `size_px/subpixel_bucket/flags`：区分栅格尺寸、亚像素相位、hint/AA/颜色格式变体，避免错误复用位图。
- **与 MeasureKey 分层**：`MeasureKey` 用 FNV-1a `text_hash` 缓存“文本串→Size”（`src/tessell/text/measurer.cr:33-40,78-88`）；atlas 缓存“glyph→bitmap/metrics/UV/页”。链路：text→shape(HB)→glyph run→measure 与 glyph→raster(FT)→atlas；MeasureKey 命中不保证 atlas 已有位图。`CachingMeasurer.stats` 提供 `hits/misses/evictions`（:100-102）。
- **LRU 与帧内不淘汰**：页满可对冷 glyph 做 LRU 回收槽位/页（代价：重栅格/重上传）`[未验证 策略细节]`；**同一帧内已被 DrawCmd/批次引用的 glyph 不得淘汰或移动**，保证 UV 有效（硬约束建议）。
- **font invalidation**：测量侧 `CachingMeasurer.invalidate_font(font_id)` 清 key 并累计 evictions，`clear` 全清（`src/tessell/text/measurer.cr:104-112`）；atlas 侧须同步清除该 `font_id` 条目/页占用，或采用 `font_set_version` 参与键/全量失效（`docs/research/font-fallback.md:77` resolve 缓存键 `(codepoint,font_set_version)`，glyph cache 可类推版本化）。
- **风险**：键缺失 subpixel/flags 致模糊/错字形；帧内淘汰致渲染错误；失效不同步致测量与绘制不一致。

## 4) 零分配口径（与 tools/zero_alloc_frame.cr 协议扩展、禁用 default 路径）

**结论**：沿用 M1-WP5 `GC.stats.bytes_since_gc` 窗口协议；新增 `glyph_reuse` 稳态场景建议；扩页/冷加载/首帧/default 路径不得计入通过。

- **协议（M1 基线）**：`warmup → GC.collect → before=GC.stats.bytes_since_gc → GC.disable → N 帧 → after → GC.enable(ensure)`，`alloc_bytes=after-before`，`delta_zero=true` 为通过（`docs/evidence/M1-WP5-zero-alloc.md:3-4,26-34`；`docs/plan.md:167`“无结构变更/无新资源加载/无文本重排重测”）。
- **实测基线**：205 节点，`scenario=static frames=200 alloc_bytes=0 delta_zero=true`，`scenario=paint1 frames=200 alloc_bytes=0 delta_zero=true`（`docs/evidence/M1-WP5-zero-alloc.md:39-51`）；局限：不含布局重算/文本 shaping/GPU 提交（:54）。
- **atlas steady 路径要求**：glyph 命中仅查表取 UV/度量并写入预分配命令/展开缓冲；atlas 页表、装箱空闲结构、LRU 节点/索引、staging 上传缓冲、glyph-run 缓冲需预分配+复用（池化）。新 glyph raster、HB/FT 临时对象、扩页/纹理创建属非稳态帧，允许分配但须与 steady 分离观测。
- **`tools/zero_alloc_frame.cr` 扩展建议**：新增 `scenario=glyph_reuse`——warmup 预填 atlas 与固定 glyph 集后，N≥200 帧重复绘制同一文本（仅查 atlas/组 DrawCmd，不触发新 raster/扩页），输出 `scenario,frames,nodes_or_glyphs,alloc_bytes,delta_zero`（对齐现有 token 形态，`docs/evidence/M1-WP5-zero-alloc.md:20,46-50`）；可选 `scenario=glyph_cold` 仅作非门禁观测 `[未实现]`。
- **禁止项**：不得用 default/首帧/冷启动/扩页/首次 shaping 分配路径作“零分配通过”判据（`docs/evidence/M1-WP5-zero-alloc.md:54,58-59` 非稳态扩容约束；`docs/plan.md:167` 口径）。
- **风险**：DrawList 预付槽位不足时 `reserve` 扩容为非稳态（`src/tessell/render/draw_list.cr:82-87`；`docs/evidence/M1-WP5-zero-alloc.md:57`）；`src/tessell/layout.cr:7,14` 标注热路径缓冲复用 TODO(M1-WP5)，atlas 侧需同样纪律。

## 5) 与 DrawList 的接口（atlas_id 粒度、clip/合批、UV 建议不改码）

**结论**：现有 `DrawCmd` 已含 `atlas_id` 与 `CmdKind::Text`，可承载页级合批；UV/源矩形缺失是 M2 接口缺口，本节仅建议不改代码。

- **现状**：`DrawCmd` 字段 `kind,bounds,color,atlas_id,clip`（`src/tessell/render/draw_list.cr:24-35`）；`CmdKind::{Rect,Text,Line}`（:18-22）；`atlas_id=-1` 表示无 atlas（:29-30）；`DrawList` clear 保留物理槽位、push 原位复用，`capacity/reuse_stats` 可观测（:7-9,56-71,76-87,112-114）。
- **批处理语义**：`build_batches` 相邻命令 `atlas_id` 相同且 `clip` 相同则合批，`kind/color` 不参与（:11-12,89-118,116-118 `same_batch_key?`）。
- **atlas_id 粒度建议**：以“page（+format）”为粒度，使同纹理页连续 Text 命令可合批；R8 与 RGBA8 不同页映射不同 `atlas_id`（或编码高位 format、低位 page）。位布局/保留值 `[未验证]`。
- **UV 从哪来（建议，不改码）**：当前 `DrawCmd` 无 uv/texcoord/源矩形字段（:24-35），`bounds` 仅为目标矩形。可选方案：(a) 扩展 `DrawCmd` 增加可选 `uv_rect/src_uv`（Text 专用）；(b) Text 命令引用 glyph-run/quad 展开缓冲区段。两者需与后端着色器（R8 alpha 或 RGBA 采样、颜色乘法）配合；**本预研不改 `draw_list.cr`**。
- **clip 与合批**：clip 变化即切批（:96-102）；文本应在同 clip 按 `atlas_id` 聚类。与脏矩形/滚动 `CompositeOnly` 及裁剪传播交互 `[未验证]`（`docs/plan.md:91,160,162`）。

## 6) FT/HB 绑定边界（src vs examples/tools、M2 MVP vs 延后）

**结论**：M2 将 FT/HB/atlas 落在 `src/tessell/text/*` 与 render 侧；`examples/tools` 仅保探针与度量工具；MVP 先 Latin/CJK 灰阶与缓存链路。

- **src（M2 实现归属）**：`Tessell::Text` 封装 HarfBuzz shaping、FreeType 栅格化/度量、字形 atlas 管理（`docs/plan.md:44-45,110,244`）。当前 `src/tessell/text/measurer.cr`：`MeasureKey`/FNV-1a（:12-41）、`abstract Measurer`（:44-51）、`StubMeasurer` 确定性桩（:55-66）、`CachingMeasurer`（:69-112，`invalidate_font` :104-108）；头注释“不引用 FFI/FreeType/HarfBuzz，真实 shaping 属 M2”（:6）。`src/tessell/layout.cr` 叶子文本测量接入点：`LayoutNode` 含 `text/font_id/font_size`（:28-31,39-42），`measure` 在 Auto 维度调用 `measurer.measure(...)`（:68-75）。
- **examples/tools（探针/证据）**：`examples/m0_text_probe.cr` 纯 FFI 验证 FT/HB、中文/阿拉伯 shaping、"你" 光栅与计时（`docs/evidence/M0-WP4-text.md:13-24,98-127,136-148`，`ft_version=2.15.0 hb_version=15.1.0 zh_glyphs=10 render_px=410 shape_us_avg=0.503 render_us_avg=7.191`）；`tools/zero_alloc_frame.cr` 零分配协议与 static/paint1（`docs/evidence/M1-WP5-zero-alloc.md:20,37-51`）。`bin/m0_text_probe.exe` 为探针产物（`docs/evidence/M0-WP4-text.md:132`）。
- **M2 最小可行**：Latin/CJK 基本 shaping + 灰阶 R8 atlas + 接入 `FontRef/font_id` 回退链（`docs/research/font-fallback.md:72,81-84`），缓存 `FT_Face`/`hb_font`/`hb_buffer` 与可复用 staging（`docs/evidence/M0-WP4-text.md:152-153`），按需 raster+上传并区分非稳态帧。
- **延后项**：hinting 精调、COLR/CPAL/CBDT 彩色 emoji 渲染、竖排、复杂脚本 cluster/BiDi 光标命中、亚像素 LCD、多 face 逐字形混排优化（`docs/evidence/M0-WP4-text.md:154,163-165` `[未验证]`）；IME 深度集成依赖 M0-WP4-IME（`docs/plan.md:245`）。
- **风险**：HB/FT 对象线程与生命周期约束未在 src 层验证 `[未验证]`；发布/开发字体集与许可不同（`docs/research/font-fallback.md:47-53,98`）。

## 7) 验收标准草案（3–6 条可测断言）

1. **glyph 复用零分配**：预热 atlas 与固定 glyph 集后绘制 N≥200 帧，`GC.disable` 窗口 `alloc_bytes==0 && delta_zero==true`；协议/token 对齐 `docs/evidence/M1-WP5-zero-alloc.md:26-34,39-51`，场景 `glyph_reuse` `[未实现]`。
2. **页容量与稳态增长**：单页 2048² R8 记录可容纳 16px 汉字字形数 X 与 `used_pixels/atlas_pixels`；重复绘制已缓存字形后 `atlas_page_count` 与 atlas 占用增长=0 `[未验证，X 依赖字形 bbox/留白与装箱]`。
3. **shaping 序列正确性**：固定 (text,FontRef,font_id,size,script/dir/lang) 下 `glyph_id+advance` 序列稳定可复现；对照探针 token（`docs/evidence/M0-WP4-text.md:50-69,108-109` zh；:71-97,111-114 ar）。lam-alef 按字体差异断言（tahoma/arial/times 1 glyph、segoeui 2 glyph，`ids_differ_from_isolated=true`，:140-147），不强制跨字体一致。
4. **淘汰与命中率**：受限页数触发 LRU 后统计 `hits/misses/evictions`（参照 `src/tessell/text/measurer.cr:100-102` 口径）且帧内引用 glyph 不被淘汰 `[未验证，未实现]`。
5. **失效一致性**：`invalidate_font(font_id)` 或 `font_set_version` 变更后，测量缓存与 atlas 对该 font 的旧条目不可命中（测量侧锚 `src/tessell/text/measurer.cr:104-112`；atlas 侧 `[未实现]`）。
6. **批次正确性**：同页同 clip 的 Text 命令合批、跨页或 clip 变化切批，符合 `build_batches/same_batch_key?`（`src/tessell/render/draw_list.cr:89-118`）；UV/字形展开落地后补回归 `[未验证]`。

## 8) 未验证项清单

- `[未验证]` 字体工具缺失：`fc-query/fc-list/otfinfo/ttx` NOT FOUND，`fontTools` 未安装（`docs/research/font-fallback.md:20,116`）。
- `[未验证]` 本机 `GL_MAX_TEXTURE_SIZE`、显存与 1024²/2048²/4096² 纹理可行性；纹理上传/子更新带宽与延迟。
- `[未验证]` COLR/CPAL（seguiemj）与 CBDT/CBLC（候选 Noto Color Emoji）在 FreeType/渲染管线支持、性能与着色路径（`docs/research/font-fallback.md:31,43,100`）。
- `[未验证]` 亚像素/LCD（`FT_RENDER_MODE_LCD`）、hinting 策略、sRGB/linear 混合对观感与度量一致性影响。
- `[未验证]` shelf/skyline/maxrects 实际浪费率与 2048² R8 页可容纳 16px 汉字数量 X（依赖 bbox/留白/字形集）。
- `[未验证]` `DrawCmd` UV 扩展形式（字段/可选结构/glyph-run 缓冲）及对 `build_batches`（`src/tessell/render/draw_list.cr:91-118`）与后端提交 API 的最终影响。
- `[未验证]` 多 face 混排、BiDi/cluster/竖排、逐字符 fallback 与 atlas/shape/measure 缓存协同细节。
- `[未验证]` `tools/zero_alloc_frame.cr` 尚无 `glyph_reuse` 场景；GPU 纹理上传/GL 调用是否可纳入同一 GC 零分配窗口。
- `[未验证]` HarfBuzz/FreeType 在 src 的 FFI 绑定形态与线程/face 生命周期约束（UI Isolated context 使用约束待设计，`docs/plan.md:153-161`）。
- `[未验证]` 复杂脚本更广覆盖（Devanagari/Thai/emoji ZWJ 等）与 hb_ft_font 集成路径（`docs/evidence/M0-WP4-text.md:164-165`）。

## 参考索引

- `docs/plan.md:167,244` 稳态零分配口径与 M2-WP2（FT+HB+atlas）目标；`docs/architecture.md:155` MeasureKey。
- `src/tessell/render/draw_list.cr:7-12,18-22,24-35,56-87,89-118` 容量/复用、CmdKind/DrawCmd、build_batches。
- `src/tessell/text/measurer.cr:6,12-41,44-51,55-66,69-112` FNV-1a/MeasureKey、Measurer 抽象、Stub/Caching/invalidate。
- `src/tessell/layout.cr:7,14,28-31,39-42,68-75` 热路径复用 TODO 与文本叶子度量输入/调用点。
- `docs/evidence/M0-WP4-text.md:13-24,50-127,136-148,152-153` FT/HB 探针 token、lam-alef 结论与 M1-WP2 含义。
- `docs/evidence/M1-WP5-zero-alloc.md:3-4,20,26-51,54,57-59` 零分配协议、基线与局限。
- `docs/research/font-fallback.md:31,40,43,47-53,72,77,81-84,98,100` 字体/许可/FontRef+resolve/版本失效/风险。