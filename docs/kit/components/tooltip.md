# Tooltip

## 何时使用

- 对图标按钮、截断文本或非常用操作提供补充说明。
- 不用于放置可交互内容；需要交互请用 Popover/Menu。
- 不抢焦点，不替代可见标签。

## 最小示例

```crystal
button.tooltip_text = "Save changes"
button.tooltip_delay_ms = 600
```

Tooltip 由 Root 在 hover 延迟到期后打开；应用需要每帧调用：

```crystal
root.advance_time(now_ms)
```

## 行为

- hover 进入后等待 `tooltip_delay_ms`，到期打开；离开立即关闭。
- 默认放在锚点上方，越界时翻转到下方并夹紧到窗口。
- 不获取焦点；`Root` 不会为 Tooltip 保存/恢复焦点。
- 点击外部、Escape、窗口 blur 关闭。
- 打开期间 `advance_time` 不重复创建。

## 无障碍

- Role：`Tooltip`。
- Name：提示文本。
- Focusable：false。
- 限制：没有“键盘焦点等价入口”的自动实现；需要键盘用户可见的提示应使用可见文本或后续 Popover。

## 主题 token

surface_raised 背景、border 边框、foreground 文本；圆角来自 `radius_md`。

## 限制

- 不支持富文本、箭头、跟随鼠标。
- 只由 hover 触发；触摸/键盘触发的等价交互需要应用自行打开。
- 真实窗口 hover/延迟路径未在 Windows 上复验。
