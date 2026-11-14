# Select

## 何时使用

- 从固定选项中选择一个值。
- 选项数量中等、需要键盘导航与浮层定位。
- 不用于多选、搜索或自由输入；这些场景后续单独组件。

## 最小示例

```crystal
sel = Tessell::Kit::Select.new(
  Tessell::UI::UiKey.root.child(1_u64),
  ["Alpha", "Beta", "Gamma"],
  selected_index: 0,
  label: "Choice"
)
sel.on_change = ->(index : Int32, value : String) { @choice = value; nil }
```

## 行为

- 受控 `selected_index`；组件不维护第二份业务值。
- 指针点击触发区打开/关闭；弹出列表通过 Root OverlayHost 显示。
- 弹出列表打开后获得焦点；Up/Down/Home/End 移动高亮，Enter/Space 选择，Escape 关闭。
- 点击外部关闭；关闭后焦点恢复到触发区。
- 选择结果只回调一次 `on_change(index, value)`。

## 无障碍

- 触发区：Role `ComboBox`，Name 来自 `label`，Value 为当前选项或 placeholder。
- 弹出列表：Role `ListBox`；选项 Role `Option`，选中项 Value=`selected`。
- 没有平台 provider；Popover 的焦点恢复由 Root 统一处理。

## 主题 token

触发区 surface/border/focus；选中项 accent；高亮行 selection；弹出层 surface + border。

## 限制

- 不支持多选、搜索、分组、空选项占位。
- 不支持拖动滚动条；选项很多时后续接入 VirtualList。
- 真实窗口的浮层裁剪与翻转未在 Windows 上复验。
