# VirtualList

## 何时使用

- 大列表，只需要可见行实例化。
- 固定行高；变量行高由核心 `Widgets::VirtualList` 支持，Kit 适配当前只暴露固定行高入口。
- 需要逻辑总行数 a11y 语义。

## 最小示例

```crystal
list = Tessell::Kit::VirtualList.new(
  Tessell::UI::UiKey.root.child(1_u64),
  1000,
  22,
  ->(index : Int32) { "Row #{index + 1}" },
  name: "Rows"
)
```

## 行为

- 可见范围、滚动钳制、回收统计由核心 `Widgets::VirtualList` 负责。
- Kit 只把可见行声明为稳定 keyed Text 节点；不物化全部行。
- `Wheel`、`Up/Down/PageUp/PageDown/Home/End` 滚动。
- 行 key 使用 `key.child(index + 1)`；滚动后复用池中的节点。

## 无障碍

- Role：`List`。
- Name：构造参数 `name`。
- `children_count` 报告逻辑总行数（例如 1000），不是可见行数。
- 可见行作为 `ListItem` 子节点；没有平台 provider。

## 限制

- 当前不支持行内自定义组件、选中态、多列。
- 变量行高入口未在 Kit 暴露；需要时再包装核心 API。
- 真实窗口像素回读与滚动性能未在本机验证。
