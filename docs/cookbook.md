# Tessell Cookbook（issue #12）

面向「只看文档就能搭出带自绘面板、文本、输入、截图的窗口应用」。
所有代码来自当前 API（2026-11），验证方式见各节；读完后无需逐层读
`src/` 源码。API 细节见 `crystal docs` 生成的 API reference（生成方式见文末）。

## 1. 最小窗口应用

核心入口不加载 Kit；组件必须显式：

```crystal
require "tessell/kit"
```

最小消费者流程（无窗口，纯逻辑可测）：

```crystal
input = Tessell::Kit::Input.new(
  Tessell::UI::UiKey.root.child(1_u64), "", "Type here", "Name")
root = Tessell::Kit::Root.new(input)
root.layout(320.0_f32, 160.0_f32)
root.build
```

真实窗口：继承 `TessellKitSdl::KitDemoApp`（examples/lib/kit_sdl_host.cr）
获得 SDL2 窗口、输入分发、PNG 截图（`--screenshot=x.png`）与帧调试 overlay。
完整可运行示例：examples/app_calculator.cr（约 20 行业务代码）。

**窗口 resize / DPI 变化（issue #30）**：改窗口尺寸时对现有 Root 调
`root.layout(new_width, new_height)`；跨屏拖动/系统缩放改 DPI 时调
`root.scale = new_scale`（联动清文本测量缓存并重排）。两者都**不重建
Root**——组件树、焦点、编辑中状态全部保留；重建 Root 是最后的手段，
它会丢焦点与 TextEditing 内容。

## 2. 文本与字体

```crystal
# 度量（逻辑单位，内建缓存）
s = ctx.measure_text("120000", 14.0_f32)

# 字体度量：不要再用 0.36*size 猜 baseline
m = ctx.text_metrics(14.0_f32)   # ascent/descent/line_height

# 矩形内九宫格对齐
Tessell::Kit::TextDrawing.draw_in_rect(ctx, painter, rect, "标题",
  color, 14.0_f32, Tessell::Kit::HAlign::Center, Tessell::Kit::VAlign::Middle)
```

**测量缓存契约（issue #24）**：缓存键含文本内容，正确性不依赖任何人清空——
组件改内容自动产生新键，不需要调用方记得 `clear_text_cache`。容量有界
（两代淘汰，上限 `Context::MEASURE_CACHE_CAP = 4096` 条），表格/行情这类
高频换文本集合的应用只需在**整体数据快照替换后**调一次
`ctx.clear_text_cache`（内存卫生，非每帧）。观测面：
`ctx.text_cache_stats`（hits/misses/size）与 `ctx.text_cache_size`。
```

多段异色/异字号：按顺序多次 `painter.text(...)`（调用顺序即绘制顺序，
issue #15 契约）。多字体/粗体/fallback 用 `Text::FontStack` + 
`SystemFonts.find(["msyh", "pingfang"])`（issue #7）；多段文本共用一个
`GlyphAtlas`，每张 face 一个 `Rasterizer`/`TextRenderer`。

## 3. 矩形与折线（Canvas）

```crystal
canvas = Tessell::Render::Canvas.new
canvas.fill_rect(bounds, 0x2f6fedff_u32)          # 0xRRGGBBAA
canvas.stroke_rect(bounds, 0x000000ff_u32, 1.0_f32)
canvas.polyline(points, 0x000000ff_u32, 2.0_f32)  # 展开为逐段 Line
canvas.push_clip(viewport)                        # 嵌套取交集
canvas.pop_clip
backend.draw_draw_list(canvas.list)               # GLBackend 或 SoftwareBackend
```

DrawList 状态：**可用**。Kit 组件经 DrawListPainter 走同一命令层；
`draw_polygon` 保留为高层路径填充（stencil/cover）。无窗口像素断言用
`Render::SoftwareBackend`（见 §8）。

## 4. 自动布局（DSL 接两遍内核）

```crystal
UI.build(UiKey.root, builder) do |x|
  x.vstack(key10, Tessell::Insets.all(10.0_f32), gap: 8.0_f32) do |y|
    y.auto_text(key1, "标题", 20.0_f32)     # 按 Measurer 测量
    y.node(key2, Rect.new(0, 0, 120, 40))   # 显式 bounds 按 Fixed 参与
  end
end
UI.apply(buf, node, pool)
UI.apply_auto_layout(buf, pool, viewport, measurer)  # 写回 Node.bounds（命中树同源）
```

## 5. 主题 token

基础六元之外：panel/panel_alt/card/grid/divider、up/down/up_soft/down_soft
（预设 A 股口径涨红跌绿，可整体替换）、hover/focus_ring、warning/danger/
success、faint。Kit 组件语义走 Kit Palette；行情/网格类语义直接读
`ctx.render_theme.panel` 等。切主题只换 token：`root.theme = Theme.dark`。

## 6. 输入

- 修饰键：`event.modifiers.shift/ctrl/alt/meta`（Kit Event 同字段）。
- 滚轮：`event.wheel_dx / wheel_dy`（设备相关步长由宿主映射）。
- 时间语义：`event.timestamp_ms`（平台单调毫秒）、`event.repeat`（自动重复）。
- 点击语义：`router.last_click_count`（1/2）、`last_drag_distance`；
  双击参数 `double_click_window_ms` / `double_click_max_dist` 可配。
- Tab 导航：组件声明 `wants_tab?` 后 Root 先把 Tab 投递给焦点组件；
  `Ctrl/Meta+Tab` 恒定留给焦点环（键盘用户的出口，issue #16）。
- 键码：Tab/Enter/Escape/Space/方向/Home/End/PageUp/PageDown/Backspace/
  Delete/A/B/C/T/V/X/Z/Digit0-9/F1-F4。

## 7. 动态文本与 atlas 同步

动态文本会往**既有页**插字形：`page_count` 不是变化信号。唯一正确写法：

```crystal
backend.sync_atlas_dirty(atlas)   # 每帧调用；无变化时是纯整数比较
```

只比较 page_count 必然运行期缺字（issue #1）。全量 `sync_atlas` 仅用于首帧。

## 8. 截图与 CI 测试

**性能口径（issue #36）**：门禁看计数、优化看分布。CI 只跑计数断言
（measure 调用数/批数/事件路由次数/帧命令数，见 spec/kit/
counting_assertions_spec.cr 与 spec/layout_cached_spec.cr）与
zero_alloc 探针；`bench_frame_time`/`bench_scroll` 是人工定位工具，
其 wall-clock 分布不进门禁。

```sh
./bin/app_calculator --frames=2 --screenshot=shot.png   # 直出 PNG
./bin/golden baseline.png shot.png --max-diff 0         # 退出码 0/1
./bin/golden --convert shot.tsraw shot.png              # TSRAW → PNG
```

无窗口像素断言（CI 无 GPU 也能跑）：

```crystal
backend = Tessell::Render::SoftwareBackend.new
backend.init(160, 120)
backend.attach_atlas(atlas)
backend.begin_frame(nil, theme)
backend.draw_draw_list(canvas.list)
backend.end_frame
backend.pixel(50, 12)   # 0xRRGGBBAA 断言
```

「脏区重绘 == 全量重绘」oracle：spec/software_backend_spec.cr。
组件级无窗口验证：`crystal run examples/kit_gallery.cr -- --verify`。

## 9. 帧调试

`F1` 开关（宿主一行 `root.debug_info = DebugInfo.collect(...)`）：
帧耗时/FPS、quads/scissor/culled、atlas used/evicted、dirty rects、
hover/focus 名。见 usage.md「帧调试 overlay」。

## API reference

```sh
bash tools/gen_api_docs.sh   # 生成到 site/api（已 gitignore）
```

## 已知边界与临时写法

以 [usage.md「已知 API 缺口」](usage.md)为准（动态更新）：Win32 平台层
收敛（issue #3）、IME composition 接入 Kit 事件、屏幕阅读器 provider、
平台剪贴板适配仍在路上；各节已给出当前可用的替代写法。
