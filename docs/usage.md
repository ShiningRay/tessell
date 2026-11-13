# Tessell 使用说明（M4 app_demo）

## 前置条件
- Crystal 1.22（Windows，msys2 ucrt64 工具链）。
- 构建/运行前设置 PATH：`$env:PATH="C:\msys64\ucrt64\bin;$env:PATH"`
- 运行时 DLL：见 `docs/evidence/M4-WP2-packaging.md`（16 个 DLL；裸 PATH
  可能退出 `-1073741515`）。
- 字体：路径硬编码为 `C:/Windows/Fonts/msyh.ttc`，该文件必须存在。

## 构建与运行（最小示例）
在仓库根目录执行：

```powershell
$env:PATH="C:\msys64\ucrt64\bin;$env:PATH"
crystal build examples/app_demo.cr -o bin/app_demo.exe
bin/app_demo.exe --frames=120 --verify
```

或：`crystal run examples/app_demo.cr -- --frames=120 --verify`

参数（`examples/app_demo.cr`）：
- `--frames=N` 默认 120
- `--verify` 运行检查并输出 token 行，通过 EXIT 0 / 失败 EXIT 1
- `--theme=light|dark` 默认 light
- `--dpi=1.0|1.25|1.5|2.0` 默认 1.0

交互：`Wheel` 滚动列表；`T` 切换主题（整窗重绘）；`Esc` 退出；
文本输入追加到聚焦的顶部输入框；`Tab` 切换焦点；`Backspace` 删除。

## UI DSL 与帧流程
每帧：`UI.build -> UI.apply(decls, root, pool) -> Node.collect_dirty
-> UI.consume`。

- `UI.build(root, b) { ... }` 产出 `Decl`（key、parent、kind、text、
  bounds、paint）。同一逻辑节点的 `UiKey` 必须**跨帧稳定**，以便
  `apply` 从 `Pool` 匹配并复用节点。
- `UI.apply(decls, root, pool)` 协调声明：创建/复用节点、更新属性与
  bounds，并**标记脏**（create/change/layout/paint）。
- `Node.collect_dirty(root, sink)` 遍历并收集脏节点/区域。
- `UI.consume(nodes)` 在渲染后**清除脏标记**。分工：`apply` 标脏，
  `consume` 清脏；下一帧仅包含新产生的脏。

脏集语义：脏是节点级失效状态。渲染提交整窗或合并后的脏区；无脏时跳过
绘制但仍 `SwapBuffers`。

## 虚拟列表
示例使用 `Widgets::VirtualList`：10000 行，`row_h` 20，列表视口 800×600。
- `scroll_by/scroll_to` 钳制偏移；`prepare_visible` 更新可见窗口。
- `visible_first/last`、`node_offset(i)`、`pool_size` 驱动行渲染。
- 滚动由 `Router` 的 `Wheel` 事件驱动。本示例约定 y 符号决定方向：
  +1 向上滚动 `row_h`，-1 向下滚动 `row_h`。
- 标签在初始化时一次性预生成；热路径仅按索引取字符串。

## 主题与 DPI
- `--theme=light|dark` 启动时选择 `Render::Theme.light/dark`。
- 运行中按 `T` 切换主题（强制整窗重绘并重新组合）。
- `--dpi=1.0|1.25|1.5|2.0`：`Render::Dpi.scale_for(dpi*96)` 得 scale；
  `Dpi.size_px(16.0, scale)` 计算字号并参与布局尺寸。

## 零分配口径与陷阱
稳态探针：3 个窗口，每窗 N=1000 帧，`GC.enable` 置于 ensure，最多 1 次重试；
始终打印 `ALLOC_ATTEMPT1` 行。
判据：A `delta_work < 1000`、B `delta_work <= 256`（取 3 窗最大值）。
**不是**严格 0；本机 16–96B 噪声可落任意窗。
`retried=false attempt=1` 为理想情况；判据允许 1 次重试通过。

陷阱：探针前预热 shaped run 并 sync atlas；热路径避免新建 `String`/`Array`/
proc 捕获；复用缓冲与 sink；避免热循环内字符串插值。

## verify 检查（app_demo --verify）
token 行包含：`frames/visible_avg/quads_dirty/quads_full/culled/diff_pixels/
diff_A_vs_C/alloc_windows/retried/attempt/verify`（及主题/DPI 字段）。
1. 滚动：脏区渲染与同状态整窗渲染像素一致，`diff_pixels==0` 且
   `diff_A_vs_C>0`。
2. 主题：切换后与该主题直接整窗渲染一致 `diff_theme==0`；切回与基线整窗
   渲染一致 `diff_theme_roundtrip==0`。
3. 分配：探针满足 A/B/重试口径，token 报告结果。

## 常见错误
- `-1073741515`（0xC0000135）：缺少运行时 DLL。将 msys2 ucrt64 bin 加入
  PATH，或按 M4-WP2-packaging.md 将所需 DLL 放到 exe 同目录。
- 字体找不到：期望 `C:/Windows/Fonts/msyh.ttc`（路径硬编码）；请安装字体
  或在示例中调整路径。
- `unexpected token "@["`：源码含 UTF-8 BOM；请另存为不带 BOM 的 UTF-8
  （Crystal 源文件不得包含 BOM）。

## 已知 API 缺口（示例层，未改 src）
- `Input::KeyCode` 无 `KeyT`：运行中 `T` 切换主题通过列表聚焦时的
  `Event.text_input("T"/"t")` 处理（顶部输入框聚焦时 `T` 作为字符追加）。
- `Event.wheel(x,y)` 无 delta 字段：示例按 y 符号约定滚动方向
  （+1 向上 `row_h`，-1 向下）。
