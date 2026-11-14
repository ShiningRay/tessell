# Text

## 何时使用

- 正文、标签、标题、辅助说明。
- 需要 muted/danger/success 语义色时。
- 不是编辑器；输入请用 Input（后续 K4）。

## 最小示例

```crystal
text = Tessell::Kit::Text.new(
  Tessell::UI::UiKey.root.child(1_u64),
  "Settings",
  Tessell::Kit::TextTone::Normal,
  Tessell::Kit::ControlSize::Large
)
```

## 状态

- `tone`：Normal / Muted / Danger / Success。
- `size`：Small / Medium / Large。
- `wrap`：是否按 bounds 宽度换行。
- `max_lines`：最多显示行数；超出时最后一行加省略号。
- `enabled=false`：使用 muted 色。

## 换行与截断

- 非 wrap：宽度不足时按 codepoint 截断并加 `…`。
- wrap：按 codepoint 贪心断行；当前不做双向文本、连字或复杂脚本排版。
- `max_lines` 在 wrap 结果上截断。

## 无障碍

- Role：`Text`。
- Name：完整文本内容（不是截断后的显示文本）。
- Focusable：false。
- 限制：没有平台 provider；文本度量由注入的 `TextMetrics` 决定，测试使用 `StubTextMetrics`。

## 主题 token

Normal 用 foreground，Muted 用 muted，Danger 用 danger，Success 用 success；字号来自 `Theme#font_size(size)`。

## 限制

- 不解析 Markdown/HTML。
- 不支持富文本内联样式。
- 不做 grapheme cluster 级截断；Emoji ZWJ 序列可能被拆开。
