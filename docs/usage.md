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

## 零分配口径与陷阱
稳态探针：3 个窗口，每窗 N=1000 帧，`GC.enable` 置于 ensure，最多 1 次重试；
始终打印 `ALLOC_ATTEMPT1` 行。
判据：A `delta_work < 1000`、B `delta_work <= 256`（取 3 窗最大值）。
**不是**严格 0；本机 16–96B 噪声可落任意窗。
`retried=false attempt=1` 为理想情况；判据允许 1 次重试通过。

陷阱：探针前预热 shaped run 并 sync atlas；热路径避免新建 `String`/`Array`/
proc 捕获；复用缓冲与 sink；避免热循环内字符串插值。

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
