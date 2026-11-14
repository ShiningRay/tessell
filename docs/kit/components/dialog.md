# Dialog

## 何时使用

- 需要用户确认或填写后才能继续的模态任务。
- 删除、发布等需要明确阻断的破坏性操作。
- 不用于非阻塞通知；Toast/Alert 后续提供。

## 最小示例

```crystal
content = Tessell::Kit::Text.new(Tessell::UI::UiKey.root.child(2_u64), "This cannot be undone.")
cancel = Tessell::Kit::Button.new(Tessell::UI::UiKey.root.child(3_u64), "Cancel")
confirm = Tessell::Kit::Button.new(Tessell::UI::UiKey.root.child(4_u64), "Delete",
  Tessell::Kit::Variant::Danger)
dialog = Tessell::Kit::Dialog.new(Tessell::UI::UiKey.root.child(5_u64),
  "Delete item?", content, [cancel, confirm])
dialog.on_close = -> { @dialog = nil; nil }

root.open_dialog(dialog)
```

## 行为

- 模态：Root 插入全窗屏障，背景内容不可点击。
- 自动居中，超出窗口时夹紧；内容高度按标题/内容/动作区测量。
- 打开后焦点移到第一个可聚焦子组件（通常是第一个动作按钮）。
- Tab/Shift+Tab 只在 Dialog 子树内循环；不会逃逸到背景。
- Escape、点击屏障关闭；关闭后恢复打开前的焦点。
- `on_close` 在真正关闭时调用；业务取消/确认逻辑自行决定何时调用 `root.close_overlay(entry)`。

## 无障碍

- Role：`Dialog`。
- Name：标题。
- 屏障 Role 为 `Group`，Name 为 `Modal barrier`；无平台 provider。
- 关闭后恢复焦点；背景控件不进入焦点环。

## 主题 token

surface 背景、border 边框、focus 焦点环；标题使用 Large 字号；动作区右对齐。

## 限制

- 不支持嵌套 Dialog 的 z-order 动画、可调整大小、拖拽。
- 不自动处理“未保存修改”拦截。
- 真实窗口的屏障像素与焦点路径未在 Windows 上复验。
