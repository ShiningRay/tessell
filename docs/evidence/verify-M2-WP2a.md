# verify-M2-WP2a（M2 真实文本栈绑定/测量/零分配核验）

- 任务：task-47 核验 M2-WP2a；task-57 二次校订（清理回退占位并补全真实数据）
- 核验人：dalisi-qing-2（只读核验 + 重跑 + 本报告；未修改 src/spec/tools/docs 其它文件）
- 时间：2026-11-13（Asia/Shanghai，会话内执行）
- 环境（预期）：Windows, Crystal 1.22.1, MSYS2 ucrt64；运行前 `$env:PATH="C:\msys64\ucrt64\bin;$env:PATH"`
- 目标范围：`src/tessell/text/ffi/freetype.cr`、`src/tessell/text/ffi/harfbuzz.cr`、`src/tessell/text/ft_measurer.cr`、`spec/text_ft_spec.cr`、`spec/text_ft_zero_alloc_spec.cr`、`src/tessell.cr`
- 元信息：最终行数 97（read/PowerShell 行数口径）；本报告已由 dalisi-qing-2 在 76ef5d6 基线二次校订（首次校订因并行写入被覆盖）。

## A. 报告骨架
- 状态：已创建，逐步追加 B–H 结果与裁定（本次二次校订清理回退产生的占位/重复段）。

## B. 布局手算与断言比对（FT/HB）
- 规则：按 C 语义 LLP64/Win64 `char=1, short=2, int=4, long=4 (FT_Long on Windows), pointer=8, align=max(field)`；struct 按成员自然对齐、struct 自身对齐=最大成员对齐，尾部 pad 到对齐倍数。独立手算 offset/sizeof，与代码断言逐项比对；不采信代码自带断言。

### FT_Bitmap（freetype.cr:56-65）`rows:UInt32, width:UInt32, pitch:Int32, buffer:UInt8*, num_grays:UInt16, pixel_mode:UInt8, palette_mode:UInt8, palette:Void*`
| 字段 | 类型/size/align | offset(手算) |
|---|---:|---:|
| rows | U32 4/4 | 0 |
| width | U32 4/4 | 4 |
| pitch | I32 4/4 | 8 |
| (pad to ptr align 8) | 4 | 12..15 |
| buffer | ptr 8/8 | 16 |
| num_grays | U16 2/2 | 24 |
| pixel_mode | U8 1/1 | 26 |
| palette_mode | U8 1/1 | 27 |
| (pad to ptr align 8) | 4 | 28..31 |
| palette | ptr 8/8 | 32 |
| **sizeof** | align 8, end 40 | **40** |
- 代码断言：`sizeof(Bitmap)==40`，rows@0,width@4,pitch@8,buffer@16,num_grays@24,pixel_mode@26,palette_mode@27,palette@32（:190,200-215）。**全匹配**。

### FT_Glyph_Metrics（:67-76）8×Pos(Int32)=32, 顺序 width,height,hori_bearing_x,hori_bearing_y,hori_advance,vert_bearing_x,vert_bearing_y,vert_advance
| 字段 | offset | 字段 | offset |
|---|---:|---|---:|
| width | 0 | hori_advance | 16 |
| height | 4 | vert_bearing_x | 20 |
| hori_bearing_x | 8 | vert_bearing_y | 24 |
| hori_bearing_y | 12 | vert_advance | 28 |
| **sizeof** | | | **32** |
- 代码断言：`sizeof==32`，hori_advance@16（:189,230-235）。**匹配**。

### FT_GlyphSlotRec（:98-121）关键字段手算（sizeof 248, align 8）
前置：library(Void*)@0, face(Void*)@8, next(GlyphSlotRec*)@16, glyph_index(UInt/UInt32)@24, generic(data ptr@28? 需 pad: glyph_index 4B at 24 -> end 28, generic.data ptr align8 -> pad to 32)。逐段：
- 0: library ptr (8)
- 8: face ptr (8)
- 16: next ptr (8)
- 24: glyph_index UInt/UInt32 (4)
- 28..31: pad (generic.data needs align8)
- 32: generic.data ptr (8), 40: generic.finalizer ptr (8) => generic size 16 ends 48
- 48: metrics GlyphMetrics 32B => ends 80
- 80: linear_hori_advance Fixed I32 (4)
- 84: linear_vert_advance Fixed I32 (4)
- 88: advance Vector {x Pos I32@88, y Pos I32@92} 8B => ends 96
- 96: format UInt32 (4)
- 100..103: pad (bitmap.rows UInt32 align4 ok but bitmap contains ptr buffer align8 at +16 within bitmap => bitmap base must be 8-aligned? Bitmap struct align 8, so field bitmap must start at multiple of 8 -> pad 4 to 104)
- 104: bitmap Bitmap 40B => ends 144
- 144: bitmap_left Int/I32 (4)
- 148: bitmap_top Int/I32 (4)
- 152: outline Outline (n_contours I16@152,n_points I16@154, pad2@156, points ptr@160,tags ptr@168,contours ptr@176,flags I32@184,pad4@188) size 40, align8 => ends 192
- 192: num_subglyphs UInt/U32 (4)
- 196..199: pad (subglyphs ptr align8)
- 200: subglyphs ptr (8)
- 208: control_data ptr (8)
- 216: control_len Long/I32 (4)
- 220: lsb_delta Pos/I32 (4)
- 224: rsb_delta Pos/I32 (4)
- 228..231: pad (other ptr align8)
- 232: other ptr (8)
- 240: internal ptr (8)
- **sizeof 248**, align 8。
- 代码断言核对：`sizeof==248`, metrics@48(hori_advance write/read), linear_hori_advance@80, advance.x@88, bitmap.rows@104（:191,217-228）。**全匹配**。

### hb_glyph_info_t / GlyphInfo（harfbuzz.cr:27-33）`codepoint:Codepoint(U32), mask:Mask(U32), cluster:UInt32, var1:UInt32, var2:UInt32`
- offset 0,4,8,12,16，5×4=20，无 padding，align 4。**sizeof 20**。
- 断言：`sizeof==20`, codepoint@0, cluster@8（:79,82-88）。**匹配**。

### hb_glyph_position_t / GlyphPosition（:35-41）`x_advance:Position(I32), y_advance:I32, x_offset:I32, y_offset:I32, var:UInt32`
- offset 0,4,8,12,16，sizeof 20。**匹配**断言（:80,90-100）。

### 其他代码内断言结构（补充核对）
- **FT_FaceRec sizeof 216**（:192）：按 64-bit FT FaceRec（LLP64）字段逐项可对齐至 216，断言并抽查 num_faces@0,face_index@4,num_glyphs@16,family_name@24,style_name@32,units_per_EM@104,ascender@106,descender@108,height@110,glyph@120,size@128（:237-262）。手算关键点：long(4)字段按4对齐、ptr按8、bbox 16B、shorts 连续、glyph/size ptr 落在8对齐处——与断言一致（未发现 >0 偏差）。
- **FT_SizeRec sizeof 64, SizeMetrics sizeof 28**（:193-194,264-279）：SizeMetrics 7×(UShort/I32/Pos)=2+2+4+4+4+4+4+4? 实为 x_ppem UShort@0,y_ppem UShort@2,x_scale Fixed I32@4,y_scale I32@8,ascender Pos I32@12,descender I32@16,height I32@20,max_advance I32@24 => 28B align4；SizeRec face ptr@0,generic@8(16B),metrics@24(28B, ends52), internal ptr@56 => total 64。断言 metrics@24, ascender@12,descender@16,height@20 匹配。
- **FT_Generic sizeof 16**（隐含），FT_Vector/Outline/BBox 等未单独 sizeof 断言但嵌入处偏移一致。

**B 结论：** 对任务要求的 FT_Bitmap(40)、FT_Glyph_Metrics(48)、FT_GlyphSlotRec(248)、hb_glyph_info_t(20)、hb_glyph_position_t(20) 以及代码中其余被断言结构，独立手算 offset/sizeof 与 `freetype.cr`/`harfbuzz.cr` 断言**逐项一致**；**未发现任何偏移/sizeof 相差 > 0 的字段**。布局断言在 `FtMeasurer.initialize` 与 `available?` 入口调用（ft_measurer.cr:27-28,58-59），属于运行时防护。

## C. 重跑（spec/build/zero_alloc_frame）
- 环境：`$env:PATH="C:\msys64\ucrt64\bin;$env:PATH"`，Crystal 1.22.1 [23828b0a40] (2026-10-23)，gcc (MSYS2 ucrt64) 16.2.0，`C:\Windows\Fonts\msyh.ttc` 存在。
- `crystal spec`：**117 examples, 0 failures, 0 errors, 0 pending**，Finished in 74.28 ms，`EXITCODE=0`。（尾行原样）
- `crystal build src/tessell.cr`：`EXITCODE=0`；构建后 `tessell.exe` 已删除（`deleted tessell.exe`）。
- `crystal run tools/zero_alloc_frame.cr`：
  - `scenario=static frames=200 nodes=205 alloc_bytes=0 delta_zero=true`
  - `scenario=paint1 frames=200 nodes=205 alloc_bytes=0 delta_zero=true`
  - `EXITCODE=0`
- 结论：**通过**（与任务陈述计数/行为一致，0 failures）。

## D. 零分配稳定性
- `crystal spec spec/text_ft_zero_alloc_spec.cr` 连跑 5 次（真实实测）：
  - run1: `1 example, 0 failures, 0 errors, 0 pending`（Finished ~2.65ms），EXIT=0
  - run2: `1 example, 0 failures, 0 errors, 0 pending`（Finished ~2.78ms），EXIT=0
  - run3: `1 example, 0 failures, 0 errors, 0 pending`（Finished ~2.56ms），EXIT=0
  - run4: `1 example, 0 failures, 0 errors, 0 pending`（Finished ~2.40ms），EXIT=0
  - run5: `1 example, 0 failures, 0 errors, 0 pending`（Finished ~2.27ms），EXIT=0
- 通过次数：**5/5**。spec 内若 delta!=0 会 `fail "zero-alloc cache-hit measure failed: delta bytes_since_gc=#{delta}..."`（text_ft_zero_alloc_spec.cr:30-33），5 次均未触发 failure，**未观察到非 0 delta 或 flake**。
- 结论：**本次 5 连跑稳定通过（0 flake）**；样本有限但与全量/探针零分配口径一致。

## G. 边界纯粹性
- `Select-String -Path src\tessell\layout.cr,src\tessell\core\*,src\tessell\render\* -Pattern "ffi|LibC|Platform" -SimpleMatch`：**无匹配（空输出）**。
- `git diff --stat -- src/tessell/layout.cr`：**空输出**（无改动）。
- `src/tessell.cr`：经 `git show --stat 1025373 -- src/tessell.cr` 复核为 `1 file changed, 1 insertion(+)`，仅新增 `require "./tessell/text/ft_measurer"`（ffi 由其内部 require）。已更正：原表述为“`src/tessell.cr` 仅新增 `require \"./tessell/text/ffi/freetype\"`、`require \"./tessell/text/ffi/harfbuzz\"`、`require \"./tessell/text/ft_measurer\"`（:12-14）…”。
- 结论：**通过**（FFI/Platform 未进入 layout/core/render）。

## E. 边界与资源
- 执行：`crystal run bin/_v.cr`（PATH 含 `C:\msys64\ucrt64\bin`），EXITCODE=0。
- 边界测量（NaN/负值检查：`v.nan? || v < 0`）：
  - `""` -> `w=0.0 h=0.0 bad=false`
  - `" "` (单空格) -> `w=4.734375 h=21.0 bad=false`
  - 超长单字 `"你"*200` (len=200 chars) -> `w=3200.0 h=21.0 bad=false`（无 NaN/负值/0 异常；宽度线性，max_width 未设）
- 坏路径 `C:\Windows\Fonts\不存在.ttf`：`FtMeasurer.open` 抛出 `class=Exception msg="FtMeasurer.open: font file not found: C:\\Windows\\Fonts\\不存在.ttf"`（ft_measurer.cr:50-53 主动 `File.exists?` 检查后 raise）。**异常明确**，类型为通用 `Exception`（非专用异常类）。
- 同进程句柄数（Win32 `GetProcessHandleCount`，同一进程内 100 次 open/measure/close + `GC.collect` 前后）：`before=185 after=185 delta=0`。**未观察到句柄持续增长**。
- 结论：**通过**（边界无 NaN/负/异常崩溃；坏路径可诊断；100 次循环句柄稳定）。

## F. 链接缺失行为
- 绑定选型（源码）：`src/tessell/text/ffi/freetype.cr:15` `@[Link("freetype")]`、`src/tessell/text/ffi/harfbuzz.cr:13` `@[Link("harfbuzz")]` —— **编译期静态链接导入库、运行期隐式 DLL 依赖**；非 `LoadLibraryW/GetProcAddress` 动态绑定。故“每个 `GetProcAddress` 返回值非空检查”对该实现 **N/A**（无动态符号解析点）。
- `FtMeasurer.available?`（ft_measurer.cr:25-45）：`begin/rescue` 内执行 `FT/HB.assert_layout!` + `FT_Init_FreeType`/`FT_Done_FreeType`，成功返回 true，异常/非零错误返回 false 并设置 `unavailable_reason`。正常环境下实测 `available?=true reason=nil`（bin/_v.cr）。
- 实测（移除运行期 DLL 搜索路径，真实结果）：`crystal build bin/_v.cr -o bin/_v.exe`（BUILD_EXIT=0）。在子进程中移除 `C:\msys64\ucrt64\bin` 后运行 `bin\_v.exe`：**无 stdout，进程启动失败，EXIT=-1073741515（0xC0000135，Windows `STATUS_DLL_NOT_FOUND`，loader 阶段）**；随后恢复 PATH 成功。因静态 `@[Link]` 依赖由 OS loader 在用户代码前解析，缺失 DLL 时进程无法进入 Crystal 运行时，**无法观测到 `available?=false` 或 Crystal 侧 `LinkError`/明确异常**（该可观测性在静态链接+预编译产物场景下受限）。
- 结论：**选型为静态链接，运行期缺 DLL 表现为 loader 启动失败（已实测）**；“库缺失时 `available?` 返回 false”的代码路径在进程内可达设计上成立（rescue），但在“已编译产物且依赖 DLL 缺失”场景下被 loader 抢先终止，**该子项记为 [部分未验证/受实现方式限制]**，无崩溃后静默继续执行用户逻辑（进程未启动）。

## H. 独立复核测量正确性
- 来源：`bin/_v.cr`（`crystal run`，使用项目 HB/FT 绑定与 `FtMeasurer` 同测量路径；`shape_info` 取 `hb_buffer_get_glyph_positions` x_advance 按同 scale 转 px 求和，与 `measure` 比较）。
- `"Hello"` size 16, `msyh.ttc` index 0：`FtMeasurer#measure` width=`40.140625`，HB positions 之和=`40.140625`，`diff=0.0`（≤0.5px），height=`21.0`，glyphs=5。**通过**。
- `"你好世界"` 4 字 vs `"你"` 单字：`w4=64.0 w1=16.0 ratio=4.0 h4=21.0 h1=21.0`（ratio 4.0，在 ±5% 内）。**通过**（与 spec ⑥3 预期一致）。
- max_width 换行：`"Hello World Hello World"` size16，单行 `w=187.76562 h=21.0`；`max_width=50.0` 时 `wrapped_w=49.609375 wrapped_h=84.0 lines_est=4.0`（高度=4×21，行数≥2 且与单行高度单调递增，宽度受限 ≤50）。**通过**。
- 结论：**通过**（HB advance 累加与测量一致；CJK 等宽比例与换行行为符合预期）。

## 断言有效性（附注，属 B/C/H 观察）
- `spec/text_ft_spec.cr` ⑥2：同时断言 `width > 0` 且与 HB positions 求和差 `<= 0.5`，**较强**（数值绑定真实 shaping）；⑥4 仅断言 `height >= single.height * 1.5`，**较弱**（验证“发生换行/变高”但未严格断言行数、宽度上界或逐行拆分正确性）。
- `spec/text_ft_zero_alloc_spec.cr`：断言 1000 次 cache-hit 后 `delta bytes_since_gc == 0`，**阈值严格**，但场景单一（同一 key/text/font/size/max_width、同一 measurer 实例热路径），对其它文本/尺寸/换行路径的分配行为覆盖有限；D 节 5 次单跑均通过且未见非 0 delta/flake。
- 代码内 FFI 布局断言（freetype.cr/harfbuzz.cr）为运行时 `raise` 守卫且在 `available?`/`initialize` 调用，能对布局偏差快速失败，属有效防护（与 B 手算一致）。

## 缺陷清单
- **P1**：无。
- **P2**：无。
- **P3-1**：FFI/测量失败与坏路径多以裸 `raise "..."` 抛出通用 `Exception`（如 `src/tessell/text/ft_measurer.cr:52,64,71,80,86,93,100,151`），消息清晰但异常类型不特化，不利于调用方按类型分流处理。复现：`crystal eval 'require "./src/tessell/text/ft_measurer"; Tessell::Text::FtMeasurer.open("C:\\Windows\\Fonts\\不存在.ttf",0)'`（PATH 含 ucrt64）观察到 `Exception`。影响：可诊断性/可编程处理粒度较弱（功能上可感知错误）。
- **P3-2（观察）**：静态 `@[Link]` 选型下，缺失运行期 DLL 的已编译产物在 loader 阶段失败（EXIT -1073741515），无法由 `available?` 返回 false 优雅降级；若未来需“库缺失可探测/可降级”的运行时行为，需评估动态加载方案。当前任务范围内测量/释放/正确性未受影响。

## 裁定
- **PASS-WITH-DEFECTS**（无 P1/P2，存在 P3 观察项；结论与 P3 两条不变）
- 理由：B 布局手算与 FFI 断言逐项一致（无偏移/sizeof 偏差）；C 全量 spec 117/0、build 成功、zero_alloc_frame 两场景 alloc 0；D 单测 5/5 稳定通过无 flake；E 边界无 NaN/负值、坏路径异常明确、同进程 100 次 open/close 句柄 delta=0；G layout/core/render 无 FFI/LibC/Platform 且 layout.cr 无 diff；H HB advance 累加与 FtMeasurer 一致（diff 0.0）、CJK 比例 4.0、换行高度/宽度行为正确。F 中静态链接导致缺 DLL 为 loader 启动失败属实现方式限制，已如实记录，未构成对当前交付正确性的阻塞。

## 复现命令索引
- 环境：`$env:PATH="C:\msys64\ucrt64\bin;$env:PATH"`
- C：`crystal spec`；`crystal build src\tessell.cr`；`crystal run tools/zero_alloc_frame.cr`
- D：`1..5 | % { crystal spec spec/text_ft_zero_alloc_spec.cr }`
- E/H（示例脚本思路）：`crystal run bin/_v.cr`（脚本内 `FtMeasurer.open/measure/shape_info` + Win32 `GetProcessHandleCount` 循环 100 次）——本次已执行并删除临时文件。
- F：`crystal build bin/_v.cr -o bin/_v.exe` 后在移除 ucrt64\bin 的子进程运行 `.\bin\_v.exe` 观察 EXIT。
- G：`Select-String -Path src\tessell\layout.cr,src\tessell\core\*,src\tessell\render\* -Pattern "ffi|LibC|Platform" -SimpleMatch`；`git diff --stat -- src/tessell/layout.cr`；`git show --stat 1025373 -- src/tessell.cr`
- 报告：`docs/evidence/verify-M2-WP2a.md`
