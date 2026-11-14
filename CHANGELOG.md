# Changelog

## 0.2.0 (2026-11-14)

ShiningRay/tessell 全部 18 个 GitHub issue 处置完成（#1–#18，逐一提交关闭）。

### Bug 修复
- **#1 GlyphAtlas GPU 同步契约**：新增 `revision` / `page_revision` /
  `rgba_page_revision`（任何像素变化含既有页插入都递增）；
  `GLBackend#sync_atlas_dirty` 按页 revision 只重传变化页（新页
  `glTexImage2D`、已有页 `glTexSubImage2D`）。动态文本不再运行期缺字；
  `page_count` 不是变化信号，示例与宿主已改用增量同步。
- **#14 Kit::Context 文本度量单位**：`measure_text` / `line_height`
  统一返回**逻辑**单位（设备字号测量后除回 scale，max_width 同步乘 scale
  保证换行一致）。DPR≠1 不再宽度翻倍，宿主无须自写除法适配器。
- **#15 Painter z-order 与 clip 契约**：契约成文（调用顺序即绘制顺序，
  clip 同时约束形状与文本）；`Backend#draw_text` 增加 `from_batch/clip`、
  `draw_draw_list` 增加区间参数；SDL 宿主按命令序交错提交，滚动边缘文本
  由后端 scissor 裁切。
- **#16 Tab 键语义**：`Component#wants_tab?` 声明后 Root 先把 Tab 投递给
  焦点组件；`Ctrl/Meta+Tab` 恒定保留给焦点环（退出路径）。
- 附带修复：`draw_polygon` dirty 模式覆盖写出脏区；SDL 截图 PNG 写入器
  BFINAL 与块遍历双缺陷；脏区清屏移至 `begin_frame`（交错提交不被清屏
  擦掉形状）。

### 新能力（增强建议研判后执行）
- **#2 Render::Canvas**：统一绘制门面（fill/stroke/round_rect/line/
  polyline/push_clip），命令进 DrawList 由 `Backend#draw_draw_list` 执行；
  `draw_polygon` 保留为路径填充入口。
- **#4 输入模型**：KeyCode 补 KeyT/Digit0-9/F1-F4；Event 增加
  `timestamp_ms` / `repeat`；Router 点击语义（`last_click_count` 单/双击、
  `last_drag_distance`、可配双击参数）。
- **#5 DSL 自动布局**：`Layout` 内核 gap 支持；`vstack/hstack/auto_text/
  auto_node` + `UI.apply_auto_layout`——布局与命中树同源。
- **#6 文本 API**：`Text::FontMetrics`（FtMeasurer 读 FT size metrics）；
  `ctx.text_metrics`（逻辑单位）；`TextDrawing.draw_in_rect` 九宫格对齐；
  `measure_text` 内建缓存。
- **#7 字体栈**：`Text::FontStack`（cmap 真实覆盖选脸）+
  `Text::SystemFonts` 标准目录发现；选脸粒度=整段文本的边界如实文档化。
- **#8 主题 token**：核心 Theme 扩展 panel/panel_alt/card/grid/divider、
  up/down/up_soft/down_soft（预设 A 股口径）、hover/focus_ring、
  warning/danger/success/faint；Kit `ctx.render_theme` 镜像。
- **#9 PNG/golden 工具**：零依赖 PNG 写读（stored zlib）；`--screenshot=x.png`
  直出 PNG；`tools/golden` 比较/diff 图/TSRAW/PPM 互转，退出码可直接用于 CI。
- **#10 SoftwareBackend**：纯 CPU 离屏后端（无窗口/GPU/FFI），与 GLBackend
  同契约；「脏区重绘 == 全量重绘」可在纯 spec 内断言。
- **#11 帧调试 overlay**：F1 开关（Root 拦截，业务零改动）；
  `DebugInfo.collect` 一行接入——帧耗时/FPS/quads/scissor/culled、
  atlas used/evicted、dirty rects、hover/focus 名。
- **#17 ScrollModel**：可复用单轴滚动数学（clamp/thumb/可见区间/坐标↔索引），
  ScrollView 委托；二维控件 x/y 各持一实例。
- **#3 App::Runner**：平台无关帧循环契约（自动化帧数/虚拟时钟/帧预算/
  干净退出），SDL 宿主已接入。

### 文档
- **#12**：docs/cookbook.md 九节 + API reference 生成脚本
  （`tools/gen_api_docs.sh` → site/api）+ README 链接真实 demo 仓；
  「已知 API 缺口」刷新为 2026-11 现状。
- **#13**：K6 复盘七项问题处置映射回填 docs/kit/K6-review.md §7。
- **#18**：usage.md 新增「写示例常撞的 Crystal 编译错误」（逐条实测）与
  Rasterizer/FtMeasurer 分工契约。
- **#17 附带**：docs/kit/cookbook-custom-widget.md 自定义大控件清单。

### 平台口径
- macOS（SDL2/OpenGL）可验证面全部闭环：真实窗口截图、gallery verify
  （light/dark/dpi=1.5/2.0）、m3_sdl_dirty_probe 像素探针。
- Windows 真机 gate 与平台 provider 维持 No-Go：Win32 平台层立项
  docs/cross-platform-plan.md §11（issue #3 关闭评论与文档同步口径）。

**Full Changelog**: https://github.com/ShiningRay/tessell/compare/00af890...v0.2.0
