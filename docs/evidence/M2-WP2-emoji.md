# M2-WP2 Emoji 证据（C1 / S-EMOJI-1 最小实现）

- 日期：2026-11-13
- 工作目录：`C:\Users\ShiningRay\projects\ShiningRay\tessell`
- 任务：`task-78`（M2 门禁阻断项 C1，`docs/plan.md:244`：CJK/Emoji 样例正确显示与测量）
- 目标：补齐 **S-EMOJI-1 最小实现（R8 灰度显示 + 测量）**；彩色 COLR/CPAL 列为 **P2 不阻塞**。

## 约束遵守

- 写 Crystal 源仅使用 `write`/`edit` 工具（未用 PowerShell `Set-Content`）。
- 未伪造结果；未用 CJK 字形冒充 Emoji；`pixel_match` 由实际 `glReadPixels` 统计得出。
- 未 commit。
- 未改：`docs/evidence/M2-summary.md`、`input/*`、`a11y/*`、`widgets/*`、`core/*`、`src/tessell/text/glyph_atlas.cr`、`src/tessell/text/rasterizer.cr`、`src/tessell/text/ft_measurer.cr`。
- `src/tessell.cr` 仅追加 1 行：`require "./tessell/text/font_fallback"`（先读后 edit）。

## 变更范围（授权内）

- `src/tessell/text/font_fallback.cr`（新增）
- `spec/font_fallback_spec.cr`（新增，6 it）
- `spec/text_emoji_spec.cr`（新增，5 it）
- `examples/m2_text_window.cr`（修改：增加 `--emoji` 分支）
- `docs/evidence/M2-WP2-emoji.md`（本文档）
- `src/tessell.cr`（仅追加 1 行 require，允许例外）

## 环境与前提（已核/实测）

- 字体：`C:\Windows\Fonts\seguiemj.ttf`（12934920B，含 COLR+CPAL）、`C:\Windows\Fonts\msyh.ttc`（ttc_index=0，CJK）。
- Crystal/FT/HB 运行：`$env:PATH="C:\msys64\ucrt64\bin;$env:PATH"`。
- 实测 `seguiemj.ttf` 在本路径（`FT_Set_Pixel_Sizes` + `FT_LOAD_RENDER` + 现有 `FtMeasurer`/`Rasterizer` R8 atlas）下 **glyph bitmap pixel_mode=2（FT_PIXEL_MODE_GRAY）**，可取得非零位图覆盖；未观察到 pixel_mode=7（BGRA）。
- 全量 spec：`182 examples, 0 failures, 0 errors, 0 pending`（基线 171，新增 font_fallback 6 + emoji 5）。

## 阶段 A：字体回退纯逻辑解析器

- 实现：`src/tessell/text/font_fallback.cr`
  - `struct FontRef(path, ttc_index, family, ranges : Array(Range(UInt32,UInt32)))`，`#covers?(codepoint)` 为 O(1) 区间判断。
  - `class FontSet`：`#add(font)` 返回 add 顺序下标作为 `font_id`；`#resolve(codepoint)` 线性扫描返回**首个**覆盖字体的 `font_id`，未命中返回 `-1`；`#font_count`。
  - 纯逻辑，无文件系统依赖。
- Spec：`spec/font_fallback_spec.cr`（6 it）
  - CJK(中 U+4E2D)→msyh(id 0)
  - Emoji(U+1F600 😀, U+1F44D 👍)→seguiemj(id 1)
  - 未覆盖码点→-1
  - 空 FontSet→-1
  - 重叠区间首个生效（'a' 同时覆盖时返回 first）
  - 边界码点（start/end 命中，start-1/end+1 为 -1）

命令与结果：
```text
$env:PATH="C:\msys64\ucrt64\bin;$env:PATH"; crystal spec spec/font_fallback_spec.cr
......
Finished in 155 microseconds
6 examples, 0 failures, 0 errors, 0 pending
```

## 阶段 B：Emoji 测量与光栅（实测，seguiemj.ttf）

Spec：`spec/text_emoji_spec.cr`（5 it），对 `seguiemj.ttf` 新开 `FtMeasurer` + `GlyphAtlas(1024,4096)` + `Rasterizer(..., font_id=1)`，size 32。

原始 EVIDENCE 输出（`crystal spec spec/text_emoji_spec.cr`）：
```text
EVIDENCE_EMOJI_MEASURE1 text="😀" w=43.9375 h=34.0 glyphs=1 sum_adv=43.9375 diff=0.0
.EVIDENCE_EMOJI_MEASURE2 text="😀👍" w=87.875 h=34.0 glyphs=2 sum_adv=87.875 diff=0.0
.EVIDENCE_EMOJI_COV i=0 gid=2317 adv=43.9375 w=34 h=35 cov=743 total=1190 cov_ratio=0.6243697478991597
EVIDENCE_EMOJI_COV i=1 gid=1213 adv=43.9375 w=30 h=37 cov=473 total=1110 cov_ratio=0.4261261261261261
.EVIDENCE_EMOJI_UV count=2 ok=true
.EVIDENCE_EMOJI_PIXELMODE i=0 gid=2317 pixel_mode=2 bm_w=34 bm_h=35 pitch=34
EVIDENCE_EMOJI_PIXELMODE i=1 gid=1213 pixel_mode=2 bm_w=30 bm_h=37 pitch=30
EVIDENCE_EMOJI_PIXELMODE_SUMMARY modes=[2, 2] (2=FT_PIXEL_MODE_GRAY,7=FT_PIXEL_MODE_BGRA)
EVIDENCE_EMOJI_GRAY_NOTE pixel_mode=2 drawable_cov=1216 status=R8_gray_path_ok
.
Finished in 9.92 milliseconds
5 examples, 0 failures, 0 errors, 0 pending
```

关键实测汇总：
- "😀"：glyph 数 1（gid 2317），measure width 43.9375，高 34.0，Σadvance 43.9375，|measure-Σadvance|=0.0。
- "😀👍"：glyph 数 2（gid 2317,1213），measure width 87.875，Σadvance 87.875，|measure-Σadvance|=0.0。
- 光栅 placement：`w/h` 均 >0（34x35, 30x37），`page>=0`，UV ∈ [0,1] 且 u1>u0/v1>v0。
- coverage 非零字节数：😀 743/1190（0.6244），👍 473/1110（0.4261），drawable_cov 合计 1216（>0）。
- `pixel_mode` 实测值：**2, 2（FT_PIXEL_MODE_GRAY）**；未出现 7（BGRA），未出现全零位图。

## 阶段 C：上屏证据（`examples/m2_text_window.cr --emoji`）

实现：在现有 `m2_text_window.cr`（复用 WGL/GL 1.1 immediate mode、`TextRenderer`、R8→GL_ALPHA 路径）增加 `--emoji` 分支。
- Emoji 段使用 `seguiemj.ttf` 的 `FtMeasurer`+`GlyphAtlas`+`Rasterizer`+`TextRenderer` 渲染 `"😀👍"`。
- 文本段使用 `msyh.ttc` 渲染 `" Hello 你好"`，接在 emoji pen 之后（两段两个 renderer/atlas/GL 纹理集）。
- emoji-only pass：清屏后仅绘制 emoji 段并 `glReadPixels` 统计非背景像素（RGB 与白底差值 >8）得 `emoji_pixels_nonbg`；以 atlas 非零 R8 字节计 `emoji_cpu_coverage_sum` 计算 ratio（容差 [0.5,1.5]）得到 `emoji_pixel_match`。
- 随后连续渲染混合串 `"😀👍 Hello 你好"` 多帧计时并 `SwapBuffers`；`--verify` 时以 `emoji_pixel_match` 作为退出码依据。

命令与原始输出（`--emoji --frames=30 --verify`）：
```text
$env:PATH="C:\msys64\ucrt64\bin;$env:PATH"; crystal run examples/m2_text_window.cr -- --emoji --frames=30 --verify
emoji_quads=2 emoji_pixels_nonbg=1171 emoji_pixel_match=true frame_p50_ms=2.0138 frame_p95_ms=4.4235 frame_p99_ms=9.8351 emoji_cpu_coverage_sum=1216 emoji_ratio=0.9629934210526315 mixed_pixels_nonbg=2939 frames=30 swapbuffers=30 pen_after_emoji_x=127.875 text_quads=7
emoji_note=rendered "😀👍 Hello 你好" as emoji(seguiemj.ttf)+text(msyh.ttc) segments; emoji metrics from emoji-only pass (RGB delta>8 vs white bg, ratio tolerance [0.5,1.5]); display path R8->GL_ALPHA (gray coverage). If seguiemj bitmap were BGRA/color-only, GL_ALPHA could not show color and pixel_match would be false (not fabricated).
gl_path=GL1.1_compat R8->GL_ALPHA glPixelStorei(GL_UNPACK_ALIGNMENT,1) glTexCoord2f/glVertex2f
```

## S-EMOJI-1 三档结论

| 档位 | 状态 | 证据/说明 |
|---|---|---|
| 测量（Measurement） | **达成** | `FtMeasurer` + HB 对 seguiemj.ttf："😀"/"😀👍" glyph 数 ≥1、advance>0，`|measure - Σadvance|` = 0.0 / 0.0（`spec/text_emoji_spec.cr` 2 it 通过，EVIDENCE_EMOJI_MEASURE1/2）。 |
| R8 灰度显示（R8 gray display） | **达成** | glyph `pixel_mode=2`（FT_PIXEL_MODE_GRAY），非零 coverage（743,473；drawable_cov 1216）。`m2_text_window.cr --emoji --verify` 实测 `emoji_quads=2 emoji_pixels_nonbg=1171 emoji_pixel_match=true`（ratio 0.963，容差 [0.5,1.5]），GL 路径 R8→GL_ALPHA 灰度覆盖显示；混合串含 CJK/ASCII 亦渲染（mixed_pixels_nonbg=2939）。 |
| 彩色 COLR/CPAL（Color） | **未达成（P2，不阻塞）** | seguiemj.ttf 含 COLR+CPAL，但当前 FT 加载/渲染路径实测得到 `pixel_mode=2` 灰度位图，未得到 `pixel_mode=7`(BGRA) 彩色位图；现有 GL 管线为 R8/GL_ALPHA 调制，不支持彩色层合成/正确 alpha 合成。真实彩色 emoji 显示列为 P2 后续工作。 |

## 未验证 / 限制

- 未验证其他机器/GPU/驱动、不同 Windows 版本或不同 seguiemj 版本下的 `pixel_mode` 与显示结果（本次仅本机实测）。
- 未验证 COLR/CPAL 彩色层合成与 BGRA 位图路径（P2）；当前仅验证 R8 灰度覆盖显示。
- 未验证 emoji 序列（ZWJ、肤色修饰符、旗帜等复合序列）的 shaping/cluster 行为；本次仅覆盖单码点 😀/👍。
- 未验证不同字号/缩放下的覆盖与显示（本次测量/光栅/上屏以 32px 为主）。
- 未做 headless/无显示环境下窗口 `--verify` 的可重复性验证；本次在可创建窗口与 WGL 上下文的环境中通过。
- `FontSet` 为纯逻辑解析器（按码点区间 resolve），尚未与 `FtMeasurer`/`Rasterizer` 的多字体选择与字形实际加载路径做端到端集成（超出本任务最小交付）。

## 结论

- C1（S-EMOJI-1 最小实现）所需的**字体回退纯逻辑解析器 + Emoji 测量/光栅 spec + 上屏证据**已交付并实测通过：测量与 R8 灰度显示两档达成；彩色 COLR/CPAL 按计划记为 P2 未达成且不阻塞。
- 无伪造数据；pixel_mode 与覆盖均为实测记录。
