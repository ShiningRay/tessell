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
- 提交 1（feat）hash：77f42d80a2f8be448dffcbd8f4838ff2ca893114
- 提交 1（feat）短 hash：77f42d8
- 提交 2（docs 回填）hash：fdb797c11e7c52bb73a8b68d1f22d883b1f2b464
- 提交 2（docs 回填）短 hash：fdb797c

---

## M2 迭代 4：文本上屏（M2-WP2d）+ IME 探针（M2-WP3 部分）

### 交付清单
- `src/tessell/render/text_renderer.cr`：CPU 四边形/批次生成（Vertex/TextRenderer，按 atlas 页分段，build_text 复用缓冲，零位图字形不产 quad 但推进 pen，UV∈[0,1]）。
- `src/tessell/render/gl/gl_renderer.cr`：GL 1.1 兼容后端（纯 FFI `opengl32`，R8→GL_ALPHA，`glPixelStorei(GL_UNPACK_ALIGNMENT,1)`，GL_LINEAR+GL_CLAMP，GL_QUADS immediate）。
- `spec/text_renderer_spec.cr`：8 examples（含稳态零分配探针，判据 A `delta_work<N` & B `<=256`，3 窗口 max，GC.enable in ensure，失败整套重试 1 次）。
- `examples/m2_text_window.cr`：窗口+GL 上屏与像素回读验证（`--frames`/`--verify`，输出 text_pixels_nonbg/cpu_coverage_sum/ratio/pixel_match/p50/p95/p99 等）。
- `examples/m2_ime_probe.cr`：IMM32 程序化注入与回读探针（焦点/HKL 枚举激活、ImmSetCompositionStringW(SCS_SETSTR)+PostMessageW(WM_IME_COMPOSITION) 回读、候选探测，标签区分 `ime_injection_available`/`ime_hkl_is_ime` 与期望/实测长度）。
- `docs/research/gl-text-renderer.md`（188 行，提交时实际值；feat 6520dca 提交时文档后续经 hanlin 扩写落盘，本次 docs 提交同步为最新稿）：GL 1.1 路径与对齐/上传/兼容性调研。
- `docs/evidence/M2-WP3-ime.md`：IME 已证/未证/手测证据（含修正后输出与渲染管线关联）。
- `docs/evidence/M2-WP3-p3-arabic-msyh.md`：`"لا"` msyh vs arial/times 定性与处置。
- `docs/evidence/verify-M2-WP2d.md`、`docs/evidence/verify-M2-iteration4.md`：独立核验报告。
- `docs/evidence/M2-WP2c-zero-alloc-criterion.md`：判据 B 升级至 256、噪声分布取证、探针重试缓解及「能证明什么/不能证明什么」补充（dalisi PASSED_BLIND 实证）。
- `docs/research/text-acceptance.md`：S-AR-LA 样例字体改为 `arial.ttf` 并注明 msyh gid=0 证据/理由。
- `src/tessell.cr`：追加 `require "./tessell/render/text_renderer"`（GL 后端不进根入口，仅样例按需 require）。
- `tools/zero_alloc_frame.cr` 与 4 既有零分配探针 spec：同步判据 B<=256 与失败整套三窗重试 1 次（`retried/attempt` 诊断）。

### 实测数字（迭代 4 收口口径）
- `crystal spec`：`149 examples, 0 failures, 0 errors, 0 pending`（EXIT=0）。
- 窗口/上屏验证（`m2_text_window --frames=60 --verify`，核验记录）：`text_pixels_nonbg=2801 cpu_coverage_sum=2638 ratio=1.0618 pixel_match=true frames=60 swapbuffers=60 p50=1.81 p95=8.16 p99=9.00 quads=14 batches=1`（GL1.1 R8→GL_ALPHA，`glPixelStorei(GL_UNPACK_ALIGNMENT,1)`）。
- IME 探针（本机修正后实测）：`ime_injection=blocked ime_injection_reason=imm_set_composition_rejected ime_injection_available=false ime_hkl_is_ime=true ... kl_count=2 kl_ids=0x8040804,0x4090409 ... candidate_list_bytes=144 candidate_list_entries=0 preedit_roundtrip=false result_roundtrip=false preedit_got_len=-1 result_got_len=-1 IMM_ERR=ImmSetCompositionStringW_rejected_preedit_ret=0_result_ret=0_win32_error=0`，`IME_PROBE_EXIT=0`（程序化注入被拒，非伪造；渲染管线 CPU 侧证据：nihao→5 quads, 你好→2 quads）。
- `"لا"`（U+0644 U+0627）：`msyh.ttc` 16/24/32px HB `glyph_ids=[0,0]`（placements w=h=0，不可绘制，advance/measure 正确；gid=0 FT 可得 .notdef 位图但非目标字形）；`arial.ttf`/`times.ttf` 对应字号 `glyph_id=1019` 1 glyph，drawable 可绘制且 advance/measure 一致（S-AR-LA 样例改用 arial）。

### 核验裁定
- **WP2d 独立核验：PASS-WITH-DEFECTS**（`docs/evidence/verify-M2-WP2d.md`）：P1 竞态为执行中途编辑所致，独立复跑确认 `149/0f`；探针重试实现认定“无放水”（整套重测且 A/B/断言不跳过）。缺陷项按报告记录（P3 级）。
- **迭代 4 证据集核验：PASS-WITH-DEFECTS**（`docs/evidence/verify-M2-iteration4.md`）：**未发现伪造**；`expected/got` 分离、`candidate_list_bytes` vs `candidate_list_entries` 拆分、Arabic 定性均被独立复算证实。缺陷项按报告记录。

### 未验证清单（逐条）
- 真实键盘 IME 手测未完成（C2 开放）：`WM_IME_STARTCOMPOSITION → COMPOSITION(GCS_COMPSTR)×n` 不丢字 → `COMPOSITION(GCS_RESULTSTR)` → `ENDCOMPOSITION`、候选窗真实定位、多 IME 切换，程序化注入本机被拒无法替代。
- Emoji 彩色（COLR/CPAL 等）未实现（当前 R8/GL_ALPHA 灰度路径）。
- GL 着色器路径未做（GL 1.1 immediate 模式兼容路径）。
- `GlRenderer#delete_textures` 生命周期/泄漏未深验。
- `ratio`（text_pixels_nonbg / cpu_coverage_sum）判据非逐像素等价，受线性滤波/混合/采样差异影响（容差 [0.5,1.5]）。
- B 门盲区：≤256B 稀疏分配可放过（dalisi PASSED_BLIND：1 次/1000→`delta_work=32`，5 次/1000→`delta_work=160`）；1536B 级 GC/簿记尖峰靠整套重试 1 次缓解，不改 A 门强度。

### 提交信息（M2-iter4）
- 提交 1（feat）hash：6520dcafebad5cf6507198cafc400d7851249c43
- 提交 1（feat）短 hash：6520dca
- 提交 2（docs 回填）hash：待回填（本次 task-67 docs 提交后）
- 提交 2（docs 回填）短 hash：待回填
