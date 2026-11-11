# 命名

**Tessell** —— 源自 tessellate（镶嵌 / 三角化）。

GPU 渲染的顶点与索引缓冲由三角化产生，名字直接指向本框架的绘制路径；同时保留“由小单元拼成整体界面”的意象，与 retained 树和布局内核契合。

## 定名过程

1. 第一轮候选 Quartz / Lamina / Prism / Bastion，选定 **Quartz**。
2. 发现 Quartz 与 **macOS Quartz 图形子系统**（Quartz 2D / Quartz Core）同名，存在文档与搜索混淆风险。
3. 第二轮给出九个候选并逐个核实 GitHub 撞名（2026-11-11），选定 **Tessell**。

### 撞名核实结果

| 候选 | GitHub 同名结果数 | 头部同名项目 | 结论 |
|---|---|---|---|
| **Tessell** | 932 | stephenh/tessell；其余多为 Tessellation 演示 | **选定**，无强势同名 |
| Vellum | 1217 | couchbase/vellum、blevesearch/vellum | 同名在数据库/搜索领域 |
| Quire | 877 | thegetty/quire | 出版工具同名 |
| Facet | 7189 | facet-rs/facet（2590★）、PAIR-code/facets（7332★） | Rust 生态强势同名，放弃 |
| Strata | 7465 | tradingtechnologies/Strata、StrataFoundation/strata | 金融/区块链同名 |
| Beryl | 2278 | ffffffff0x/BerylEnigma | Compiz Beryl 历史包袱 |
| Onyx | 9159 | onyx-dot-app/onyx（33334★） | 已被占，放弃 |
| Lumen | 23018 | laravel/lumen（7556★） | 已被占，放弃 |
| Iris | 93089 | kataras/iris（25557★）、IrisShaders/Iris | 已被占，放弃 |

说明：结果数为 GitHub `in:name` 搜索的 `result_count`，含部分匹配与派生词，不等于精确同名仓库数；结论依据头部同名项目的领域与影响力判断。

### Quartz 落选原因

与 Apple 图形子系统同名。虽不占 GitHub 仓名，但跨平台 GUI 框架长期与 macOS 平台层代码共存，混淆成本高，不值得保留。

## 命名约定

- Crystal 命名空间：`Tessell`
- 模块：`Tessell::Layout`、`Tessell::Render`、`Tessell::Platform`、`Tessell::Widget`
- 后端 shard（若拆分）：`tessell-metal`、`tessell-vulkan`
- 仓库：`tessell`；发布前需核对 `ShiningRay/tessell` 可用性
- 环境变量与日志前缀：`TESSELL_` / `tessell`
