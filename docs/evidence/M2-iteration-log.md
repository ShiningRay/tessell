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
- 提交 1（feat）hash：10253733405e9f936abab8b43103e9e56198d22e
- 提交 1（feat）短 hash：1025373
- 提交 2（docs 回填）hash：76ef5d6e6f06b6358329049a049c89d32c913a1e
- 提交 2（docs 回填）短 hash：76ef5d6

---

## M2 迭代 3（M2-WP2b / M2-WP2c）

### 任务与状态
| 任务 | 状态 | 说明/产出 |
|---|---|---|
| T49（M2-WP2b 字形图集） | 完成 | `src/tessell/text/glyph_atlas.cr`、`spec/glyph_atlas_spec.cr`：R8 Page/shelf 装箱、GlyphKey(FNV-1a-64)/GlyphSlot、lookup/insert(LRU tick)/invalidate_font/begin_frame-end_frame 帧内禁止淘汰(FrameEvictionError)/evict_lru 与页复用/page_data+slot_rect 等 |
| T52（WP2b 核验） | 完成（核验） | `docs/evidence/verify-M2-WP2b.md`（99 行，read 工具口径），裁定 **PASS-WITH-DEFECTS**（P1/P2 无；P3-1 超大字形 acquire_page 后失败遗留空页、P3-2 0 尺寸/重复 key 尺寸忽略语义未约束） |
| T53（M2-WP2c 光栅化） | 完成 | `src/tessell/text/rasterizer.cr`、`spec/rasterizer_spec.cr`：Rasterizer(face,atlas)、rasterize/rasterize_into、GlyphPlacement、HB shaping 复用、FT_Load_Glyph(FT_LOAD_RENDER) 8bpp 写 atlas、负 pitch 拷贝逻辑、命中复用 stats(hits/misses/rasters) |
| T54（atlas P3 修复 + 接线） | 完成 | P3-1 超大字形在 acquire_page 前预检 raise（page_count/旧槽不变，消息不变）；P3-2 0 尺寸 `ArgumentError`、同 key 重复 insert 首槽生效(忽略新参数)；`src/tessell.cr` +2 行 require(glyph_atlas/rasterizer)；glyph_atlas_spec 保留既有并补充覆盖 |
| T55/T56（WP2c 首轮核验与探针加固） | 完成（发现缺陷/加固未根治） | `docs/evidence/verify-M2-WP2c.md`（88 行）裁定 **FAIL**（P1 rasterize_into 全缓存命中 `delta_steady=16` 非 0；P2 零分配稳定性不足 5 次中 1 次 flake；P3-1 空白/零尺寸字形抛异常、P3-2 `"لا"` placements/advance 三方不一致、P3-3 负 pitch 未触达、P3-4 单跑 FT::Lib 未限定）。task-56 将 core_node/render_dirty/text_ft 三探针改为 prime+steady 双窗口并补诊断，但 dalisi 独立连跑 5 次仍 run1 失败 1/5（双窗口未根治） |
| T58（零分配判据可判定化） | 完成 | 4 探针(core_node/render_dirty_into/text_ft/glyph_atlas)+`tools/zero_alloc_frame.cr` 统一：warmup→prime(诊断)→calib(N 空迭代,诊断)→3 work 窗口取 max；`GC.enable` in ensure；打印 `delta_prime/delta_calib/delta_work/N/windows=[w1,w2,w3]`；判据 **A `delta_work < N`(N=1000)**、**B `delta_work <= 64`**；修 glyph_atlas_spec.cr:151 旧单窗口；报告 `docs/evidence/M2-WP2c-zero-alloc-criterion.md`（24 行）。验收：全量 10/10 绿 `141 examples, 0 failures`；4 探针各 10 次 40/40 绿 |
| T59（rasterizer 三缺陷修复 + spec 单跑） | 完成 | D1：gid==0/bitmap w<=0||h<=0 不入图集仍产 placement(w=h=0,uv 空,保留 HB advance/bearing)；D2：RTL `"لا"` placements 数==HB glyph 数且 Σadvance 与 measure/HB 一致（msyh count==2，tahoma/arial/times count==1）；D3：新增 `spec/spec_helper.cr`，15 个 spec 补 require/spec_helper 与必要限定，逐文件单跑 15/15 全绿；rasterizer_spec 11 examples 0 failures |
| T60（修复复核） | 完成（核验） | `docs/evidence/verify-M2-WP2c-fix.md`（83 行），裁定 **PASS**；对抗实验 `bin/_negctl.cr` (8B×1000/call) **RESULT=CAUGHT** `delta_work=31968 windows=[28576,31968,31968] criterion_ok=false`（判据未放水）；独立 5/5 全量 + 20/20 探针全绿 |

### 两轮核验裁定
- `docs/evidence/verify-M2-WP2b.md`（99 行）：**PASS-WITH-DEFECTS**（P3-1/P3-2 观察项）。
- `docs/evidence/verify-M2-WP2c.md`（88 行）：**FAIL**（P1/P2 + P3 若干）。
- 修复（T54/T56/T58/T59）后 `docs/evidence/verify-M2-WP2c-fix.md`（83 行）：**PASS**（P3 观察项 2 条，非阻塞）。

### 零分配判据变更与理由
- 背景：Boehm `GC.stats.bytes_since_gc` 在 GC.disable 下仍可出现间歇簿记噪声，严格 `delta==0` 在 Windows 上不可判定。
- 取证（task-59，rasterize_into 全缓存命中 1000 次 × 20 窗口）：`0,0,0,0,16,0,16,0,0,16,0,0,16,0,16,0,0,16,0,0`（+16B 间歇、非 per-call，可落任意窗口）。
- task-58 step1 全量 20 次 flake 原始失败行：run1,3-7,9-17,19-20 EXIT=0 `138 examples, 0 failures`；run2 EXIT=1 `138 examples, 2 failures` — `spec\glyph_atlas_spec.cr:151` `Expected 0 got 16`；`spec\render_dirty_into_spec.cr:90` `delta_steady.should eq 0` Expected 0 got 16 (Finished 100.44ms)；run8 EXIT=1 `138 examples, 1 failures` — `spec\glyph_atlas_spec.cr:151` Expected 0 got 16 (Finished 137.08ms)；run18 EXIT=1 `138 examples, 1 failures` — `spec\core_node_zero_alloc_spec.cr:109` `delta_steady should eq 0` Expected 0 got 16 (Finished 142.42ms)。未复现 `spec/text_ft_zero_alloc_spec.cr:12`；`glyph_atlas_spec.cr:151` 原为旧单窗口协议。
- 新判据：`delta_work = max(3 work windows)`；**A `delta_work < N`**（N=1000，1B/次 per-call ⇒ 每窗 ≥1000B 必失败）；**B `delta_work <= 64`**（容忍观测到的 +16B 噪声，仍检出 ≥100B 固定分配）；prime/calib 仅诊断，失败打印四数+序列。
- 强度/对抗：对抗实验 `bin/_negctl.cr` 每调用分配 8B×1000 次 → **CAUGHT** `delta_work=31968 windows=[28576,31968,31968] criterion_ok=false`。判据不证明“绝对 0 分配”，提供 Boehm 噪声下可判定的强下界检测；若观测到 >64B 噪声需升级分位法。

### 验收数字（M2-iter3，收口自检）
- `crystal spec`：141 examples / 0 failures / 0 errors / 0 pending（EXIT=0）
- 逐文件单跑：15/15 全绿（EXIT=0）
- `crystal build src/tessell.cr`：EXIT=0（构建产物 `tessell.exe` 删除）
- `crystal run tools/zero_alloc_frame.cr`：scenario=static/paint1 `alloc_bytes` 0 或在判据内、`criterion_ok=true`

### 未验证清单
- 真实 IME 组合 / 绝对坐标换算（沿用）
- 真实负 pitch 位图样本在本机未触达（代码分支按 FT 语义实现，正 pitch 路径已验证）
- 真实 IME 手测未做
- GPU 上传未纳入 GC 窗口（沿用）

### 已知缺口与 P3 观察项
- M2-WP2 文本栈其余、M2-WP3 IME、M2-WP4 虚拟列表、M2-WP5 a11y（虚拟列表/a11y 设计预研见 `docs/research/virtual-list-a11y.md`，100 行）
- P3 观察项（verify-M2-WP2c-fix）：空白 bitmap 路径（rasterizer）累计 `miss/rasters` 但不增 `used_pixels`（统计口径与 gid==0 路径不完全一致，placements/advance 正确且不入图集）；`tools/zero_alloc_frame.cr` paint1 偶发 `alloc_bytes=16`（windows 含 16，仍 `criterion_ok=true`，在 A/B 内）

### 提交信息（M2-iter3）
- 提交 1（feat）hash：待回填
- 提交 1（feat）短 hash：待回填
- 提交 2（docs 回填）hash：待回填（本次收口第二次提交后）
- 提交 2（docs 回填）短 hash：待回填（本次收口第二次提交后）
