# Button

## 何时使用

- 触发一个明确动作，例如保存、提交、删除。
- 需要 primary/secondary/ghost/danger 四种语义层级时。
- 不用于导航链接；导航应由应用层决定语义。

## 最小示例

```crystal
require "tessell/kit"

button = Tessell::Kit::Button.new(
  Tessell::UI::UiKey.root.child(1_u64),
  "Save",
  Tessell::Kit::Variant::Primary,
  Tessell::Kit::ControlSize::Medium
)
button.on_click = -> { save; nil }

column = Tessell::Kit::Column.new(Tessell::UI::UiKey.root.child(2_u64))
column.add(button)
root = Tessell::Kit::Root.new(column)
root.layout(320.0_f32, 120.0_f32)
root.build
```

## Variant 与 Size

| Variant | 用途 | 背景/文字 |
|---|---|---|
| Primary | 页面主操作 | accent / accent_foreground |
| Secondary | 次要操作 | surface / foreground + border |
| Ghost | 低强调操作 | 透明；hover/pressed 才有背景 |
| Danger | 删除/破坏性操作 | danger / danger_foreground |

Size 为 `Small/Medium/Large`，高度、字号、水平内边距来自 `Theme::Metrics`。组件不提供任意尺寸覆盖。

## 状态与事件

- `hovered/pressed/focused` 是组件瞬态；`enabled` 由调用方控制。
- 指针按下后在按钮内抬起 → 一次 `on_click`；在按钮外抬起 → 不触发。
- `Space` 或 `Enter` 按下-抬起 → 一次 `on_click`。
- disabled 不进入焦点环、不响应指针与键盘激活。
- 一次用户动作最多一次回调；不存在 PointerUp + Enter 双发。

## 键盘

| 键 | 行为 |
|---|---|
| Tab / Shift+Tab | 由 Root 焦点环移动 |
| Space / Enter | 激活（按下态，抬起触发） |

## 无障碍

- Role：`Button`。
- Name：`label`；无可见文本的按钮也必须提供 label。
- Value：空。
- Focusable：`enabled && visible`。
- 限制：只产出进程内 A11y 树，没有 UIA/AppKit/AT-SPI provider。

## 主题 token

背景、前景、边框、焦点环都通过 `Theme#button_colors(variant, size, state)` 解析；组件绘制代码不写死最终色值。

## 限制

- 不绘制图标；不提供 loading 态（后续组件扩展）。
- 不支持任意圆角/颜色覆盖；需要完全定制时用核心绘制原语自建组件。
- 真实 GL 上屏与 Windows 窗口交互尚未在本机验证。
