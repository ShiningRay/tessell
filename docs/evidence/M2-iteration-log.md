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
---

## M2 迭代 5：虚拟列表（M2-WP4）+ 无障碍最小树（M2-WP5）

### 任务与状态
| 任务 | 状态 | 说明/产出 |
|---|---|---|
| task-68（M2-WP4 A/B/C/D） | 完成 | `src/tessell/widgets/virtual_list.cr`、`spec/virtual_list_spec.cr`、`tools/bench_scroll.cr`、`docs/evidence/M2-WP4-virtual-list.md`；`src/tessell.cr` 追加 require；VirtualList 固定/变高行高+prefix-sum+二分、`visible_range`/`prepare_visible` 仅可见行绑定、回收池、`Dirty.merge_into` 脏条带；spec 12 examples 全绿，簿记路径零分配探针 `delta_work=0 windows=[0,0,0]` |
| task-70（bench 补强） | 完成（并入 task-71 裁断） | bench 由簿记帧改为真实 CPU 帧（DrawList 背景/分隔线 + Rasterizer/TextRenderer 固定标签 "row 12345" + `build_batches`）；发现帧时间可解释但稳态分配未清零，转 task-71 专项 |
| task-71（稳态分配查清与修复） | 完成（部分达成 + 残余已证据化） | bisect a–f + 组件探针；修复/改造：`VirtualList` 无块 API（`visible_first/visible_last`、`prepare_visible`、`node_offset`）、`DrawList#build_batches_into(sink)` 复用、`GlyphPlacement.page` 避免 build_text 逐字形 lookup、`GlyphAtlas::Entry` struct→class 且命中不回写 Hash、`Rasterizer` 去 `GlyphPlacement?` union 装箱；bench 热路径去块/闭包；批数组分配 64064→0、scroll p50 1765→1269µs；真实 CPU 帧残余未清零（见下） |
| task-72（M2-WP5 A11y 最小树） | 完成 | `src/tessell/a11y/tree.cr`、`spec/a11y_tree_spec.cr`、`docs/evidence/M2-WP5-a11y-tree.md`；`src/tessell.cr` 追加 require；`A11y::Role/Meta/Node`、`Builder`(DFS 先序+sink 复用+`focused` 经 `FocusManager` 实时查询不另存)、`VirtualWindow.emit`(万行→容器 List+可见窗口项)；core/input/render/text/widgets 未改 |

### 核验裁定
- **PASS-WITH-DEFECTS**（`docs/evidence/verify-M2-iteration5.md`，dalisi-qing-2，task-75；62 行；HEAD 7cfb44f + 未提交工作区冻结核验）：**无 P0/P1/P2，P3×2，未发现伪造**。WP4 另有 `docs/evidence/verify-M2-WP4.md`（PASS-WITH-DEFECTS）。
- 六项硬判定（verify-M2-iteration5 结论，记入核验记录）：
  1. **a11y 焦点**：`src/tessell/a11y/tree.cr:105` `focused` 实时查询 `FocusManager#focused?`，**符合**（非旁挂缓存）；独立验证 `FOCUSED_SEQ empty=true after_focus_a=true after_focus_b=true`。
  2. **a11y 万行 emit/DFS/sink**：10000 行 `VirtualWindow#emit` 实际 **31 节点**（1 容器 + 30 可见，`children_count=10000`、scroll 前后 size 均 31）；DFS 先序稳定且随重排改变；`sink.clear` 语义为**清空覆写非追加**（build/emit 预填充被丢弃，`tree.cr:88,94,145`）。Meta 旁挂无删除 API，detach/remove 后残留 → 记为 **P3-2**。
  3. **atlas**：`Entry` `struct→class` + `lookup` 命中不回写 Hash 后，LRU tick/`evict_lru` 选最旧**正确**、`invalidate_font` 定向驱逐**正确**、**无别名 bug**（返回 `GlyphSlot` 值拷贝，Entry 私有不外泄）。
  4. **rasterizer/text_renderer 分组**：glyph 数 == placement 数三路成立（空白/notdef/零尺寸）；跨页分组与旧逐字形 lookup **等价**（placement pages `[0,1]` / 纹理 `[101,202]`，`eq_per_glyph=true`）；text_renderer 按 `placement.page` 分组无逐字形 atlas lookup。
  5. **draw_list**：`build_batches` 与 `build_batches_into` 逐字段**等价**、`batch_count` 一致；sink 预含内容时**覆写逻辑前缀 + 返回逻辑 count，尾部残留不清**（非追加，按 count 消费安全）→ 记为 **P3-1**。
  6. **virtual_list**：`prepare_visible` 与 `bind_visible` fetch 次数一致（30/30，不重复不漏）；`dirty_rects` 两带语义与 verify-M2-WP4 一致。

### 交付与实测数字
- `crystal spec spec/virtual_list_spec.cr`：**12 examples, 0 failures**（EXIT=0）；VirtualList 簿记路径零分配探针：`delta_prime=0 delta_calib=0 delta_work=0 N=1000 windows=[0,0,0] retried=false attempt=1`。
- `crystal spec spec/a11y_tree_spec.cr`：**10 examples, 0 failures**（EXIT=0，J1–J9/J5b）；A11y build 探针：`delta_prime=0 delta_calib=0 delta_work=0 N=1000 windows=[0,0,0] retried=false attempt=1`。
- `crystal spec`（全量）：**171 examples, 0 failures, 0 errors, 0 pending**（EXIT=0，从迭代 4 的 149 增至 171）。
- 万行虚拟列表（10000×20px, viewport 600）：`visible_avg=30.95/30.9555`，`fetched_per_frame_avg` 同值 ≤32，`pool_size=32 created=32`；A11y `VirtualWindow.emit` 节点数 **≤32**（容器 1 + 可见窗口项），`children_count==10000`、`scroll_offset` 正确。
- 真实 CPU 帧 bench（`tools/bench_scroll.cr`，frames=2000, n_alloc=1000，"row 12345" 16px msyh）：scroll_plus1px `cmds_avg=61.9 batches_avg=1.0 quads_avg=247.6 frame_cpu_p50_us=1269 p95=2031 p99=2688 alloc_bytes=3920 alloc_windows=[3920,0,3712] delta_prime=0 delta_calib=0 retried=true attempt=2`；jump_fixed_seed `cmds_avg=61.911 batches_avg=1.0 quads_avg=247.644 frame_cpu_p50_us=1775 p95=3669 p99=4421 alloc_bytes=4000 alloc_windows=[0,4000,0] delta_prime=3888 retried=true attempt=2`。`GL_SCROLL_WINDOW=not_done`。

### 已知缺陷（P3，verify-M2-iteration5）
- **P3-1** `src/tessell/render/draw_list.cr:92-112`：`build_batches_into` 对传入已含内容的 sink 是「覆写逻辑前缀 + 返回逻辑 count，尾部残留不清（物理尾部未清理）」；按 count 消费安全，调用方须以此语义使用（勿按 `sink.size`/越界读取尾部）。*(verify-M2-iteration5 §5)*
- **P3-2** `src/tessell/a11y/tree.cr:75-79`：`A11y::Meta` 旁挂无删除 API，节点 detach/remove 后 meta 残留（陈旧/泄漏风险，长生命周期/大量 churn 场景可能无界增长）；列入后续清理（与 task-73 同批）。*(verify-M2-iteration5 §5)*

### 残余与 task-73 承接（关键，按裁断口径）
- **量级定性**：真实 CPU 帧路径 `alloc_bytes=3920/4000` 为 **1000 帧合计**（~3.9 B/帧均摊），且集中在个别窗口（`[3920,0,3712]` / `[0,4000,0]`），**不是每帧固定分配**；正确定性为「**低频重复分配事件**（约每几百帧一次 ~4KB）」，非「每帧分配未清零/已零分配」。
- **判据裁定（分离）**：A 门（`delta_work < N`，3920>1000）真实 CPU 帧路径**未通过**；M2-WP4 零分配主张**仅覆盖 VirtualList 簿记路径**（`delta_work=0 windows=[0,0,0]`）。真实 CPU 帧路径标注「**未达零分配，残余 ~4KB/1000 帧，根因定位 text 整形/build_text 命中路径（rasterize_into/build_text 缓存命中路径簇状分配，含 HB/FT 每帧重整形候选），后续专项**」。
- **承接**：M2-WP4 真实帧残余由 **task-73**（shaped-run 跨帧缓存专项）承接，本轮不解锁门禁放水、不再深挖。

### 未验证清单（迭代 5 补充）
- 真实帧路径零分配未达成（见上，task-73 承接）；alloc_window 尖峰与 HB/FT/FFI+GC 交互的精确单点根因未以原生剖析证实（证据不足断言单一来源）。
- GL 滚动上屏基准未做（`--window`/`GL_SCROLL_WINDOW` 未实现）。
- A11y：屏幕阅读器（NVDA/Narrator）端到端、DPI/高 DPI bounds 解释、retained↔a11y 双树一致性同步时机、UIA COM provider/线程与导出形状、焦点落在被回收虚拟行时回落联动均**未验证**；J9 零分配按 A/B 判据观测通过但不能证明绝对零分配（≤256B 稀疏/簇状盲区，见判据文档）。
- 沿用迭代 4 未验证：真实键盘 IME 手测 C2 开放（程序化注入本机被拒）、Emoji COLR/CPAL、GL 着色器、`GlRenderer#delete_textures` 泄漏、`ratio` 非逐像素等价、B 门盲区与 1536B GC 尖峰 flake 风险。

### 提交信息（M2-iter5）
- 提交 1（feat）hash：a280169edd0c1526b83ff51dc30cdcd47c7ee98f
- 提交 1（feat）短 hash：a280169
- 提交 2（docs 回填）hash：待回填（本次 task-76 docs 提交后）
- 提交 2（docs 回填）短 hash：待回填

---

## M2 迭代 6：M2-WP4 真实帧路径收尾（task-73 shaped-run 跨帧缓存）

### 任务与状态
| 任务 | 状态 | 说明/产出 |
|---|---|---|
| task-73（M2-WP4 收尾） | 完成（A/B 判据达成；严格 `[0,0,0]` 未达成，给出机制性证据） | `src/tessell/text/rasterizer.cr`（`ShapedRunKey`、`shape_run_into`、shaped-run LRU 缓存 256、`begin_frame/end_frame` 帧内禁淘汰/`FrameEvictionError`、`evict_run_lru`；`rasterize_into` 保持 per-glyph 语义/统计）、`src/tessell/render/text_renderer.cr`（`build_text_cached` + `build_text_from_placements`）、`tools/bench_scroll.cr`（帧路径改用 `build_text_cached`）、`spec/shaped_run_spec.cr`（4 examples）、`docs/evidence/M2-WP4-virtual-list.md`（结论更新） |

### Spec 数字
- `crystal spec spec/shaped_run_spec.cr`：**4 examples, 0 failures, 0 errors, 0 pending**
- `crystal spec spec/rasterizer_spec.cr`：**11 examples, 0 failures**；`spec/text_renderer_spec.cr`：**8 examples, 0 failures**（含 shaped-run 变更后回归确认）
- `crystal spec`（全量）：**186 examples, 0 failures, 0 errors, 0 pending**（基线 182 + 新增 4）

### Bench 原始行（`crystal run tools/bench_scroll.cr`，2026-11-13）
```
bench_scroll config row_count=10000 row_h=20 viewport_h=600 viewport_w=800 frames=2000 n_alloc=1000 font=C:/Windows/Fonts/msyh.ttc label="row 12345"
scenario=scroll_plus1px visible_avg=30.95 fetched_per_frame_avg=30.95 cmds_avg=61.9 batches_avg=1.0 quads_avg=247.6 alloc_bytes=112 frame_cpu_p50_us=102 frame_cpu_p95_us=190 frame_cpu_p99_us=202 frames=2000 alloc_windows=[112,112,112] delta_prime=112 delta_calib=0 retried=false attempt=1 pool_size=32 created=32
scenario=jump_fixed_seed seed=12345 visible_avg=30.9555 fetched_per_frame_avg=30.9555 cmds_avg=61.911 batches_avg=1.0 quads_avg=247.644 alloc_bytes=144 frame_cpu_p50_us=101 frame_cpu_p95_us=175 frame_cpu_p99_us=192 frames=2000 alloc_windows=[96,128,144] delta_prime=112 delta_calib=0 retried=false attempt=1 pool_size=32 created=32
GL_SCROLL_WINDOW=not_done reason=optional_not_implemented_in_task70
BENCH_SCROLL_EXIT=0
```

### 判据与机制性证据（结论）
- **A/B 判据**：两场景 `alloc_bytes` 112/144，`alloc_windows=[112,112,112]/[96,128,144]`，`delta_work < N(1000)` 且 `<=256`，`retried=false`；`frame_cpu_p50_us` 102/101µs ≪ 1775µs×1.5。**严格字面 `alloc_windows=[0,0,0]` 未达成**。
- **定性（二选一）**：机制性不可清零（至严格 `[0,0,0]`）+ 证据。HB/FT 每帧重整形由 shaped-run 缓存命中消除（`build_text_cached`），应用层 per-frame 结构性分配已清零；残余为 Boehm `GC.stats.bytes_since_gc` 在 `GC.disable` 下间歇簿记噪声（~16B 簇，非每帧）。
- **1000 帧 delta 序列探针（同文本同 size，31 行/帧，预热后 cache hit）**：`PROBE73 frames=1000 total_delta=128 nonzero_frames=8 nz_min=16 nz_max=16 calls_est=31000 bytes_per_call_est=0.004129032258064516`；`first60=[0,0,0,0,0,0,0,0,0,0,16,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]`；`nz_indices_first40=[10,92,226,375,532,645,722,891]`；`nz_values_first40=[16,16,16,16,16,16,16,16]`；`shaped_run_cache_size=1 run_in_frame=false`。非每帧分配（~每百余帧一次 16B 事件），与 HB buffer 增长无正比；HB/FT 重整形在命中路径未调用。临时探针已删除。

### 提交信息（M2-iter6 / task-73）
- 提交 1（feat）：9159f35ce0d329a194e182f37dc2448c51ad9a86（`feat(m2): Emoji 样例与字体回退、shaped-run 缓存清除真实帧分配（C1/C6 证据）`）
- 提交 2（docs）：581439349b42a879231fde05d6c665af51f3339f（`docs: M2 门禁终审与 M3 后端预研入库`）
- 提交 3（docs 回填）：见本迭代收口提交 `docs: 回填 M2 迭代 6 提交 hash`
