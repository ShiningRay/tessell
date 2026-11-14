# 仓策略

## 当前结论

Kit 留在 `tessell` 同仓，通过 `require "tessell/kit"` 提供可选入口；核心入口 `require "tessell"` 不聚合 Kit。Kit 单向依赖核心公开 API，核心不得依赖 Kit。

## 为什么不是现在拆仓

- 核心与 Kit 会同频修改：主题 token、绘制原语、事件模型、a11y role 都还在补。
- 单一 CI、issue、版本与证据链更容易保持“组件行为 + 核心契约”一致。
- Shards 没有为同仓多 shard 独立发版设计；立即拆仓会引入双仓版本矩阵与 path 依赖联调。

## 拆仓触发条件

至少满足两项，且确有独立发布需求：

1. 有仓外消费者要求 Kit 与核心不同发布节奏。
2. 核心 API 连续两个 Kit 版本无需改动。
3. Kit 需要独立维护者、issue/PR 分流或权限。
4. 已定义并实测 `tessell` 与 `tessell-kit` 的版本兼容矩阵。
5. 已在临时消费者项目验证 path/Git 依赖、构建、测试、发布。

## 边界检查

- `src/tessell.cr` 不 require `kit`。
- `src/tessell/kit.cr` 只 require 核心公开入口与 Kit 子模块。
- 组件不得 require `render/gl`、平台 FFI 或示例私有路径。
- 核心新增 API 必须先在核心 spec 中验证，再被 Kit 使用。

## 未来迁移

拆仓时优先保留 Kit 路径历史（`git filter-repo` 或等价方案），主仓保留迁移提交与说明。迁移前不承诺新仓名可用，也不复制不完整历史冒充完整迁移。
