# M3-WP5: DPI 缩放 + Theme token 证据（task-101）

- 任务：task-101（M3-WP5 实现：Theme 值类型 + DPI 缩放纯函数 + 后端主题接入 + m3_dpi_theme example J1–J5）
- 仓库：`C:\Users\ShiningRay\projects\ShiningRay\tessell`
- 基线提交：`HEAD c364223b4f8392773119be651edc2cd7312e43ac`（工作区在此基础上修改，未 commit）
- 环境：Windows，Crystal `1.22.1 [23828b0a40] (2026-04-21)`，`$env:PATH="C:\msys64\ucrt64\bin;$env:PATH"`
- 取证时间样本：`2026-11-13T15:34:33+08:00 [Asia/Shanghai]`
- 约束遵守：Crystal 源仅 `write/edit`；DPI 感知 FFI（`SetProcessDpiAwarenessContext`）仅在 `examples/m3_dpi_theme.cr` 的 `--dpi-aware` 显式参数下调用，`src/` 无自动初始化；`docs/evidence/M2-*.md`、`docs/research/m3-platform-matrix.md` 未改动。

## 1. 阶段 A：核心类型（已完成并回报）

### 1.1 新增/修改文件
- `src/tessell/render/theme.cr`：`struct Tessell::Render::Theme`，值类型；字段 `bg/fg/accent/muted/border/selection : UInt32`（格式 `0xRRGGBBAA`）。
  - 通道解包（静态，无分配）：`rb/gb/bb/ab(c):UInt8`；归一化：`r/g/b/a(c):Float32`（`byte/255.0f32`）。
  - 预设：`Theme.light` = `bg 0xffffffff fg 0x000000ff accent 0x2f6fedff muted 0x8a8a8aff border 0xd0d0d0ff selection 0xbcd4ffff`；`Theme.dark` = `bg 0x1e1e1eff fg 0xe0e0e0ff accent 0x4c8dffff muted 0x9a9a9aff border 0x3a3a3aff selection 0x2b4a7dff`。
- `src/tessell/render/dpi.cr`：`module Tessell::Render::Dpi`，纯函数、不调 FFI。
  - `scale_for(dpi : UInt32) : Float32` = `dpi/96.0f32`，clamp `[0.5, 4.0]`。
  - `size_px(point_size : Float32, scale : Float32) : Float32` = `(point_size*scale).round`，下限 `1.0f32`。
  - `logical_to_device(v : Float32, scale : Float32) : Float32` = `v*scale`。
- `src/tessell.cr`：追加 `require "./tessell/render/theme"`、`require "./tessell/render/dpi"`。
- `spec/theme_spec.cr`（7 examples）、`spec/dpi_spec.cr`（6 examples）。

### 1.2 阶段 A spec 结果（原始行）
```
$env:PATH="C:\msys64\ucrt64\bin;$env:PATH"; crystal spec spec/theme_spec.cr spec/dpi_spec.cr
.............
Finished in 15.52 milliseconds
13 examples, 0 failures, 0 errors, 0 pending
```
全量：`207 examples, 0 failures, 0 errors, 0 pending`（基线 194 + 13）。

## 2. 阶段 B：后端主题接入与渲染改动

### 2.1 Backend/GL 接口与行为
- `src/tessell/render/backend.cr`：`require "./theme"`；抽象签名改为
  - `abstract def begin_frame(dirty : Array(Tessell::Rect)? = nil, theme : Tessell::Render::Theme = Tessell::Render::Theme.light) : Nil`
- `src/tessell/render/gl/gl_backend.cr`：
  - `begin_frame` 同步接收 `theme`（默认 `Theme.light`），清屏色取自 `Theme.r/g/b/a(theme.bg)`；保留 dirty-nil 全帧清屏与 dirty-rect scissor+局部清屏/绘制语义。
  - **移除硬编码** `glColor4f(0.0,0.0,0.0,1.0)`（原在 blend 设置后）；改为逐顶点色：新增 `emit_vertex(v)` 输出 `glColor4f`（由 `v.rgba` 拆 RRGGBBAA 字节归一化）+ `glTexCoord2f` + `glVertex2f`；全帧与 dirty 批次路径均使用 `emit_vertex`。
  - 图集纹理上传由 `GL_ALPHA` 改为 `GL_INTENSITY`（internal）+ `GL_LUMINANCE`（format），使覆盖度 texel 变为 `(I,I,I,I)` 并与顶点色调制：`(R*I,G*I,B*I,A*I)`，从而 `Vertex.rgba`（主题 fg/调用方 rgba）可正确着色文本（含深色主题前景）。
  - **混合（task-103 修复）**：`glBlendFunc(GL_ONE, GL_ONE_MINUS_SRC_ALPHA)`（预乘覆盖度混合）。图集为 INTENSITY 覆盖度纹理、顶点色为直通（非预乘）前景色，故片元为 `(fg*I, I)`，输出 `rgb = fg*I + bg*(1-I)`、`alpha = I + (1-I) = 1`。修复前误用 `(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA)` 会再次乘 alpha 得 `fg*I^2`（双重乘 coverage）。
  - `set_clear_color(r,g,b,a)` 保留以兼容既有 example（如 `m3_dirty_window.cr`）。`end_frame` 恢复 `GL_SCISSOR_TEST/GL_BLEND/GL_TEXTURE_2D` 为禁用，避免状态泄漏。
- `src/tessell/render/gl/gl_renderer.cr`：`begin_frame(viewport_w,h,bg_r,g,b,a)` 将 bg float 转为 `Theme` 并委托 `begin_frame(viewport_w,h,theme)` → `@backend.begin_frame(nil, theme)`；新增 `begin_frame(viewport_w,h,theme)` 重载；无独立 `glBlendFunc` 调用（混合由后端统一设置）。
- `spec/backend_protocol_spec.cr`：`RecordingBackend#begin_frame` 签名同步增加 `theme` 参数（默认 light）；全量 spec 回归通过。
- `examples/m2_text_window.cr`：`gl_path` 打印串更新为 `R8->GL_INTENSITY_blend_one_minus_src_alpha`（仅字符串，与实际格式/混合一致；测量逻辑未改）。

### 2.2 TextRenderer 颜色默认值
- `src/tessell/render/text_renderer.cr`：`append_text_cached/build_text/build_text_cached` 及兼容重载的默认 `rgba` 由 `0xffffffff_u32` 调整为 `0x000000ff_u32`（RRGGBBAA，黑色不透明），以适配 INTENSITY 调制下“默认文本可见且可被显式 rgba 覆盖”的语义；调用方可传入 `theme.fg` 或任意 `rgba`。

### 2.3 坐标与缩放约定
- DPI：`scale = Dpi.scale_for(dpi)`（96→1.0, 120→1.25, 144→1.5, 192→2.0，clamp [0.5,4.0]）。
- 字号/光栅：`size_px = Dpi.size_px(point_size, scale).to_i`（示例用 16pt；13pt@1.25→16px 由 Dpi 规则实测验证于 spec）；`size_px` 参与 glyph raster/cache key（`GlyphKey.size_px`），不同 DPI 自然隔离缓存条目。
- 布局/顶点：示例将逻辑坐标经 `Dpi.logical_to_device(v, scale)` 转为设备像素后生成四边形（y-down 屏幕空间，与现有 `glOrtho(0,w,h,0,-1,1)` 一致）。
- 背景：由 `theme.bg` 决定 clear color 与 J3 期望值；前景文本由 `theme.fg` 作为 `Vertex.rgba` 传入。

## 3. 新增示例与判据实现（`examples/m3_dpi_theme.cr`）

- 参数：`--dpi=1.0|1.25|1.5|2.0`、`--theme=light|dark`、`--frames=N`、`--verify`、`--dpi-aware`。
- `--dpi-aware`：仅在 example 内调用 `SetProcessDpiAwarenessContext(PER_MONITOR_AWARE_V2)`（`-4`），不进入 `src/`。
- 场景：≥3 段文本（`Hello DPI` / `Theme Token` / `Scale Test`），文本颜色 `theme.fg`；J5 增加 `MOVE` 元素并做位移产生 dirty 区域。
- 输出 token（每 case 一行）：`dpi_scale theme_bg theme_fg text_pixels_nonbg corner_pixel_rgba expected_bg text_advance pen_end_x quads batches alloc_bytes alloc_windows retried attempt [bg_pixel_delta=...] verify`；`--verify` 另输出 J1 汇总行、J5 行与总 `verify=pass|fail`。
- 取样注意：J3 角点与帧像素在 **SwapBuffers 前** 从后缓冲读取（避免呈现后前/后缓冲状态不确定）；角点取 GL 窗口坐标 `(0, h-1)` 对应 y-down 左上角。
- J4 探针：预热（含 atlas sync）后 3 组窗口 × 1000 帧 `render_full`，`GC.disable/enable` in ensure，记录 3 窗 max；首轮不满足 `delta_work < 1000` 且 `delta_work <= 256` 则重试 1 次（`retried/attempt` 如实输出）。

### 3.1 判据对照（按首辅裁定）
- **J1**：`--verify` 下对 dpi 1.0/1.5/2.0（light）测 `text_pixels_nonbg`，要求严格单调 `px(1.0)<px(1.5)<px(2.0)` 且 `r15=px(1.5)/px(1.0) ∈ [1.5,3.5]`、`r20=px(2.0)/px(1.0) ∈ [2.5,5.0]`。
- **J3**：读回画布左上角像素 RGBA 必须**逐字节等于** `theme.bg`；不等则打印 `bg_pixel_delta=dr,dg,db,da actual=... expected=...` 并 fail（未加容差）。
- **J4**：稳态零分配判据 A `delta_work < 1000`、B `delta_work <= 256`，3 窗取 max，重试最多 1 次。
- **J5**：`dpi=1.5 theme=dark`，脏区提交（`Dirty.merge_into`）与整帧重绘逐字节比较，要求 `diff_pixels==0`、`diff_A_vs_C>0`（防空证明）、`submitted_quads_dirty < submitted_quads_full`。

## 4. 实测结果（task-101，修复前基线记录）

### 4.1 `crystal run examples/m3_dpi_theme.cr -- --verify`（EXIT 0，task-101 当时取证）
```
dpi_scale=1.00 theme_bg=0xffffffff theme_fg=0x000000ff text_pixels_nonbg=1605 corner_pixel_rgba=0xffffffff expected_bg=0xffffffff text_advance=71.554688 pen_end_x=91.554688 quads=27 batches=3 alloc_bytes=80 alloc_windows=[32,80,80] retried=false attempt=1 verify=pass
dpi_scale=1.50 theme_bg=0xffffffff theme_fg=0x000000ff text_pixels_nonbg=3079 corner_pixel_rgba=0xffffffff expected_bg=0xffffffff text_advance=107.332031 pen_end_x=137.332031 quads=27 batches=3 alloc_bytes=96 alloc_windows=[32,64,96] retried=false attempt=1 verify=pass
dpi_scale=2.00 theme_bg=0xffffffff theme_fg=0x000000ff text_pixels_nonbg=5094 corner_pixel_rgba=0xffffffff expected_bg=0xffffffff text_advance=143.109375 pen_end_x=183.109375 quads=27 batches=3 alloc_bytes=96 alloc_windows=[64,48,96] retried=false attempt=1 verify=pass
J1 mono=true px10=1605 px15=3079 px20=5094 r15=1.918380 r20=3.173832 r15_ok=true r20_ok=true j1_pass=true
J5 dpi_scale=1.50 theme=dark diff_pixels=0 diff_A_vs_C=1181 a_nonbg=3784 b_nonbg=3784 c_nonbg=3784 ac_loc=x=32 y=180 a=108,108,108,198 c=30,30,30,255 submitted_quads_dirty=4 submitted_quads_full=31 culled_quads=27 dirty_rects=1 corner_pixel_rgba=0x1e1e1eff expected_bg=0x1e1e1eff j5_pass=true j5_j3_pass=true
verify=pass
EXIT=0
```

### 4.2 `crystal run examples/m3_dpi_theme.cr -- --dpi=1.5 --theme=dark --verify`（EXIT 0，task-101 当时取证）
```
dpi_scale=1.00 theme_bg=0xffffffff theme_fg=0x000000ff text_pixels_nonbg=1605 corner_pixel_rgba=0xffffffff expected_bg=0xffffffff text_advance=71.554688 pen_end_x=91.554688 quads=27 batches=3 alloc_bytes=96 alloc_windows=[16,64,96] retried=false attempt=1 verify=pass
dpi_scale=1.50 theme_bg=0xffffffff theme_fg=0x000000ff text_pixels_nonbg=3079 corner_pixel_rgba=0xffffffff expected_bg=0xffffffff text_advance=107.332031 pen_end_x=137.332031 quads=27 batches=3 alloc_bytes=80 alloc_windows=[32,80,64] retried=false attempt=1 verify=pass
dpi_scale=2.00 theme_bg=0xffffffff theme_fg=0x000000ff text_pixels_nonbg=5094 corner_pixel_rgba=0xffffffff expected_bg=0xffffffff text_advance=143.109375 pen_end_x=183.109375 quads=27 batches=3 alloc_bytes=64 alloc_windows=[48,64,64] retried=false attempt=1 verify=pass
J1 mono=true px10=1605 px15=3079 px20=5094 r15=1.918380 r20=3.173832 r15_ok=true r20_ok=true j1_pass=true
J5 dpi_scale=1.50 theme=dark diff_pixels=0 diff_A_vs_C=1181 a_nonbg=3784 b_nonbg=3784 c_nonbg=3784 ac_loc=x=32 y=180 a=108,108,108,198 c=30,30,30,255 submitted_quads_dirty=4 submitted_quads_full=31 culled_quads=27 dirty_rects=1 corner_pixel_rgba=0x1e1e1eff expected_bg=0x1e1e1eff j5_pass=true j5_j3_pass=true
verify=pass
EXIT=0
```
说明：example 在 `--verify` 模式下固定执行 J1 扫描（1.0/1.5/2.0）+ J5（1.5 dark），因此附带 `--dpi/--theme` 时仍输出完整 sweep/J5 证据与 J5 dark 结果（含 requested 场景）。`alloc_windows/alloc_bytes` 为 GC 探针观测值，运行间可有小波动；判据为 A `<1000` 且 B `<=256`。

### 4.3 结果解读（task-101）
- J1：`mono=true`，`r15=1.918380 ∈ [1.5,3.5]`，`r20=3.173832 ∈ [2.5,5.0]`，`j1_pass=true`。
- J3：light/dark 相关帧 `corner_pixel_rgba == expected_bg`（0xffffffff / 0x1e1e1eff），未出现 `bg_pixel_delta=`。
- J4：`alloc_bytes < 1000` 且 `<= 256`，`retried=false attempt=1`。
- J5：`diff_pixels=0`，`diff_A_vs_C=1181>0`，`submitted_quads_dirty=4 < submitted_quads_full=31`，`culled_quads=27`，`dirty_rects=1`，`j5_pass=true j5_j3_pass=true`。

## 5. 颜色与混合（覆盖度调制与 I² 缺陷修复，task-103）

### 5.1 公式与实现
- 图集：R8 覆盖度上传为 `GL_INTENSITY`（internal）/`GL_LUMINANCE`（format），采样 texel 为 `(I,I,I,I)`，其中 `I = atlas_R8/255`。
- 顶点色：`Vertex.rgba` 为直通（非预乘）前景色 `(fg_r,fg_g,fg_b,fg_a)`，`a_fg=1`（如 `0xe0e0e0ff`）。
- 调制后片元：`src = (fg*I, a_fg*I)`。
- 混合：`glBlendFunc(GL_ONE, GL_ONE_MINUS_SRC_ALPHA)`（预乘覆盖度混合）在不透明画布上得到
  - `out_rgb = src_rgb + dst_rgb*(1-src_a) = fg*I + bg*(1-I)`
  - `out_a   = src_a   + dst_a*(1-src_a)   = I + 1*(1-I) = 1`（**画布 alpha 恒为 255**，语义约束：当前后端面向不透明窗口画布，不表达文本覆盖度到最终 framebuffer alpha）
- 缺陷根因（修复前）：使用 `glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA)` 时 RGB 再乘 `src_a=I`，变为 `out_rgb = fg*I*I + bg*(1-I)`（覆盖率被乘两次，边缘发暗），alpha 为 `I^2 + 1*(1-I)`。

### 5.2 修复前后边缘像素对照（同一 NEAREST 探针，`S`@48px，Theme.dark bg=0x1e1e1eff fg=0xe0e0e0ff）

| 状态 | screen_xy | atlas_xy | atlas I | L=I/255 | measured RGBA | expected `fg*I+bg*(1-I)` (RGB,α) | Δ(线性) | expected `fg*I^2+bg*(1-I)` (RGB) | Δ(I²) |
|---|---|---:|---:|---:|---|---|---:|---|---:|
| 修复前 | (51,83) | (8,0) | 126 | 0.494118 | 70,70,70,191 | 126,126,126,255 | 56 | 70,70,70 | 0 |
| 修复前 | (52,83) | (9,0) | 178 | 0.698039 | 118,118,118,201 | 165,165,165,255 | 47 | 118,118,118 | 0 |
| 修复前 | (60,83) | (17,0) | 180 | 0.705882 | 120,120,120,202 | 167,167,167,255 | 47 | 120,120,120 | 0 |
| 修复后 | (51,83) | (8,0) | 126 | 0.494118 | 126,126,126,255 | 126,126,126,255 | **0** | 70,70,70 | 56 |
| 修复后 | (52,83) | (9,0) | 178 | 0.698039 | 165,165,165,255 | 165,165,165,255 | **0** | 118,118,118 | 47 |
| 修复后 | (60,83) | (17,0) | 180 | 0.705882 | 167,167,167,255 | 167,167,167,255 | **0** | 120,120,120 | 47 |

结论：修复后 3 个半覆盖边缘像素均满足 `measured ≈ fg*I + bg*(1-I)` 且 **max_delta=0（≤2）**；alpha 为 255（不透明画布，符合 `I + 1*(1-I)=1`）。

### 5.3 探针原始输出（修复后，task-103）

```
THEME bg=30,30,30,255(0x1e1e1eff) fg=224,224,224,255(0xe0e0e0ff)
EDGE idx=0 screen_xy=(51,83) atlas_xy=(8,0) atlas_I=126 L=I/255=0.494118
  measured_rgba=126,126,126,255
  expected_linear_fgI_plus_bg1mI=126,126,126 a=255 max_delta=0
  expected_I2_fgI2_plus_bg1mI=70,70,70 max_delta=56
EDGE idx=1 screen_xy=(52,83) atlas_xy=(9,0) atlas_I=178 L=I/255=0.698039
  measured_rgba=165,165,165,255
  expected_linear_fgI_plus_bg1mI=165,165,165 a=255 max_delta=0
  expected_I2_fgI2_plus_bg1mI=118,118,118 max_delta=47
EDGE idx=2 screen_xy=(60,83) atlas_xy=(17,0) atlas_I=180 L=I/255=0.705882
  measured_rgba=167,167,167,255
  expected_linear_fgI_plus_bg1mI=167,167,167 a=255 max_delta=0
  expected_I2_fgI2_plus_bg1mI=120,120,120 max_delta=47
FOUND=3 pen_end_x=67.703125 quads=1
PROBE_EXIT=0
```

## 6. 回归与全量验证（task-103，修复后）

### 6.1 `crystal run examples/m3_dpi_theme.cr -- --verify` 与 `-- --dpi=1.5 --theme=dark --verify`
（原始 token 行与 EXIT 见本次回报附录；J1/J3/J4/J5 均 pass，未出现 `bg_pixel_delta=`。）

### 6.2 `m2_text_window` 回归
- `crystal run examples/m2_text_window.cr -- --frames=60 --verify`：`text_pixels_nonbg=2801 cpu_coverage_sum=2638 ratio=1.0617892342683852 pixel_match=true`，EXIT 0（与基线 2801 / ratio≈1.0618 一致）。
- `crystal run examples/m2_text_window.cr -- --emoji --frames=30 --verify`：`emoji_quads=2 emoji_pixels_nonbg=1171 emoji_pixel_match=true emoji_cpu_coverage_sum=1216 emoji_ratio=0.9629934210526315 mixed_pixels_nonbg=2939`，EXIT 0（与基线 1171 / match=true 一致）。
- 说明：白底+黑字场景下 `out = fg*I + bg*(1-I)` 与修复前 `fg*I^2 + bg*(1-I)` 在 fg=0,bg=1（或等价黑白极值）时数值等价，故计数/判据不变；`gl_path` 字符串已更新为实际格式/混合。

### 6.3 全量 spec
```
$env:PATH="C:\msys64\ucrt64\bin;$env:PATH"; crystal spec
207 examples, 0 failures, 0 errors, 0 pending
```

### 6.4 bench / zero_alloc（各 1 次）
（原始行见本次回报附录；`tools/bench_scroll.cr`、`tools/zero_alloc_frame.cr` 正常产出。）

## 7. 与 `docs/research/dpi-theme.md` 的偏差记录

- **J1 阈值（按首辅裁定）**：采用 `r15 ∈ [1.5,3.5]`、`r20 ∈ [2.5,5.0]` 且严格单调（面积按 scale² 增长）；研究文档中给出的 `[1.3,1.7]`/`[2.5,3.5]` 区间与面积增长/实测像素计数存在矛盾，故实现与证据以 lead 裁定为准。
- **文本着色/GL 路径**：为支持主题前景色，GL atlas 上传改为 `GL_INTENSITY/GL_LUMINANCE` 并启用逐顶点 `glColor4f(Vertex.rgba)` 调制；`TextRenderer` 默认 `rgba` 调整为 `0x000000ff_u32`（可被 `theme.fg` 覆盖）。task-103 进一步将混合由错误的 `(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA)`（导致 `fg*I^2` 双重乘 coverage）修正为预乘语义 `(GL_ONE, GL_ONE_MINUS_SRC_ALPHA)`，得到 `out = fg*I + bg*(1-I)`、`alpha=1`（不透明画布）。研究草案未细化此 GL/混合细节，属实现必要偏差与缺陷修复。
- **DPI 感知调用点**：`SetProcessDpiAwarenessContext` 仅在 `examples/m3_dpi_theme.cr --dpi-aware` 中调用，未在 `src/` 自动初始化（与 lead 约束一致）。
- **J3 严格性**：按要求逐字节比较、无容差；若出现 ±1 将输出 `bg_pixel_delta=` 并 fail（本次未触发）。

## 8. 未验证清单（每条附验证所需）

1. **真实 DPI/多显示器**：未实测 `WM_DPICHANGED`、跨显示器拖拽、`GetDpiForWindow`/manifest 在不同 Windows 版本行为与 fallback。需要：在 100%/125%/150%/200% 多显示器环境运行带 `--dpi-aware` 的窗口并拖拽跨屏，记录系统 DPI、窗口物理/逻辑尺寸与渲染输出。
2. **`--dpi-aware` 实效**：仅调用 API 未验证其对实际窗口/DPI 查询与缩放链路的端到端影响。需要：对比有/无 `--dpi-aware` 下 `GetDpiForWindow`、客户区像素尺寸与 readback 像素比例。
3. **不同 GPU/驱动/GL 实现**：仅在当前机器单次会话验证；`GL_INTENSITY/GL_LUMINANCE`、readback RGBA 字节序/精度在其他驱动上未验证。需要：在不同显卡/驱动与 WGL 实现上重跑 `m3_dpi_theme --verify` 并比对 token/J3。
4. **Subpixel/ClearType 与 gamma**：未处理 subpixel 渲染、LCD 布局与 gamma 校正；高 DPI 下视觉锐度/覆盖率与像素计数可能随策略变化。需要：引入/对比 subpixel 模式并在多 DPI 下做视觉与计数基线。
5. **主题切换热路径分配**：J4 仅覆盖示例 `render_full` 稳态；真实 UI 频繁切主题/重建场景/缓存失效路径未做长时分配与性能剖析。需要：压力场景连续切换 theme/dpi 并采集 GC/allocation 与帧时间区间。
6. **字体/字形覆盖**：仅用 `C:/Windows/Fonts/msyh.ttc` 与固定文本；其他字体、fallback、emoji 与复杂整形在 theme+缩放下未验证。需要：扩展样例与对应字体可用性后实测。

## 9. 行数（`[System.IO.File]::ReadAllLines` 口径，task-103 回报时复核）

- `examples/m3_dpi_theme.cr`：724
- `docs/evidence/M3-WP5-dpi-theme.md`：见本次回报（ReadAllLines 实测值）
- `spec/theme_spec.cr`：87
- `spec/dpi_spec.cr`：41
