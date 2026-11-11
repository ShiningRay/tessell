# 命名

**Quartz** —— 石英。天然晶体，呼应宿主语言 Crystal；同时是图形学的经典词，与自绘渲染定位相符。

候选与落选原因：

| 候选 | 结果 | 原因 |
|---|---|---|
| Quartz | **选定** | 短、可读、与 Crystal 意象一致 |
| Lamina | 落选 | 点题分层合成，但词义偏冷，识别度低 |
| Prism | 落选 | 与既有 Prism 语法高亮库撞名 |
| Bastion | 落选 | 与“晶体/渲染”意象关联弱 |

## 已知撞名风险

- **macOS Quartz**（Quartz 2D / Quartz Core / Core Graphics）是 Apple 的图形子系统。这是最主要的命名冲突。
  - 影响：文档与搜索结果易混淆；macOS 平台层代码中若同时引用 Apple Quartz 与本库，需用模块路径区分。
  - 当前处置：Crystal 命名空间固定为 `Quartz`，仓库名 `quartz`，macOS 平台后端文件中显式标注 Apple 框架全名，不使用缩写。
  - 若后续证明冲突代价过高，备选改名窗口为 M1 之前，越晚代价越大。
- 其他语言生态中亦有同名项目。发布到 shards/GitHub 前需核对 `ShiningRay/quartz` 可用性。

## 派生命名约定

- 模块：`Quartz::Layout`、`Quartz::Render`、`Quartz::Platform`、`Quartz::Widget`
- 后端 shard（若拆分）：`quartz-metal`、`quartz-vulkan`
- 不派生 Quartzite 等岩石名，避免命名体系膨胀。
