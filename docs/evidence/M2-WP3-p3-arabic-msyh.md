# M2-WP3 / M2-WP2 P3 定性：S-AR-LA（`"لا"`）msyh 上屏问题

- 时间：2026-11-13（Asia/Shanghai）
- 背景（lead m01111）：`"لا"`（`C:/Windows/Fonts/msyh.ttc`，16px）placement `drawable=0`（w=h=0）但 advance 正确，Arabic 验收样例无法上屏；要求查 HB `glyph_id`、`FT_Load_Glyph(FT_LOAD_RENDER)` 后 bitmap/pitch/pixel_mode、`FT_GlyphSlot.advance` 与 `metrics.width`，并对比 24px/32px 与 `arial.ttf`/`times.ttf`，定性后如实记录并调整 S-AR-LA 样例字体（若为 msyh 字形无轮廓/位图为空）。
- 约束遵守：未改 `src/tessell/text/*`；未改 spec/探针逻辑；临时调查脚本 `_tmp_ar_investigate.cr` 运行后已删除（`deleted_tmp=True`）。

## 调查方法

临时脚本（已删）使用 `FtMeasurer.open(path)` + `Rasterizer(measurer, atlas)`：
- `shape_info(text, size)` 取 HB glyph ids/count
- `rasterize_into(text, size, sink)` 取 placement（w/h/offset/advance/drawable）
- 对每个 placement 的 glyph id 重新执行 `FT_Lib.set_pixel_sizes` + `FT_Lib.load_glyph(face, gid, FT_LOAD_RENDER)`，记录 `bitmap.width/rows/pitch/pixel_mode`、`advance.x(26.6)`、`metrics.width/hori_bearing_x/y`、`bitmap_left/top`、`load_err`

`AR_INVESTIGATE_EXIT=0`。

## 结果

| font | size | HB glyph_ids/count | placements(drawable) | Σadvance(px) / measure(px) | FT per-glyph（load_err=0） |
|---|---:|---|---:|---:|---|
| msyh.ttc | 16 | `[0,0]` / 2 | 2（均 `w=h=0`, drawable=false） | 22.3125 / 22.3125 | gid=0: `bitmap 9x12 pitch=9 pixel_mode=2`, `advance_x26=704`, `metrics_w26=576 metrics_h26=768`, `bearing 64,768`, `bitmap_left/top=1,12` |
| msyh.ttc | 24 | `[0,0]` / 2 | 2（均 drawable=false） | 33.46875 / 33.46875 | gid=0: `bitmap 13x18 pitch=13 pm=2`, `adv26=1088`, `metrics 832x1152`, `bearing 128,1152`, `left/top=2,18` |
| msyh.ttc | 32 | `[0,0]` / 2 | 2（均 drawable=false） | 44.625 / 44.625 | gid=0: `bitmap 18x24 pitch=18 pm=2`, `adv26=1408`, `metrics 1152x1536`, `bearing 128,1536`, `left/top=2,24` |
| arial.ttf | 16 | `[1019]` / 1 | 1（drawable=true, 9x10） | 8.703125 / 8.703125 | gid=1019: `bitmap 9x10 pitch=9 pm=2`, `adv26=576`, `metrics 576x640`, `left/top=0,11` |
| arial.ttf | 24 | `[1019]` / 1 | 1（drawable=true, 13x16） | 13.0546875 / 13.0546875 | gid=1019: `bitmap 13x16 pitch=13 pm=2`, `adv26=832`, `metrics 832x1024` |
| arial.ttf | 32 | `[1019]` / 1 | 1（drawable=true, 16x21） | 17.40625 / 17.40625 | gid=1019: `bitmap 16x21 pitch=16 pm=2`, `adv26=1088`, `metrics 1024x1344` |
| times.ttf | 16 | `[1019]` / 1 | 1（drawable=true, 9x10） | 8.703125 / 8.703125 | gid=1019: `bitmap 9x10 pitch=9 pm=2`, `adv26=576`, `metrics 576x640` |
| times.ttf | 24 | `[1019]` / 1 | 1（drawable=true, 13x16） | 13.0546875 / 13.0546875 | gid=1019: `bitmap 13x16 pitch=13 pm=2`, `adv26=832`, `metrics 832x1024` |
| times.ttf | 32 | `[1019]` / 1 | 1（drawable=true, 16x21） | 17.40625 / 17.40625 | gid=1019: `bitmap 16x21 pitch=16 pm=2`, `adv26=1088`, `metrics 1024x1344` |

## 定性结论

- **非绑定/像素模式 bug**：`FT_Load_Glyph(..., LOAD_RENDER)` 对 arial/times 的 gid=1019 与对 msyh 的 gid=0 均返回 `load_err=0`、`pixel_mode=2`（8bpp gray）、合理 `bitmap width/rows/pitch` 与非零 `advance_x26`/`metrics`；渲染与 FFI 路径正常。
- **msyh 根因（字体覆盖/映射）**：msyh.ttc 在 16/24/32px 下对 `"لا"` 的 HarfBuzz shaping 产出 `glyph_ids=[0,0]`（.notdef），而非可用的阿拉伯 lam-alef 字形（对比 arial/times 为单 ligature `glyph_id=1019`）。因此：
  - advance 由 HB/测量路径保持正确（22.3125/33.46875/44.625 px），与“测量可用”一致；
  - rasterizer 对 `gid==0` 按现有语义返回零位图 placement（`w=h=0`、不入图集、无可见像素），导致**无法上屏**；
  - FT 能为 gid=0 生成 `.notdef` 位图，但这不是目标阿拉伯字形，且当前实现刻意不将 gid=0 作为可绘制文本输出。
- **结论**：`"لا"` 在 msyh（16/24/32px）下为 **mapped-to-notdef（glyph_id 0）导致无可见字形/无可绘制位图输出**，属字体覆盖/映射与现有 gid=0 策略问题，**不是 `src/tessell/text/*` 的绑定或像素模式缺陷**。S-AR-LA 验收样例字体改为 **arial（1 glyph, glyph_id=1019）**；理由已同步至 `docs/research/text-acceptance.md` §1.4。

## 处置

- 已更新 `docs/research/text-acceptance.md` §1.4：S-AR-LA 样例字体指定为 `arial.ttf`（1 glyph）并注明 msyh 证据与原因。
- 未修改 `src/tessell/text/*`、未改主逻辑；未改 spec/探针。