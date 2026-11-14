# ScrollView

## 何时使用

- 单个可滚动内容区域，内容高度/宽度超过视口。
- 需要裁切、滚动条、滚轮与键盘滚动。
- 长列表优先使用 VirtualList 适配，而不是把全部行放进 ScrollView。

## 最小示例

```crystal
content = Tessell::Kit::Column.new(Tessell::UI::UiKey.root.child(1_u64), spacing: 8.0_f32)
# ... add rows ...
scroll = Tessell::Kit::ScrollView.new(
  Tessell::UI::UiKey.root.child(2_u64),
  content,
  vertical: true
)
```

## 滚动行为

- `scroll_to` / `scroll_by` 钳制到 `[0, max_scroll]`。
- `Wheel` 使用 `wheel_dx/wheel_dy`；旧事件没有 delta 时不滚动。
- `PageUp/PageDown` 滚动 90% 视口；`Up/Down` 滚动 24 逻辑像素；`Home/End` 到端点。
- 滚动条按内容/视口比例绘制；当前不支持拖动滚动条。

## 裁切

- `clip_bounds` 返回视口；Root 同步到 `Node#clip`，命中测试不会命中视口外内容。
- 绘制使用 `push_clip/pop_clip`，异常路径由调用方保证成对。

## 无障碍

- Role：`ScrollView`。
- Focusable：当且仅当存在可滚动范围。
- 没有暴露滚动条为单独 a11y 节点；平台 provider 仍未实现。

## 主题 token

轨道使用 surface_raised，滑块使用 muted；内容颜色由子组件决定。

## 限制

- 不支持惯性滚动、缩放、嵌套滚动优先级。
- 水平/垂直滚动条不支持拖动与键盘焦点。
- 真实窗口滚轮 delta 映射尚未在 Windows 上复验。
