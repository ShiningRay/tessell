# Tessell Kit 组件文档

> 中文优先。每个组件页固定包含：何时使用、最小示例、状态/variant/size、键盘、无障碍、主题 token、限制。
> 当前状态：K2 已交付 Button、Checkbox、Text、ScrollView、VirtualList 适配；Input、Select、Tooltip、Dialog 在后续阶段补齐前不列入“可用”表。

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

## 尚未交付

Input、Select、Tooltip、Dialog、Radio/Switch 等仍在 [plan.md](plan.md) 的后续工作包中。不要把“目录里没有”理解为“已经支持”。

## 运行示例

无窗口组件矩阵（可在 macOS/Linux 运行）：

```bash
crystal run examples/kit_gallery.cr -- --verify --frames=60 --theme=dark --dpi=1.5
```

真实窗口上屏需要 Windows + OpenGL 后端；当前 macOS 环境不能替代验证。
