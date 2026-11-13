# M2-WP2「文本上屏」GL 渲染器设计预研（R8 图集上屏 / 批处理 / 验收口径）

- 产出：docs/research/gl-text-renderer.md（task-62，翰林院编修 hanlin-bianxiu，仅写本文件）
- 时间：2026-11-13 09:55 +08:00；HEAD=fdb797c11e7c52bb73a8b68d1f22d883b1f2b464
- 边界：未写 src/spec，未改 docs/plan*.md、roadmap.md、plan-execution.md，未 commit，未动他人文件
- 口径：事实标 `文件:行` 或命令输出；[未验证]=未实测；[推断]=推演；GL 符号均引自既有声明

## 0) 现状（已落地事实，含更正）

- CPU 顶点/批次层已落地：src/tessell/render/text_renderer.cr（196 行）
- API：TextRenderer#build_text(...) :100-161；TextBatch(start,count,texture) :36-43
- API：reserve_quads :82-87、reserve_batches :88-93、stats{quads,batches} :77-79
- Vertex(x,y,u,v:Float32,rgba:UInt32) 20B/vertex :24-33；write_batch/write_vertex 原位复用 :163-193
- :9 注释：NDC 转换不在此层完成；GL 后端按视口做正交/立即模式映射
- GL 提交层已落地：src/tessell/render/gl/gl_renderer.cr（211 行）
- API：sync_atlas_textures :119-150；begin_frame :153-170；draw_text :173-194；delete_textures :202-207
- 示例探针：examples/m2_text_window.cr（398 行）已串成可运行上屏链路
- 实测（--verify，verify-M2-WP2d.md:57）：quads=14 batches=1 pen_end_x=300.96875
- 实测像素：text_pixels_nonbg=2801 cpu_coverage_sum=2638 ratio=1.0618 pixel_match=true
- 实测帧时（gongbu 通报口径，verify :96）：frame_p50/p95/p99 = 1.85/10.95/12.88ms
- 独立重跑帧时 2.17/5.35/5.84ms 属环境波动；像素/计数/比例/通过性一致（verify :96）
- 上屏链路实测：gl_path=GL1.1_compat R8->GL_ALPHA glPixelStorei(GL_UNPACK_ALIGNMENT,1)（verify :58）
- 更正：lead 通报「153/193 行」与实测不符；实读 text_renderer.cr=196、gl_renderer.cr=211 行
- 历史诚实：09:10 grep src/ 尚无 GL 提交代码；上述落地为 gongbu 并行提交，本节按实读更正
- 本节只陈述已读源码事实；GL 细节推断一律标 [未验证]，不冒充实测

## 1) R8 图集 → GL 纹理：三路比较与推荐

- 路径 a：GL_RED + 片元 shader `color=vec4(c,c,c,tex.r)`（GL 3.3 core，需 shader+VAO/VBO）
- 路径 b：GL_LUMINANCE/GL_ALPHA（GL 2.1 immediate；core profile 已移除，驱动兼容风险 [未验证]）
- 路径 c：GL 1.1 固定管线（GL_ALPHA + glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA)）
- 推荐：M2 走 c（已落地）；前瞻 a。理由引 gl_renderer.cr:1-7 原文（无 shader/FFI 面最小）
- 路径 a FFI（[未验证] 按 OpenGL 3.3 core 惯例列举，本仓库无 shader 先例）：
- glCreateShader(type:UInt32):UInt32；glShaderSource(sh:UInt32,count:Int32,src:UInt8**,len:Int32*):Void
- glCompileShader(sh:UInt32):Void；glCreateProgram():UInt32；glAttachShader(prog,sh:UInt32):Void
- glLinkProgram(prog:UInt32):Void；glUseProgram(prog:UInt32):Void
- glGenVertexArrays(n:Int32,arr:UInt32*):Void；glGenBuffers(n:Int32,buf:UInt32*):Void
- glBindBuffer(target:UInt32,buf:UInt32):Void
- glBufferData(target:UInt32,size:Int32,data:Void*,usage:UInt32):Void
- glEnableVertexAttribArray(idx:UInt32):Void
- glVertexAttribPointer(idx,size:Int32,type:UInt32,norm:UInt8,stride:Int32,ptr:Void*):Void
- glGetUniformLocation(prog:UInt32,name:UInt8*):Int32；glUniform1i(loc:Int32,v:Int32):Void
- 路径 b FFI：同 c 的上传符号，internalformat/format 改 GL_LUMINANCE [未验证]（无先例）
- 路径 c FFI：gl_renderer.cr:67-99 已声明（本次实测 grep 逐行核准）：
- glViewport/glClearColor/glClear/glFlush/glFinish/glGetError :67-72
- glEnable/glDisable/glBlendFunc/glColor4f :74-77；glMatrixMode/glLoadIdentity/glOrtho :79-81
- glGenTextures/glBindTexture/glDeleteTextures :83-85
- glTexImage2D :86、glTexSubImage2D :89（已声明但 sync 未用，见 §2）、glTexParameteri/glPixelStorei :91-92
- glBegin/glEnd/glTexCoord2f/glVertex2f :94-97；glReadPixels :99
- m0_window_probe.cr 可复用：glViewport/glClearColor/glClear/glBegin/glEnd :131-137
- 可复用：glColor3f/glVertex2f :136-137、glFlush/glGetString/glReadPixels/glGetError :138-141
- 可复用：WGL :115-120、gdi32 :110-112；差异：glColor3f 无 alpha，文本需 glColor4f（gl_renderer :77）

## 2) 上传策略

- 实际：sync_atlas_textures 整页 glTexImage2D 每帧重传（gl_renderer.cr:119-150，verify :68）
- 优化建议：稳态改逐槽 glTexSubImage2D 部分上传（符号已声明 :89，仅接线未用 [推断]）
- GL_UNPACK_ALIGNMENT=1 必设（R8 行宽非 4 对齐）；每次上传前显式设置（gl_renderer.cr:137，verify :67）
- pitch≠width 时用 GL_UNPACK_ROW_LENGTH=page_size（常量声明待核 [未验证]）
- 最小正确序列（帧内新建槽 → 本帧上传）：
- ① insert 落槽（glyph_atlas.cr:183-206）→ ② page_data 拷贝位图（rasterizer.cr:170-198）
- ③ bind 纹理 → ④ glPixelStorei(UNPACK_ALIGNMENT,1) → ⑤ 上传（整页或逐槽）→ ⑥ draw
- 页扩容：acquire_page 新页 + 新纹理 id（gl_renderer.cr:129-148 遍历 page_count，verify :68）
- 淘汰/释放：delete_textures 全量 glDeleteTextures + clear（gl_renderer.cr:202-207，verify :72）
- 帧内不淘汰为契约（glyph_atlas.cr:227-238 raise；verify-M2-WP2b）

## 3) 四边形 / UV / NDC / 亚像素 / 混合

- pen+offset → 屏幕矩形（CPU 已实现，text_renderer.cr:142-145）：
- left=pen_x+offset_x；top=pen_y-offset_y；right=left+w；bottom=top+h（y-down）
- NDC：x_ndc=2*x/w-1、y_ndc=1-2*y/h；实际由 glOrtho(0,w,h,0,-1,1) 等价实现（gl_renderer.cr:162）
- 方向实测支持（核验员已验，verify-M2-WP2d.md:69-71）：glOrtho 与 CPU top=pen_y-offset_y 同向
- "gy" CPU：above=18 below=8（off_y=18 top=82 bottom=108，有下伸）
- "AV" CPU：above=25 below=0（off_y=25 top=75 bottom=100，全在基线上）
- "gy" 屏幕回读：above=714 below=225（总 939；verify 原文 above_baseline/below_or_on）
- "AV" 屏幕回读：above=960 below=0（总 960，同上口径）
- 结论：AV 基线下方为 0、gy 基线下方显著 >0，与 CPU extents 同向，未见 y 翻转（verify :71）
- UV：placement_from_slot 由 slot_rect/page_size 推导（rasterizer.cr:200-212）；uv∈[0,1]（spec :49-53）
- 亚像素：subpixel bucket 进 GlyphKey（glyph_atlas.cr:8-67）；两条实现路径 [推断]：
- 路径 1：bucket 只进 key，不改 advance/UV（与 m2 现状一致）
- 路径 2：bucket 改 pen 起点（x+bucket/64），UV 不变；两者对 UV/advance 影响等价 [未验证]
- 混合：glEnable(GL_BLEND)+glBlendFunc(GL_SRC_ALPHA,GL_ONE_MINUS_SRC_ALPHA)（gl_renderer.cr:168）
- 顺序：不透明/半透明混排按 pen 顺序绘制；同批按页分组（text_renderer.cr:129-138）

## 4) 批处理（对齐 DrawList.build_batches 语义）

- 实际：draw_text 以 glBegin(GL_QUADS)/glEnd 立即模式逐批绘制（gl_renderer.cr:173-194）
- 批键：同页 texture id 一致（text_renderer.cr:129-138；spec :66-72 单页单批、:76-104 跨页多批）
- 顶点格式：Vertex(x,y,u,v:Float32,rgba:UInt32) 20B/vertex（text_renderer.cr:24-33）
- rgba 当前固定 0xffffffff，字段保留（text_renderer.cr:100-161 默认参数）
- 稳态零分配：@vertices/@batches 原位写 + vertex_count/batch_count 截断（:105-106,164-192）
- 每帧顶点数上限：4× drawable glyphs；reserve_quads 仅不足时扩容（:82-93）
- 升级路径：VBO+IBO+glDrawElements（与 spec :18 vertex_count==drawable*4 兼容）[推断]
- m0_window_probe.cr 无 VAO/VBO 声明；升级需新增 FFI（GL 1.1 路不需要）

## 5) Emoji / 彩色路径

- GL_ALPHA 单通道 ⇒ 当前仅灰度 emoji；seguiemj.ttf 含 COLR+CPAL（font-fallback.md §2 [未验证]）
- 彩色路径：RGBA8 第二图集 + 独立纹理单元/shader 分派（atlas_kind 或批内切绑）[未验证]
- M2 范围裁剪：只做 R8 + 灰度 emoji；彩色列 [未验证]/排期（与 glyph-atlas.md §1 一致）
- Noto Color Emoji 本机不存在（font-fallback.md §2），获取与许可见该文档 §6

## 6) 验收口径（可测、可复现）

- a) 屏幕读回：m2_text_window.cr 判据 ratio∈[0.5,1.5]（:6,:369）、non-bg=RGB|Δ|>8（:361-363）
- cpu_coverage_sum=渲染字形矩形内非零 R8 atlas 字节计数（verify :59）
- ratio 实测 1.0618；多阈值复算 1.06~1.45，GL_LINEAR/混合/光栅差异致偏高（verify :60-63）
- ⇒ ratio 仅证「可观文本像素且量级匹配」，不能单独证逐字形精确一致（verify :63）
- 严格逐像素 ±2 须 NEAREST 采样 + 无混合 premul 差异 [推断]
- b) 帧时间：--frames=N 分布 p50/p95/p99（percentile 实现 m2_text_window.cr:195-201）
- 实测 p50/p95/p99=1.85/10.95/12.88ms（gongbu 通报，verify :96）；重跑 2.17/5.35/5.84ms（环境波动）
- 量级参考：M0-WP5m 基线 p50=14.6µs 属布局/绘制 CPU 侧；GL 提交另计（M0-WP5m-metrics.md）
- c) 零分配：沿用 M2-WP2c 判据（现行 B=256，M2-WP2c-zero-alloc-criterion.md:5-6）：
- A 硬门 delta_work < N（N=1000）；B 噪声上限 delta_work <= 256；delta_work=max(3 work 窗) :4
- GC.enable 在 ensure；prime/calib 仅诊断不参与断言（criterion :4,:15-16）
- B=256 由 max(128, 4×实测最大窗 64B) 裁断（:6）；build_text 20 窗实测 max=64B（:11-12）
- 历史：rasterize_into 20 窗 +16B 间歇噪声（:19），故严格 ==0 不可判定
- 失败必打印 delta_work/delta_calib/delta_prime/N/windows（:7）
- 缓解：3 窗失败时整套三窗重试最多 1 次（:38；verify :140-145 重试合法未放水）
- d) 文本正确性：屏幕像素 vs CPU 光栅图集区域逐像素比对，允许 ±2 灰度（m0_window_probe.cr:357-364）

## 7) 风险与未决（≥6，均标 [未验证] 或实测锚点）

- R1 Intel 驱动/GL 版本差异：本机 GL 4.6（m0_window_probe.cr），他机未测 [未验证]
- R2 FFI struct 布局（Vertex 20B）跨平台对齐差异 [未验证]（text_renderer.cr:24-33）
- R3 sRGB/线性空间未处理，混合与读回可能偏色 [未验证]
- R4 DPI 96 vs 144：NDC 与图集无关，但字号/笔刷缩放未测 [未验证]
- R5 窗口 resize：glOrtho 每帧重建（gl_renderer.cr:162），图集页不变；resize 路径未压测 [未验证]
- R6 Windows 无交互桌面：WGL 依赖，降级路径未实现 [未验证]
- R7 GL 1.1 immediate 逐顶点 FFI 调用开销，万行级批成本 [未验证]
- R8 subpixel 64 bucket 使槽位数×64，页扩容/淘汰压力放大 [未验证]
- R9 整页每帧重传 O(page²) vs 逐槽 O(Σw·h)：大页高 DPI 下带宽浪费 [未验证]
- R10 GL_CLAMP_TO_EDGE vs GL_CLAMP 语义差异（gl_renderer.cr:141-142）[未验证]
- R11 实测：判据 B=256 可被 1536B 级 GC 簿记尖峰击穿 → 保守方向误报 flake（criterion :14-16,:37）
- R11b 缓解：整套三窗重试 1 次已落地（criterion :38；verify :140-145）；单次 >256B 仍可误报 :39
- R12 实测盲区：≤256B 稀疏分配被放过（1 次/1000→32B、5 次/1000→160B，PASSED_BLIND）
- R12b 出处：criterion :31-34（bin/_negctl.cr 对抗实验）、verify :33-36,:108
- R12c 含义：判据只能证明「无 per-call 分配」，不能证明绝对零分配（criterion :30-34）

## 8) 3 个不依赖 GL 的 CPU 侧可单测不变量

- I1 placement 矩形面积 == 槽位 w×h：text_renderer.cr:144-145 用 p.w/p.h；spec :106-135 ±0.001
- I2 同一批内 texture id 同质：text_renderer.cr:129-138 换页即 flush；spec :66-72 单页单批
- I3 uv∈[0,1]：uv 由 slot_rect/page_size 推导（rasterizer.cr:200-212）；spec :49-53 逐顶点断言
- 守护：帧内淘汰必 raise（glyph_atlas.cr:227-238）⇒ I1-I3 前置条件成立（verify-M2-WP2b）

## 9) 与「GL 1.1 固定管线」的两项对照结论

- 轴 1 FFI 面：固定管线只需 m0_window_probe.cr 已声明子集 + gl_renderer.cr:67-99；shader 路全新
- 轴 2 稳态成本：固定管线逐顶点 FFI 调用；shader 路一次 draw 调用但需 VAO/VBO 维护 [推断]
- 实测佐证：上屏链路 ratio=1.0618 pixel_match=true（verify :57），GL 1.1 路功能可达

## 10) 证据锚点

- examples/m0_window_probe.cr:110-142（WGL/gdi32/LibGL 声明）、:357-364（±2 像素比对）
- src/tessell/render/text_renderer.cr:24-43,:77-79,:82-93,:100-193（Vertex/TextBatch/构建/复用）
- src/tessell/render/gl/gl_renderer.cr:1-7,:67-99,:119-150,:153-170,:173-194,:202-207
- src/tessell/text/glyph_atlas.cr:8-67,:158-168,:183-206,:208-214,:227-238
- src/tessell/text/rasterizer.cr:14-32,:58-75,:85-123,:170-198,:200-212
- docs/evidence/verify-M2-WP2d.md:57-72（实测/方向/GL 路径）、:24-25,:33-36,:107-108（判据强度）
- docs/evidence/M2-WP2c-zero-alloc-criterion.md:4-7（A/B 判据）、:11-16（分布）、:31-34（盲区）、:37-39（残余）
- docs/evidence/M0-WP3-window.md:73（GL 4.6 Intel Iris Xe pixel_match=true）、:80（±2）
- docs/evidence/M0-WP5m-metrics.md（帧时间分布口径与基线）
- tools/zero_alloc_frame.cr:72-147（measure_scenario 协议）、docs/evidence/M1-WP5-zero-alloc.md（协议出处）
- docs/research/glyph-atlas.md（帧内不淘汰/键设计）、docs/research/font-fallback.md（COLR/CPAL）

## 11) 结论摘要（8 条，对应任务书 8 节）

1. 三路比较：GL_RED+shader 前瞻推荐；GL_LUMINANCE 仅兼容回退；GL 1.1 固定管线为 M2 落地
2. 上传：实际整页每帧重传；稳态应逐槽 glTexSubImage2D（符号已声明 :89，仅接线未用）
3. 四边形/UV：CPU 侧 y-down 矩形与 UV 就绪；NDC 由 glOrtho 等价；方向实测无翻转
4. 批处理：立即模式逐批 glBegin/glEnd；升级 VBO+IBO+glDrawElements 与 spec :18 兼容 [推断]
5. Emoji：GL_ALPHA 仅单色；COLR 彩色需 RGBA8 第二图集+shader，M2 裁剪灰度 emoji
6. 验收：ratio∈[0.5,1.5]+|ΔRGB|>8 落地冒烟口径；严格 ±2 逐像素须 NEAREST [推断]
7. 风险 ≥6：驱动/FFI 布局/sRGB/DPI/resize/headless/core 移除/subpixel/整页重传/判据强度
8. 不变量 3 条：placement==槽位、批内纹理同质、uv∈[0,1]（帧内淘汰必 raise 守护）

## 12) 补充观测（读源所得，未实测运行）

- m2 首建以空 page_texture_ids 调 build_text，tex=0 回退（text_renderer.cr:127）
- 页扩容后重 sync+build 两次（m2_text_window.cr:301-305）
- batch_runs 为逻辑视图（按 batch_count 截断，text_renderer.cr:71-75）；GL 路径只读前缀
- m2 percentile 实现 :195-201；frame_times << 每帧 push 属探针侧成本，非稳态热路径 [推断]

## 13) 边界

- 仅本文件；未写 src/spec，未改 plan/roadmap，未 commit；他人工作区文件未触碰
- lead 通报行数与实测不符处已在 §0 更正；判据 B=256 与方向实测已按 m01028 纳入 §6c/§3/§7
