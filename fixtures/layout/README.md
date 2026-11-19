# 布局正确性 oracle fixtures（issue #64）

Tessell `Layout` 纯函数内核的**外部正确性参照**：期望几何来自上游 Taffy
（不是我们自己推导），加上本地文本测量用例。**不宣称 CSS 全量兼容**，
也不替代 `spec/layout_spec.cr` 的单点行为断言。

## 来源与许可证

- 上游：[DioxusLabs/taffy](https://github.com/DioxusLabs/taffy)，
  commit `1abd8ee`（2026-11），目录 `tests/xml/flex/*__content_box_ltr.xml`。
- 许可证：MIT（上游 LICENSE 副本在 `upstream/taffy/LICENSE`）。
- 转换器：`tools/layout_fixture_convert.cr`——同输入同输出，可复现；
  过滤规则见下。上游原始 XML 保留在 `upstream/taffy/`（审计用）。

## 目录

| 路径 | 内容 |
|---|---|
| `upstream/taffy/*.xml` | 挑出的上游受控子集（原始文件，未改动） |
| `taffy/*.json` | 转换后的 oracle fixture（树 + taffy 期望几何） |
| `local/*.json` | 本地文本测量代表用例（StubMeasurer 确定性口径推导，是 harness/缓存一致性 oracle，**不是** CSS 外部语义） |
| `known_failures.json` | 豁免清单：fixture → 已知语义缺口原因 |

## 支持语义（受控子集边界）

flex row/column、Fixed/Auto 尺寸（px）、padding（content-box）、主轴 gap、
`flex-grow` + `flex-basis:0%/0px`（映射 Fraction，basis-0 分配语义）、
嵌套容器、文本叶子（仅本地 fixtures）。

转换期过滤的不支持特性（转换器逐条报告原因）：border/margin/min-max 尺寸、
% 尺寸、align-items（stretch 以外）、align-self/justify-content、flex-wrap、
reverse 方向、position（absolute 除根外）、aspect-ratio、text 叶子（上游
期望依赖 taffy 测试闭包，非 CSS）、非整数期望（rounding 语义）。

## 统计口径（验收：通过/豁免/不支持分别计数）

- 上游候选 37 → 转换成功 22（15 个不支持，原因见转换器输出）；
  本地文本用例 3；合计 25。
- 纯函数路径：**pass=12**，**known_fail=13**（豁免清单）。
- 缓存路径（`Layout.solve_cached`）：25/25 与纯函数路径几何一致。
- 不支持：15 个（转换期过滤，未进入 oracle）。

## known-failures 政策

1. 豁免条目必须带**具体语义缺口原因**（不是"先跳过"）。
2. 豁免条目一旦开始通过，spec 立即报 `EXPIRED-KNOWN-FAIL` 并**强制要求
   清除该条目**（不允许静默放宽，AGENTS.md 不变量 8）。
3. 当前两类缺口：
   - **交叉轴 stretch**（10 个）：taffy `align-items` 默认 stretch——子项
     拉伸到容器交叉轴；内核 `resolve_cross` 对 Auto 按内容测量。
     Kit::Container 层有 Stretch 语义；内核层是否补齐需另立项决策。
   - **溢出钳制**（3 个）：内核 `constraints.constrain` 把 Auto 尺寸钳到
     约束上限（`spec/layout_spec.cr` 钉住的行为），taffy 允许子项溢出容器。

## 敏感性（验收：破坏规则必须失败）

临时破坏 `resolve_measure` 的 Fixed 分支（×0.5）实测：pass 12→2、
10 个 fixture 失败、spec 失败——套件对内核回归敏感，不是恒绿装饰。

## 命令

```bash
# 重新转换（改过滤规则或上游子集时）
crystal run tools/layout_fixture_convert.cr

# 运行 oracle（随 crystal spec 全量执行）
crystal spec spec/layout_oracle_spec.cr
```
