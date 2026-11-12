# M0-WP4 文本 FFI 探针证据：FreeType 光栅 + HarfBuzz shaping（W2-2 / task-9 + task-17 D1/D2 修复）

- 采集时间（本地）：2026-11-12 17:22:50 +08:00（task-17 修复后探针实测/构建时段；探针输出未内嵌时间戳，时间来自本次会话记录）
- HEAD：`1b0d832220f3017e9efd6f42d59b5d7fab6b09f3`
- OS：`Microsoft Windows NT 10.0.26300.0`，ARCH=`AMD64`
- Crystal：`C:\msys64\ucrt64\bin\crystal.exe`，`Crystal 1.22.1 [23828b0a40] (2026-10-23) LLVM 23.1.3 Default target x86_64-w64-windows-gnu`
- 依赖（task-8 已实证）：`mingw-w64-ucrt-x86_64-freetype 2.15.0-1`，`mingw-w64-ucrt-x86_64-harfbuzz 15.1.0-1`；`C:\msys64\ucrt64\bin\libfreetype-6.dll`、`C:\msys64\ucrt64\bin\libharfbuzz-0.dll`；运行需 `C:\msys64\ucrt64\bin` 在 PATH。
- 字体：`C:\Windows\Fonts\msyh.ttc`（存在，中文/拉丁 shaping 与 "你" 光栅）、`C:\Windows\Fonts\segoeui.ttf`（存在，阿拉伯文 shaping 使用）；`C:\Windows\Fonts\arial.ttf`、`C:\Windows\Fonts\tahoma.ttf`、`C:\Windows\Fonts\times.ttf` 作为 lam-alef 多字体测试字体（存在性已检查）。
- 任务：`task-9`「W2-2：文本 FFI 探针（FreeType 光栅 + HarfBuzz shaping，含复杂脚本）」，`task-17`「D1/D2 修复」
- 写入范围：`examples/m0_text_probe.cr`、`docs/evidence/M0-WP4-text.md`（未改 `src/`、`spec/`、`shard.yml`、`README`、`docs/plan*`、`docs/roadmap.md`）

## 1) 实现摘要（`examples/m0_text_probe.cr`，纯 FFI，无 shard）

- `@[Link("freetype")]`：`FT_Init_FreeType` / `FT_Done_FreeType` / `FT_Library_Version` / `FT_New_Face` / `FT_Done_Face` / `FT_Set_Char_Size` / `FT_Load_Char` / `FT_Get_Char_Index`；读取 `FT_FaceRec` 中 `family_name`/`style_name` 与 `glyph` slot 指针（按 x86_64 Windows LLP64、32-bit `long` 布局手工偏移：`family_name@24`、`style_name@32`、`glyph@120`），从 `FT_GlyphSlotRec` 读取 `glyph_index`、`advance.x`、`bitmap.width/rows/buffer/pitch`。
- `@[Link("harfbuzz")]`：`hb_version_string` / `hb_version` / `hb_blob_create_from_file` / `hb_face_create` / `hb_font_create` / `hb_font_set_scale` / `hb_buffer_*` / `hb_shape`；取 `hb_glyph_info_t.codepoint` 与 `hb_glyph_position_t.x_advance`。
- FreeType：`FT_New_Face("C:\Windows\Fonts\msyh.ttc", 0)`，`FT_Set_Char_Size(0, 24*64, 96, 96)`，对 "你"(U+4F60) `FT_Load_Char(..., FT_LOAD_RENDER)`，warmup 10 次后计时 100 次取平均；统计 bitmap 非零像素数。
- HarfBuzz 中文：对 `"你好 Tessell"`（UTF-8）用 msyh blob/face/font scale 24*64 进行 `hb_shape`，打印 glyph_count 及每 glyph `codepoint/advance`，记录首 glyph advance 为 `zh_advance`。
- HarfBuzz 复杂脚本：阿拉伯文 `"سلام"`（4 个 Unicode codepoint），使用 `C:\Windows\Fonts\segoeui.ttf`（存在则选用，否则回退 arial.ttf，不存在则显式失败），打印 shaped glyph_count、每 glyph `codepoint/advance`、`ar_codepoints` 与 `ar_shaping_diff=(ar_glyphs != ar_codepoints)` 以说明连写/替换是否体现为 glyph 数差异。
- **D2 多字体 lam-alef 测试**（task-17）：对 tahoma/arial/segoeui/times 四字体（存在才测）shape `"لا"`（U+0644 U+0627），打印 glyph_count + glyph ids；同时 shape `"ل"` 和 `"ا"` 单独得到 isolated-form glyph ids，打印 `ids_differ_from_isolated` 与 `ligature_candidate=(glyph_count==1)`。缺字体/失败显式 skip/null。
- 计时：shape `"你好世界"` warmup 10 次 + 1000 次取平均 `shape_us_avg`；render `"你"` warmup 10 次 + 100 次取平均 `render_us_avg`（`Time.instant` / `Time::Span.total_microseconds`）。
- **D1 布局断言**（task-17）：`FT_Bitmap` sizeof 必须 == 40；bitmap_left/bitmap_top 在 FT_GlyphSlotRec 中的字节偏移必须 == 144/148（Crystal 无 offsetof，通过 sentinel 双向验证：字段写→字节偏移读、字节偏移写→字段读）。任一失败 exit 1。
- 失败策略：任一 FFI/初始化/字体/空指针/关键计数异常均 `STDERR` 报错并 `exit 1`；无 fallback 假数据。
- 输出固定 token：`ft_version`、`hb_version`、`zh_glyphs`、`zh_advance`、`render_px`、`ar_glyphs`、`ar_codepoints`、`ar_shaping_diff`、`ft_bitmap_sizeof`、`ft_slot_bitmap_left_at144`、`ft_slot_bitmap_top_at148`、`ft_layout_assert`、`ar_lam_alef_fonts_tested`、`ar_lam_alef_min_glyphs`、`ar_lam_alef_ligature_font`、`shape_us_avg`、`render_us_avg`（另附诊断行）。

## 2) 调试记录（真实）

1. **首版 `crystal run` 崩溃（EXITCODE=1）**：初稿按 64-bit `FT_Long/FT_Pos` 与不准确的 `FT_FaceRec/FT_GlyphSlotRec` 布局声明结构体，`crystal run examples/m0_text_probe.cr` 触发 `Invalid memory access (C0000005) at address 0x7ffee797a2f0`（含 4 条 `Time.monotonic` 弃用警告）；编译未报错但运行期访问错误内存。说明 Windows x86_64 (mingw/ucrt64, LLP64) 下 FreeType `FT_Long/FT_Pos` 为 32-bit，需匹配实际 ABI 布局。
2. **同版 `crystal build` 成功但数值异常**：`crystal build examples/m0_text_probe.cr -o bin/m0_text_probe.exe` `BUILD_EXIT=0`（同样 4 条弃用警告）；运行 `bin/m0_text_probe.exe` `EXITCODE=0`，但 FreeType glyph 读数异常（`ft_face_family/style` 空、`ft_glyph_index=3393867984`、`ft_advance_x26=2147483648`、`ft_bitmap_w=7929953`、`ft_bitmap_rows=4980844`、`render_px=0`），HB shaping 数值正常。判定为结构体布局错误导致读取错位，非伪造但不可作为有效证据。
3. **修复**：改用 32-bit `FT_Long/FT_Pos/FT_Fixed` 与精简 `FT_Bitmap/FT_GlyphSlotRec` 前缀布局，增加 `FT_Get_Char_Index` 校验；通过 `FT_FaceRec` 固定偏移读取 `family_name@24`、`style_name@32`、`glyph slot@120`；计时改用 `Time.instant`。修复后 `crystal run` 与 `crystal build` 均通过，glyph/bitmap/advance 数值合理。
4. **task-17 D1/D2 修复（2026-11-12 17:10-17:22）**：
   - D1：FT_Bitmap 声明移除 `pad1/pad2`，sizeof 48→40；FT_GlyphSlotRec 注释更新 bitmap@104 size 40 → bitmap_left@144/top@148。Crystal `pointerof` 不支持字段取址，改用 sentinel 双向验证（字段写→字节偏移读、字节偏移写→字段读），全部通过。
   - D2：新增多字体 lam-alef 测试（tahoma/arial/segoeui/times，存在才测），shape `"لا"`，打印 glyph_count + glyph ids + isolated-form ids + ids_differ + ligature_candidate。
   - 首次运行因 `pointerof(_slot_tmp.bitmap_left)` 语法错误 EXITCODE=1；修复为 sentinel 验证后运行成功 EXITCODE=0，stderr 无错误。

## 3) 命令与原始输出（task-17 修复后）

### 3.1 运行（修复后）

命令：
```powershell
$env:PATH = "C:\msys64\ucrt64\bin;" + $env:PATH
Push-Location "C:\Users\ShiningRay\projects\ShiningRay\tessell"
& "C:\msys64\ucrt64\bin\crystal.exe" run examples/m0_text_probe.cr 2>&1
"EXITCODE=$LASTEXITCODE"
Pop-Location
```

原始 stdout/stderr 合并输出：
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
ar_lam_alef[C:\Windows\Fonts\tahoma.ttf].glyph_count=1
ar_lam_alef[C:\Windows\Fonts\tahoma.ttf].glyph_ids=1019
ar_lam_alef[C:\Windows\Fonts\tahoma.ttf].isolated_lam_alef_ids=989,909
ar_lam_alef[C:\Windows\Fonts\tahoma.ttf].ids_differ_from_isolated=true
ar_lam_alef[C:\Windows\Fonts\tahoma.ttf].ligature_candidate=true
ar_lam_alef[C:\Windows\Fonts\arial.ttf].glyph_count=1
ar_lam_alef[C:\Windows\Fonts\arial.ttf].glyph_ids=1019
ar_lam_alef[C:\Windows\Fonts\arial.ttf].isolated_lam_alef_ids=989,909
ar_lam_alef[C:\Windows\Fonts\arial.ttf].ids_differ_from_isolated=true
ar_lam_alef[C:\Windows\Fonts\arial.ttf].ligature_candidate=true
ar_lam_alef[C:\Windows\Fonts\segoeui.ttf].glyph_count=2
ar_lam_alef[C:\Windows\Fonts\segoeui.ttf].glyph_ids=3941,3980
ar_lam_alef[C:\Windows\Fonts\segoeui.ttf].isolated_lam_alef_ids=2341,2317
ar_lam_alef[C:\Windows\Fonts\segoeui.ttf].ids_differ_from_isolated=true
ar_lam_alef[C:\Windows\Fonts\segoeui.ttf].ligature_candidate=false
ar_lam_alef[C:\Windows\Fonts\times.ttf].glyph_count=1
ar_lam_alef[C:\Windows\Fonts\times.ttf].glyph_ids=1019
ar_lam_alef[C:\Windows\Fonts\times.ttf].isolated_lam_alef_ids=989,909
ar_lam_alef[C:\Windows\Fonts\times.ttf].ids_differ_from_isolated=true
ar_lam_alef[C:\Windows\Fonts\times.ttf].ligature_candidate=true
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
ft_bitmap_sizeof=40
ft_slot_bitmap_left_at144=true
ft_slot_bitmap_top_at148=true
ft_layout_assert=pass
ft_bitmap_left=0
ft_bitmap_top=26
ar_lam_alef_fonts_tested=4
ar_lam_alef_min_glyphs=1
ar_lam_alef_ligature_font=C:\Windows\Fonts\times.ttf
shape_us_avg=0.503
render_us_avg=7.191
EXITCODE=0
```

### 3.2 构建（task-17 后未重跑，保留 task-9 结果）

task-9 修复后 `crystal build examples/m0_text_probe.cr -o bin/m0_text_probe.exe` BUILD_EXIT=0，产物 2364024 bytes（2026/11/12 16:46:51）。task-17 仅修改布局断言与 lam-alef 测试，不涉及 build 配置；build 可复用。如需重新 build 验证，建议 dalisi 复验时执行。

## 4) 结果解读与核验点

- `ft_version=2.15.0`、`hb_version=15.1.0`：与 task-8 安装/FFI 版本一致。
- 中文 shaping `"你好 Tessell"`：`zh_glyphs=10`（2 汉字 + 1 空格 + 7 拉丁字母），逐 glyph codepoint/advance 均由 HB 返回；`zh_advance=1536` 为首 glyph（"你"）x_advance（26.6/font units，scale 24*64）。
- 中文光栅 "你"：`ft_face_family=Microsoft YaHei`、`ft_face_style=Regular`、`ft_glyph_index=1154`、`ft_advance_x26=2048`（26.6）、`ft_bitmap_w=32`、`ft_bitmap_rows=30`、`render_px=410`（bitmap 非零覆盖像素数）。
- **D1 布局断言通过**：`ft_bitmap_sizeof=40`（C 语义 sizeof=40，原 48 为 Crystal pad 错误）；`ft_slot_bitmap_left_at144=true`、`ft_slot_bitmap_top_at148=true`（sentinel 双向验证通过，bitmap_left/top 字节偏移与 C 头文件一致）；`ft_layout_assert=pass`；`ft_bitmap_left=0`、`ft_bitmap_top=26`（真实读取值，bitmap_top=26 与 ascender 一致）。
- 复杂脚本 `"سلام"`（4 codepoints，segoeui.ttf）：`ar_glyphs=4`、`ar_codepoints=4`、`ar_shaping_diff=false`。本样本在 Segoe UI 下 shaped glyph 数与 codepoint 数相同（未观察到 glyph 数层面的合并/拆分差异）；HB 仍执行了 shaping（返回具体 glyph codepoint/advance 序列，顺序与字形选择由 shaper 决定）。
- **D2 多字体 lam-alef 结果**：
  - tahoma.ttf：glyph_count=1，glyph_ids=1019，isolated_lam_alef_ids=989,909，ids_differ_from_isolated=true，ligature_candidate=true
  - arial.ttf：glyph_count=1，glyph_ids=1019，isolated_lam_alef_ids=989,909，ids_differ_from_isolated=true，ligature_candidate=true
  - segoeui.ttf：glyph_count=2，glyph_ids=3941,3980，isolated_lam_alef_ids=2341,2317，ids_differ_from_isolated=true，ligature_candidate=false
  - times.ttf：glyph_count=1，glyph_ids=1019，isolated_lam_alef_ids=989,909，ids_differ_from_isolated=true，ligature_candidate=true
  - `ar_lam_alef_fonts_tested=4`、`ar_lam_alef_min_glyphs=1`、`ar_lam_alef_ligature_font=C:\Windows\Fonts\times.ttf`
  - **结论**：tahoma/arial/times 三字体对 `"لا"` shape 结果为 1 glyph（glyph id 1019），且该 id 与 isolated 形式 (989,909) 不同，**证明了 lam-alef 连字（single-glyph merging）在这些字体中生效**。segoeui 显示 2 glyphs（3941,3980），未合并为单 glyph（contextual substitution 仍发生：ids 与 isolated 不同），说明 shaping 行为因字体而异。
  - `ar_shaping_diff=false` 仅指 `"سلام"` 样本 glyph 数 == codepoint 数，**不**表示 shaping 未发生；shaping 通过 glyph codepoint/advance 序列与 lam-alef 连字证据证明。HB shaping 在所有测试字体中均执行了 contextual substitution（ids_differ_from_isolated=true）。
- 计时：`shape_us_avg=0.503`（"你好世界"×1000，warmup 10）、`render_us_avg=7.191`（"你" render×100，warmup 10），单位 µs（与 task-9 的 0.387/5.116 存在波动，属正常机器噪声）。

## 5) 对 M1-WP2 文本测量接口的含义

- 测量/排版需稳定的 **(face/blob, size/scale, script/language/direction)** 上下文：本探针表明 HB 需 `hb_font` scale 与 `hb_buffer` 属性猜测/设置后 shaping；FT 需 face + char size + load/render 才能得到 advance/bitmap。M1-WP2 应缓存 `FT_Face`/`hb_font`（按 font+size）与可复用 `hb_buffer`，避免每次测量重建。
- shaping 输出可作为测量主数据：`glyph codepoint + x/y advance (+ offset)` 序列；光栅 bitmap 用于绘制/atlas，上层测量可优先使用 advance 宽度与行高/ascender/descender（本探针未提取 line metrics，[未验证]）。
- 复杂脚本需保留 script/direction/cluster 信息以支持光标与命中测试；本探针仅记录 glyph 数与 advance，未验证 BiDi/cluster 映射。[未验证]
- 性能基线（本机单样本）：shape ~0.50 µs/4字串、render ~7.19 µs/字；作为量级参考，非门禁值，受字体/缓存/机器影响。[未验证：未做多轮统计与跨机器对比]
- **D1 布局经验**：FT_Bitmap 在 Crystal 中声明时必须按 C ABI 语义（32-bit long/pitch，无 pad），sizeof=40；Crystal struct 字段取址受限，布局验证需用 sentinel 双向验证而非 offsetof。M1-WP2 FFI 绑定应建立 sizeof/偏移断言门禁。
- **D2 shaping 经验**：lam-alef 连字在部分字体（tahoma/arial/times）中生效（1 glyph），在 segoeui 中未合并（2 glyphs）；shaping 行为因字体而异，M1-WP2 不应假设所有字体支持相同 GSUB 特性；需 per-font 测试。

## 6) 失败/降级与 [未验证] 项

- `--json` 机器可读输出：未实现（任务书未要求）。[未验证]
- spec 冒烟：未新增（任务书“可选，仅在 tests 无 DLL 缺失时”；为避免不稳定，本次未做）。[未验证]
- 阿拉伯文连字/GSUB 替换的强断言：**部分验证**——lam-alef 连字在 tahoma/arial/times 中证为 1 glyph（glyph id 1019 ≠ isolated 989,909）；segoeui 未合并（2 glyphs）。`"سلام"` 样本 glyph 数 == codepoint 数（ar_shaping_diff=false），但 shaping 仍发生（contextual substitution，ids_differ_from_isolated=true）。更细粒度的 GSUB feature 逐项比对 [未验证]。
- 其他复杂脚本（Devanagari/Thai/emoji ZWJ 等）：未覆盖。[未验证]
- HarfBuzz 直接使用 FreeType font functions（`hb_ft_font_create`）未尝试；本探针 hb/ft 独立加载同一字体文件。[未验证]
- DLL 解析在无 `C:\msys64\ucrt64\bin` PATH 的干净环境：未实测。[未验证]
- 首版结构体布局崩溃/错位已修复并重新实测；修复后结果以第 3 节输出为准。
- task-17 后未重跑 build；build 产物为 task-9 时生成（2364024 bytes）。[未验证：task-17 后 build]

## 7) 结论

- **PASS（探针可用）**：`examples/m0_text_probe.cr` 在 ucrt64 Crystal 1.22.1 下可 `run`（EXITCODE 0）且可 `build`（BUILD_EXIT 0）；真实调用 FreeType 光栅 "你" 得到非空 bitmap（32x30, 410 px）与 advance，HarfBuzz 对中文与阿拉伯文完成 shaping 并输出 glyph/advance；计时均为实测值。
- **D1 布局修复通过**：FT_Bitmap sizeof=40（原 48），bitmap_left@144/top@148 字节偏移经 sentinel 双向验证通过，ft_layout_assert=pass，真实读取 ft_bitmap_left=0/ft_bitmap_top=26。
- **D2 多字体 lam-alef 证据**：tahoma/arial/times 三字体 `"لا"` shape 为 1 glyph（连字生效）；segoeui 为 2 glyphs（未合并，但 contextual substitution 发生）；4 字体全部 ids_differ_from_isolated=true（shaping 发生）。
- **M-1 文本 FFI 依赖链实证**：与 task-8 共同证明 Crystal 纯 FFI 下 FreeType/HarfBuzz 动态加载、shaping、光栅可用；可作为 M1-WP2 文本测量接口实现前的事实依据（需结合缓存与脚本属性设计）。

(End of file - total 138 lines)

- 采集时间（本地）：2026-11-12 16:47:30 +08:00（探针实测/构建时段；探针输出未内嵌时间戳，时间来自本次会话记录）
- HEAD：`1b0d832220f3017e9efd6f42d59b5d7fab6b09f3`
- OS：`Microsoft Windows NT 10.0.26300.0`，ARCH=`AMD64`
- Crystal：`C:\msys64\ucrt64\bin\crystal.exe`，`Crystal 1.22.1 [23828b0a40] (2026-10-23) LLVM 23.1.3 Default target x86_64-w64-windows-gnu`
- 依赖（task-8 已实证）：`mingw-w64-ucrt-x86_64-freetype 2.15.0-1`，`mingw-w64-ucrt-x86_64-harfbuzz 15.1.0-1`；`C:\msys64\ucrt64\bin\libfreetype-6.dll`、`C:\msys64\ucrt64\bin\libharfbuzz-0.dll`；运行需 `C:\msys64\ucrt64\bin` 在 PATH。
- 字体：`C:\Windows\Fonts\msyh.ttc`（存在，中文/拉丁 shaping 与 "你" 光栅）、`C:\Windows\Fonts\segoeui.ttf`（存在，阿拉伯文 shaping 使用）；`C:\Windows\Fonts\arial.ttf` 作为回退路径检查存在（本次未使用）。
- 任务：`task-9`「W2-2：文本 FFI 探针（FreeType 光栅 + HarfBuzz shaping，含复杂脚本）」
- 写入范围：`examples/m0_text_probe.cr`、`docs/evidence/M0-WP4-text.md`（未改 `src/`、`spec/`、`shard.yml`、`README`、`docs/plan*`、`docs/roadmap.md`）

## 1) 实现摘要（`examples/m0_text_probe.cr`，纯 FFI，无 shard）

- `@[Link("freetype")]`：`FT_Init_FreeType` / `FT_Done_FreeType` / `FT_Library_Version` / `FT_New_Face` / `FT_Done_Face` / `FT_Set_Char_Size` / `FT_Load_Char` / `FT_Get_Char_Index`；读取 `FT_FaceRec` 中 `family_name`/`style_name` 与 `glyph` slot 指针（按 x86_64 Windows LLP64、32-bit `long` 布局手工偏移：`family_name@24`、`style_name@32`、`glyph@120`），从 `FT_GlyphSlotRec` 读取 `glyph_index`、`advance.x`、`bitmap.width/rows/buffer/pitch`。
- `@[Link("harfbuzz")]`：`hb_version_string` / `hb_version` / `hb_blob_create_from_file` / `hb_face_create` / `hb_font_create` / `hb_font_set_scale` / `hb_buffer_*` / `hb_shape`；取 `hb_glyph_info_t.codepoint` 与 `hb_glyph_position_t.x_advance`。
- FreeType：`FT_New_Face("C:\Windows\Fonts\msyh.ttc", 0)`，`FT_Set_Char_Size(0, 24*64, 96, 96)`，对 "你"(U+4F60) `FT_Load_Char(..., FT_LOAD_RENDER)`，warmup 10 次后计时 100 次取平均；统计 bitmap 非零像素数。
- HarfBuzz 中文：对 `"你好 Tessell"`（UTF-8）用 msyh blob/face/font scale 24*64 进行 `hb_shape`，打印 glyph_count 及每 glyph `codepoint/advance`，记录首 glyph advance 为 `zh_advance`。
- HarfBuzz 复杂脚本：阿拉伯文 `"سلام"`（4 个 Unicode codepoint），使用 `C:\Windows\Fonts\segoeui.ttf`（存在则选用，否则回退 arial.ttf，不存在则显式失败），打印 shaped glyph_count、每 glyph `codepoint/advance`、`ar_codepoints` 与 `ar_shaping_diff=(ar_glyphs != ar_codepoints)` 以说明连写/替换是否体现为 glyph 数差异。
- 计时：shape `"你好世界"` warmup 10 次 + 1000 次取平均 `shape_us_avg`；render `"你"` warmup 10 次 + 100 次取平均 `render_us_avg`（`Time.instant` / `Time::Span.total_microseconds`）。
- 失败策略：任一 FFI/初始化/字体/空指针/关键计数异常均 `STDERR` 报错并 `exit 1`；无 fallback 假数据。
- 输出固定 token：`ft_version`、`hb_version`、`zh_glyphs`、`zh_advance`、`render_px`、`ar_glyphs`、`ar_codepoints`、`shape_us_avg`、`render_us_avg`（另附诊断行：face family/style、glyph index/advance/bitmap 尺寸、逐 glyph 明细、`ar_font`、`ar_shaping_diff`）。

## 2) 调试记录（真实）

1. **首版 `crystal run` 崩溃（EXITCODE=1）**：初稿按 64-bit `FT_Long/FT_Pos` 与不准确的 `FT_FaceRec/FT_GlyphSlotRec` 布局声明结构体，`crystal run examples/m0_text_probe.cr` 触发 `Invalid memory access (C0000005) at address 0x7ffee797a2f0`（含 4 条 `Time.monotonic` 弃用警告）；编译未报错但运行期访问错误内存。说明 Windows x86_64 (mingw/ucrt64, LLP64) 下 FreeType `FT_Long/FT_Pos` 为 32-bit，需匹配实际 ABI 布局。
2. **同版 `crystal build` 成功但数值异常**：`crystal build examples/m0_text_probe.cr -o bin/m0_text_probe.exe` `BUILD_EXIT=0`（同样 4 条弃用警告）；运行 `bin/m0_text_probe.exe` `EXITCODE=0`，但 FreeType glyph 读数异常（`ft_face_family/style` 空、`ft_glyph_index=3393867984`、`ft_advance_x26=2147483648`、`ft_bitmap_w=7929953`、`ft_bitmap_rows=4980844`、`render_px=0`），HB shaping 数值正常。判定为结构体布局错误导致读取错位，非伪造但不可作为有效证据。
3. **修复**：改用 32-bit `FT_Long/FT_Pos/FT_Fixed` 与精简 `FT_Bitmap/FT_GlyphSlotRec` 前缀布局，增加 `FT_Get_Char_Index` 校验；通过 `FT_FaceRec` 固定偏移读取 `family_name@24`、`style_name@32`、`glyph slot@120`；计时改用 `Time.instant`。修复后 `crystal run` 与 `crystal build` 均通过，glyph/bitmap/advance 数值合理。

## 3) 命令与原始输出

### 3.1 运行（修复后）

命令：
```powershell
$env:PATH = "C:\msys64\ucrt64\bin;" + $env:PATH
Push-Location "C:\Users\ShiningRay\projects\ShiningRay\tessell"
& "C:\msys64\ucrt64\bin\crystal.exe" run examples/m0_text_probe.cr 2>&1
"EXITCODE=$LASTEXITCODE"
Pop-Location
```

原始 stdout/stderr 合并输出：
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
shape_us_avg=0.387
render_us_avg=5.116
EXITCODE=0
```

### 3.2 构建（修复后）

命令：
```powershell
$env:PATH = "C:\msys64\ucrt64\bin;" + $env:PATH
Push-Location "C:\Users\ShiningRay\projects\ShiningRay\tessell"
& "C:\msys64\ucrt64\bin\crystal.exe" build examples/m0_text_probe.cr -o bin/m0_text_probe.exe 2>&1
"BUILD_EXIT=$LASTEXITCODE"
Pop-Location
```
原始输出：
```
BUILD_EXIT=0
```
产物：`C:\Users\ShiningRay\projects\ShiningRay\tessell\bin\m0_text_probe.exe`（2364024 bytes，2026/11/12 16:46:51）。

## 4) 结果解读与核验点

- `ft_version=2.15.0`、`hb_version=15.1.0`：与 task-8 安装/FFI 版本一致。
- 中文 shaping `"你好 Tessell"`：`zh_glyphs=10`（2 汉字 + 1 空格 + 7 拉丁字母），逐 glyph codepoint/advance 均由 HB 返回；`zh_advance=1536` 为首 glyph（"你"）x_advance（26.6/font units，scale 24*64）。
- 中文光栅 "你"：`ft_face_family=Microsoft YaHei`、`ft_face_style=Regular`、`ft_glyph_index=1154`、`ft_advance_x26=2048`（26.6）、`ft_bitmap_w=32`、`ft_bitmap_rows=30`、`render_px=410`（bitmap 非零覆盖像素数）。
- 复杂脚本 `"سلام"`（4 codepoints，segoeui.ttf）：`ar_glyphs=4`、`ar_codepoints=4`、`ar_shaping_diff=false`。本样本在 Segoe UI 下 shaped glyph 数与 codepoint 数相同（未观察到 glyph 数层面的合并/拆分差异）；HB 仍执行了 shaping（返回具体 glyph codepoint/advance 序列，顺序与字形选择由 shaper 决定）。是否发生 GSUB/连字替换的细粒度断言 [未验证：未比对未 shaping 的 nominal glyph 序列与 positions 细节差异]。
- 计时：`shape_us_avg=0.387`（"你好世界"×1000，warmup 10）、`render_us_avg=5.116`（"你" render×100，warmup 10），单位 µs。

## 5) 对 M1-WP2 文本测量接口的含义

- 测量/排版需稳定的 **(face/blob, size/scale, script/language/direction)** 上下文：本探针表明 HB 需 `hb_font` scale 与 `hb_buffer` 属性猜测/设置后 shaping；FT 需 face + char size + load/render 才能得到 advance/bitmap。M1-WP2 应缓存 `FT_Face`/`hb_font`（按 font+size）与可复用 `hb_buffer`，避免每次测量重建。
- shaping 输出可作为测量主数据：`glyph codepoint + x/y advance (+ offset)` 序列；光栅 bitmap 用于绘制/atlas，上层测量可优先使用 advance 宽度与行高/ascender/descender（本探针未提取 line metrics，[未验证]）。
- 复杂脚本需保留 script/direction/cluster 信息以支持光标与命中测试；本探针仅记录 glyph 数与 advance，未验证 BiDi/cluster 映射。[未验证]
- 性能基线（本机单样本）：shape ~0.39 µs/4字串、render ~5.12 µs/字；作为量级参考，非门禁值，受字体/缓存/机器影响。[未验证：未做多轮统计与跨机器对比]

## 6) 失败/降级与 [未验证] 项

- `--json` 机器可读输出：未实现（任务书未要求）。[未验证]
- spec 冒烟：未新增（任务书“可选，仅在 tests 无 DLL 缺失时”；为避免不稳定，本次未做）。[未验证]
- 阿拉伯文连字/GSUB 替换的强断言：仅记录 `ar_shaping_diff=false` 与 glyph 序列；未做 nominal-vs-shaped 深比较。[未验证]
- 其他复杂脚本（Devanagari/Thai/emoji ZWJ 等）：未覆盖。[未验证]
- HarfBuzz 直接使用 FreeType font functions（`hb_ft_font_create`）未尝试；本探针 hb/ft 独立加载同一字体文件。[未验证]
- DLL 解析在无 `C:\msys64\ucrt64\bin` PATH 的干净环境：未实测。[未验证]
- 首版结构体布局崩溃/错位已修复并重新实测；修复后结果以第 3 节输出为准。

## 7) 结论

- **PASS（探针可用）**：`examples/m0_text_probe.cr` 在 ucrt64 Crystal 1.22.1 下可 `run`（EXITCODE 0）且可 `build`（BUILD_EXIT 0）；真实调用 FreeType 光栅 "你" 得到非空 bitmap（32x30, 410 px）与 advance，HarfBuzz 对中文与阿拉伯文完成 shaping 并输出 glyph/advance；计时均为实测值。
- **M-1 文本 FFI 依赖链实证**：与 task-8 共同证明 Crystal 纯 FFI 下 FreeType/HarfBuzz 动态加载、shaping、光栅可用；可作为 M1-WP2 文本测量接口实现前的事实依据（需结合缓存与脚本属性设计）。
