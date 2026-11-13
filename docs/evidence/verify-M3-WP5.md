# verify-M3-WP5 — M3-WP5 (DPI 缩放 + 主题 token) 独立核验

## §0 元信息
- 核验人：dalisi-qing-2（大理寺卿副手），受 lead 节制，只读核验
- 仓库：`C:\Users\ShiningRay\projects\ShiningRay\tessell`
- HEAD：`c364223b4f8392773119be651edc2cd7312e43ac`（工作区含未提交 M3-WP5 改动，未 commit）
- 取证环境：Windows/PowerShell，`$env:PATH="C:\msys64\ucrt64\bin;$env:PATH"`，Crystal 1.22.1
- 命令：`crystal spec`；`crystal build src\tessell.cr -o bin\tessell.exe`；`crystal run examples/m3_dpi_theme.cr -- --verify`；`-- --dpi=1.5 --theme=dark --verify`；`crystal run examples/m2_text_window.cr -- --frames=30 --verify`；`-- --emoji --frames=30 --verify`；`crystal run tools/bench_scroll.cr`；`crystal run tools/zero_alloc_frame.cr`；独立探针 `bin/_v_wp5_math.cr`（调制数学，运行后已删）；grep blend/调用点。
- 约束：未改 `src/spec/examples/tools/docs` 其他文件；临时探针已删除；未 commit。

## §1 结论总览
- **裁定：PASS-WITH-DEFECTS**
- P1：无
- P2：无（回归 2801/1171、全量 207/0f、m3_dpi_theme verify 全绿，未见已触发语义破坏）
- P3-1 **[未验证/证据不足] A 调制数学**：独立逐像素 Δ≤2 未复现（探针坐标失败，不采信其 FAIL）；实现与 J3/bg/回归支持修复方向，但不能独立证实工部“Δ=0”表
- P3-2 **C 默认前景色语义漂移风险**：`text_renderer` 默认 rgba `0xffffffff→0x000000ff`，依赖默认的调用点语义变更；仓内必跑全绿，仓外/潜在期望旧白色者风险
- P3-3（观察）：`GLBackend#close` 仅删纹理未显式 disable BLEND（end_frame 已 disable）

## §2 必跑原始结果
- `crystal spec`：**207 examples, 0 failures, 0 errors, 0 pending**（413.14ms）EXIT=0
- `crystal build src\tessell.cr -o bin\tessell.exe`：BUILD_EXIT=0（exe 已删）
- `m3_dpi_theme -- --verify` EXIT=0：`J1 mono=true px10=1605 px15=3079 px20=5094 r15=1.918380 r20=3.173832 r15_ok=true r20_ok=true j1_pass=true`；`J5 dpi_scale=1.50 theme=dark diff_pixels=0 diff_A_vs_C=1180 a_nonbg=3779 b_nonbg=3779 c_nonbg=3779 ac_loc=x=32 y=180 a=158,158,158,255 c=30,30,30,255 submitted_quads_dirty=4 submitted_quads_full=31 culled_quads=27 dirty_rects=1 corner_pixel_rgba=0x1e1e1eff expected_bg=0x1e1e1eff j5_pass=true j5_j3_pass=true`；三档 light `corner_pixel_rgba=0xffffffff expected_bg=0xffffffff`，alloc `[16,80,96]/[32,80,112]/[32,64,96] retried=false attempt=1`，`verify=pass`
- `m3_dpi_theme -- --dpi=1.5 --theme=dark --verify` EXIT=0：`J5 ... diff_pixels=0 diff_A_vs_C=1180 ... corner_pixel_rgba=0x1e1e1eff expected_bg=0x1e1e1eff j5_pass=true j5_j3_pass=true verify=pass`
- `m2_text_window -- --frames=30 --verify` EXIT=0：`text_pixels_nonbg=2801 cpu_coverage_sum=2638 ratio=1.0617892342683852 pixel_match=true frames=30 swapbuffers=30 pen_end_x=300.96875 quads=14 batches=1 gl_path=GL1.1_compat R8->GL_INTENSITY_blend_one_minus_src_alpha ...`
- `m2_text_window -- --emoji --frames=30 --verify` EXIT=0：`emoji_quads=2 emoji_pixels_nonbg=1171 emoji_pixel_match=true ... emoji_cpu_coverage_sum=1216 emoji_ratio=0.9629934210526315 mixed_pixels_nonbg=2939 frames=30 swapbuffers=30 pen_after_emoji_x=127.875 text_quads=7 gl_path=GL1.1_compat R8->GL_INTENSITY_blend_one_minus_src_alpha ...`
- `bench_scroll` EXIT=0：`scroll_plus1px ... alloc_bytes=112 frame_cpu_p50_us=106 ... windows=[112,96,112] retried=false attempt=1`；`jump_fixed_seed ... alloc_bytes=128 ... windows=[96,112,128] retried=false attempt=1`；`GL_SCROLL_WINDOW=not_done`
- `zero_alloc_frame` EXIT=0：`static frames=200 nodes=205 alloc_bytes=16 criterion_ok=true ... windows=[0,16,0] retried=false attempt=1`；`paint1 ... alloc_bytes=16 criterion_ok=true ... windows=[0,16,0] retried=false attempt=1`

## §3 穿透点 A — 调制数学（GL_INTENSITY + blend）
- 实现（读码）：`src/tessell/render/gl/gl_backend.cr:169-177` 每帧 `glEnable(GL_TEXTURE_2D)`,`glEnable(GL_BLEND)`,`glBlendFunc(GL_ONE, GL_ONE_MINUS_SRC_ALPHA)`（注释称预乘/线性覆盖修复 fg*I²→fg*I+bg*(1-I)）；`:209-214` atlas R8 → `glTexImage2D(..., GL_INTENSITY, ..., GL_LUMINANCE, GL_UNSIGNED_BYTE, data)`，texel=(I,I,I,I)；顶点色为 straight fg（`:373-381` emit RGBA）。
- 独立探针 `bin/_v_wp5_math.cr`（自写，Theme.dark "Sample gyAV" 48px，HB/FT raster+atlas 取 slot 字节 I，GL readback 像素，对照 linear/I²）：**EXIT=1 FAIL，结论不采信**。输出：`SELECTED count=6 edge=3 has_opaque=true has_i0=true total_glyph_samples=8757`；edge (51,83) I=126 meas=15,15,15,255 exp_linear=126,126,126,255 Δl=111 Δi2=55；(61,83) I=132 meas=14,14,14,255 Δl=116；(48,84) I=117 meas=16,16,16,255 Δl=103；opaque (50,84) I=255 meas=0,0,0,255 Δl=224；glyph_I0/blank Δl=0。诊断：边缘/不透明采样坐标落在字形外（measured≈bg/极暗）与实现/J5 证据矛盾，属探针 readback/屏幕坐标映射 bug；探针已删。
- 独立可采信证据：`m3_dpi_theme --dpi=1.5 --theme=dark --verify` → `corner_pixel_rgba=0x1e1e1eff expected_bg=0x1e1e1eff j5_j3_pass=true`（I=0/底色精确），`ac_loc=x=32 y=180 a=158,158,158,255 c=30,30,30,255`（暗底 30,30,30 上出现 158,158,158 字形像素，非 I² 全暗），`diff_pixels=0 diff_A_vs_C=1180`；`--verify` light 三档 corner/bg 精确、J1 单调比例过；回归 m2 2801/1171 match=true。实现链路与工部修复方向一致。
- 判定：**[未验证/证据不足]**。未能独立产出“≥3 半覆盖 + I=255 + I=0 且各 Δ≤2”逐像素对照表；不能确认也不能否定工部 Δ=0 声称（P3-1）。

## §4 穿透点 B — 混合状态泄漏
- grep：`gl_backend.cr:32/69-71/169-170/177/180/187/252/284/424-426`；`gl_renderer.cr` 无 blend 调用（`begin_frame` 仅委托 backend）。
- 成对性：`begin_frame :169-177` 每帧设 `GL_BLEND` + `GL_ONE,GL_ONE_MINUS_SRC_ALPHA`；draw 路径 `:251-345`、全帧/dirty 分支均无 `glBlendFunc/glEnable(GL_BLEND)/glDisable(GL_BLEND)` 切换（仅 scissor/texture/begin-end quads）；`end_frame :425` `glDisable(GL_BLEND)`（与 170 配对）；`close :431-433` 仅 `delete_textures` 未 disable（非帧内状态、P3 观察）。
- 结论：帧内混合状态单一且一致设置，无同帧两种混合并存证据。**通过（保留 close 观察项）**。

## §5 穿透点 C — 默认前景色影响面（`0x000000ff`）
- 变更：`src/tessell/render/text_renderer.cr:48,81,106,129,154` 默认 `rgba : UInt32 = 0x000000ff`（原 0xffffffff）。
- 依赖默认（未显式传 rgba）：`examples/m2_text_window.cr:347,349,355,357,387,389,435,437,459` build_text；`tools/bench_scroll.cr:56,88,127,170,203,261,310,343,383,413,473` build_text/build_text_cached；`spec/text_renderer_spec.cr:15,31,46,66,90,117,148,149,173,177,185,221` build_text（spec 仍绿，顶点色按默认黑写入，与白底/断言兼容）。
- 显式传 rgba/不受默认影响：`examples/m3_dpi_theme.cr:269-271,274` append_text_cached(..., theme_fg)；`examples/m3_dirty_window.cr:208-212` append_text_cached（签名走主题/显式路径）；`spec/backend_protocol_spec.cr:174-177` Vertex.rgba 显式 0xffffffff；`spec/theme_spec.cr:75` 主题 bg 断言。
- 评估：白底场景下黑字可见，回归 2801/1171 与全量 207/0f 证明仓内现有路径未破坏；但 API 默认语义由白变黑，若调用方在非白底/暗底期望旧“白色默认”将出现对比度/可见性反转风险（主题化调用如 m3_dpi_theme 已显式传 fg，规避）。记 **P3-2**（风险，非实证缺陷）。

## §6 穿透点 D — J3 逐字节 + J4 零分配判据
- J3：`examples/m3_dpi_theme.cr:465-482` 逐字节比较 corner RGBA 与 `theme.bg`，失败则计算并输出 `bg_pixel_delta=dr,dg,db,da actual=... expected=...` 且 `j3_pass=false`（反例分支可达，非始终 true）；本次 `--verify`/`--dpi=1.5 --theme=dark --verify` 均 `corner_pixel_rgba==expected_bg`、`j5_j3_pass=true`，delta 分支未触发但存在。
- J4（示例 alloc probe）：`m3_dpi_theme.cr:496-556` warmup 后 3 窗测量，`GC.disable`→N=1000 次 `render_full`→读 delta→`ensure GC.enable`（:511-524,536-549），取 `windows.max`；criterion `mxw >= 1000_i64 || mxw > 256_i64` 则失败并**至多 1 次**整窗重试 `retried=true attempt=2`（:528-552）后仍判 `j4_pass = alloc_bytes < 1000 && alloc_bytes <= 256`（:555）；未缩短 N、无提前 break 放水。实测：light 三档/verify windows ≤112，dark verify j5 前 J1/J4 路径同口径均 `retried=false attempt=1`。
- J4（backend spec）：`spec/backend_protocol_spec.cr` probe 打印 `delta_prime=0 delta_calib=0 delta_work=16 N=1000 windows=[0,16,0]/[16,0,0] retried=false attempt=1`，8/0f；判据 3 窗 max + A `<N` + B `<=256`、整窗重试≤1、ensure GC.enable（与既有 WP5/M3 口径一致）。
- 结论：**通过**（J3 分支可达、J4 无放水）。

## §7 回归与对照
- m2_text_window（light/white 默认路径）：2801（基线 2801）、ratio 1.061789，emoji 1171/1216=0.962993 均 match=true，gl_path `R8->GL_INTENSITY_blend_one_minus_src_alpha`；与历史基线一致。
- bench/zero_alloc：alloc 112/128（≤256）、static/paint1 16 bytes criterion_ok=true；无异常峰值。
- 工部声称 Δ=0：我方未能独立逐像素复现（P3-1），但实现/回归/J3 bg 证据未构成反证。

## §8 裁定与缺陷清单
- **裁定：PASS-WITH-DEFECTS**（P1/P2 无；P3 项见下）
- **P3-1（证据不足）A 调制数学独立复现失败**：自写探针 `bin/_v_wp5_math.cr`（已删）EXIT=1、采样坐标错误导致 measured 偏离 atlas I，不可作为 Δ 证据；未满足“暗色 ≥3 半覆盖 + I=255 + I=0 且 Δ≤2”独立对照。实现 `gl_backend.cr:170-177,209-214` 与回归/J5 bg 支持修复，但 [未验证]。文件：`src/tessell/render/gl/gl_backend.cr:170-177,209-214`（实现待独立数学确证）。
- **P3-2（语义漂移风险）默认前景色**：`src/tessell/render/text_renderer.cr:48,81,106,129,154` 默认 `0x000000ff`；依赖默认调用点 `examples/m2_text_window.cr:347,349,355,357,387,389,435,437,459`、`tools/bench_scroll.cr:56,88,127,170,203,261,310,343,383,413,473`、`spec/text_renderer_spec.cr:15,31,46,66,90,117,148,149,173,177,185,221` 等当前绿但语义变化。
- **P3-3（观察）close 未 disable BLEND**：`src/tessell/render/gl/gl_backend.cr:431-433`（end_frame:425 已 disable）。

## §3A 合成覆盖度梯度验证（task-105，A-recheck）

方法：自造 atlas 条目，已知覆盖度 I∈{0,64,128,255}，1 texel=1 屏幕像素 quad，
NEAREST 采样，直接读回 4 像素；不依赖 FT/HB 光栅化与坐标反解。

探针输出（bin/_v_wp5_grad.cr，运行后删除，EXIT=0）：
```
SYNTH I=0 screen=(10,10) measured=30,30,30,255 exp_linear=30,30,30,255 delta_linear=0 exp_i2=30,30,30,255 delta_i2=0
SYNTH I=64 screen=(11,10) measured=78,78,78,255 exp_linear=79,79,79,255 delta_linear=1 exp_i2=37,37,37,207 delta_i2=48
SYNTH I=128 screen=(12,10) measured=127,127,127,255 exp_linear=127,127,127,255 delta_linear=0 exp_i2=71,71,71,191 delta_i2=64
SYNTH I=255 screen=(13,10) measured=224,224,224,255 exp_linear=224,224,224,255 delta_linear=0 exp_i2=224,224,224,255 delta_i2=0
THEME bg=0x1e1e1eff fg=0xe0e0e0ff page0_writable=true ps=64 tex=1 slot_bytes=0,64,128,255 submitted=1
CHECK all_delta_linear_le2=true I0_eq_bg=true I255_eq_fg=true
A_RECHECK=PASS
```

结论：I=0 逐字节等于 bg（30,30,30,255），I=255 逐字节等于 fg（224,224,224,255），
Δ_linear≤1≤2（通过），Δ_i²=48/64（显著大于 2，确认 I² 模型已被排除）。
A-recheck=PASS

**P3-1 修正**：此前 [未验证] 标记撤回，A 点现在有独立证据。
- 暗色主题 ≥3 半覆盖边缘像素 + I=255 + I=0 的 measured vs `fg*I+bg*(1-I)`/`fg*I²+bg*(1-I)` 逐像素对照且 Δ≤2（独立探针失败）。
- 不同 GPU/驱动/GL 实现下 `GL_INTENSITY`+premultiplied blend 的像素级一致性（本机单次环境）。
- 交互窗口目视/截图对比（仅 verify/headless 证据）。
- 仓外或未来依赖旧默认白色前景的调用兼容性。
- 本报告行数：`(Get-Content docs/evidence/verify-M3-WP5.md | Measure-Object -Line).Lines` 结果见回报。

