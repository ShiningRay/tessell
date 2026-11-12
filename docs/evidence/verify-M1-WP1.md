# verify-M1-WP1：M1-WP1 布局内核独立核验报告

- 核验角色：大理寺卿（dalisi-qing，独立核验），受首辅 lead 节制
- 核验任务：`task-26`「M1-WP1 核验：布局内核纯函数性/两遍语义/单测有效性」
- 核验对象：`src/tessell/layout.cr`、`spec/layout_spec.cr`、`src/tessell.cr`（task-25 交付，未 commit）
- 依据：`docs/research/layout-two-pass.md`（240 行，EX-W1-08，9 条单测计划）、`docs/plan.md` M1-WP1
- 核验时间（本地）：2026-11-12 18:53:27 +08:00 ～ 2026-11-12 18:57:00 +08:00（Asia/Shanghai，会话采样）
- 仓库：`C:\Users\ShiningRay\projects\ShiningRay\tessell`
- HEAD：`eeee8e6`（`docs: 回填 W3 提交 hash`）
- OS/Arch：`Microsoft Windows NT 10.0.26300.0` / `AMD64`
- Crystal：`C:\msys64\ucrt64\bin\crystal.exe`，`Crystal 1.22.1 [23828b0a40] (2026-10-23)`，`LLVM 23.1.3`，`Default target: x86_64-w64-windows-gnu`
- 命令 PATH 前置：`$env:PATH="C:\msys64\ucrt64\bin;"+$env:PATH`

## 0. 范围与边界

- 唯一写入：本报告 `docs/evidence/verify-M1-WP1.md`。**未修改** `src/tessell/layout.cr`、`spec/layout_spec.cr`、`src/tessell.cr`、`src/tessell/geometry.cr` 及其他源码/证据。
- `git status --short`（核验时）：
  - task-25 范围：` M src/tessell.cr`、`?? spec/layout_spec.cr`、`?? src/tessell/layout.cr`
  - 预存 untracked（非本次引入，未触碰）：`docs/evidence/M0-WP4-*.md`、`docs/evidence/M0-WP5m-metrics.md`、`docs/evidence/M0-gate.md`、`docs/evidence/M0-summary.md`、`docs/evidence/verify-W2-*.md`、`docs/evidence/W3-iteration-log.md`、`docs/research/layout-two-pass.md`、`examples/m0_*`、`tools/` 等（工作区原有未跟踪产物）。
  - 本报告写入后新增：`?? docs/evidence/verify-M1-WP1.md`（唯一新增）。
- 文件行数（`Get-Content ... | Measure-Object -Line`）：`src/tessell/layout.cr` 190 行、`spec/layout_spec.cr` 136 行、`src/tessell.cr` 17 行（与 m00244 提及的 163/121 行存在计数差异，以当前文件实测为准）。

## 1. 重跑命令与原始结果

命令：
```powershell
$env:PATH="C:\msys64\ucrt64\bin;"+$env:PATH
Set-Location "C:\Users\ShiningRay\projects\ShiningRay\tessell"
crystal spec
echo "SPEC_EXITCODE=$LASTEXITCODE"
crystal build src/tessell.cr
echo "BUILD_EXITCODE=$LASTEXITCODE"
```

原始输出：
```
===CRYSTAL_SPEC===
..................

Finished in 366 microseconds
18 examples, 0 failures, 0 errors, 0 pending
SPEC_EXITCODE=0
===CRYSTAL_BUILD===
BUILD_EXITCODE=0
```

- `crystal spec`：**18 examples, 0 failures, 0 errors, 0 pending，EXITCODE=0**（≥15，满足）。
- `crystal build src/tessell.cr`：**EXITCODE=0**。

## 2. 逐项核验

### 2.1 纯函数性 / 无全局状态 / 无禁用依赖

- 源码审查（`src/tessell/layout.cr`）：定义 `enum Direction`、`struct LayoutNode`、`struct LayoutBox` 与 `module Tessell::Layout` 的类方法 `measure/arrange/solve` 及私有 helper；无 `@@` 类变量、无全局可变状态、无 `$` 全局变量标记（`grep '^(\s*@@|@@)|class_property|...'` 无输出）。
- 无时间/随机/IO/进程依赖：`grep` 对 `Platform|FFI|LibC|Render|Time\.|Random|IO\.|File\.|Process\.|sleep` 在 `src/tessell/layout.cr,spec/layout_spec.cr,src/tessell.cr` 的命中仅为注释：
  - `src/tessell/layout.cr:4`：`# 约束：不依赖 widget/UI/FFI；相同输入得到相同输出；无全局状态。`（设计约束说明）
  - `src/tessell.cr:5`：`#       → render（DrawList 与后端）→ platform（窗口/输入）→ widget / dsl`（架构分层注释）
  无实际 `Platform/FFI/LibC/Render` 调用或 require。
- 行为：`measure` 返回新 `Size`（`:66,77`），`arrange/solve` 返回新 `LayoutBox/Rect`（`:91,113,120`）；过程中创建的 `child_sizes/child_boxes/result` 为方法内局部数组（`:72,95,98,150`），不写入共享状态。输入 `LayoutNode`（struct，含 `Array(LayoutNode)` children 引用）在求解中不被修改。给定相同输入与约束，路径确定。
- 单测证据：`spec/layout_spec.cr:101-111` “pure function: same input yields same output” 对同一 `node/c` 连续 `measure` 与 `solve`，断言 `width/height` 相等。
- **结论：通过**（纯函数语义成立；无全局可变状态/时间随机/IO/FFI/UI/Platform/LibC/Render 实际依赖）。

### 2.2 两遍语义与 Dimension 处理

- **Pass A `measure(node, constraints)`**（`layout.cr:58-79`）：约束下行、尺寸上行。
  - 叶子（无子）：按约束可用空间解析 `width/height` Dimension + `padding` 得尺寸，`constraints.constrain` 后返回（`:62-66`）。
  - 容器：计算内区可用尺寸（减 padding，`:69-71`）构造子约束，下发并 `children.map { |ch| measure(ch, child_constraints) }` 收集子尺寸（`:72`），聚合 intrinsic（Vertical 取子宽 max、子高 sum；Horizontal 反之，`:136-145`），按父可用空间与 intrinsic 解析自身 Dimension + padding，`constrain` 返回（`:74-77`）。
- **Pass B `arrange(node, rect)`**（`layout.cr:82-114`）：给定最终 Rect，自顶向下写回位置/尺寸。
  - 计算 content Rect（origin 加 padding.left/top，尺寸减 padding 且 clamp，`:83-88`）；叶子返回 `LayoutBox(rect, [])`（`:90-92`）。
  - 容器：以 content 尺寸构造子约束重新 `measure` 子节点（`:94-95`），`resolve_main` 按主轴分配 Fixed/Auto/Fraction（`:147-184`），逐子计算 cross 尺寸与 child rect，递归 `arrange(ch, child_rect)` 收集 `LayoutBox`（`:98-113`）。
- **`solve`**（`:117-120`）：`measure` → `constraints.constrain(size)` → `arrange` 到最终 Rect，组合两遍。
- **Fixed/Auto/Fraction**：`resolve_measure`（`:125-134`）Fixed 取值、Fraction 按有限 avail 乘 weight（avail 非有限则 0）、Auto 取 intrinsic；`resolve_main`（`:147-184`）先累加 Fixed/Auto 基线与 Fraction 权重，剩余空间按 weight 比例分配 Fraction；`resolve_cross`（`:186-196`）按交叉轴维度解析。spec 覆盖 Fixed 叶子/容器子、Auto 叶子、Fraction 水平分配（`:41-47,86-99`）。
- **结论：通过**（两遍职责与数据流清晰：measure 下约束上尺寸，arrange 按最终 rect 落位；Fixed/Auto/Fraction 路径具备）。

### 2.3 约束正确性（padding、clamp、零尺寸/溢出/嵌套）

- **Padding**：measure 中尺寸 `+ node.padding.horizontal/vertical`（`:65,75-76`）；子测量与 arrange 内容区 `avail/content` 减 `padding.horizontal/vertical`（`:69-70,86-87`）；arrange 内容 origin 偏移 `padding.left/top`（`:84-85`）。spec “nested padding accumulates insets” 验证 all(4) => 总 18x18、子 origin (4,4)（`:49-59`）。
- **父约束裁剪**：`measure` 返回前 `constraints.constrain(...)`（`:66,77`）；`solve` 再次 `constraints.constrain(size)`（`:119`）；`resolve_main` 对 Fixed 子项 `clamp(0, avail_main)`（`:159`），最终 `result.map!` 非负化（`:182`）；`clamp_avail` 保护负可用空间（`:198-200`）。
- **覆盖情况**：零尺寸（`:69-77`）、单子溢出/宽度被父约束裁剪（`:79-84,34-39`）、嵌套 padding（`:49-59`）均有 spec；垂直/水平主轴排列有 spec（`:113-135`）。
- **结论：通过**（padding 计入/扣减与约束 clamp 行为与 spec 一致）。

### 2.4 单测有效性与空泛断言

- `spec/layout_spec.cr` 共 **12 个 `it` 示例**（计数自文件 `:14,27,34,41,49,61,69,79,86,101,113,125`）；结合仓库其他 spec 全量 `crystal spec` 为 **18 examples**。
- `grep 'should_not be_nil' spec/layout_spec.cr`：**无匹配**。断言均为具体数值/布尔/容差比较（`eq`、`be_true` 配合 `close?` EPS=1e-4）。
- 每例均对 size/rect/origin 或相等性给出可判定期望；非空泛。

### 2.5 边界与代码真实性抽查

- `src/tessell.cr` 仅增加 `require "./tessell/layout"`（`:9`），与 task-25 最小改动要求一致；未改 `geometry.cr`。
- git 变更仅 task-25 三文件（`M src/tessell.cr`、`?? spec/layout_spec.cr`、`?? src/tessell/layout.cr`）+ 预存 untracked；无其他源码修改。
- 实现为真实计算（非硬编码返回常量伪装）：分支/聚合/比例分配逻辑依赖输入，spec 多组不同输入得到对应结果（见 §3 手算复核）。

## 3. `docs/research/layout-two-pass.md` 9 用例覆盖映射

| 研究用例（layout-two-pass.md:185-228） | 覆盖状态 | 映射到 spec/layout_spec.cr（行号/标题）与说明 |
|---|---|---|
| 1 固定尺寸叶子节点 | **覆盖** | `:14` “fixed-size leaf node measures and arranges (use case 1)”：measure 得 (100,20)，solve 后 rect origin/size 正确。 |
| 2 文本单行测量与布局 | **未覆盖（超出 WP1）** | 需 `TextNode`+`TextMeasurer` 及缓存命中语义（plan M1-WP2 / 研究 `:190-193`）；当前 layout 内核无文本测量接口与桩。 |
| 3 文本换行（受限宽度） | **未覆盖（超出 WP1）** | 需 measurer 按 `max_width` 返回换行高度（` :195-198`）；WP1 无文本依赖。注：spec `:34` 标题含“wrapping under constrained width (use case 3)”但实际为**容器/子在受限宽度下被 clamp**（子 Fixed 80 在 max_w=50 下容器测得 50），非研究用例 3 的文本换行。 |
| 4 百分比/弹性尺寸容器（依赖父最终空间） | **覆盖（核心语义）** | `:41` “fraction sizing depends on parent final rect (use case 4)”：Horizontal 容器内 Fraction(1.0) 子在 200 宽最终 rect 下得 200；另 `:86` 验证 1:2 比例分配与总和（与弹性/余量分配相关）。 |
| 5 嵌套 Padding | **覆盖** | `:49` “nested padding accumulates insets (use case 5)”：总尺寸 18x18，子 origin (4,4)。 |
| 6 约束冲突与 clamp 行为 | **覆盖** | `:61` “constraint conflict clamps size (use case 6)”：250x50 在 max(100,100) 下 clamp 为 100x50。 |
| 7 失效重算与缓存复用 | **未覆盖（超出 WP1）** | 需 dirty 标记/局部重算与缓存命中观测（` :215-218`，衔接 M1-WP3/Core）；layout 为无状态纯求解器，未提供失效调度。 |
| 8 稳态零分配（layout 热路径） | **未覆盖（超出 WP1）** | 需 `GC.collect→disable→bytes_since_gc` 稳态差值=0（` :220-223`，M1-WP5）；实现中 `children.map`/`Array`/`LayoutBox` 分配存在且 `layout.cr:20` 标注 `TODO(M1-WP5)`，spec 无分配门禁。 |
| 9 浮点确定性 / epsilon 比较 | **部分覆盖** | `:86-99` 使用 `close?(…, EPS)`（`EPS=1.0e-4_f32`）验证 Fraction 比例与总和；`:101-111` 验证同输入重复 measure/solve 结果相等（确定性）。未显式覆盖跨运行/更复杂浮点累积场景，但 epsilon 比较与确定性意图已体现。 |

**小结**：WP1 核心几何/约束/两遍求解用例（1,4,5,6 及 9 的 epsilon/确定性要点）已覆盖；2,3,7,8 依赖后续 WP（M1-WP2 文本测量、M1-WP3 失效/retained、M1-WP5 零分配）或更高层集成，属范围外未覆盖而非本实现回归。

## 4. 手算复核（2 例）

### 4.1 嵌套 padding（`spec/layout_spec.cr:49-59`）
- 输入：`inner = Fixed(10,10)`；`outer = padding Insets.all(4.0)` 包裹 `inner`，约束 `max(100,100)`，origin `(0,0)`。
- measure：inner 尺寸 `10+0=10, 10+0=10`（无 padding）；outer 为容器，`inner_w=100-8=92, inner_h=92`，子测得 10x10，intrinsic_w=max(10)=10, intrinsic_h=sum(10)=10；outer 尺寸 `resolve(Auto,100,10)+8=18`，`resolve(Auto,100,10)+8=18` => **(18,18)**。
- arrange：content rect = `(0+4, 0+4, 18-8, 18-8) = (4,4,10,10)`；子 fixed 10x10，child rect `(4,4,10,10)`。
- 结论：与断言 `sz.width==18, sz.height==18, child origin==(4,4)` 一致。**正确**。

### 4.2 Fraction 1:2 分配（`spec/layout_spec.cr:86-99`）
- 输入：Horizontal 容器，子 a=`Fraction(1.0),h=10`，b=`Fraction(2.0),h=10`，约束 `max(300,50)`。
- measure 子（content 宽 300）：Fraction 在 measure 中 `avail*weight` => a 宽 300, b 宽 600（各自按子约束 max 300 视上下文；容器 intrinsic_w = sum(child widths) 经子约束后为 300+300=600 再被容器约束 clamp 为 300；arrange 决定最终分配）。
- arrange：`avail_main=300`，无 Fixed/Auto 主轴基线，`base_sum=0, frac_weight_sum=3, remaining=300`；a=`300*(1/3)=100`，b=`300*(2/3)=200`；cursor 从 x=0 依次放置 => a rect `(0,0,100,10)`，b rect `(100,0,200,10)`。
- 结论：与断言 `close(a_w,100), close(b_w,200), close(sum,300)` 一致。**正确**（`close?` 容差 EPS=1e-4）。

## 5. 缺陷与观察清单（P1/P2/P3）

| ID | 级别 | 位置 | 描述 | 影响/说明 |
|---|---|---|---|---|
| 观察-1 | P3 | `src/tessell/layout.cr:20,72,95,98,150` | 热路径存在分配（`children.map`、`Array(LayoutBox).new`、`Array(Float32).new` 等），`arrange` 再次 measure 子节点；代码已标注 `TODO(M1-WP5): 复用/零分配`。 | 功能正确性不受影响；与 M1-WP5 “稳态零分配”目标尚未对齐（属后续 WP），本 WP 未声明达成。 |
| 观察-2 | P3 | `src/tessell/layout.cr:26,64` | `LayoutNode.margin` 字段存在但 measure/arrange 未参与计算（注释称“margin 不计入尺寸，由 arrange 处理间距”但未实现间距分配）。spec 未覆盖 margin。 | 可能为预留字段；当前 API 对外可见但无效，建议在后续 WP 明确语义或实现/移除，避免误用。 |
| 观察-3 | P3 | `docs/research/layout-two-pass.md` 用例 2,3,7,8 | 研究计划中的文本单行/换行、失效重算、稳态零分配在本 WP 未覆盖。 | 依赖 M1-WP2/M1-WP3/M1-WP5；非本交付回归。 |
| 观察-4 | P3 | `spec/layout_spec.cr:34` 标题 vs 研究用例 3 | 用例标题 “wrapping under constrained width (use case 3)” 测的是约束裁剪而非研究文档用例 3 的“文本换行”。 | 表述易混淆，覆盖矩阵需按实际行为映射（已在 §3 说明）。 |
| 观察-5 | P3 | 交付说明与实测 | m00244 描述行数/示例数（163/121 行、14 examples）与实测（190/136 行、layout spec 12 its、全量 18 examples）有偏差。 | 以本次实测与 `crystal spec` 原始输出为准；不影响功能结论。 |

- **P1**：无。
- **P2**：无。

## 6. 最终裁定

**裁定：PASS**

**理由**：`src/tessell/layout.cr` 实现了两遍布局内核（measure 约束下行/尺寸上行，arrange 按最终 Rect 自顶向下落位，`solve` 组合）并支持 Fixed/Auto/Fraction、padding 与约束 clamp；源码无全局可变状态与 Platform/FFI/LibC/Render/IO/时间/随机实际依赖，具备纯函数语义且有同输入同输出用例。`crystal spec` **18 examples, 0 failures, 0 errors, 0 pending（EXITCODE=0）**，`crystal build src/tessell.cr` **EXITCODE=0**；断言具体有效、无 `should_not be_nil`。手算复核嵌套 padding 与 Fraction 1:2 分配与实现/测试一致。研究计划用例 2,3,7,8 及 margin/零分配完善属于后续 WP（M1-WP2/WP3/WP5）范围，记为 P3 观察/待办，不构成 WP1 功能缺陷。边界合规（仅 task-25 相关代码变更 + 本报告）。
