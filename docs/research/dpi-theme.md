# M3-WP5 设计草案：DPI 缩放与主题 token

- 任务：task-99（M3-WP5；纯文档，只看不写码、不 commit）
- 产出：本文件 docs/research/dpi-theme.md（唯一写入范围）
- 时间：2026-11-13（Asia/Shanghai）；HEAD=c364223
- 纪律：每条事实给 path:line；[未验证] 真实并附「验证所需」
- 格式：一条一行 bullet；每行 ≤90 字符；每节含【结论】【依据】【遗留缺口】
- 红线：不写 src/、spec/、tools/、examples/；不改证据；不 commit

## 1. DPI 感知 API 选型（Windows）
- 【结论】推荐 SetProcessDpiAwarenessContext(PER_MONITOR_AWARE_V2)
- 【结论】V2 支持每监视器 DPI 变化通知与自动缩放，V1 仅系统级
- 【结论】SetProcessDPIAware 为 legacy，Windows 10 1607+ 已弃用语义
- 【结论】清单方式（app.manifest dpiAwareness）仅启动时生效，无法运行时切换
- 【依据】m3-backends.md:112 grep Dpi|dpi|DPI ⇒ No matches found（2026-11-13）
- 【依据】m0_window_probe.cr:1-60 无 DPI API 调用（负结果，grep 已证）
- 【依据】Windows API 文档：PER_MONITOR_AWARE_V2 = -4（DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2）
- 【依据】GetDpiForWindow(hwnd) 返回 UINT（96/120/144/192 → 1.0/1.25/1.5/2.0）
- 【依据】GetDpiForMonitor(hmonitor, MDT_EFFECTIVE_DPI, *dpiX, *dpiY) via Shcore
- 【未验证】以上 API 在 ucrt64 Crystal FFI 中的调用可行性 [未验证]
- 验证需要：最小 Crystal FFI 探针调用 GetDpiForWindow 并打印返回值
- 【未验证】PER_MONITOR_AWARE_V2 在 Windows 10 1703+ 可用，更早版本 fallback [未验证]
- 验证需要：Windows 版本矩阵测试（本机 Windows 11，最低支持版本未测）
- FFI 草案（Crystal lib 形式，@[Link] 归属）：
-   @[Link("user32")] lib LibUser32Dpi
-     fun SetProcessDpiAwarenessContext(value : Void*) : Int32
-     fun GetDpiForWindow(hwnd : Void*) : UInt32
-   end
-   @[Link("shcore")] lib LibShcoreDpi
-     fun GetDpiForMonitor(hmonitor : Void*, dpi_type : Int32, dpi_x : UInt32*, dpi_y : UInt32*) : Int32
-   end
- 【遗留缺口】FFI 签名未编译验证（[未验证]）；验证需要：crystal build 探针
- 【遗留缺口】WM_DPICHANGED 消息处理未实现 [未验证]；验证需要：窗口 resize DPI 切换实测

## 2. 缩放策略（逻辑单位 vs 设备像素）
- 【结论】布局与命中测试用逻辑单位（logical px），光栅化用设备像素
- 【结论】size_px = round(point_size × dpi_scale) 参与 GlyphKey，UV/四边形用逻辑坐标 × scale
- 【结论】atlas key 的 size_px 必须参与 key，否则跨 DPI 复用会模糊
- 【依据】glyph_atlas.cr:8-13 GlyphKey(font_id, glyph_id, size_px, subpixel, flags)
- 【依据】glyph_atlas.cr:16-18 initialize 计算 key_hash 含 size_px
- 【依据】text_renderer.cr:116-119 build_text 接收 size_px 参数
- 【依据】text_renderer.cr:142-145 left=pen_x+offset_x, top=pen_y-offset_y（逻辑坐标）
- 【依据】gl_backend.cr:158 glOrtho(0,w,h,0,-1,1) 用视口像素尺寸
- 预期 advance 变化（同一 "Hello 你好" 16pt）：
-   DPI 1.0 (96): size_px=16, advance≈N logical px
-   DPI 1.25 (120): size_px=20, advance≈1.25×N logical px
-   DPI 1.5 (144): size_px=24, advance≈1.5×N logical px
-   DPI 2.0 (192): size_px=32, advance≈2.0×N logical px
- 【依据】rasterizer.cr:88-126 rasterize_into 用 size_px 光栅化
- 【依据】GlyphKey.size_px 参与 hash ⇒ 跨 DPI 自动隔离（不整表作废）
- 实测 text_advance：DPI 1.0=71.554688、1.5=107.332031、2.0=143.109375（来源 examples/m3_dpi_theme.cr --verify，2026-11-13）
- 【遗留缺口】subpixel bucket 在高 DPI 下的取值策略 [未验证]；验证需要：探针

## 3. WM_DPICHANGED 与 resize 语义
- 【结论】DPI 变化时：物理尺寸不变、逻辑尺寸 = 物理 / scale；触发全量重绘
- 【结论】atlas 不整表作废：按 font_id+size_px 分键自然隔离
- 【结论】Backend#resize(width,height) 传入物理像素（与 glViewport 一致）
- 【依据】gl_backend.cr:133-137 resize 设置 viewport_w/h + glViewport(0,0,w,h)
- 【依据】gl_backend.cr:146-177 begin_frame 用 viewport_w/h 做 glOrtho
- 【依据】backend.cr:23 resize(width,height) 抽象签名
- 【依据】m3-backends.md:115 glOrtho 用物理像素，未乘设备像素比
- 【遗留缺口】WM_DPICHANGED 处理路径未实现 [未验证]；验证需要：窗口拖到另一显示器
- 【遗留缺口】DPI 变化时 atlas 是否需 invalidate [未验证]；验证需要：多显示器实测

## 4. 主题 token
- 【结论】最小集合：bg/fg/accent/muted/border/selection，每项 UInt32 RGBA
- 【结论】struct Theme 为值类型，Theme.light/Theme.dark 常量，禁止 draw 路径分配
- 【结论】落点 = Backend#begin_frame(dirty, theme?) 或 GlBackend 构造注入
- 【依据】gl_backend.cr:107-110 @bg_r/g/b/a 字段；:139-144 set_clear_color
- 【依据】gl_backend.cr:154 glClearColor(@bg_r,@bg_g,@bg_b,@bg_a)
- 【依据】gl_backend.cr:165 glColor4f(0,0,0,1) 黑字硬编码
- 【依据】text_renderer.cr:119 rgba 默认 0xffffffff_u32（白字）
- 【依据】m3-backends.md:111 无主题 token；落点=begin_frame 参数化
- 【依据】m3-backends.md:116 bg 默认白、黑字硬编码
- struct Theme
-   getter bg : UInt32
-   getter fg : UInt32
-   getter accent : UInt32
-   getter muted : UInt32
-   getter border : UInt32
-   getter selection : UInt32
-   def initialize(@bg, @fg, @accent, @muted, @border, @selection)
-   end
- end
- Theme.light = Theme.new(0xffffffff_u32, 0x000000ff_u32, ...)
- Theme.dark = Theme.new(0x1e1e1eff_u32, 0xe0e0e0ff_u32, ...)
- 【遗留缺口】Theme 结构未编译验证 [未验证]；验证需要：crystal build 探针
- 【遗留缺口】主题切换是否需 atlas 重光栅化 [未验证]；验证需要：切换主题 readback 比对
- 【遗留缺口】暗色模式下 GL_ALPHA 纹理与背景混合效果 [未验证]；验证需要：实机 readback

## 5. 可测判据（J1–J5）
- J1 DPI=1.0/1.5/2.0 下 text_pixels_nonbg 严格单调增加；r15=px(1.5)/px(1.0) in [1.5,3.5]、r20=px(2.0)/px(1.0) in [2.5,5.0]；实测 r15=1.918380、r20=3.173832（落区间内，来源 examples/m3_dpi_theme.cr --verify，2026-11-13）
-   如何观测：m2_text_window.cr --dpi=X --verify 输出 text_pixels_nonbg
-   阈值来源：面积按 scale^2 增长（1.5^2=2.25、2^2=4.0）；像素计数受边缘覆盖率与 GL_LINEAR 采样影响有偏，故给宽区间；实测值必须回填本文档
-   已知风险：GL_LINEAR 采样+边缘混合使 readback 计数非线性（verify-M2-WP2d.md §4）
- J2 同一文本跨 DPI 的 glyph 缓存不串页
-   如何观测：atlas.page_count 与 dpi 切换次数一致增长；lookup(key) 不命中旧页
-   阈值来源：GlyphKey.size_px 参与 hash（glyph_atlas.cr:8-13）⇒ 自然隔离
-   已知风险：subpixel bucket 在高 DPI 下取值策略未定 [未验证]
- J3 主题切换后 readback 背景像素 == token 值（逐字节）
-   如何观测：m2_text_window.cr --theme=dark --verify 读回左上角像素 == Theme.dark.bg
-   阈值来源：GL 清屏色 = theme.bg，readback 直接比对
-   已知风险：GL 清屏精度（8bit）与 UInt32 token 的 alpha 通道 [未验证]
- J4 主题/DPI 切换稳态零分配
-   如何观测：判据 A delta_work<N(1000)、B delta_work<=256；retry-once 合法
-   阈值来源：M2-WP2c-zero-alloc-criterion.md §1-§7
-   已知风险：Boehm 16B 噪声窗；重试后仍失败必 fail
- J5 --dpi 与 --theme 组合不做视觉回归
-   如何观测：截图像素差异仅在预期区域（文本+背景）；其他区域 diff==0
-   阈值来源：dirty rect 提交语义（gl_backend.cr:264-332）
-   已知风险：GL scissor 与 DPI 坐标换算一致性 [未验证]
-   验证需要：多组合截图 diff 工具

## 6. 风险清单（≥6，每条附缓解）
- R1 每显示器 DPI 不可在单显示器机器上真测
-   缓解：用 --dpi 模拟参数 + GetDpiForWindow 单点验证
- R2 进程级 DPI 感知一旦设置不可撤销
-   缓解：启动时设一次，不运行时切换；测试用子进程
- R3 逻辑/设备混用导致 1px 抖动
-   缓解：统一约定：布局逻辑 px，光栅化设备 px，glOrtho 用设备 px
- R4 主题与 Atlas 背景假设耦合
-   缓解：Atlas R8 单通道与背景无关；主题只影响 clear color 和 text color
- R5 glOrtho 用物理或逻辑像素需与 scissor 换算一致
-   缓解：gl_backend.cr:274-280 已做 y-down→GL scissor 换算；DPI scale 统一乘
- R6 高 DPI 下图集容量翻倍（size_px 翻倍 ⇒ 每 glyph 占 4× 像素）
-   缓解：page_size 可配置；capacity 自动扩容；LRU 淘汰
- R7 WM_DPICHANGED 不可编程触发
-   缓解：用 --dpi 参数模拟；真实 DPI 切换靠拖窗验证
- R8 主题切换需重建所有纹理？（Atlas R8 与主题无关，不应重建）
-   缓解：Theme 只影响 clear color 和 text color，不触 atlas

## 7. 不改码声明
- 本文件仅设计草案与判据，不改 src/、spec/、tools/、examples/
- 所有 [未验证] 均真实并附「验证所需」
- [推断] 标注设计判断，非实测

## 8. 证据锚点
- m3-backends.md:110-123 DPI/主题节（grep 零命中、无 token）
- gl_backend.cr:133-137 resize；:146-177 begin_frame；:158 glOrtho；:107-110 bg 字段
- text_renderer.cr:116-119 build_text size_px；:142-145 quad 坐标
- glyph_atlas.cr:8-13 GlyphKey 含 size_px
- rasterizer.cr:88-126 rasterize_into 用 size_px
- M2-WP2c-zero-alloc-criterion.md:4-7 判据定义
- verify-M2-WP2d.md §4 ratio 多口径证据
- m0_window_probe.cr:1-60 无 DPI 调用（负结果）

## 9. 边界
- 本文件纯设计草案；不写 src/spec/tools/examples；不改证据；不 commit
- [未验证] 均真实且附验证需要；[推断] 标注设计判断；判据全可测

