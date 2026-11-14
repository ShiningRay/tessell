# Tessell 使用说明（M4 app_demo）

> 本文是 Windows + msys2 ucrt64 的 `app_demo` 专项说明；三平台支持级别、SDL2 宿主与待验证项见 [cross-platform-plan.md](cross-platform-plan.md)。

## 前置条件
- Crystal 1.22（Windows，msys2 ucrt64 工具链）。
- 构建/运行前设置 PATH：`$env:PATH="C:\msys64\ucrt64\bin;$env:PATH"`
- 运行时 DLL：见 `docs/evidence/M4-WP2-packaging.md`（16 个 DLL；裸 PATH
  可能退出 `-1073741515`）。
- 字体：路径硬编码为 `C:/Windows/Fonts/msyh.ttc`，该文件必须存在。

## 构建与运行（最小示例）
在仓库根目录执行：

```powershell
$env:PATH="C:\msys64\ucrt64\bin;$env:PATH"
crystal build examples/app_demo.cr -o bin/app_demo.exe
bin/app_demo.exe --frames=120 --verify
```

或：`crystal run examples/app_demo.cr -- --frames=120 --verify`

参数（`examples/app_demo.cr`）：
- `--frames=N` 默认 120
- `--verify` 运行检查并输出 token 行，通过 EXIT 0 / 失败 EXIT 1
- `--theme=light|dark` 默认 light
- `--dpi=1.0|1.25|1.5|2.0` 默认 1.0

交互：`Wheel` 滚动列表；`T` 切换主题（整窗重绘）；`Esc` 退出；
文本输入追加到聚焦的顶部输入框；`Tab` 切换焦点；`Backspace` 删除。

## UI DSL 与帧流程
`paint` 参数语义：**变更探测 token**（状态变化时改变它触发 Paint 失效），
不是颜色；应用从外部状态派生（如对内容做 hash）。

### 自动布局（issue #5）
显式 bounds 之外，DSL 支持把子树交给核心两遍内核求解（布局与命中树
同源，Router/HitTest 直接读同一棵树）：

```crystal
UI.build(UiKey.root, builder) do |x|
  x.vstack(key10, Tessell::Insets.all(10.0_f32), gap: 8.0_f32) do |y|
    y.auto_text(key1, "标题", 20.0_f32)   # 宽高按注入 Measurer 测量
    y.node(key2, Rect.new(0, 0, 120, 40)) # 显式 bounds 按 Fixed 参与
  end
end
UI.apply(buf, node, pool)
UI.apply_auto_layout(buf, pool, viewport, measurer)  # 求解并写回 bounds
```

- `vstack`/`hstack`（padding/gap）、`auto_text`（测量定尺寸）、
  `auto_node`（Auto 容器）；容器按内容收缩（Auto 语义）。
- 内核 `Layout::LayoutNode` 新增 `gap`：主轴子项间距，计入 intrinsic
  与 Fraction 余量分配。
- 顺序：先 `UI.apply` 再 `UI.apply_auto_layout`；稳态回写为 0（零改动）。
- 命中测试无需另建命中树：`UI.apply_auto_layout` 写回的就是 Node.bounds。
每帧：`UI.build -> UI.apply(decls, root, pool) -> Node.collect_dirty
-> UI.consume`。

- `UI.build(root, b) { ... }` 产出 `Decl`（key、parent、kind、text、
  bounds、paint）。同一逻辑节点的 `UiKey` 必须**跨帧稳定**，以便
  `apply` 从 `Pool` 匹配并复用节点。
- `UI.apply(decls, root, pool)` 协调声明：创建/复用节点、更新属性与
  bounds，并**标记脏**（create/change/layout/paint）。
- `Node.collect_dirty(root, sink)` 遍历并收集脏节点/区域。
- `UI.consume(nodes)` 在渲染后**清除脏标记**。分工：`apply` 标脏，
  `consume` 清脏；下一帧仅包含新产生的脏。

脏集语义：脏是节点级失效状态。渲染提交整窗或合并后的脏区；无脏时跳过
绘制但仍 `SwapBuffers`。

## 虚拟列表
示例使用 `Widgets::VirtualList`：10000 行，`row_h` 20，列表视口 800×600。
- `scroll_by/scroll_to` 钳制偏移；`prepare_visible` 更新可见窗口。
- `visible_first/last`、`node_offset(i)`、`pool_size` 驱动行渲染。
- 滚动由 `Router` 的 `Wheel` 事件驱动。本示例约定 y 符号决定方向：
  +1 向上滚动 `row_h`，-1 向下滚动 `row_h`。
- 标签在初始化时一次性预生成；热路径仅按索引取字符串。

## 主题与 DPI
- `--theme=light|dark` 启动时选择 `Render::Theme.light/dark`。
- 运行中按 `T` 切换主题（强制整窗重绘并重新组合）。
- `--dpi=1.0|1.25|1.5|2.0`：`Render::Dpi.scale_for(dpi*96)` 得 scale；
  `Dpi.size_px(16.0, scale)` 计算字号并参与布局尺寸。
- 语义 token（issue #8）：基础六元 bg/fg/accent/muted/border/selection 之外，
  扩展 panel/panel_alt/card/grid/divider、up/down/up_soft/down_soft（预设
  A 股口径：涨红跌绿，可整体替换）、hover/focus_ring、warning/danger/
  success、faint。行情/面板类应用直接用这些 token，不再自建平行 Palette；
  Kit 侧经 `ctx.render_theme` 读取（组件语义仍走 Kit Palette）。
  6 参 `Theme.new` 会从基础六元推导扩展 token（既有调用点兼容），质量
  要求高时用 light/dark 预设或全参构造。

## 零分配口径与陷阱
稳态探针：3 个窗口，每窗 N=1000 帧，`GC.enable` 置于 ensure，最多 1 次重试；
始终打印 `ALLOC_ATTEMPT1` 行。
判据：A `delta_work < 1000`、B `delta_work <= 256`（取 3 窗最大值）。
**不是**严格 0；本机 16–96B 噪声可落任意窗。
`retried=false attempt=1` 为理想情况；判据允许 1 次重试通过。

陷阱：探针前预热 shaped run 并 sync atlas；热路径避免新建 `String`/`Array`/
proc 捕获；复用缓冲与 sink；避免热循环内字符串插值。

## 离屏测试（issue #10）
`Render::SoftwareBackend`：纯 CPU 光栅到内存 RGBA 缓冲，无窗口/GPU/FFI，
CI 可跑。与 GLBackend 同契约（draw_draw_list/draw_text/draw_polygon、
per-command clip、premultiplied 混合、dirty 逐矩形清屏+重画）。

```crystal
backend = Tessell::Render::SoftwareBackend.new
backend.init(160, 120)
backend.attach_atlas(atlas)          # 文本采样需要页数据
backend.begin_frame(nil, theme)
backend.draw_draw_list(canvas.list)
backend.draw_text(renderer.vertices, renderer.batch_runs, renderer.batch_count)
backend.end_frame
backend.pixel(50, 12)                # 0xRRGGBBAA 断言
```

- 命中测试照常走 Router/HitTest（同一棵 retained 树）。
- 「脏区重绘 == 全量重绘」可在纯 spec 内断言（spec/software_backend_spec.cr
  的 oracle 用例：多边形跨脏区 + 脏区外文本，inside==full、outside==bg）。
- 边界：nearest 采样；draw_draw_list 的形状命令不受脏矩形裁剪（与 GL
  行为一致）；文本/多边形受 dirty 裁剪。

## 截图与 golden-image 回归（issue #9）
- 截图三格式：`--screenshot=x.png` 直出 PNG（stored zlib，标准解码器可读）；
  其他扩展名为 P6 PPM；`TessellShot.save`（tools/lib/shot.cr）输出 TSRAW
  （top-down RGBA，`m3_*` 探针使用）。
- 转换：`bin/golden --convert in.tsraw out.png`（也支持 .ppm）。
- golden 比较：`bin/golden baseline current --diff out.png --max-diff N`；
  退出码 0=pass / 1=fail / 2=用法错误；输出 diff_pixels / max_channel_diff
  与差异标红、其余压暗的 diff 图。支持 .png/.tsraw/.ppm 互比。
- CI smoke 示例：
  ```sh
  crystal build examples/app_calculator.cr -o bin/app_calculator
  ./bin/app_calculator --frames=2 --screenshot=shot.png
  crystal build tools/golden.cr -o bin/golden
  ./bin/golden baseline.png shot.png --max-diff 0
  ```
- PNG 读取端仅支持本工具写出的 stored-zlib 格式；读到压缩 PNG 时明确报
  错提示用本工具重生成（不假装支持任意 PNG）。

## 动态文本与 atlas 同步契约
`GlyphAtlas` 会把新字形插进**既有页**，所以 `page_count` / `used_pixels` /
`evicted_total` 只是观测计数，**不是**内容变化信号；只比较 `page_count` 的
同步在动态文本（改字号、改内容、主题切换换字）下必然运行期缺字。
正确写法（issue #1）：

- 用 `atlas.revision`（任何像素变化都递增）判断「是否需要同步」；
- `GLBackend#sync_atlas_dirty(atlas)` 每帧调用是廉价的：按
  `page_revision` / `rgba_page_revision` 只重传内容变化的页（新页
  `glTexImage2D` 首传，已有页 `glTexSubImage2D`）；
- `GLBackend#sync_atlas(atlas)` 保留为全量上传，仅用于首帧或显式重建。

```crystal
# 每帧：无变化时是纯整数比较，有变化时只上传脏页
backend.sync_atlas_dirty(atlas)
```

## verify 检查（app_demo --verify）
token 行包含：`frames/visible_avg/quads_dirty/quads_full/culled/diff_pixels/
diff_A_vs_C/alloc_windows/retried/attempt/verify`（及主题/DPI 字段）。
1. 滚动：脏区渲染与同状态整窗渲染像素一致，`diff_pixels==0` 且
   `diff_A_vs_C>0`。
2. 主题：切换后与该主题直接整窗渲染一致 `diff_theme==0`；切回与基线整窗
   渲染一致 `diff_theme_roundtrip==0`。
3. 分配：探针满足 A/B/重试口径，token 报告结果。

## Kit 组件库（K0–K4）

核心入口 `require "tessell"` 不加载组件；组件必须显式：

```crystal
require "tessell/kit"
```

最小消费者流程：

```crystal
input = Tessell::Kit::Input.new(
  Tessell::UI::UiKey.root.child(1_u64), "", "Type here", "Name"
)
root = Tessell::Kit::Root.new(input)
root.layout(320.0_f32, 160.0_f32)
root.build
root.handle(Tessell::Input::Event.key_down(Tessell::Input::KeyCode::Tab))
root.handle(Tessell::Input::Event.text_input("hi"))
```

- 组件文档：[kit/index.md](kit/index.md)。
- 无窗口验证：`crystal run examples/kit_gallery.cr -- --verify --frames=30`。
- 外部消费者验证：`bash tools/kit_consumer_verify.sh`（临时目录 + Shards path 依赖）。
- 限制：真实窗口/GL、平台 IME、屏幕阅读器 provider、平台剪贴板未验证。

## 字体栈与系统字体发现（issue #7）
- `Tessell::Text::FontStack.open([{path, ttc_index, weight, label}, ...])`：
  按优先级打开多张 face（regular/bold/fallback），`pick(text)` 用真实
  cmap 覆盖（`FtMeasurer#covers?`）选出覆盖整段文本的第一张脸，未覆盖
  返回 nil 由应用回退。
- 共享一个 `GlyphAtlas`，每张 face 一个 `Rasterizer`/`TextRenderer`
  （font_id 区分）；批按页合批，绘制按 #15 契约按序提交。
- `Tessell::Text::SystemFonts.find(["msyh", "pingfang", ...])`：标准目录
  扫描 + 文件名模式匹配，替代硬编码绝对路径；候选仍需 `covers?` 验证。
- Fallback 边界：选脸粒度是整段文本而非逐字形；逐字形混排（emoji+中文）
  需应用按段拆分分别 pick。语义化 family 匹配（sfnt name 表）留待后续。

## 文本 API（issue #6）
- 测量：`ctx.measure_text(text, size[, max_width])` 返回**逻辑**尺寸并内建
  缓存（key=(text,size,max_width)，文本集合变化时 `ctx.clear_text_cache`）；
  底层建议注入 `CoreTextMetrics.new(CachingMeasurer.new(ft))` 与渲染同走
  shaped-run 路径。
- 字体度量：`ctx.text_metrics(size)` 返回逻辑单位 ascent/descent/
  line_height；垂直居中用 `(rect.h - (ascent+descent))/2 + ascent`，不要
  再用 `0.36 * size` 之类的经验系数。
- 矩形内对齐：`Tessell::Kit::TextDrawing.draw_in_rect(ctx, p, rect, text,
  color, size, halign, valign)`，HAlign left/center/right、VAlign
  top/middle/bottom。
- 多段异色/异字号文本：按顺序多次 `p.text(...)` 即可（issue #15 契约：
  调用顺序即绘制顺序，同 clip 内自动合批）。

## 常见错误
- `-1073741515`（0xC0000135）：缺少运行时 DLL。将 msys2 ucrt64 bin 加入
  PATH，或按 M4-WP2-packaging.md 将所需 DLL 放到 exe 同目录。
- 字体找不到：期望 `C:/Windows/Fonts/msyh.ttc`（路径硬编码）；请安装字体
  或在示例中调整路径。
- `unexpected token "@["`：源码含 UTF-8 BOM；请另存为不带 BOM 的 UTF-8
  （Crystal 源文件不得包含 BOM）。

## 写示例常撞的 Crystal 编译错误（issue #18，均在 1.21.1 实测）
1. **带类型注解的 ivar 用 `self` 参与初始化不被认作初始化**：

   ```crystal
   class Sheet
     @evaluator : Evaluator   # 显式注解时必踩

     def initialize
       @evaluator = Evaluator.new(self)  # Error: doesn't explicitly initialize '@evaluator'
     end
   end
   ```

   编译器无法证明含 `self` 的调用顺序安全。workaround：去掉类级注解靠
   推断，或 `@evaluator = uninitialized Evaluator` 后立刻赋值（注明原因）；
   更好的解法是让 Evaluator 不持有所有者——`Evaluator.new` +
   `evaluate(sheet)` 传参。
2. **`extend` 不能作参数名**：`def select_cell(row : Int32, extend : Bool)`
   直接语法错误（`extend` 是关键字），改 `extending` / `extend_selection`。
3. **`Int32#to_char` 不存在**：用 `chr`（越界抛异常）或 `unsafe_chr`
   （热路径/已验证范围）。IDE 补全常误导出 `to_char`。
4. **`<=>` 的结果可能是 `Int32?`**：内建 `Int32#<=>`/`String#<=>` 返回
   非空 `Int32`；但走 `Comparable` mixin 或自定义可比较 union（如单元格
   值 `Number | String`）时 `<=>` 理论上可返回 nil，直接赋给 `Int32` 报错。
   写 `(a <=> b) || 0` 显式兜底。
5. **`Rasterizer` 只收 `FtMeasurer`（分工契约，不是 bug）**：Rasterizer
   直接驱动 FT/HB 句柄（face/buffer/upem），需要原始 `FtMeasurer`；
   布局测量用 `CachingMeasurer.new(ft_measurer)` 包装同一个实例。宿主
   不要把 `CachingMeasurer` 传给 `Rasterizer`——两个对象共享一个
   `FtMeasurer` 是既定用法：

   ```crystal
   ft = Tessell::Text::FtMeasurer.open(font_path)
   rasterizer = Tessell::Text::Rasterizer.new(ft, atlas, 0)
   caching = Tessell::Text::CachingMeasurer.new(ft)   # 布局/测量用
   ```

## 已知 API 缺口（示例层，未改 src）
- `Input::KeyCode` 无 `KeyT`：运行中 `T` 切换主题通过列表聚焦时的
  `Event.text_input("T"/"t")` 处理（顶部输入框聚焦时 `T` 作为字符追加）。
- `Event.wheel(x,y)` 无 delta 字段：示例按 y 符号约定滚动方向
  （+1 向上 `row_h`，-1 向下）。
