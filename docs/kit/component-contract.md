# 组件契约

> 这是 Kit 组件的公共约定，不是某个组件的实现说明。组件文档可以补充，但不能削弱这里的规则。

## 身份与状态

- 每个组件必须有一个跨帧稳定的 `Tessell::UI::UiKey`。子部件从组件根 key 派生子 key，禁止用显示文本生成身份。
- 应用持有业务值（输入文本、选中项、开关值）；组件只持有 `hovered/pressed/focused/open/scroll` 等瞬态。首版默认受控。
- 组件统一识别：`disabled`、`read_only`、`hovered`、`pressed`、`focused`、`selected`、`open`、`invalid`。不适用时显式忽略，不把 `disabled` 与 `read_only` 混用。
- 一次用户动作最多触发一次语义回调。指针抬起与键盘激活不得双发；程序化 setter 是否触发回调必须逐组件写明。

## 尺寸与布局

- 尺寸档位只有 `Small / Medium / Large`；间距、圆角、边框、焦点环、控件高度来自 `Theme::Metrics`，组件不得另造一套尺寸。
- `measure` 只依赖 `Context`（主题、文本度量、DPI scale）与组件自身状态；不得读窗口或 GPU 状态。
- `arrange` 接收绝对 bounds，递归给子组件分配绝对 bounds。热路径可以复用组件对象，但不得复用上一帧的错误几何。
- 文本尺寸统一经 `Context#measure_text`；组件不得自行按字符数猜宽度。

## 失效最小化

- 文本、颜色、hover、按压、焦点变化只影响绘制，应走 Paint 语义；尺寸、可见结构、禁用导致的可聚焦性变化走 Layout。
- 不允许因为 hover 重排整棵树；不允许每帧重建全部子组件。
- `Root#build` 复用 `UI::Builder`、`UI::Pool` 与节点；稳态不增长节点数。

## 输入

- 组件不直接读 Win32/WGL/Cocoa 事件；输入来自 `Kit::Event`，由 `Root` 统一路由。
- 指针按下前必须命中组件 bounds；按压释放只有在同一组件内才算激活。
- 键盘激活键：按钮用 `Space/Enter`；复选框用 `Space`；Select/Dialog/Tooltip 的键位在各自文档写明。
- `disabled` 组件不进入焦点环、不接收激活；`read_only` 仍可聚焦、可选择、可复制，但不可修改值。
- Tab/Shift+Tab 的焦点顺序由 Root 的焦点环决定，组件不得自建平行焦点系统。
- 键盘键的唯一真相是 `Tessell::Input::KeyCode`；`Kit::Key` 是它的 alias（issue #27），
  核心新增键自动对组件可见，不存在"核心已支持、Kit 收到 Unknown"的漂移
  （spec/kit/key_mapping_spec.cr 全量锁住）。例外：`F1` 被 Root 预留给帧调试
  overlay 开关，不投递给组件；`Unknown` 表示宿主无法识别的 keysym 占位值。
- 焦点投递契约（issue #26）：组件间转移 A→B 时 A 先收到 `on_focus_changed(false)`，
  B 依次收到 `handle(Focus)` 与 `on_focus_changed(true)`；窗口级失焦时组件先收到
  `handle(Blur)` 再收到 `on_focus_changed(false)`。`Blur` 事件语义 = 窗口失焦，
  组件间转移不投递。顺序由 spec/kit/focus_events_spec.cr 锁住。
- 编辑态 Tab 语义（issue #32）由 API 声明，组件不得在 key_down 里手写分支：
  表单提交用 `Input#submit_on_tab = true`（Tab 触发 on_submit 并消费；
  「提交并前进」在 on_submit 里自行 root.focus 下一字段）；代码编辑用
  `TextEditing#tabs = Insert`（\t 展开 tab_width 个空格，文本永不出现 \t
  字形，宽度与光标不依赖字体制表符）；表格类由父容器 `wants_tab?` 接管
  提交与移动。默认 `TextEditing#tabs = Reject`，\t 整体拒绝。

## 绘制

- 组件只通过 `Kit::Painter` 发出 `fill_rect/stroke_rect/fill_round_rect/stroke_round_rect/text/push_clip/pop_clip`。
- 组件不得调用 GL、平台绘图 API，也不得直接写像素。
- 圆角、描边、焦点环必须能在无窗口的 `PaintList` 中验证；真实后端只需实现 Painter。
- 裁切必须成对 push/pop；异常路径也不能泄漏裁切状态。

## 无障碍

- 可访问名称是必需契约。无可见文本的按钮必须提供名称；Input 必须关联 label/description/error。
- `a11y_role/name/value/focusable/enabled` 随声明同步；装饰性子节点不重复曝光。
- 本库只产出进程内 a11y 树，不承诺 UIA/AppKit/AT-SPI provider。文档必须写明这个限制。
- 二维网格 a11y（issue #31）：坐标/选区/表头用 Meta 结构化字段
  （a11y_row/col/row_count/col_count/row_index_text/col_index_text/selected/
  active_cell/first_visible_index），禁止把坐标拼进 a11y_value 字符串；
  Role 用 Grid/GridCell/RowHeader/ColumnHeader。

## 测试门槛

每个组件至少具备：

1. 状态迁移与事件次数 spec（含 disabled/read_only 反例）。
2. measure/arrange 与声明/a11y 元数据 spec。
3. `PaintList` 命令与裁切成对 spec。
4. 键盘路径 spec；适用时覆盖指针进入/离开/取消。
5. 主题 light/dark 与至少 1.0/1.5/2.0 scale 的纯逻辑验证。
6. 真实窗口验证另记；未运行不得写成通过。
