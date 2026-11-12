# W2-核验1：文本依赖与 FFI 探针独立核验报告（task-8/9）

- 报告：`docs/evidence/verify-W2-text.md`
- 核验对象：`examples/m0_ffi_load.cr`、`examples/m0_text_probe.cr`、`docs/evidence/M0-WP4-text-deps.md`、`docs/evidence/M0-WP4-text.md`
- 任务：`task-13`「W2-核验1：文本依赖与 FFI 探针独立核验（task-8/9）」
- 核验方：dalisi-qing（大理寺卿，独立核验，只读重跑+写本报告）

## 1) 核验环境

- 本地时间：2026-11-12 17:05 (approx, from session context) / 复核采集时段 2026-11-12 17:0x +08:00
- 工作目录：`C:\Users\ShiningRay\projects\ShiningRay\tessell`
- HEAD：`1b0d832220f3017e9efd6f42d59b5d7fab6b09f3`（`git rev-parse HEAD`）
- OS：`Microsoft Windows NT 10.0.26300.0`；Arch：`AMD64`
- Crystal：`C:\msys64\ucrt64\bin\crystal.exe`，`Crystal 1.22.1 [23828b0a40] (2026-10-23)`，`LLVM: 23.1.3`，`Default target: x86_64-w64-windows-gnu`
- 重跑 PATH 前置：`$env:PATH="C:\msys64\ucrt64\bin;"+$env:PATH`（按任务书）
- 依赖（证据/本机）：`mingw-w64-ucrt-x86_64-freetype 2.15.0-1`，`mingw-w64-ucrt-x86_64-harfbuzz 15.1.0-1`；`C:\msys64\ucrt64\bin\libfreetype-6.dll`，`C:\msys64\ucrt64\bin\libharfbuzz-0.dll`（见 task-8 证据）

## 2) 重跑命令与原始输出（逐项）

### 2.1 `examples/m0_ffi_load.cr`

命令：
```powershell
$env:PATH="C:\msys64\ucrt64\bin;"+$env:PATH
crystal run examples/m0_ffi_load.cr 2>&1
"EXITCODE=$LASTEXITCODE"
```

原始输出：
```
ft_init_ok=true
ft_library_version=2.15.0
hb_version_string=15.1.0
hb_version=15.1.0
EXITCODE=0
```

与证据 `docs/evidence/M0-WP4-text-deps.md` 对比：`ft_init_ok=true`、`ft_library_version=2.15.0`、`hb_version_string=15.1.0`、`hb_version=15.1.0`、`EXITCODE=0` 一致。

### 2.2 `examples/m0_text_probe.cr`

命令：
```powershell
$env:PATH="C:\msys64\ucrt64\bin;"+$env:PATH
crystal run examples/m0_text_probe.cr 2>&1
"EXITCODE=$LASTEXITCODE"
```

原始输出：
```
zh_glyph[0].codepoint=1154
zh_glyph[0].advance=1536
zh_glyph[1].codepoint=1521
zh_glyph[1].advance=1536
zh_glyph[2].codepoint=3
zh_glyph[2].advance=455
zh_glyph[3].codepoint=58
zh_glyph[3].advance=795
zh_glyph[4].codepoint=75
zh_glyph[4].advance=787
zh_glyph[5].codepoint=89
zh_glyph[5].advance=711
zh_glyph[6].codepoint=89
zh_glyph[6].advance=711
zh_glyph[7].codepoint=75
zh_glyph[7].advance=872
zh_glyph[8].codepoint=82
zh_glyph[8].advance=409
zh_glyph[9].codepoint=82
zh_glyph[9].advance=409
ar_glyph[0].codepoint=2342
ar_glyph[0].advance=898
ar_glyph[1].codepoint=3941
ar_glyph[1].advance=513
ar_glyph[2].codepoint=3981
ar_glyph[2].advance=385
ar_glyph[3].codepoint=2260
ar_glyph[3].advance=1283
ft_version=2.15.0
hb_version=15.1.0
ft_face_family=Microsoft YaHei
ft_face_style=Regular
ft_glyph_index=1154
ft_advance_x26=2048
ft_bitmap_w=32
ft_bitmap_rows=30
render_px=410
zh_text=你好 Tessell
zh_glyphs=10
zh_advance=1536
ar_text=سلام
ar_font=C:\Windows\Fonts\segoeui.ttf
ar_glyphs=4
ar_codepoints=4
ar_shaping_diff=false
shape_us_avg=0.431
render_us_avg=5.883
EXITCODE=0
```

与证据 `docs/evidence/M0-WP4-text.md` token 对比：
- `ft_version=2.15.0` 一致；`hb_version=15.1.0` 一致；`zh_glyphs=10` 一致；`zh_advance=1536` 一致；`render_px=410` 一致；`ar_glyphs=4` 一致；`ar_codepoints=4` 一致；逐 glyph codepoint/advance 序列（zh/ar）一致；`ft_glyph_index=1154`、`ft_advance_x26=2048`、`ft_bitmap_w=32`、`ft_bitmap_rows=30`、`ft_face_family/style`、`ar_font`、`ar_shaping_diff` 一致。
- `shape_us_avg=0.431` vs 证据 `0.387`、`render_us_avg=5.883` vs 证据 `5.116`：计时项，允许波动，非数值一致性项。
- `EXITCODE=0` 一致。结论：关键 token 与数值项一致，可复现。

## 3) 真实性检查（源码 grep/读码）

### 3.1 硬编码结果检查

命令：
```powershell
Select-String -Path examples/m0_ffi_load.cr,examples/m0_text_probe.cr -Pattern 'ft_version=2\.15\.0|hb_version=15\.1\.0|render_px=410|zh_glyphs=10|ar_glyphs=4|zh_advance=1536'
```
结果：无输出（未发现硬编码期望 token 字符串）。

读码确认：
- `examples/m0_ffi_load.cr:30` `LibFT.FT_Library_Version(...)`，`:32` `LibHB.hb_version_string`，`:42` `LibHB.hb_version(...)`；`:50-53` 打印由调用返回值/变量组成，`:55` 仅在 `hb_ver_str.size > 0` 时 `exit 0` 否则报错 `exit 1`（非冒充版本值）。
- `examples/m0_text_probe.cr:179-186` FT/HB 版本来自 `FT_Library_Version`/`hb_version_string`；`:205-231` render 循环真实 `FT_Load_Char(..., FT_LOAD_RENDER)` 计时并读取 slot/bitmap，`:232` 平均；`:246-261` zh shape 来自 `hb_shape` + `hb_buffer_get_length/glyph_infos/positions`；`:282-297` ar 同理；`:310-318` shape 计时 1000 次平均；`:334-352` token 输出均为变量插值。

### 3.2 失败路径 `exit 1`

命令：
```powershell
Select-String -Path examples/m0_ffi_load.cr,examples/m0_text_probe.cr -Pattern 'exit 1|fail\(|STDERR|exit\(1\)'
```
结果（命中行）：`examples/m0_ffi_load.cr:23,24,34,36,46,47,56,57`（FT init/FT_Done/HB version 空等 `STDERR.puts` + `exit 1`）；`examples/m0_text_probe.cr:129-131` 定义 `fail(msg){STDERR.puts msg; exit 1}`；后续 `:176,184,186,190,193,196,203,208,220,223,236,238,240,244,253,254,270,273,275,277,281,290,291,302` 在 FFI/字体/指针/长度/计数异常时调用 `fail` 退出 1。`m0_text_probe.cr` 成功路径末尾 `exit 0`（:353）。结论：失败路径显式报错并退出 1，无静默成功/假数据 fallback。

## 4) LLP64 结构体布局核查（FT_Long/FT_Pos/FT_Fixed, FT_Glyph_Metrics, FT_Bitmap, FT_GlyphSlotRec 前缀）

### 4.1 头文件语义（本机 ucrt64 freetype）

- `C:\msys64\ucrt64\include\freetype2\freetype\fttypes.h:243` `typedef signed long  FT_Long;`，`:288` `typedef signed long  FT_Fixed;`（Windows x64 LLP64 下 `long` 为 32-bit，与探针 `alias FT_Long/FT_Fixed/FT_Pos = Int32` 一致）。
- `C:\msys64\ucrt64\include\freetype2\freetype\freetype.h`：`FT_Glyph_Metrics` 为 8 个 `FT_Pos` 字段（width,height,horiBearingX,horiBearingY,horiAdvance,vertBearingX,vertBearingY,vertAdvance）。
- `FT_GlyphSlotRec_` 字段顺序（头文件）：`library, face, next, glyph_index(FT_UInt), generic(FT_Generic), metrics(FT_Glyph_Metrics), linearHoriAdvance(FT_Fixed), linearVertAdvance(FT_Fixed), advance(FT_Vector), format(FT_Glyph_Format), bitmap(FT_Bitmap), bitmap_left(FT_Int), bitmap_top(FT_Int), ...`
- `C:\msys64\ucrt64\include\freetype2\freetype\ftimage.h`：`FT_Vector{FT_Pos x,y}`；`FT_Bitmap{unsigned int rows,width; int pitch; unsigned char* buffer; unsigned short num_grays; unsigned char pixel_mode,palette_mode; void* palette;}`（无额外 pad 字段）。

### 4.2 探针布局与实测验证（临时脚本，`bin/_verify_w2_text_checks.cr`，gitignored；未改被核验文件）

命令（摘要）：
```powershell
# bin/_verify_w2_text_checks.cr: 定义与 probe 同风格的 VFT::FT_Bitmap/VFT::FT_GlyphSlotRec(部分),
# 打印 sizeof, 通过写入字段后按字节偏移读回验证偏移; 并做 lam-alef/سلام/孤立字形 shaping 证伪
$env:PATH="C:\msys64\ucrt64\bin;"+$env:PATH
crystal run bin/_verify_w2_text_checks.cr 2>&1; "EXITCODE=$LASTEXITCODE"
```

原始输出（与布局相关部分）：
```
sizeof_VoidPtr=8
sizeof_FT_Long=4
sizeof_FT_Pos=4
sizeof_FT_Fixed=4
sizeof_FT_Vector=8
sizeof_FT_Bitmap=48
sizeof_FT_GlyphSlotRec_partial=160
val_glyph_index_at24=true
val_m_width_at48=true
val_m_horiAdvance_at64=true
val_m_vertAdvance_at76=true
val_linearHoriAdvance_at80=true
val_linearVertAdvance_at84=true
val_advance_x_at88=true
val_format_at96=true
val_bitmap_left_at144=false
val_bitmap_top_at148=false
bm_rows_at0=true
bm_width_at4=true
bm_pitch_at8=true
bm_buffer_at16=true
bm_num_grays_at24=true
bm_pixel_mode_at26=true
...
EXITCODE=0
```

裁决：
- `FT_Long/FT_Pos/FT_Fixed` 在目标 `x86_64-w64-windows-gnu` (LLP64) 下为 32-bit：**正确**（`sizeof=4`，与头文件 `signed long`/LLP64 语义一致）。
- `FT_Glyph_Metrics` 8 字段（FT_Pos, 32-bit）在 slot 内嵌偏移 `48..76`、`linearHoriAdvance@80`、`linearVertAdvance@84`、`advance(FT_Vector)@88`、`format@96`：读回验证 **正确**。
- `FT_Bitmap`：C 语义结构体按 64-bit 对齐有效载荷为 40 字节（palette 指针末端），但 probe 定义 `pad1:UInt8, pad2:UInt32` 额外字段使 `sizeof(FT_Bitmap)=48`（`examples/m0_text_probe.cr:28-39`），而 bitmap 内部关键字段偏移（rows/width/pitch/buffer/num_grays/pixel_mode）本身读回正确。
- **偏移错误（尾部）**：probe 注释与假设 `bitmap@104 (40 bytes) -> 144`、`bitmap_left@144`、`bitmap_top@148`（`examples/m0_text_probe.cr:65-68`），但由于 probe `FT_Bitmap` 实际为 48 字节，`bitmap_left/bitmap_top` 在 probe 布局中位于 152/156，而非 C 语义期望的 144/148；读回验证 `val_bitmap_left_at144=false`、`val_bitmap_top_at148=false` 证实。C 头文件 `FT_GlyphSlotRec_` 中 `bitmap` 后紧跟 `bitmap_left, bitmap_top`，若按 C 布局应在 144/148。
- **对当前读数的影响**：probe 仅使用 `glyph_index(24)`、`advance.x(88)`、`bitmap.width/rows/buffer/pitch`（`examples/m0_text_probe.cr:225-229,138-153`），未读取 `bitmap_left/bitmap_top`。上述已用字段偏移与 bitmap 内部字段偏移验证正确，且重跑输出与证据一致（`ft_glyph_index=1154, ft_advance_x26=2048, ft_bitmap_w=32, ft_bitmap_rows=30, render_px=410`）。因此**当前探针已报告 token 的读数非噪声**；但 `FT_Bitmap/FT_GlyphSlotRec` 尾部布局与 freetype 语义不一致，属于**潜在正确性缺陷**（未来若读取 bitmap_left/top 或按 C 布局扩展将读错）。

## 5) 证伪尝试：lam-alef "لا"（U+0644 U+0627）与 "سلام"

临时脚本（同上，segoeui.ttf, scale 24*64, HB shape）原始输出：
```
lam_alef_text=لا
lam_alef_cps=1604,1575
lam_alef_glyph_count=2
lam_alef_glyph_cps=3941,3980
slam_glyph_count=4
slam_glyph_cps=2342,3941,3981,2260
isolated_lam=2341
isolated_alef=2317
isolated_sin=2329
isolated_mim=2342
EXITCODE=0
```

分析：
- `لا`（2 codepoints）shaping 后 `glyph_count=2`（非 1），未形成单 glyph lam-alef 强制连字；但 glyph id `3941,3980` 与孤立 `lam=2341, alef=2317` 不同，说明发生了字形选择/上下文替换。
- `سلام`（4 codepoints）`glyph_count=4`，glyph ids `2342,3941,3981,2260` 与孤立 `sin=2329, mim=2342, lam=2341, alef=2317` 比较显示上下文形式变化（如首字母/词中形式 id 不同），但无数量变化。
- 结论：HarfBuzz shaping 在该文本/字体上产生了上下文相关 glyph 变化，但 **lam-alef 未合成为 1 glyph**。因此 probe/evidence 以 `ar_glyphs==ar_codepoints` / `ar_shaping_diff=false` 作为“连写/替换生效”证明（`examples/m0_text_probe.cr:350` 输出、`docs/evidence/M0-WP4-text.md:18,88,115-116` 解释）**不足以证明连字合并（mandatory ligature）**；当前阿拉伯文测试对“shaping 是否生效”的证明是弱证据（仅计数相同且未展示与 nominal/未 shaping 的充分对照）。此为需指出的缺陷/不足。

## 6) 证据一致性与 `[未验证]` 诚实性

- `docs/evidence/M0-WP4-text-deps.md`：含时间/HEAD/OS/Crystal、pacman 实测（含失败包名与成功包名）、`pacman -Q`、DLL 路径/大小/时间、`objdump -p` 依赖、探针源码要点、重跑输出与 EXITCODE、分发含义；`[未验证]` 列出传递依赖闭包、干净环境 PATH、静态链接等，标注诚实。与本次重跑一致。
- `docs/evidence/M0-WP4-text.md`：含环境/HEAD/依赖/字体、实现摘要、**真实调试记录**（首版崩溃 EXITCODE=1 与 build 后数值异常、修复过程）、修复后 run/build 原始输出与 EXITCODE、结果解读、对 M1-WP2 含义、`[未验证]` 项。关键数值 token 与本次重跑一致；计时波动已如实呈现不同值；未把设计写成实测（计时为实测、未验证项明确）。
- 证据中对 Arabic shaping 的表述“`ar_shaping_diff=(ar_glyphs != ar_codepoints)` 以说明连写/替换生效与否”及“未观察到 glyph 数层面的合并/拆分差异”（`:18,115-116`）事实正确但证明力不足，结合 lam-alef 证伪应视为**证据强度不足**（已在缺陷列出）。

## 7) 边界检查

命令：
```powershell
git status --short
git status --short -- src spec shard.yml docs/plan.md docs/roadmap.md docs/plan-execution.md README
```
原始输出：
```
?? docs/evidence/M0-WP4-text-deps.md
?? docs/evidence/M0-WP4-text.md
?? docs/research/layout-two-pass.md
?? examples/m0_ffi_load.cr
?? examples/m0_ime_probe.cr
?? examples/m0_text_probe.cr

(第二条命令无输出, STATUS_EXIT=0)
```

- 仅新增未跟踪文件；`src/`、`spec/`、`shard.yml`、`docs/plan.md`、`docs/roadmap.md`、`docs/plan-execution.md`、`README` 无改动。`examples/m0_ime_probe.cr`、`docs/research/layout-two-pass.md` 为同批 W2 其他任务产物（非本 task-8/9 交付但在工作区），未被本核验修改。
- 本报告仅新增 `docs/evidence/verify-W2-text.md`；未修改被核验文件 `examples/m0_ffi_load.cr`、`examples/m0_text_probe.cr`、`docs/evidence/M0-WP4-text-deps.md`、`docs/evidence/M0-WP4-text.md`。

## 8) 逐项结论表

| 核验项 | 结论 | 证据/说明 |
|---|---|---|
| 1. 重跑 `m0_ffi_load.cr`（含 ucrt64 PATH） | 通过 | EXITCODE=0；`ft_library_version=2.15.0`、`hb_version=15.1.0` 与证据一致 |
| 1. 重跑 `m0_text_probe.cr`（含 ucrt64 PATH） | 通过 | EXITCODE=0；`ft_version=2.15.0,hb_version=15.1.0,zh_glyphs=10,zh_advance=1536,render_px=410,ar_glyphs=4,ar_codepoints=4` 及逐 glyph 值与证据一致；计时波动允许 |
| 2. 真实性（无硬编码 token、失败路径 exit 1） | 通过 | grep 未命中硬编码期望值；token 来自 FFI 调用/循环计算；`m0_ffi_load.cr:23-24,34,36,46-47,56-57`、`m0_text_probe.cr:129-131` 及多处 `fail(...)/exit 1` |
| 3. LLP64 `FT_Long/FT_Pos/FT_Fixed` 为 Int32 | 通过 | `fttypes.h` typedef + sizeof=4 验证 |
| 3. `FT_Glyph_Metrics` / glyph slot 已用字段布局 | 通过（有保留缺陷） | metrics/linearHoriAdvance/linearVertAdvance/advance/format/glyph_index 偏移读回正确；但 `FT_Bitmap` 声明 48B vs C 40B 导致 probe 内 `bitmap_left/top` 偏移错位（当前未使用，读数非噪声） |
| 4. lam-alef `لا` 证伪 | 失败（证据强度不足，已记录） | `glyph_count=2`（`3941,3980`）非 1；证明当前 ar 测试不足以证明 lam-alef 连字合并，且 `ar_shaping_diff=false` 证据表述偏弱 |
| 5. 证据一致性 / `[未验证]` 诚实性 | 通过（附说明） | 命令/输出/EXITCODE 与重跑一致；调试过程与未验证项如实记录；无“设计当实测”；ar shaping 证明力见缺陷 D2 |
| 6. 边界（未改 src/spec/shard.yml/docs/plan*） | 通过 | `git status -- src spec shard.yml docs/plan* README` 空；工作区新增为 W2 预期未跟踪文件；本核验未改被核验文件 |

## 9) 缺陷清单

| ID | 严重性 | 文件:行号 | 问题 | 复现/证据 | 影响 |
|---|---|---|---|---|---|
| D1 | 中（潜在） | `examples/m0_text_probe.cr:28-39`, `:65-68` | `FT_Bitmap` 结构体定义含额外 `pad1:UInt8`/`pad2:UInt32` 使 `sizeof(FT_Bitmap)=48`（C 语义 40B），导致嵌入 `FT_GlyphSlotRec` 时 `bitmap_left/bitmap_top` 实际位于 152/156 而非 C 布局 144/148（probe 注释写 144/148）。临时布局验证：`val_bitmap_left_at144=false`, `val_bitmap_top_at148=false`；`FT_Long/Pos/Fixed` 及已用字段（glyph_index/metrics/advance/format/bitmap 内容）偏移正确。 | `bin/_verify_w2_text_checks.cr`（gitignored，按报告所述运行）输出如 §4.2；读码 `m0_text_probe.cr:28-39,65-68,225-229` | 当前报告 token 未读 `bitmap_left/top`，实测读数未受影响；但布局与 freetype 头文件不一致，后续若读取 bitmap_left/top 或依赖 C 布局将产生错误读数（风险） |
| D2 | 中（证据/测试充分性） | `examples/m0_text_probe.cr:264-297,350`, `docs/evidence/M0-WP4-text.md:18,88,115-116` | 阿拉伯文 shaping 证据不足以证明连字/替换“生效”的强结论：`"سلام"` 仅验证 glyph 数=codepoint 数（`ar_shaping_diff=false`）；lam-alef 证伪 `"لا"`(U+0644,U+0627) 在 `segoeui.ttf` + HB shaping 下 `glyph_count=2`（`3941,3980`，非 1），虽 glyph id 与孤立形式不同（上下文替换存在），但未出现单 glyph lam-alef 合并。 | 临时脚本输出：`lam_alef_cps=1604,1575 lam_alef_glyph_count=2 lam_alef_glyph_cps=3941,3980`；`isolated_lam=2341 isolated_alef=2317`；`slam_glyph_count=4` | 可能误导对“复杂脚本连字/替换已被充分证明”的判断；M1 文本/复杂脚本支持仍需更强样例（含 mandatory ligature 或与 nominal 序列对照）验证（证据力度不足） |

## 10) 最终裁定

**PASS-WITH-DEFECTS**

依据：task-8/9 探针可在指定环境重跑且 EXITCODE=0，关键 token/数值与证据一致；源码无硬编码伪造、失败路径 `exit 1`；LLP64 基本类型与当前使用的 glyph/metrics/advance/bitmap 读数布局正确、实测非噪声；证据与 `[未验证]` 记录基本诚实、边界合规。但存在 D1（`FT_Bitmap/slot` 尾部 bitmap_left/top 布局偏差，潜在正确性风险）与 D2（阿拉伯文 shaping 证明不足，lam-alef 未合并为单 glyph），需后续修正/补证。
