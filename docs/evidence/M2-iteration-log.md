# M2 迭代 1 收口日志（M2-iter1）

## 迭代概览
- 迭代：M2-iter1
- 仓库：C:\Users\ShiningRay\projects\ShiningRay\tessell（HEAD=a74823b，origin/main 同步）
- 执行：gongbu-shangshu-2（工部尚书副手）
- 收口任务：task-44「M2 迭代 1 收口：提交并推送」

## 任务表
| 任务 | 状态 | 说明 |
|---|---|---|
| T39（输入/命中/焦点/路由） | 完成 | 输入事件、命中测试、焦点与路由；spec 数量 107→110 examples，全绿 |
| T40（font-fallback） | 完成 | `docs/research/font-fallback.md`（117 行） |
| T41（核验 PASS） | 完成（核验） | P3 六条核验通过，flake 0/20 不复现（`docs/evidence/verify-M2-WP1.md`） |
| T42（glyph-atlas） | 完成 | `docs/research/glyph-atlas.md`（108 行） |
| T43（PointerUp 清 pressed 修复 + 4 用例） | 完成（已由首辅复核并由本次执行者完成确认） | `src/tessell/input/router.cr:46-49` 修复；`spec/input_router_spec.cr` 覆盖相关用例；`crystal spec` 全绿 |

## 本机环境
- Crystal：1.22.1 [23828b0a40]
- 平台：Windows（ucrt64）
- PATH：需 `C:\msys64\ucrt64\bin`（执行前设置 `$env:PATH="C:\msys64\ucrt64\bin;$env:PATH"`）

## 验收数字（提交前自检）
- `crystal spec`：110 examples / 0 failures / 0 errors / 0 pending（SPEC_EXIT=0）
- `crystal build src/tessell.cr`：EXITCODE 0（构建产物 `tessell.exe` 已按流程删除）
- `crystal run tools/zero_alloc_frame.cr`（两场景 token）：static/paint1 alloc_bytes=0

## 未验证清单
- 真实 IME 组合
- 绝对坐标换算
- 冒泡/enabled 未实现
- glyph atlas 未实现
- GPU 上传未纳入 GC 窗口

## 已知缺口与后续
- M2-WP2 文本栈
- M2-WP3 IME
- M2-WP4 虚拟列表
- M2-WP5 a11y

## 提交信息
- 提交 1（feat）hash：17814ca9465eb1f3353bc689797392449fc7215d
- 提交 1（feat）短 hash：17814ca
- 提交 2（docs 回填）hash：78ee3afa975397aef53e93ddc1677b30ebd15bf9
- 提交 2（docs 回填）短 hash：78ee3af

---

## M2 迭代 2（M2-iter2）

### 任务与产出
- **T45（M2-WP2a，FtMeasurer + FFI）**：静态 `@[Link("freetype")]` / `@[Link("harfbuzz")]` 本机直接链接成功（`crystal build` EXIT=0），未采用 LoadLibraryW 动态绑定，决策写入 FFI 文件头。产出：`src/tessell/text/ffi/freetype.cr`、`src/tessell/text/ffi/harfbuzz.cr`、`src/tessell/text/ft_measurer.cr`、`spec/text_ft_spec.cr`（6 条）、`spec/text_ft_zero_alloc_spec.cr`（1 条）、`src/tessell.cr`（+1 行 `require "./tessell/text/ft_measurer"`）。
  - **教训（BOM 误报）**：曾用 PowerShell `Set-Content -Encoding UTF8` 写源码/文件导致首字节带 BOM，编译报 `Error: unexpected token: "@["`，误判为链接/语法问题；根因实为 BOM。后续代码与提交信息一律用 `write` 工具写入（禁 `Set-Content` 默认编码）。
- **T46（样例集与验收口径）**：`docs/research/text-acceptance.md`，100 行（含 Latin/AV kerning、CJK「你好世界」与扩展 B「𠀀」、Emoji「😀」三档、阿拉伯语「لا」lam-alef 字体差异、组合字符 e+U+0301；验收口径表；P0/P1/P2 分级；计划映射；未验证清单 10 条）。
- **T47（独立核验）**：`docs/evidence/verify-M2-WP2a.md`（16629B），裁定 **PASS-WITH-DEFECTS**（P1/P2 无）。

### T47 核验要点（摘录）
- **P3 两条**：P3-1 `ft_measurer.cr` 多处抛裸 `Exception` 而非专门异常类型；P3-2 静态 `@[Link]` 下 DLL 缺失时已编译产物表现为 loader 失败（EXIT=-1073741515/0xC0000135），`available?=false` 路径在该部署形态下不可达（实现方式限制，未阻塞）。
- **B 段（布局手算，全部一致）**：`FT_Bitmap` 40B、`FT_Glyph_Metrics` 32B（horiAdvance@16）、`FT_GlyphSlotRec` 248B（metrics@48 linearHoriAdvance@80 advance@88 bitmap@104）、`FT_FaceRec` 216B、`FT_SizeRec` 64B（metrics@24）、`FT_Size_Metrics` 28B（ascender@12 descender@16 height@20）；`hb_glyph_info_t` 20B（codepoint@0 cluster@8）、`hb_glyph_position_t` 20B（x_advance@0 y_advance@4 x_offset@8 y_offset@12）。`FT_Long=4`、指针=8。
- **D 段（零分配）**：`spec/text_ft_zero_alloc_spec.cr` 5/5 无 flake；warmup+GC.collect+GC.disable 窗口内 1000 次命中 `delta bytes_since_gc==0`。
- **E 段（边界/健壮性）**：空串 `""`→0/0、空白 `" "`→w4.734375 h21.0、`"你"*200`→w3200.0 h21.0，均无 NaN/负值；坏路径明确异常（如 `FtMeasurer.open: font file not found: ...`）；100 次 open/measure/close 句柄计数 delta 0（185→185）。
- **H 段（HB 一致性）**：`"Hello"` size16 msyh.ttc idx0 width=40.140625 == HB positions advance 求和，`diff=0.0`，height=21.0，glyphs=5。

### 验收数字（提交前自检，M2-iter2）
- `crystal spec`：117 examples / 0 failures / 0 errors / 0 pending（EXIT=0）
- `crystal build src/tessell.cr`：EXITCODE 0（构建产物 `tessell.exe` 已删除）
- `crystal run tools/zero_alloc_frame.cr`：两场景（static/paint1）`alloc_bytes=0`

### 未验证清单（沿用 + M2-WP2a 范围）
- 真实 IME 组合
- 绝对坐标换算
- 冒泡/enabled 未实现
- glyph atlas 未实现
- GPU 上传未纳入 GC 窗口
- M2-WP2a 以外文本栈（排版/渲染集成）、多字体回退链、复杂脚本/BiDi/emoji 彩色实渲未覆盖

### 已知缺口与后续
- M2-WP2 文本栈其余
- M2-WP3 IME
- M2-WP4 虚拟列表
- M2-WP5 a11y

### 已知瑕疵（不改写历史）
- **M2-iter1 `17814ca` commit message 首字节带 BOM（U+FEFF, EF BB BF）**：原因同上（PowerShell `Set-Content -Encoding UTF8` 写提交信息文件）。原样取证，不改写历史。
  - 取证命令：`git log --format=%s -1 17814ca | Format-Hex`（PowerShell 管道显示，非 ASCII 显示为 `?`/`3F`）：
```
           00 01 02 03 04 05 06 07 08 09 0A 0B 0C 0D 0E 0F

00000000   66 65 61 74 28 6D 32 29 3A 20 3F 3F 3F 3F 3F 3F  feat(m2): ??????
00000010   3F 3F 3F 3F 3F 3F 3F 3F 3F 20 2B 20 3F 3F 3F 3F  ????????? + ????
00000020   2F 3F 3F 3F 3F                                   /????           
```
  - 字节级取证（`git log --format=%s -1 17814ca` 重定向后 `[IO.File]::ReadAllBytes`）：`len=87 first16=EF BB BF 66 65 61 74 28 6D 32 29 3A 20 E8 BE 93`（首字节 `EF BB BF` 确认 UTF-8 BOM）。

### 提交信息（M2-iter2）
- 提交 1（feat）hash：待回填（docs: 回填 M2 迭代 2 提交 hash）
- 提交 1（feat）短 hash：待回填
- 提交 2（docs 回填）hash：待回填
- 提交 2（docs 回填）短 hash：待回填
