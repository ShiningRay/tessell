# verify-M2-WP2-emoji.md — M2 C1 Emoji 独立核验（dalisi-qing-2, task-80）
- 元信息：报告 39 行（read/UTF-8 实测）；HEAD `2a2b620`+未提交；2026-11-13 Asia/Shanghai；只读核验，未改源码/spec/示例、未 commit。
- 对象：`src/tessell/text/font_fallback.cr`、`spec/font_fallback_spec.cr`、`spec/text_emoji_spec.cr`、`examples/m2_text_window.cr`(--emoji)、`src/tessell.cr`(+1)、`docs/evidence/M2-WP2-emoji.md`。

## 1. 必跑命令与原始结果
- `git diff -- src/tessell.cr`：仅 `+require "./tessell/text/font_fallback"`（`src/tessell.cr:19`），`M src/tessell.cr`。符合“+1 行”。
- `crystal spec spec/font_fallback_spec.cr` → `6 examples, 0 failures, 0 errors, 0 pending` EXIT=0（155µs）。
- `crystal spec spec/text_emoji_spec.cr` → `5 examples, 0 failures, 0 errors, 0 pending` EXIT=0（8.46ms）。原始 EVIDENCE：`EVIDENCE_EMOJI_MEASURE1 text="😀" w=43.9375 h=34.0 glyphs=1 sum_adv=43.9375 diff=0.0`；`MEASURE2 "😀👍" w=87.875 h=34.0 glyphs=2 sum_adv=87.875 diff=0.0`；`COV i=0 gid=2317 adv=43.9375 w=34 h=35 cov=743 total=1190 cov_ratio=0.6243697478991597`、`i=1 gid=1213 adv=43.9375 w=30 h=37 cov=473 total=1110 cov_ratio=0.4261261261261261`；`UV count=2 ok=true`；`PIXELMODE i=0 gid=2317 pixel_mode=2 ... i=1 gid=1213 pixel_mode=2 ... SUMMARY modes=[2, 2] (2=FT_PIXEL_MODE_GRAY,7=FT_PIXEL_MODE_BGRA) drawable_cov=1216 status=R8_gray_path_ok`。
- 全量 `crystal spec` → **`182 examples, 0 failures, 0 errors, 0 pending`** EXIT=0（382.32ms，与基线 182 一致）。
- `crystal run examples/m2_text_window.cr -- --emoji --frames=30 --verify` EXIT=0 原始行：`emoji_quads=2 emoji_pixels_nonbg=1171 emoji_pixel_match=true frame_p50_ms=2.4308 frame_p95_ms=4.0871 frame_p99_ms=6.5811 emoji_cpu_coverage_sum=1216 emoji_ratio=0.9629934210526315 mixed_pixels_nonbg=2939 frames=30 swapbuffers=30 pen_after_emoji_x=127.875 text_quads=7`；`emoji_note=... emoji-only pass (RGB delta>8 vs white bg, ratio tolerance [0.5,1.5]); display path R8->GL_ALPHA (gray coverage)...`；`gl_path=GL1.1_compat R8->GL_ALPHA glPixelStorei(GL_UNPACK_ALIGNMENT,1) glTexCoord2f/glVertex2f`。

## 2. 真实性（防冒充，独立探针 `bin/_v_emoji.cr` 已运行并删除）
- seguiemj（😀 32px）：`hb_glyphs=1 gid0=2317 hb_adv0=43.9375 hb_sum=43.9375 measure_w=43.9375 ft_bm_w=34 ft_bm_h=35 ft_pixel_mode=2 load_err=0 is_notdef=false`
- msyh.ttc（😀 32px）：`hb_glyphs=1 gid0=0 hb_adv0=22.3125 hb_sum=22.3125 measure_w=22.3125 ft_bm_w=18 ft_bm_h=24 ft_pixel_mode=2 load_err=0 is_notdef=true`
- 结论：**非冒充**。同一码点两字体 glyph id/advance/bitmap 尺寸均不同；msyh 对 😀 得 `gid0=0 (.notdef)` 且宽/高/前进与 seguiemj 不同，未绘出同形 emoji。😀 字形来源可判定为 seguiemj（与 spec EVIDENCE gid 2317 一致）。

## 3. 测量与光栅口径复算
- `"😀"`：measure=43.9375, Σadvance=43.9375, |diff|=0.0；glyphs=1。`"😀👍"`：measure=87.875, Σadvance=87.875, |diff|=0.0；glyphs=2（gid 2317,1213），与实测一致。
- 光栅：placement w/h>0(34x35,30x37)、`page>=0`（atlas 插入成功）、`UV count=2 ok=true`；coverage 非零 743/1190=0.6243697、473/1110=0.4261261，drawable_cov=1216；`pixel_mode=2`(FT_PIXEL_MODE_GRAY) 与 FT 语义一致，未见 7(BGRA)/全零。

## 4. 上屏诚实性（代码证据）
- `examples/m2_text_window.cr:364` `glReadPixels(...)` 读回 → `:365` `emoji_pixels_nonbg = count_nonbg(...)`（RGB delta>8 vs 白底）→ `:366` `emoji_ratio = cpu_cov_e>0 ? emoji_pixels_nonbg/cpu_cov_e : 0.0` → `:367` `emoji_pixel_match = (emoji_pixels_nonbg>0)&&(emoji_ratio>=0.5)&&(emoji_ratio<=1.5)`。**非硬编码**（由实测统计计算）；`--verify` 退出 `:426` `exit(emoji_pixel_match ? 0 : 1)`；无 GL/窗口时报错不伪造 `:503`。
- 自洽：1171/1216=0.9629934210526315，与实测 `emoji_ratio=0.9629934210526315`、`emoji_pixel_match=true` 一致。

## 5. 文档对账（`docs/evidence/M2-WP2-emoji.md`）
- 实际行数 **64 行**（read 计数，末行含 `## 结论` 与正文），而 task/部分描述称 74 行（以实际为准；文档内未自述行数）。主要实测数字(182/0f、EVIDENCE_MEASURE/COV/UV/PIXELMODE、emoji-only 像素/ratio/cpu_cov/quads/match)与本次复跑一致。
- 三档结论与实测一致：测量达成、R8 灰度显示达成、**彩色 COLR/CPAL 明确标“未达成（P2，不阻塞）”**（:102-103, :29, :108），未含糊过关；`pixel_mode=2` 证据支撑。
- “未验证/限制”(:105-112)列出 6 项限制；部分未附具体验证步骤（信息性，见 P3）。

## 6. 缺陷清单（P0–P3）
- P1：无。P2：无（emoji 来源/测量/光栅/上屏统计/匹配判定均有实证且自洽）。
- P3-1（文档元信息轻微偏差）：`docs/evidence/M2-WP2-emoji.md` 实际 64 行；外部声称 74 行，易致对账混淆（建议在文档内标注实测行数）。
- P3-2（信息性）：`docs/evidence/M2-WP2-emoji.md:105-112` “未验证/限制”未逐项给出可执行验证路径（仅列范围）。

## 7. 未验证清单
- 其他机器/GPU/驱动/Windows 或 seguiemj 版本下 `pixel_mode` 与显示一致性；COLR/CPAL 彩色/BGRA 路径(P2)；ZWJ/肤色/旗帜等复合 emoji 序列 shaping/cluster；不同字号/缩放；无显示/headless 下 `--verify` 可重复性；`FontSet` 与 `FtMeasurer/Rasterizer` 多字体端到端集成(超范围)。

## 8. 裁定
**PASS-WITH-DEFECTS**（P3-1/P3-2；无 P1/P2；防冒充与上屏统计证据充分且自洽，未发现伪造）。