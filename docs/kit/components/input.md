# Input

## 何时使用

- 单行文本输入；受控或非受控由应用读取 `input.text`。
- 需要 label、placeholder、read-only、invalid/error、光标/选区与剪贴板。
- 不用于多行文本、富文本、密码输入；这些场景后续单独组件。

## 最小示例

```crystal
input = Tessell::Kit::Input.new(
  Tessell::UI::UiKey.root.child(1_u64),
  "",
  "Type here…",
  "Name"
)
input.on_change = ->(value : String) { @name = value; nil }
input.on_submit = ->(value : String) { submit(value); nil }
```

## 状态

- `enabled=false`：不进入焦点环，不接收文本。
- `read_only=true`：可聚焦、可选择、可复制，但不可插入/删除/剪切/粘贴。
- `invalid` + `error_text`：危险色边框与错误文本；不自动拦截提交。
- `placeholder`：空值时显示。
- `label`：字段上方标签，同时作为 a11y Name；为空时退回 placeholder。

## 键盘与编辑

| 键 | 行为 |
|---|---|
| 字符输入 / TextInput | 在光标处插入，替换选区，触发一次 `on_change` |
| Left/Right | 按 grapheme cluster 移动；有选区时折叠 |
| Shift+Left/Right | 扩展/收缩选区 |
| Home/End | 到行首/行尾（Shift 扩展） |
| Backspace/Delete | 按 grapheme cluster 删除；有选区时删除选区 |
| Ctrl/Cmd+A | 全选 |
| Ctrl/Cmd+C/X/V | 复制/剪切/粘贴；read-only 下禁止剪切/粘贴 |
| Enter | 触发 `on_submit`，不插入换行 |
| Escape | 折叠选区 |

## 剪贴板

通过注入的 `Kit::Clipboard` 实现；默认 `MemoryClipboard`。平台剪贴板需要应用提供实现：

```crystal
input.clipboard = MyPlatformClipboard.new
```

组件不直接调用系统剪贴板 API。

## IME / 组合输入

- `input.set_preedit("ni")` 显示组合预览，不修改文档。
- `input.commit_preedit` 将预览写入文档并触发 `on_change`。
- 失焦时若仍有 preedit，会尝试提交。
- 平台 IME 事件尚未接入 Kit::Event；`docs/evidence` 中的 C7 人工 IME 验证仍未关闭。真实 Windows IME 路径未在 Kit Input 中验证。

## 无障碍

- Role：`TextField`。
- Name：label，空时 placeholder。
- Value：当前文本。
- Focusable：`enabled && visible`；read-only 仍可聚焦。
- 限制：没有平台 provider；不暴露组合输入状态给屏幕阅读器。

## 主题 token

surface/surface_raised 背景、border/focus/danger 边框、selection 选区、foreground/muted 文本、accent 组合输入。

## 限制

- 不做密码模式；不要在账号密码场景直接使用。
- 不做撤销/重做、词级移动、双向文本、完整 UAX #29 grapheme 分割。
- 不自动校验/格式化；`invalid` 只是视觉状态。
- 程序化 `set_text` 不触发 `on_change`。
- 真实窗口 IME、剪贴板与像素回读未验证。
