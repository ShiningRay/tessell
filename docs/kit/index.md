# Tessell Kit 组件文档

> 中文优先。每个组件页固定包含：何时使用、最小示例、状态/variant/size、键盘、无障碍、主题 token、限制。
> 当前状态：K2 已交付 Button、Checkbox、Text、ScrollView、VirtualList 适配；K3 已交付 Tooltip、Dialog、Select 与 Root Overlay；K4 已交付单行 Input（含 grapheme 光标/选区、剪贴板接口与 IME 预览 API，平台 IME 事件仍未接入）。
> 跨平台（Windows/macOS/Linux）按 L0→L2 分级收口，见 [跨平台方案](https://github.com/ShiningRay/tessell/blob/main/docs/cross-platform-plan.md)；未完成的平台证据不得写成“已支持”。

## 入口

```crystal
require "tessell/kit"
```

核心入口 `require "tessell"` 不加载 Kit。组件需要显式的 `Tessell::UI::UiKey`；同一个逻辑组件跨帧必须使用同一个 key。

## 组件状态

| 组件 | 状态 | 文档 |
|---|---|---|
| Button | primary/secondary/ghost/danger；small/medium/large；disabled；hover/pressed/focus | [button.md](components/button.md) |
| Checkbox | checked/unchecked/indeterminate；disabled；hover/pressed/focus | [checkbox.md](components/checkbox.md) |
| Text | normal/muted/danger/success；size；wrap/max_lines | [text.md](components/text.md) |
| ScrollView | vertical/horizontal；滚动条；wheel/键盘 | [scroll-view.md](components/scroll-view.md) |
| VirtualList | 固定行高；可见窗口；逻辑总行数 a11y | [virtual-list.md](components/virtual-list.md) |
| Tooltip | hover 延迟；不抢焦点；边界翻转 | [tooltip.md](components/tooltip.md) |
| Dialog | 模态屏障；焦点圈定/恢复；Escape/外部点击 | [dialog.md](components/dialog.md) |
| Select | 单选；键盘导航；Popover 列表 | [select.md](components/select.md) |
| Input | 单行文本；grapheme 光标/选区；剪贴板接口；IME 预览 | [input.md](components/input.md) |

## 尚未交付

Radio/Switch、Slider、Progress、Tabs、Menu、密码输入、平台 IME 事件接入等仍在 [plan.md](plan.md) 的后续工作包中。不要把“目录里没有”理解为“已经支持”。

## 视觉预览（无窗口）

以下预览由 `Kit::SvgPainter` 从 `PaintList` 生成，再用 `rsvg-convert` 转 PNG；
它们证明绘制命令与主题/布局组合，不等于真实窗口上屏证据。

- [light PNG](../../site/previews/gallery-light.png)
- [dark PNG](../../site/previews/gallery-dark.png)

静态文档站生成：

```bash
crystal run tools/build_kit_site.cr
# 输出 site/index.html 与 site/kit/*.html
```

## 示例应用

- [计算器与文本编辑器](apps.md)：SDL2 窗口 + OpenGL，真实可交互；含运行命令、截图与限制。
- [自定义大控件 cookbook](cookbook-custom-widget.md)：表格/时间线类控件的
  滚动/命中/裁切/键盘/a11y 清单，复用 `Kit::ScrollModel`（issue #17）。

## 复核与反馈

- [K6 复核（Go-with-conditions）](K6-review.md)
- [架构复盘 issue #13](https://github.com/ShiningRay/tessell/issues/13)

## 运行示例

无窗口组件矩阵（可在 macOS/Linux 运行）：

```bash
crystal run examples/kit_gallery.cr -- --verify --frames=60 --theme=dark --dpi=1.5
```

真实窗口上屏已在本机 macOS SDL2/OpenGL 验证；Windows SDL2 与 Linux GUI 仍需按跨平台计划补证据，headless gallery 不能替代真实窗口。
