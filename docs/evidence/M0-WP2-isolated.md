# M0-WP2 Isolated+Channel 仓内探针实测证据

- 任务：`task-3` / `M0-WP2`（对应 `docs/plan.md` B.1、`docs/plan-execution.md` EX-W1-02）
- 仓库：`C:\Users\ShiningRay\projects\ShiningRay\tessell`
- 采集时间（本地）：`2026-11-12 16:15:09 +08:00`（证据整理时记录）
- `HEAD`：`981e7a9f0d401170472eb1e52d90b8338dc4d577`
- 运行环境：Windows（ucrt64），Crystal `1.22.1 [23828b0a40] (2026-10-23), LLVM 23.1.3, Default target x86_64-w64-windows-gnu`（`C:\msys64\ucrt64\bin\crystal.exe`）

## 探针实现

- 文件：`examples/m0_isolated.cr`
- 关键 API：
  - UI 侧：`Fiber::ExecutionContext::Isolated.new("tessell-ui") { ... }`
  - 跨 context 通信：`Channel(Int32)` 默认 context 与 Isolated 间收发（`41 -> 42`）
  - 并行同步：`Fiber::ExecutionContext::Parallel.new("worker", 4)` + `spawn` + `Mutex#synchronize` 累加 4 次
  - 采样：在 Isolated 内同一 fiber 两次记录 fid/tid（`Fiber.yield` 后）并与 main 比较

## 执行命令

```powershell
cd C:\Users\ShiningRay\projects\ShiningRay\tessell
crystal run examples/m0_isolated.cr
```

## 原始输出

```text
main_fid=2061926027008 main_tid=2061926022816 iso_fid=2061926026208 iso_tid=2061926022192 same_fiber=true same_tid=true diff_from_main=true cross_iso=42 mutex_val=4
```

## 退出码

```text
0
```

## 结论对照（`docs/research/crystal-capabilities.md`）

| 检查项 | 本次结果 | 对照结论 | 说明 |
|---|---|---|---|
| `Isolated.new(name,&)` 可用且独占线程样本 | `diff_from_main=true`，`same_fiber=true`，`same_tid=true`（两次采样） | 与 capabilities.md:L9 一致（样本中 Isolated 纤程运行在独立于主线程的系统线程） | 本次为新样本，id 值与历史探针不同属正常 |
| `Channel(Int32)` 跨默认/Isolated context 收发 | `cross_iso=42` | 与 capabilities.md:L14 一致 | — |
| `Parallel.new("worker", 4)` + `Mutex#synchronize` 跨 fiber 同步 | `mutex_val=4` | 与 capabilities.md:L14/L15 方向一致（Mutex 可同步） | — |
| `Parallel.new(name,size,&)` 编译期报错 | `[未验证]`（本探针未触发该构造） | capabilities.md:L9 记录“not expected to be invoked with a block” | 本轮未复测该负例 |
| Parallel 迁移 `migrated_any=false` 仅样本 | `[未验证]`（本探针未做迁移采样） | capabilities.md:L15,L18 限制照抄，不得写成“不会迁移” | 本轮未复测 |
| ExecutionContext 重载穷举 | `[未验证]` | capabilities.md:L18 | — |

## 总结

- M0-WP2 仓内探针：**通过（本机实测）**。输出含全部要求 token，`diff_from_main=true`、`cross_iso=42`、`mutex_val=4`，退出码 0，自然退出。
- 与 research 既有实测结论无冲突；未复测项已标 `[未验证]`。
