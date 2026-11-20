# 第三方组件包分发约定（issue #68）

> 定位：约定而非 registry——不建包索引/插件市场（#57 结论）；Crystal
> shards 生态本身没有集中索引，分发靠 GitHub + shards 依赖解析。

## 命名与入口

- 包名 `tessell-<name>`（如 `tessell-badge`），组件类名自由（建议
  `TessellBadge::Badge` 这类 `tessell-<name>::<Class>` 命名空间，避免
  与 Kit 内置类冲突）。
- 入口文件 = 包名：`require "tessell-badge"`（shards 约定，src/<name>.cr）。

## 版本约束

- 依赖本仓：`github: ShiningRay/tessell` + `version: ~> <minor>`（如
  `~> 0.4`——minor 升级才破坏 API，patch 不依赖）。
- 本地开发：`path:` 依赖指回本仓克隆。

```yaml
dependencies:
  tessell:
    github: ShiningRay/tessell
    version: ~> 0.4
```

## 必测门槛（模板自带）

`templates/kit-component/` 是可运行的起点（shard.yml + 组件 + spec）：

- 组件四件套 + a11y 元数据 + dispose 释放（AGENTS #9）；
- spec 覆盖 measure/arrange、emit 与 visible 双守卫、PaintList op 流、
  dispose、主题 token 差异——对应
  [component-contract.md](component-contract.md)「测试门槛」；
- 一键验证：`bash tools/kit_template_verify.sh`——拷贝模板到临时目录、
  path 依赖指回本仓、`shards install && crystal spec`，退出码 0 且输出
  `KIT_TEMPLATE_VERIFY verify=pass`。

## 发布清单

1. `spec` 全绿（模板门槛 + 自有组件测试）。
2. `README` 写明依赖 tessell 版本、支持级别（L0–L3，诚实口径，
   见 [cross-platform-plan](../cross-platform-plan.md)）。
3. 打 GitHub release tag（`v0.x.y`）；shards 用户锁 `~>` 约束。
4. 不宣称平台 provider / 完整 IME / 打包完成——本库未交付的能力
   第三方包同样不得宣称。

## 关联

- 三条路径与常见坑：[extending.md](extending.md)（#67）
- 可覆写切面：[component-contract.md](component-contract.md)（#66）
- 机制调研：[../research/component-extension-survey.md](../research/component-extension-survey.md)（#57）
