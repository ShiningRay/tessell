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
- 与 research 既有实测结论无冲突；原未复测项中“`Parallel.new(name,size,&)` 负例”与“Parallel 迁移观测”已于 task-23（W3-3）补充样本证据（见下节）；其余仍 `[未验证]`。

## 负例与迁移观测（task-23 / W3-3，C1 补证）

- 采集时间（本地）：2026-11-12 18:11:27 +08:00（会话记录）；HEAD（工作区基线）：`602a52533592a12db6a8b1058768003be604e1ca`
- 环境：`Crystal 1.22.1 [23828b0a40] (2026-10-23), LLVM 23.1.3, Default target x86_64-w64-windows-gnu`，`C:\msys64\ucrt64\bin\crystal.exe`，PATH 含 `C:\msys64\ucrt64\bin`

### A) `Parallel.new(name,size,&)` 编译期负例（API 形状）

- 探针：`examples/m0_parallel_block_neg.cr`（文件头注明“本文件预期编译失败，仅作负例证据”，故意不可编译）

命令：

```powershell
$env:PATH = "C:\msys64\ucrt64\bin;" + $env:PATH
Push-Location "C:\Users\ShiningRay\projects\ShiningRay\tessell"
& "C:\msys64\ucrt64\bin\crystal.exe" build examples/m0_parallel_block_neg.cr 2>&1
"BUILD_EXIT=$LASTEXITCODE"
Pop-Location
```

原始输出（含 stderr）：

```text
BUILD_EXIT=1
[stderr]
crystal.exe : Showing last frame. Use --error-trace for full trace.
所在位置 行:1 字符: 225
+ ... $env:PATH"; & "C:\msys64\ucrt64\bin\crystal.exe" build examples/m0_pa ...
+                 ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    + CategoryInfo          : NotSpecified: (Showing last fr...for full trace.:String) [], RemoteException
    + FullyQualifiedErrorId : NativeCommandError

In examples\m0_parallel_block_neg.cr:5:41

 5 | par = Fiber::ExecutionContext::Parallel.new("w", 4) { }
                                             ^--
Error: 'Fiber::ExecutionContext::Parallel.new' is not expected to be invoked with a block, but a block was given
```

- 关键错误原文行：`Error: 'Fiber::ExecutionContext::Parallel.new' is not expected to be invoked with a block, but a block was given`（`examples\m0_parallel_block_neg.cr:5:41`）
- EXITCODE：`1`（非 0，符合预期）

### B) Parallel 迁移观测样本

- 探针：`examples/m0_parallel_migrate.cr`（8 fibers × 3 次 yield，记录每 fiber 的 tid 序列并汇总）

命令：

```powershell
$env:PATH = "C:\msys64\ucrt64\bin;" + $env:PATH
Push-Location "C:\Users\ShiningRay\projects\ShiningRay\tessell"
& "C:\msys64\ucrt64\bin\crystal.exe" run examples/m0_parallel_migrate.cr 2>&1
"EXIT=$LASTEXITCODE"
Pop-Location
```

原始输出：

```text
fiber=0 tids=2213146606640,2213146606224,2213146606640 migrated=true
fiber=1 tids=2213146606640,2213146606224,2213146606640 migrated=true
fiber=2 tids=2213146606640,2213146606224,2213146606224 migrated=true
fiber=3 tids=2213146606224,2213146606224,2213146606640 migrated=true
fiber=4 tids=2213146606640,2213146606640,2213146606224 migrated=true
fiber=5 tids=2213146606640,2213146606640,2213146606224 migrated=true
fiber=6 tids=2213146606640,2213146606640,2213146606224 migrated=true
fiber=7 tids=2213146606224,2213146606640,2213146606224 migrated=true
migrated_any=true fibers=8 migrated_fibers=8 yields=3
EXIT=0
```

- 结论：`migrated_any=true`（fibers=8, migrated_fibers=8, yields=3）。

### 说明与边界

- **编译期 API 形状已证**：`Fiber::ExecutionContext::Parallel.new(name, size, &block)` 形式在当前环境（Crystal 1.22.1）下被编译器拒绝，错误原文与 capabilities.md 记录一致。
- **迁移观测为单次样本**：本次运行观察到 fiber 在不同系统线程间迁移（`migrated_any=true`），但**仅为单次样本**，不得据此写成“总会迁移”或反向写成“不会迁移”；迁移行为受调度器/负载/版本影响。[未验证：多次/长时/不同负载下分布]
- 负例文件 `examples/m0_parallel_block_neg.cr` 故意不可编译，属证据文件；`crystal spec` 不编译 `examples/`（task-23 验证：`crystal spec` 仍 `6 examples, 0 failures, 0 errors, 0 pending`，SPEC_EXIT=0）。
