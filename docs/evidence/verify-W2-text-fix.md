# verify-W2-text-fix：W2-复验（task-17 D1/D2 修复）独立核验报告

- 核验角色：大理寺卿（dalisi-qing，独立核验），受首辅 lead 节制
- 核验任务：`task-18`「W2-复验：D1 布局修复与 D2 shaping 证据复验（task-17）」
- 复验依据：`docs/evidence/verify-W2-text.md:246-257`（task-13 裁定 D1/D2）
- 复验对象：`examples/m0_text_probe.cr`、`docs/evidence/M0-WP4-text.md`（task-17 修改后）
- 核验时间（本地）：2026-11-12 17:24:38 +08:00 ～ 2026-11-12 17:28:00 +08:00（Asia/Shanghai，会话采样）
- 仓库：`C:\Users\ShiningRay\projects\ShiningRay\tessell`
- HEAD：`1b0d832220f3017e9efd6f42d59b5d7fab6b09f3`
- OS/Arch：`Microsoft Windows NT 10.0.26300.0` / `AMD64`
- Crystal：`C:\msys64\ucrt64\bin\crystal.exe`，`Crystal 1.22.1 [23828b0a40] (2026-10-23)`，`LLVM 23.1.3`，`Default target: x86_64-w64-windows-gnu`
- 命令 PATH 前置：`$env:PATH="C:\msys64\ucrt64\bin;"+$env:PATH`

## 0. 范围与边界

- 唯一写入：本报告 `docs/evidence/verify-W2-text-fix.md`。**未修改**被核验文件 `examples/m0_text_probe.cr`、`docs/evidence/M0-WP4-text.md`，未改 `src/`、`spec/`、`shard.yml`、`README`、`docs/plan*`、`docs/roadmap.md`。
- `git status --short -- examples/m0_text_probe.cr docs/evidence/M0-WP4-text.md`：`?? docs/evidence/M0-WP4-text.md`、`?? examples/m0_text_probe.cr`（task-17 目标文件在当前工作区为 untracked）。
- `git status --short`（核验时全局）：另含 `?? docs/evidence/M0-WP4-ime.md`、`?? docs/evidence/M0-WP4-text-deps.md`、`?? docs/evidence/M0-WP5m-metrics.md`、`?? docs/evidence/verify-W2-ime-metrics.md`、`?? docs/evidence/verify-W2-text.md`、`?? docs/research/layout-two-pass.md`、`?? examples/m0_ffi_load.cr`、`?? examples/m0_ime_probe.cr`、`?? tools/` 等预存 W2 未跟踪产物；非本次复验引入，未触碰。`src/spec/shard.yml/docs/plan*` 无修改。

## 1. 重跑命令与原始输出

命令：
```powershell
$env:PATH="C:\msys64\ucrt64\bin;"+$env:PATH
crystal run examples/m0_text_probe.cr 2>&1
"EXITCODE=$LASTEXITCODE"
```

原始输出（stdout/stderr 合并）：
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
shape_us_avg=0.45
render_us_avg=9.773
EXITCODE=0
```

### 1.1 既有 token 与修复前（verify-W2-text.md 基线）对比

| token | 修复前基线（`docs/evidence/verify-W2-text.md:79-98` 等） | 本次重跑 | 结论 |
|---|---|---|---|
| `ft_version` | 2.15.0 | 2.15.0 | 一致 |
| `hb_version` | 15.1.0 | 15.1.0 | 一致 |
| `ft_glyph_index` | 1154 | 1154 | 一致 |
| `ft_advance_x26` | 2048 | 2048 | 一致 |
| `ft_bitmap_w` | 32 | 32 | 一致 |
| `ft_bitmap_rows` | 30 | 30 | 一致 |
| `render_px` | 410 | 410 | 一致 |
| `zh_glyphs` | 10 | 10 | 一致 |
| `zh_advance` | 1536 | 1536 | 一致 |
| `ar_glyphs` | 4 | 4 | 一致 |
| `ar_codepoints` | 4 | 4 | 一致 |
| `ar_shaping_diff` | false | false | 一致 |
| `ar_font` | `C:\Windows\Fonts\segoeui.ttf` | 同左 | 一致 |
| `shape_us_avg` / `render_us_avg` | 0.387 / 5.116（证据）；0.431 / 5.883（task-13 重跑） | 0.45 / 9.773 | 计时量级一致、数值波动（允许） |
| `EXITCODE` | 0 | 0 | 一致 |

新增/修复 token：`ft_bitmap_sizeof=40`、`ft_slot_bitmap_left_at144=true`、`ft_slot_bitmap_top_at148=true`、`ft_layout_assert=pass`、`ft_bitmap_left=0`、`ft_bitmap_top=26`、`ar_lam_alef_*` 多字体结果（见 §3）。

## 2. 复验项 1：D1 代码核（FT_Bitmap 布局 / offsetof 断言 / 失败路径）

**FT_Bitmap 声明**（`examples/m0_text_probe.cr:28-41`）：按 freetype `ftimage.h` 语义声明 `rows:UInt32, width:UInt32, pitch:Int32, buffer:Pointer(UInt8), num_grays:UInt16, pixel_mode:UInt8, palette_mode:UInt8, palette:Pointer(Void)`，字段顺序/类型与 C 头文件一致，无 task-13 D1 所述额外 `pad1/pad2`。

**FT_GlyphSlotRec 位置**（`examples/m0_text_probe.cr:67-70`）：`bitmap : FT_Bitmap` 位于 `104`，注释 `sizeof=40 -> 144`，`bitmap_left : FT_Int @144`，`bitmap_top : FT_Int @148`，与 freetype `FT_GlyphSlotRec_` 头文件顺序（`... format, bitmap, bitmap_left, bitmap_top, ...`）一致。

**sizeof 断言（真测，运行期）**（`:181-185`）：
- `ft_bitmap_sizeof = sizeof(LibFT::FT_Bitmap)`；若 `!= 40` 则 `STDERR.puts "assert_fail=ft_bitmap_sizeof=#{ft_bitmap_sizeof} expected=40"` 并 `exit 1`。
- 重跑输出 `ft_bitmap_sizeof=40`。

**bitmap_left/top “offsetof”证明（真测，运行期 sentinel 双向验证）**（`:186-199`）：
- 在未初始化 slot 上通过字段写入后按 C 期望字节偏移读回、再按字节偏移写入后经字段读回，验证 `bitmap_left@144`、`bitmap_top@148`；任一不匹配则 `STDERR.puts "assert_fail=ft_slot_offsets ..."` 并 `exit 1`。
- 重跑输出 `ft_slot_bitmap_left_at144=true`、`ft_slot_bitmap_top_at148=true`、`ft_layout_assert=pass`。
- 说明：Crystal 无编译期 `offsetof` 宏，采用 sentinel 读写等价证明运行时偏移正确，且为探针启动必经断言（非仅文档声明）。

**失败路径**：`:133 exit 1`（`fail`）、`:184 exit 1`（sizeof）、`:198 exit 1`（offset）及其他 FFI/字体异常 `fail` 路径均存在（grep 见 `examples/m0_text_probe.cr:133,184,198,470-473` 等）。

**读取值合理性**：`ft_bitmap_left=0`、`ft_bitmap_top=26` 与 32x30 位图、26.6 字号 msyh 渲染 "你" 的典型承载/顶偏移一致（非噪声 sentinel）。

**D1 结论**：**关闭（通过）**。FT_Bitmap 声明与 freetype 头文件顺序/类型一致；`sizeof(FT_Bitmap)==40` 及 `bitmap_left/top@144/148` 由运行期断言真实验证且通过；断言失败路径为 `exit 1`；既有 token 不变。

## 3. 复验项 3：D2 多字体 lam-alef shaping 证据与表述诚实性

**重跑实测（`"لا"` U+0644 U+0627）**：

| 字体 | glyph_count | glyph_ids | isolated_lam_alef_ids | ids_differ_from_isolated | ligature_candidate |
|---|---:|---|---|---|---|
| `C:\Windows\Fonts\tahoma.ttf` | 1 | 1019 | 989,909 | true | true |
| `C:\Windows\Fonts\arial.ttf` | 1 | 1019 | 989,909 | true | true |
| `C:\Windows\Fonts\segoeui.ttf` | 2 | 3941,3980 | 2341,2317 | true | false |
| `C:\Windows\Fonts\times.ttf` | 1 | 1019 | 989,909 | true | true |

汇总：`ar_lam_alef_fonts_tested=4`、`ar_lam_alef_min_glyphs=1`、`ar_lam_alef_ligature_font=C:\Windows\Fonts\times.ttf`。

**判定**：tahoma/arial/times 中 `glyph_count==1` 且 glyph id 与孤立形式不同，**lam-alef 单 glyph 连字证据成立**（按字体记录如上）。segoeui 中 `glyph_count==2`（未合并）但 `ids_differ_from_isolated=true`，**上下文替换已证，单 glyph 合并未证（就该字体）**；行为因字体而异，已如实呈现。

**`ar_shaping_diff=false` 表述检查**（`docs/evidence/M0-WP4-text.md`）：
- `:114`（行号按当前文件）：“`ar_shaping_diff=(ar_glyphs != ar_codepoints)` 以说明连写/替换是否体现为 glyph 数差异。”——定义性描述，未宣称“生效”。
- `:139`：“`... ar_glyphs=4、ar_codepoints=4、ar_shaping_diff=false`。本样本在 Segoe UI 下 shaped glyph 数与 codepoint 数相同（未观察到 glyph 数层面的合并/拆分差异）；HB 仍执行了 shaping（返回具体 glyph codepoint/advance 序列...）”——未写成“shaping 生效/连写生效”。
- `:147`：“`ar_shaping_diff=false` 仅指 `"سلام"` 样本 glyph 数 == codepoint 数，**不**表示 shaping 未发生；shaping 通过 glyph codepoint/advance 序列与 lam-alef 连字证据证明。HB shaping 在所有测试字体中均执行了 contextual substitution（ids_differ_from_isolated=true）。”
- `:163` [未验证] 记录：`"سلام"` 样本 glyph 数==codepoint 数（ar_shaping_diff=false），但 shaping 仍发生；更细粒度 GSUB feature 逐项比对 **[未验证]**。
- grep 未发现“`ar_shaping_diff=false` 说明连写生效/连字生效/说明 shaping 生效”等弱结论表述。

**D2 结论**：**关闭（通过）**。多字体 lam-alef 证据已补强（tahoma/arial/times 连字成立，segoeui 上下文替换已证、单 glyph 合并未证）；证据表述诚实，未再把 `ar_shaping_diff=false` 写成 shaping 生效；细粒度 GSUB 特征对照仍标 [未验证]，符合要求。

## 4. 复验项 4：证据一致性（`docs/evidence/M0-WP4-text.md`）

- 修复说明与实现摘要（D1 断言、D2 多字体测试、token 列表）与源码一致（`examples/m0_text_probe.cr:28-41,67-70,175-199,331-417,470-478`）。
- 证据 §3.1 记录的修复后运行输出（`ft_bitmap_sizeof=40`、offset 断言 true、`ft_layout_assert=pass`、`ft_bitmap_left=0`/`ft_bitmap_top=26`、4 字体 lam-alef 结果、`ar_lam_alef_ligature_font=C:\Windows\Fonts\times.ttf`、EXITCODE=0）与本次重跑稳定 token/结构一致；计时值存在合理波动（证据 0.503/7.191 vs 本次 0.45/9.773），证据已多处提示计时为噪声/量级参考。
- task-17 后未重跑 `crystal build` 已在证据中如实标注 [未验证]（`:132,168`）；其他未覆盖项（BiDi/cluster、其他复杂脚本、hb_ft 字体函数、干净 PATH、跨机统计等）标注诚实。
- 旧版 §3.2/§4/§5/§6/§7 作为 task-9 历史段仍保留在文件尾部（含当时数据与旧 `[未验证]` 表述），但文档头部与前段已明确为 task-17 修复后版本且给出更新结论；本复验以当前源码+当前重跑+文档修复段为准，未发现与修复后事实矛盾的隐瞒（建议后续整理去重历史重复段，非本复验阻断项）。

## 5. 逐项结论表

| # | 复验项 | 结论 | 依据 |
|---|---|---|---|
| 1 | D1 代码核（FT_Bitmap 声明/sizeof/bitmap_left@144,top@148/断言失败 exit 1） | 通过 | `m0_text_probe.cr:28-41,67-70,181-199,133,184,198`；重跑 `ft_bitmap_sizeof=40, ft_slot_bitmap_left_at144=true, ft_slot_bitmap_top_at148=true, ft_layout_assert=pass, ft_bitmap_left=0, ft_bitmap_top=26, EXITCODE=0` |
| 2 | 重跑与既有 token 一致性 | 通过 | EXITCODE=0；ft_version/hb_version/ft_glyph_index/ft_advance_x26/ft_bitmap_w/rows/render_px/zh_glyphs/zh_advance/ar_glyphs/ar_codepoints/ar_shaping_diff 均与 task-13 基线一致；计时量级一致 |
| 3 | D2 多字体 lam-alef 与表述诚实性 | 通过 | tahoma/arial/times glyph_count=1（连字成立），segoeui glyph_count=2 且 ids_differ_from_isolated=true（上下文替换已证、单 glyph 合并未证）；`M0-WP4-text.md:114,139,147,163` 未将 `ar_shaping_diff=false` 写成 shaping 生效，细粒度 GSUB [未验证] 已标注 |
| 4 | 证据一致性与 [未验证] 诚实性 | 通过 | 修复段输出/结论与重跑及源码一致；未重跑 build 等已标 [未验证] |
| 5 | 边界 | 通过（按复验范围） | 未改被核验文件/`src/spec/shard.yml/docs/plan*`；task-17 目标文件为 untracked 修改态；本次仅新增本报告；工作区存在其他预存 W2 untracked 文件未触碰 |

## 6. D1/D2 关闭判定

- **D1（FT_Bitmap/FT_GlyphSlotRec 尾部布局偏差，`verify-W2-text.md:250`）**：**关闭**。已修正为与 C 语义一致的 `FT_Bitmap`（sizeof 40）且 `bitmap_left/top` 位于 144/148，经运行期断言与实测读数验证；当前及后续按 C 布局读取不再受原 pad 偏移影响。
- **D2（阿拉伯文 shaping 证据强度不足，`verify-W2-text.md:251`）**：**关闭**。已补充多字体 lam-alef 实测：tahoma/arial/times 产生 1 glyph 连字（证据成立），segoeui 为 2 glyph 但存在上下文替换；证据文档不再将 `ar_shaping_diff=false` 表述为 shaping 生效，并保留细粒度/跨字体差异的 [未验证] 说明。剩余字体差异与更深 GSUB 特征验证属后续增强，不构成本缺陷未关闭。

## 7. 缺陷清单

| ID | 严重性 | 位置 | 描述 | 影响/建议 |
|---|---|---|---|---|
| （无新增阻断缺陷） | - | - | D1/D2 修复经复验通过；未发现新的伪证或回归。 | - |
| 观察-1 | 低（文档卫生） | `docs/evidence/M0-WP4-text.md` 尾部历史段 | 文件保留 task-9 时期的重复历史章节与旧输出片段，可能增加阅读歧义。 | 建议后续收口时整理去重，保留单一权威修复后证据段；不影响本次裁定。 |
| 观察-2 | 低（已声明） | `docs/evidence/M0-WP4-text.md:132,168` | task-17 后 `crystal build` 未重跑。 | 证据已标 [未验证]；如需发布产物可补跑 build。 |

## 8. 最终裁定

**裁定：PASS**

理由：task-17 对 D1/D2 的修复经独立重跑与源码审查验证有效——FT_Bitmap 布局与 bitmap_left/top 偏移由真实运行期断言通过（`ft_layout_assert=pass`），既有文本/shaping 光栅 token 与修复前一致；lam-alef 在 tahoma/arial/times 三字体上证实 1 glyph 连字成立，segoeui 为 2 glyph 且上下文替换已证，证据表述诚实且未将 `ar_shaping_diff=false` 写成 shaping 生效；边界符合“仅核验对象相关修改 + 本报告”。D1、D2 关闭。无新增阻断缺陷。
