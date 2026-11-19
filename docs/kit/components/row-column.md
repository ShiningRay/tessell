# Row / Column

## 何时使用

- 线性排列子组件：工具栏、表单行、列表行、操作区。
- Row 水平、Column 垂直；配合 padding/spacing/alignment。
- 子组件需要分享剩余空间（输入框 + 按钮同排、分隔占位）时用 grow 权重。
- 不替代核心 Layout 两遍内核；组件仍产出绝对 bounds。

## 最小示例

```crystal
row = Tessell::Kit::Row.new(key, Tessell::Insets.all(8.0_f32), 8.0_f32)
row.add(input, grow: 1.0_f32)   # 输入框吃掉剩余宽度（issue #49）
row.add(button)                 # 固定内容宽度，紧跟其后
```

## 参数

- `padding`：Insets，四边内边距。
- `spacing`：主轴子项间距。
- `alignment`：**交叉轴**对齐——Start / Center / End / Stretch（默认
  Stretch：交叉轴填满）。

## 弹性布局（grow，issue #49）

- `container.add(child, grow: weight)` 或
  `container.set_grow(child, weight)`（weight ≤ 0 取消）登记弹性权重。
- 主轴有界时：固定子项先按内容测量，剩余主轴空间
  （`inner − 固定子项 − spacing`）按权重紧约束分配给弹性子项
  （min=max=share，Flutter Expanded 语义；最后一个弹性子项吃浮点余数，
  恰好填满）。
- 剩余空间不足时弹性子项塌缩为 0，固定子项优先。
- 主轴无界（内在尺寸测量）时不做分配：弹性子项不参与内在尺寸。
- 权重变化与 `add`/`remove` 一样打结构脏标记，`root.build` 自动补重排。
- `Spacer`：弹性占位组件——`row.add(Tessell::Kit::Spacer.new(key), grow: 1.0)`；
  不进命中树、不绘制。单独使用为 0×0。
- 限制：不做 flex-wrap 换行、不做交叉轴多行、不解析 CSS；比例分配是
  Float32 直算，不保证跨平台逐位一致。

## 键盘 / 无障碍

- Container 自身不聚焦、不拦截键盘事件；子组件按各自契约处理。
- emit 为 `Group`（visible 时）；不可见子树整棵跳过。
- `Spacer` 不 emit（不可命中、无角色）。

## 主题 token

- 不消费颜色 token；布局数值来自组件参数与父级约束，不受主题影响。

## 限制

- 一个方向一个用途：需要嵌套组合（Row 套 Column）表达复杂布局。
- `alignment` 只作用交叉轴；主轴始终按顺序排布，不留白。
