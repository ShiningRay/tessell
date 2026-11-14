# Checkbox

## 何时使用

- 单个布尔选项，或“全选/半选”场景。
- 多选列表中的独立选项。
- 不用于互斥选项；互斥用 RadioGroup（后续）。

## 最小示例

```crystal
require "tessell/kit"

checkbox = Tessell::Kit::Checkbox.new(
  Tessell::UI::UiKey.root.child(1_u64),
  "Enable notifications",
  checked: true
)
checkbox.on_change = ->(value : Bool) { @notifications = value; nil }
```

## 状态

- `checked`：受控布尔值，由应用持有。
- `indeterminate`：半选展示；用户切换时清除半选并置为 checked。
- `disabled`：不响应指针/键盘，不进入焦点环。
- `hovered/pressed/focused`：组件瞬态。

## 事件

- 指针在组件内按下并抬起 → 切换一次，回调收到新值。
- `Space` 抬起 → 切换一次；仅当组件聚焦且 enabled。
- 程序化修改 `checked` 不触发 `on_change`；需要事件时由应用自己调用业务逻辑。

## 键盘

| 键 | 行为 |
|---|---|
| Tab / Shift+Tab | 由 Root 焦点环移动 |
| Space | 切换 |

## 无障碍

- Role：`CheckBox`。
- Name：`label`。
- Value：`checked` / `unchecked` / `mixed`。
- Focusable：`enabled && visible`。
- 限制：没有平台 provider；标签作为 Name 而不是独立 Text 子节点，避免重复曝光。

## 主题 token

框体使用 surface/border/accent；勾与半选线使用 accent_foreground 或前景色；焦点环使用 focus。

## 限制

- 不支持自定义勾选图标。
- 不内置“全选”逻辑；由应用组合多个 Checkbox。
- 真实窗口键盘路径尚未在 Windows 上复验。
