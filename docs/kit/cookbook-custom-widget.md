# 自定义大控件实现清单（issue #17）

写表格、时间线、画布类大控件时，`Kit::ScrollView` 的单子组件模型不够用。
以下清单按依赖顺序列出必须处理的点；滚动/clamp/thumb/可见区间数学直接
复用 `Kit::ScrollModel`（x/y 各持一个实例），不要重写。

## 1. 滚动数学（复用 ScrollModel）
- `content_size` / `viewport_size` / `offset`（写入即 clamp）；
- `visible_range(item_size, total_count)`：等高行/列的可见区间（含端点、
  尾部收敛到 total-1）；
- `offset_at(index, item_size)` / `index_at(coord, item_size)`：坐标↔索引
  双向换算（坐标相对 viewport 起点）；
- `thumb(track_len)` / `offset_for_thumb(pos, track_len)`：滚动条几何。

## 2. 命中
- 组件维护 Node↔Component 映射（Root 自动做）；命中子项时回退到最近的
  可聚焦祖先（`wants_tab?`、`focusable?`）。
- clip：`clip_bounds` 返回可视区，Root 同步到 Node#clip，HitTest 继承。

## 3. 绘制与裁切
- `paint` 里 `push_clip(viewport)` → 内容 → 滚动条 → `pop_clip`。
- 文本裁切依赖后端 scissor（issue #15 契约）：半可见行的文本直接发命令，
  不需要自己算可见性；`text` 调用顺序即绘制顺序。

## 4. 键盘与滚动
- `focusable?` = 有可滚动内容或行可聚焦；
- Key Down/Up/PageUp/PageDown/Home/End 与 wheel 的 delta（`event.wheel_dy`，
  issue #4 语义）映射到 `model.scroll_by`。

## 5. a11y
- 虚拟化控件必须报告逻辑总数：`a11y_children_count`（逻辑行数）与
  `a11y_scroll_offset`（当前 offset 取整）；进程内树 ≠ 平台 provider，
  文档不得暗示屏幕阅读器可用。
- 二维网格控件（issue #31）：坐标/选区/表头走结构化字段，**不拼 value 字符串**。
  容器声明 `a11y_role = Grid` + `a11y_row_count`/`a11y_col_count` +
  `a11y_first_visible_index`（可视窗口起点，provider 据此定位在逻辑总量中
  的位置）；单元格声明 `a11y_role = GridCell` + `a11y_row`/`a11y_col` +
  `a11y_row_index_text`/`a11y_col_index_text`（"1"/"A" 的朗读文本）+
  `a11y_selected`/`a11y_active_cell`；行/列标头声明
  `RowHeader`/`ColumnHeader` + 对应 index_text。全部字段默认 nil，
  非网格组件零改动。读方语义（对齐 UIA `DataItem`/NSAccessibility
  `GridCell`/AT-SPI `TableCell`）：当前活动单元格 = active_cell=true 的
  GridCell，"我在 B4" = row_index_text+col_index_text，不再出现 `"A1 42"`。

## 6. 半可见与边界
- 行坐标 = `offset_at(index) - model.offset`；首末行允许部分可见，交给
  后端 scissor 裁切。
- 内容尺寸变化后重新 clamp：`model.offset = model.offset`。

## 参考
- 单轴模型与全部数学：`src/tessell/kit/scroll_model.cr`
- 委托示例：`src/tessell/kit/scroll_view.cr`
- 二维用法：x/y 两个 `ScrollModel`；冻结表头 = 表头区域不应用 y 模型
  的 offset，仅 body 应用。
