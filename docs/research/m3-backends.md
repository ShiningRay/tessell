# M3 预研：后端抽象、脏矩形提交、stencil-cover、macOS/Linux 前置、DPI/主题
- 任务：task-74（M3 预研；纯文档，只看不写码、不 commit）
- 产出：本文件 docs/research/m3-backends.md（唯一写入范围）
- 时间：2026-11-13（Asia/Shanghai）；HEAD=7cfb44f（lead 指派时点）
- 纪律：每条事实给 path:line；[未验证] 真实并附「需要什么才能验证」
- 格式：一条一行 bullet；每行 ≤100 字符；每节含【结论】【依据】【遗留缺口】
- 红线：不写 src/、spec/、tools/、examples/；不改证据文件；不 commit

## 1) 后端抽象最小接口
- 【结论】7 方法（init/resize/begin_frame/sync_atlas/draw_text/end_frame/delete）基本够用
- 【结论】但 resize 未显式；scissor/stencil 无入口；atlas 句柄归属待定
- 【结论】DrawCmd→顶点/批 留 CPU（TextRenderer 已做）；backend 只收顶点/批
- 【结论】GPU 侧 atlas 句柄应收归 backend；page_texture_ids 外泄是历史兼容 [推断]
- 方法核对：initialize(@atlas) :112-115 存在，仅存 atlas 引用不持纹理
- 方法核对：resize 不存在；尺寸经 begin_frame(viewport_w,h) :153-154 传入
- 方法核对：begin_frame :153-170 存在（viewport/清屏/投影/混合/黑字）
- 方法核对：sync_atlas_textures :119-150 存在（gen+整页重传 :143-146）
- 方法核对：draw_text :173-194 存在（按批绑纹理+GL_QUADS :181-182）
- 方法核对：end_frame :196-200 存在（禁用 blend/tex+glFlush）
- 方法核对：delete_textures :202-207 存在（glDeleteTextures+clear ids）
- 【依据】page_texture_ids getter :107 暴露句柄给调用方（m2_text_window 首建 :241）
- 【依据】m2_text_window.cr:301-305 空 ids 再 sync 兜底 ⇒ 归属分裂
- 【依据】m2_text_window.cr:327-328 每帧 sync+build 两步全量走
- 【依据】text_renderer.cr:100-161 build_text 已在 CPU 完成 cmd→顶点/批
- 【依据】text_renderer.cr:24-33 Vertex(x,y,u,v,rgba:UInt32) 20B/vertex
- 【依据】text_renderer.cr:36-43 TextBatch(start,count,texture:Int32)
- 【依据】text_renderer.cr:82-93 reserve_quads/reserve_batches 不足才扩容
- 【依据】text_renderer.cr:9 注释：NDC 不在此层 ⇒ 投影属 backend
- 【依据】architecture.md:173 后端 trait 泛型、编译期选定、无虚分派
- 【依据】gl_renderer.cr:67-100 lib 清单无 glScissor/glStencil*/glAlphaFunc
- 【依据】draw_list.cr:89-118 build_batches 键=atlas_id&&clip（CPU 合批先例）
- 【遗留缺口】RHI 是否含 create_texture/destroy 须 M3-WP1 评审定 [未验证]
- 验证需要：M3-WP1 评审产出 trait 草案并过审（纪要入证据）

## 2) 脏矩形提交流程
- 【结论】merge_into 输出 ≤max_regions 条保守矩形，可直接映射 glScissor 序列
- 【结论】方案 A 整帧重绘 vs B 脏区 scissor 重绘；GL 无部分提交代价模型
- 【结论】换不换须实测建成本表；当前证据不足以判 B 优于 A [未验证]
- 验证需要：同机 A/B 对照（readback 全等 + 帧 CPU 计时）
- 【依据】dirty.cr:1-9 五条语义（重叠/接触并 bbox；空矩形丢弃；贪心非最优）
- 【依据】merge_into :30-88：sink.clear :31 + 三趟处理
- 【依据】pass1 写非空矩形 :33-39；pass2 相邻并 :42-59；pass3 贪心 :63-85
- 【依据】贪心代价 = 并集面积 − 面积和 :63-85；保证 ≤max_regions :1-9
- 【依据】merge :18-22 一次分配结果数组，非热路径（hot path 用 merge_into）
- 【依据】virtual_list.cr:411 dirty_rects(max_regions=8):NamedTuple(count,area)
- 【依据】virtual_list.cr:394-439 语义引 verify-M2-WP4.md:69：dy==0 空 :402-403
- 【依据】|dy|>=vh → 整窗 1 条 (0,0,w,vh) :405；小步 → 2 条带 :407-421
- 【依据】dy>0 带=(0,vh-d,w,d)+(0,0,w,d) :413-415；dy<0 对称 :417-419
- 【依据】两带再经 Render::Dirty.merge_into 汇入（verify-M2-WP4.md:69）
- 【依据】P2 实测：down10/up10 均 count=2，对侧带为过绘（verify-M2-WP4.md:104）
- 【依据】bench_scroll.cr:44-68 run_frame 全路径 CPU 帧计时
- 【依据】verify-M2-WP4.md:94 bench_scroll p50≈1765µs（frame_cpu 口径）
- 【依据】spec/virtual_list_spec.cr:133-214 判据 A/B + retry-once（verify:83）
- 【判据】等价性=仅重绘脏区 vs 整帧重绘 readback 逐像素 diff==0（当且仅当）
- 【判据】B 启用条件：dirty 面积占比<阈值 且 readback 全等 且 帧 CPU p95 不劣
- 【判据】阈值常量 [未验证]；验证需要：Iris Xe 上 scissor+clear+readback 对照
- 【依据】glClear 是否受 scissor 限制为 GL 语义，本驱动未实测 [未验证]
- 验证需要：对照实验加清屏分支，读回对比清屏区域像素
- 【遗留缺口】swap 仍整帧提交；「部分提交」省的是 CPU 重绘非带宽
- 【遗留缺口】glScissor 符号未声明 ⇒ M3-WP1 新增 FFI 行（gl_renderer lib 段）

## 3) stencil-cover 抗锯齿
- 【结论】stencil-cover 在 GL1.1 下可行（符号族属 core 旧规格 [未验证]）；PFD 已请 8bit
- 验证需要：实读 Khronos GL 1.1 spec 或 gl3.h 中 glStencilFunc/glStencilOp 条目
- 【结论】但 gl_renderer.cr 未声明/未启用任何 stencil 调用 ⇒ 可行未用
- 【结论】MSAA 需扩展路径（当前固定 PFD+ChoosePixelFormat）⇒ M3 选 stencil-cover [推断]
- 【结论】边缘膨胀 1px 落 backend clip/stencil 计算，不动 TextRenderer
- 【依据】m0_window_probe.cr:101 cStencilBits 字段；:285 pfd.cStencilBits=8
- 【依据】8bit 是否真分配到上下文 [未验证]；验证需要：wglDescribePixelFormat 实读
- 【依据】gl_renderer.cr:17-101 lib 无 glStencilFunc/glStencilOp/GL_STENCIL_BIT 常量
- 【依据】plan.md:256 M3-WP4 路径 stencil/cover 可选、不阻塞核心 UI
- 【依据】architecture.md:233 风险登记：GPU 路径渲染工作量过大→延后
- 【依据】原理（设计非实测）：几何写 stencil → 覆盖通道出 AA 边缘
- 【依据】text_renderer.cr:100-161 build_text 无 clip 参数 ⇒ 不感知裁剪
- 【依据】text_renderer.cr:142-145 quad 矩形=pen+offset±w/h（膨胀不改其几何）
- 【判据】落地：同文本同字体 stencil 路径 vs 全帧重绘 readback diff==0
- 【判据】落地：膨胀 1px 后边缘非背景像素变化率 ≤X%（X 待实测 [未验证]）
- 验证需要：m2_text_window.cr --verify 加 stencil 开关比对 ratio 与 diff
- 【判据】不落地：驱动无 stencil 或 diff≠0 ⇒ 回退全帧重绘+接受无 AA
- 【缺口】驱动 stencil 精度/慢路径未测 [未验证]；验证需要：glGet+readback 探针
- 【缺口】COLR/CPAL emoji 与 stencil 无关，彩色路径另路（gl-text-renderer.md §5）
- 【遗留缺口】MSAA 取舍缺本机数据：PFD 样本字段是否设置 [未验证]
- 验证需要：实读 m0_window_probe.cr PFD 初始化段核对 cSampleBuffers/cSampleCounts

## 4) 平台前置（macOS/Linux）
- 【结论】本机 Windows ⇒ macOS/Linux 一律 [未验证]；代码库仅 WGL 路径
- 【结论】M3 跑通需下列证据逐条补齐；缺一不可
- 【依据】grep `NSOpenGL|CGLContext|GLX|EGL|Metal` --include=*.cr ⇒ 0 命中（2026-11-13）
- 【依据】grep `wglCreateContext|ChoosePixelFormat` ⇒ 18 命中全在 3 个 example WGL 段
- 【依据】命中：m0_window_probe.cr:110,117,288-295；m0_ime_probe.cr:111,118,330-334
- 【依据】m2_text_window.cr:109,116,290-295；plan.md:254-255；architecture.md:217-220
- macOS 证据 1：macOS CI runner/物理机 + `crystal build` EXIT=0 [未验证]
- 验证需要：一台 macOS 机器/CI 作业 + Crystal 工具链（macOS）
- macOS 证据 2：NSOpenGLView/CGL 弃用状态读 Apple 文档确认 [未验证]
- 验证需要：Apple 开发者文档 NSOpenGLView 页面现行声明（实读截图/URL）
- macOS 证据 3：Metal 是否必须＝GL 上下文能否创建 [未验证]
- 验证需要：同机最小 GL 上下文创建探针（对标 m0_window_probe.cr:288-295）
- macOS 证据 4：一样例上屏 + pixel_match=true [未验证]
- 验证需要：m2_text_window 级样例在 macOS 跑 --verify 通过
- macOS 证据 5：输入/IME 事件映射（NSEvent→Input::Event） [未验证]
- 验证需要：事件映射表 + 键盘/IME 探针在 macOS 实跑
- Linux 证据 1：X11 GLX vs EGL 决策（wayland 无头 CI）[未验证]
- 验证需要：Linux CI 双后端各一次 crystal build + 运行记录
- Linux 证据 2：libGL 可链接性（@[Link("GL")] 或等效）[未验证]
- 验证需要：Linux 容器最小链接探针 + ldd 输出
- Linux 证据 3：无 GPU 降级（llvmpipe/swrast）可用 [未验证]
- 验证需要：无 GPU 容器跑通一样例 + 帧时间分布记录
- 【遗留缺口】无任何 macOS/Linux 实机 ⇒ 本节全为证据清单，无实测

## 5) DPI/主题
- 【结论】当前无 DPI 感知声明、无主题 token；颜色硬编码在 backend 层
- 【依据】grep `Dpi|dpi|DPI` --include=*.cr ⇒ No matches found（2026-11-13 实测）
- 【依据】m0 窗口探针未调用 SetProcessDpiAwareness（同上负结果）
- 【依据】grep `Theme|scale` ⇒ 仅字体 scale 命中（rasterizer.cr:113,120 等）
- 【依据】gl_renderer.cr:162 glOrtho(0,w,h,0,-1,1) 像素坐标未乘设备像素比
- 【依据】gl_renderer.cr:154 bg 默认白；:169 glColor4f(0,0,0,1) 黑字
- 【依据】text_renderer.cr:100-161 build_text rgba 参数默认 0xffffffff_u32
- 【结论】DPI 落点=SetProcessDpiAwareness + glOrtho 用 scaled 坐标 [推断]
- 【结论】主题落点=颜色 token 表 + begin_frame/draw_text 参数化 [推断]
- 【判据】144 DPI 下文本 bounds 缩放 1.5× 且 readback 分布与 96 DPI 同文本一致 [未验证]
- 验证需要：144 DPI 显示器实机 + 同文本两档 readback 比对
- 【遗留缺口】Windows 缩放设置、主题 token 表、三平台视觉一致证据均未建

## 6) 风险（≥6，每条一行）
- R1 仅 Iris Xe GL4.6 实测（M0-WP3-window.md:73），他驱动未测 [未验证]
- 验证需要：他驱动实机/CI 同一样例 readback 对照
- R2 GL1.1 固定管线在 core context 不可用（gl_renderer.cr:1-7 选 1.1 即为此）
- R3 脏区保守放大（dirty.cr:1-9）+ 对侧带过绘（verify-M2-WP4.md:104）
- R4 stencil 驱动慢路径/精度未测 [未验证]；验证需要：驱动 stencil 探针
- R5 判据 B=256 对 1536B GC 尖峰可误报；≤256B 稀疏盲区（criterion:24-25,31-34）
- R6 DPI 未声明 ⇒ 高 DPI 文本模糊/错位 [未验证]；验证需要：144 DPI 实机
- R7 无 GPU 降级路径未建 [未验证]；验证需要：无 GPU 容器样例记录
- R8 主题 token 缺失 ⇒ 三平台视觉一致无依据 [未验证]
- 验证需要：三平台同一样例 readback 比对
- R9 工期膨胀（plan.md:256 可选项；architecture.md:233 风险登记）

## 7) M3 可测判据（≥6，判据式）
- C1 同一样例在 GL 后端与 stub 后端 readback 逐像素 diff==0
- C2 dirty 面积占比<阈值 时：B 方案 readback 全等 且 帧 CPU p95 ≤ A 方案
- C3 任意 scroll_by(1) 后 dirty_rects count≤2 且 area 覆盖新露出区（同现行语义）
- C4 stencil-cover 开/关两路径同文本 readback diff==0（AA 关闭对照）
- C5 新路径零分配沿用 A/B：delta_work<N 且 delta_work<=256，retry-once 合法
- C6 144/96 DPI 同文本 readback 非背景像素数比值∈[0.5,1.5] 且 bounds×1.5 [未验证]
- 验证需要：144 DPI 实机两档 readback 计数比对
- C7 macOS/Linux CI：crystal build EXIT=0 且 --verify pixel_match=true [未验证]
- 验证需要：macOS/Linux CI 作业各一次完整运行记录
- C8 万行滚动帧时间 p99 不劣 M2-WP4 基线（bench_scroll；分布非平均 FPS plan.md:219）
- C9 C2/C6 的阈值常量须先测量后入文档（禁拍脑袋；先跑 A/B 与 DPI 实验）

## 8) 证据锚点（命令/文件原文）
- gl_renderer.cr 全文 211 行实读（lib :17-101；sync :119-150；begin :153-170；draw :173-194）
- dirty.cr 全文 110 行实读（语义 :1-9；merge_into :30-88；merge :18-22）
- virtual_list.cr:8,:411 grep 实读；:394-439 语义引 verify-M2-WP4.md:69
- text_renderer.cr 196 行（task-62 已读）：:24-33,:36-43,:82-93,:100-161,:142-145
- m0_window_probe.cr 385 行（task-62 已读）：:101,:285 stencil；:110,:117,:288-295 WGL
- m2_text_window.cr 398 行（task-62 已读）：:6,:369 ratio；:327-328 帧循环
- M2-WP2c-zero-alloc-criterion.md:4-7,:24-25,:31-34,:36-39 实读
- verify-M2-WP2d.md:57-63,:69-71,:106-111 实读（ratio 多口径/P1 时点竞态复核）
- verify-M2-WP4.md:13,:69,:83,:94,:104 实读
- M2-WP4-virtual-list.md:11,:13,:49-66,:73 实读
- plan.md:249-257（M3 表）；architecture.md:173,:200-209,:213-221,:227-236 实读
- grep 负结果：Dpi（0 命中）；NSOpenGL/CGL/GLX/EGL/Metal（0 命中）；stencil 符号 0 命中

## 9) 边界
- 本文件纯预研；不写 src/spec/tools/examples；不改证据；不 commit
- [未验证] 均真实且附验证需要；[推断] 标注设计判断；判据全可测
