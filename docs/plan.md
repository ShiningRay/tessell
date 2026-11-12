# Tessell 方案与规划（A. Design + B. WBS）

> 文档职责：本文件是 **A 方案（Design）** 与 **B 规划（WBS）** 的权威主体，回答“是什么、怎么设计、拆成哪些工作包”。  
> 不负责什么：不写阶段门禁细节与并行/平台路线全貌（见 [roadmap.md](roadmap.md)），不写本轮逐任务执行清单、复盘与裁剪排期细节（见 [plan-execution.md](plan-execution.md)）。  
> 与另两份的关系：B 节工作包编号（`M*-WP*`）供 [roadmap.md](roadmap.md) 引用门禁/并行与 [plan-execution.md](plan-execution.md) 落地执行；执行与路线若调整，须回写本文件对应工作包定义。

**状态与证据边界**  
- 草拟依据：[architecture.md](architecture.md)（236 行）、仓库现状、本机任务输入；翰林调研 [research/ecosystem.md](research/ecosystem.md) 与 [research/crystal-capabilities.md](research/crystal-capabilities.md)（本机实测 Crystal 1.22.1 / Windows ucrt64，探针脚本位于 `%TEMP%\tessell-probe\`，2026-11-12 会话实测）已到货并纳入 [来源: research/crystal-capabilities.md:L1-L6,L19]。  
- 证据标注：`[来源: architecture.md:Lx]` / `[来源: 仓库:路径:行]` / `[来源: research/ecosystem.md:Lx]` / `[来源: research/crystal-capabilities.md:Lx]` / `[来源: 本机实测:...]` / `[来源: 任务输入]` / `[来源: 推演]` / `[待证据]` / `[未验证]`。未实测不得写成实测；ecosystem.md 中“未能核实/未实测/许可证未确认”项照抄其限定，不得升级 [来源: research/ecosystem.md:L6,L97-L105]。  
- 时间口径：相对周 `W1/W2…`，禁止绝对日期。工作量口径：**人日（pd）区间，单人全职（每周 5 天）**，熟悉 Crystal 与图形 API 且可获得必要原生库二进制时的估算；不确定性显式保留 `[未验证]`。  
- 禁止编造：日期、性能数字、star 数、人名均不编造；引用 research 已记录事实时保留原限定。

---

## 0. 输入与现状基线

| 输入 | 路径 | 关键事实 | 来源 |
|---|---|---|---|
| 战略架构 | [architecture.md](architecture.md) | 自绘 retained 树 + 声明式响应式；Isolated UI；M0–M4；风险与反目标 | [来源: architecture.md:L25-L236] |
| 入口与上下文 | [../src/tessell.cr](../src/tessell.cr) | 聚合 `version/geometry`；`ui_context` 返回 `Fiber::ExecutionContext::Isolated.new("tessell-ui")` | [来源: 仓库:src/tessell.cr:L7-L15] |
| 几何骨架 | [../src/tessell/geometry.cr](../src/tessell/geometry.cr) | `Point/Size/Rect/Insets/Color/Constraints` 为 struct；`Dimension = Auto|Fixed|Fraction` union | [来源: 仓库:src/tessell/geometry.cr:L1-L142] |
| 现有测试 | [../spec/geometry_spec.cr](../spec/geometry_spec.cr) | 覆盖 Rect/Constraints/Insets/Point | [来源: 仓库:spec/geometry_spec.cr:L1-L49] |
| 构建元信息 | [../shard.yml](../shard.yml) | `crystal: ">= 1.21.0"`，无运行时依赖 | [来源: 仓库:shard.yml:L10-L20] |
| 项目状态 | [../README.md](../README.md) | 早期设计阶段，M0 未完成，不可用于生产 | [来源: 仓库:README.md:L16-L18] |
| 命名 | [naming.md](naming.md) | 命名空间 `Tessell`，模块 `Layout/Render/Platform/Widget`，前缀 `TESSELL_` | [来源: 仓库:docs/naming.md:L34-L39] |
| 生态调研 | [research/ecosystem.md](research/ecosystem.md) | Windows 候选/取舍、OpenGL/WGL 优先、文本/2D 绑定现状、分发约束、未核实清单 | [来源: research/ecosystem.md:L1-L114] |
| 能力调研 | [research/crystal-capabilities.md](research/crystal-capabilities.md) | 本机实测（Crystal 1.22.1 / Windows ucrt64）：ExecutionContext 可用形态与 Isolated 线程证据、GC.stats/collect/零分配可测性、struct vs class 可测方法、宏编译样本、user32 FFI、Channel/Mutex 跨 context、Parallel 迁移样本与未穷举项 | [来源: research/crystal-capabilities.md:L7-L19] |
| 开发机 | 任务输入 + 本机实测 | Windows + Crystal 1.22.1（ucrt64）；capabilities 探针已实测，本文其他命令未逐一复跑 | [来源: 任务输入; research/crystal-capabilities.md:L3-L5] |

**关键矛盾（必须正面处理）**：architecture.md 平台优先级 macOS → Linux → Windows，且 M0 通过条件写为“macOS 窗口显示中文与 Emoji” [来源: architecture.md:L57,L217]；开发机仅 Windows。解法与 M0-Windows 验证路径、取舍及“是否动摇第 3 节定案”的结论见 [roadmap.md](roadmap.md) 的 C.3；本文件在 A.4–A.6/B 节保证设计与工作包可在 Windows 先行验证下推进且不破坏跨平台抽象 [来源: 推演]。

---

## A. 方案（Design）

### A.1 分层与模块目录：职责边界与依赖方向

| 层 | 命名空间/目录（建议） | 职责边界 | 允许依赖 | 禁止依赖 | 来源 |
|---|---|---|---|---|---|
| Geometry / Value Types | `Tessell`（`src/tessell/geometry.cr`） | `Point/Size/Rect/Insets/Color/Constraints/Dimension` 等纯值类型与几何计算；脏矩形并集等基础操作 | Crystal stdlib 基础 | UI 树、平台句柄、后端状态 | [来源: architecture.md:L105,L151,L187; 仓库:src/tessell/geometry.cr:L1-L142] |
| Layout Kernel | `Tessell::Layout` | 两遍布局（约束下行、尺寸上行）、纯函数求解、文本测量缓存接口；输入输出为结构化数据/缓冲 | Geometry、抽象 `TextMeasurer` | Widget 可变实例、平台/GPU C 调用 | [来源: architecture.md:L97,L151-L156; docs/naming.md:L35] |
| Core / Retained Tree | `Tessell::Core`（或 `Tessell` 子模块） | Retained 节点树、失效传播（Layout/Paint/CompositeOnly）、事件路由、命中测试、焦点、帧调度 | Layout、Render 抽象、Platform 事件抽象、Channel | 业务 I/O、散落的窗口/图形 API 调用 | [来源: architecture.md:L95-L99,L137-L145,L160] |
| Render | `Tessell::Render` | DrawList/命令缓冲、批次构建、脏矩形提交抽象、字形 atlas 接口 | Geometry、后端 trait/泛型接口 | 窗口系统细节、业务逻辑 | [来源: architecture.md:L98,L160-L175; docs/naming.md:L35] |
| Text | `Tessell::Text` | HarfBuzz shaping、FreeType 栅格化/度量、缓存键与字形数据管理 | Geometry、FFI、Render atlas 抽象 | 具体平台窗口代码 | [来源: architecture.md:L107,L155,L179-L182] |
| Platform | `Tessell::Platform` | 窗口、输入、剪贴板、IME、DPI、文件对话框、事件泵；后端上下文生命周期 | OS/窗口库 FFI、Render 提交点 | Widget/DSL 业务语义 | [来源: architecture.md:L105; docs/naming.md:L35] |
| Widget | `Tessell::Widget` | 基础控件、虚拟化容器、可访问性节点同步 | Core、Layout、Render、Text 抽象 | 直接 C 平台/图形 API、业务网络/存储 | [来源: architecture.md:L92; docs/naming.md:L35] |
| DSL / State | `Tessell::DSL`、`Tessell::State` | 宏 DSL、`Signal(T)`、声明式组合与快照传递 | Widget/Core/Geometry 类型 | 后端句柄、平台可变句柄 | [来源: architecture.md:L91,L165-L168,L192] |
| App Entry | `Tessell` 顶层 | 版本聚合、`ui_context`、启动入口 | 子模块公共 API | 实现细节下沉到顶层 | [来源: 仓库:src/tessell.cr:L7-L15] |

**依赖方向（单向）**  
```text
DSL/State → Widget → Core → Render → Platform(Backend)
                ↘      ↘
              Layout   Text(抽象/FFI)
                 ↘   ↗
                Geometry  (全层可依赖)
```  
[来源: architecture.md:L90-L109,L151-L156]

**边界约束**：`Layout` 不依赖可变 widget 树；触及窗口/GL/Metal 的调用收敛于 Platform/Render 且仅在 UI Isolated context 执行；UI 与业务仅通过 Channel/不可变快照通信 [来源: architecture.md:L123-L126,L156]。

### A.2 公开 API 契约草案（关键类型签名，struct/union 选择理由）

> 设计契约草案（实现阶段可在保持不变量前提下微调）。不变量：热路径零分配可度量、布局纯函数可测、UI/业务隔离 [来源: architecture.md:L28,L151,L167]。

#### A.2.1 Geometry（已存在）

| 类型 | 关键签名/行为 | 选择理由（struct/union） | 来源 |
|---|---|---|---|
| `Point` | `x,y : Float32`; `+(other:Point):Point` | `struct` 值语义、栈分配 | [来源: 仓库:src/tessell/geometry.cr:L5-L15; architecture.md:L40,L187] |
| `Size` | `width,height : Float32`; `zero?` | `struct` | [来源: 仓库:src/tessell/geometry.cr:L17-L27] |
| `Rect` | `origin:Point`; `size:Size`; `contains?(Point)`; `union(Rect):Rect` | `struct`，命中与脏矩形纯计算 | [来源: 仓库:src/tessell/geometry.cr:L29-L59] |
| `Insets` | `top/right/bottom/left : Float32`; `horizontal/vertical` | `struct` | [来源: 仓库:src/tessell/geometry.cr:L62-L83] |
| `Color` | `r,g,b,a : Float32` | `struct` | [来源: 仓库:src/tessell/geometry.cr:L85-L93] |
| `Dimension` | `alias Dimension = Auto | Fixed | Fraction` | `union` 非法状态不可表示 | [来源: 仓库:src/tessell/geometry.cr:L95-L113; architecture.md:L193] |
| `Constraints` | `min/max width/height`; `tight(Size)`; `loosen`; `constrain(Size):Size` | `struct`，两遍布局约束 | [来源: 仓库:src/tessell/geometry.cr:L115-L142; architecture.md:L151] |

#### A.2.2 Layout（规划）

| 契约 | 建议签名（草案） | 说明 | 来源 |
|---|---|---|---|
| 布局输入节点 | `struct LayoutNode`（id、`Dimension`、padding/insets、子引用、测量请求） | 纯数据，可脱离 UI 测试 | [来源: architecture.md:L151-L156] |
| 布局结果 | `struct LayoutBox`（`Rect`/`Size`、子偏移）或预分配缓冲 | 降低每帧分配 | [来源: architecture.md:L151,L187; 推演] |
| 求解入口 | `module Tessell::Layout; def self.solve(...)` | 两遍约束下行/尺寸上行 | [来源: architecture.md:L151-L152,L156] |
| 文本测量 | `measure(font_id,size,text_hash,max_width) : Size`；缓存键 `(font_id,size,text_hash,max_width)` | 可替换桩/FFI 实现 | [来源: architecture.md:L155,L179] |

#### A.2.3 Core / Event / Invalidation（规划）

| 契约 | 建议签名（草案） | 说明 | 来源 |
|---|---|---|---|
| 失效级别 | `enum Invalidation { Layout; Paint; CompositeOnly }` | 滚动走 `CompositeOnly` | [来源: architecture.md:L160] |
| 失效标记 | `mark_dirty(kind : Invalidation)` | 最小范围传播 | [来源: architecture.md:L139,L160-L161] |
| 帧驱动 | 事件驱动唤醒，无事件睡眠 |  | [来源: architecture.md:L143] |
| 跨界消息 | 不可变 `struct/record` + `Channel(T)` | UI 不持有业务可变对象 | [来源: architecture.md:L123,L126,L167] |

#### A.2.4 Render（规划）

| 契约 | 建议签名（草案） | 说明 | 来源 |
|---|---|---|---|
| 绘制命令 | `struct DrawCmd`（几何、颜色、atlas/纹理引用、clip） | 值类型优先，批处理友好 | [来源: architecture.md:L172,L187] |
| DrawList | 可复用缓冲（`clear/reuse`） | 稳态复用 | [来源: architecture.md:L172; 推演] |
| 后端 | 泛型 `Backend`：`submit(draw_list, dirty_regions : Array(Rect))` | 编译期选择；泛型/单态化与编译期单态化开销未系统测量 [未验证: capabilities 未探泛型开销] | [来源: architecture.md:L173,L193; 推演] |
| 脏区域 | `Rect` 集合并合并后提交 | 部分提交 | [来源: architecture.md:L162,L174] |

#### A.2.5 Platform / Text（规划）

| 契约 | 建议签名（草案） | 说明 | 来源 |
|---|---|---|---|
| Window/Loop | `Platform::Window` 抽象：创建/显示/尺寸/DPI/关闭/请求重绘；事件 `poll` 或回调 | 封装 Win32/WGL 或 GLFW+OpenGL 等（见 roadmap C.3） | [来源: architecture.md:L105; research/ecosystem.md:L34-L41] |
| Text Engine | `Text::Shaper/Rasterizer` 抽象封装 HarfBuzz/FreeType FFI | 最小度量/字形先行 | [来源: architecture.md:L179-L182; research/ecosystem.md:L43-L58] |

#### A.2.6 Widget / DSL / State（规划）

| 契约 | 建议形态（草案） | 说明 | 来源 |
|---|---|---|---|
| 声明式 DSL | 宏展开（如 `column { text ...; button ... }`） | 本机实测可编译运行：宏 `column(&block)` 展开为 `Builder.build {{ block }}`；`crystal run` 单次样本耗时 5053ms（秒级量级，**非泛化数据**） | [来源: architecture.md:L192; 本机实测 Crystal 1.22.1 / Windows ucrt64: research/crystal-capabilities.md:L12] |
| `Signal(T)` | `get` 订阅、`set` 失效；UI 消费快照 | 状态计算可在默认 context | [来源: architecture.md:L165-L167] |
| 虚拟列表 | 视口实例化 + 复用 | 禁止一次性超大节点集 | [来源: architecture.md:L168] |

### A.3 数据流（事件 → 失效 → 布局 → 绘制 → 提交）

```text
Platform/Window Input + Channel(UiSnapshot)
            │  (UI Isolated context)
            ▼
 1. 输入分发：命中测试(Rect.contains?) → 焦点 → 组件处理
            ▼
 2. 状态变更 → mark_dirty(Layout | Paint | CompositeOnly)
            ▼
 3. 布局（仅 Layout 脏子树）：Constraints 下行 → Size/Rect 上行
            ▼
 4. 绘制（仅 Paint 脏子树）：生成/复用 DrawList，合并脏矩形
            ▼
 5. 提交：atlas 更新 → 批次 → 后端 submit(仅脏区域)
            ▼
 6. 无事件且无失效 → 等待唤醒（不空转）
```  
[来源: architecture.md:L137-L145,L160-L162,L172-L174]

| 阶段 | 输入 | 输出 | 稳态要求 | 来源 |
|---|---|---|---|---|
| 事件 | OS 输入、窗口事件、业务快照 | `UiEvent` | 无事件阻塞等待 | [来源: architecture.md:L137,L143] |
| 失效 | 事件/状态写 | 脏标记与范围 | 无变更不标记 | [来源: architecture.md:L139,L160] |
| 布局 | 脏子树+约束+测量缓存 | 布局结果 | 仅脏子树 | [来源: architecture.md:L140,L151-L155] |
| 绘制 | 脏子树+布局结果 | DrawList+脏矩形 | 仅脏子树/CompositeOnly | [来源: architecture.md:L141,L160,L172] |
| 提交 | DrawList+脏矩形 | 呈现 | 仅脏区域；内容不变不提交 | [来源: architecture.md:L142,L144,L162] |

### A.4 线程与内存预算

#### A.4.1 线程/执行上下文模型（含本机实证）

| 上下文 | 责任 | 约束与本机实证 | 来源 |
|---|---|---|---|
| UI：`Fiber::ExecutionContext::Isolated` | 平台事件循环、布局、绘制、全部窗口/图形 C 调用 | 独占系统线程。**本机实测（Crystal 1.22.1 / Windows ucrt64）**：`Fiber::ExecutionContext::Isolated.new(name : String, &block)` 可用；样本中 main `fid=1784721854208 tid=9176`，Isolated 内 `fid=1784721852288 tid=332`，两次采样同 fiber 同 tid 且与主线程不同（`same_fiber=true same_tid=true diff_from_main=true`），表明该 Isolated fiber 运行在独立于主线程的系统线程上（本次样本） | [来源: architecture.md:L116-L118,L124-L125; 仓库:src/tessell.cr:L12-L15; research/crystal-capabilities.md:L9] |
| Default context | 业务逻辑、I/O、状态计算 | 不直接操作 UI/图形句柄 | [来源: architecture.md:L119] |
| Worker：`Parallel`（规划） | 解码、预计算等 | 结果以不可变数据回传。**本机实测**：`Parallel.new(name : String, size)` 可用；`Parallel.new(name,size,&block)` 编译期报错“not expected to be invoked with a block”；`Concurrent.new(name : String)` 可用。Parallel 迁移观测：8 fibers×3 次 yield 共 24 样本，按 fiber 汇总 `migrated_any=false fibers=8`（样本中各 fiber tid 保持一致）——**不得写成“不会迁移”** | [来源: architecture.md:L120-L121; research/crystal-capabilities.md:L9,L15,L18] |

通信：仅 Channel/同步原语，UI 消费不可变快照。**本机实测**：`Channel(Int32)` 可在默认上下文与 `Isolated` execution context 间收发（`cross_iso=42`）；`Mutex#synchronize` 可在 `Parallel` context 的 `spawn` 纤程间正确同步（`mutex_val=4`）[来源: architecture.md:L123; research/crystal-capabilities.md:L14]。

**未穷举/未证实（照抄）**：ExecutionContext 全部重载与默认参数未穷举 [来源: research/crystal-capabilities.md:L18]。

#### A.4.2 内存预算与“零分配”定义、度量口径（可执行）

| 项目 | 定义/口径 | 目标 | 可执行度量方法（本机可测） | 来源 |
|---|---|---|---|---|
| 稳态帧零分配（Zero-allocation steady frame） | 在**无结构变更、无新资源加载、无文本重排/重测**的稳定场景下，目标热路径执行前后堆分配增量为 0。启动、首帧、资源加载、结构变化帧不计入稳态 | M1 起作为硬指标/CI 指标 | **本机实测方法（Crystal 1.22.1 / Windows ucrt64）**：`GC.collect` 归零观测基线（样本 `bytes_since_gc 74128→0`）→ `GC.disable` → 记录 `GC.stats.bytes_since_gc`/`total_bytes`（`GC::Stats` 字段 `heap_size/free_bytes/unmapped_bytes/bytes_since_gc/total_bytes` 均 `UInt64`）→ 执行目标路径 → 再记录 → 判定 `bytes_since_gc` 前后差值为 0（稳态整数循环样本：1,000,000 次累加前后 `bytes_since_gc=0,total_bytes=75040` 不变）。探针命令示例：`crystal run %TEMP%\tessell-probe\probe_gc.cr` | [来源: architecture.md:L53,L144,L218,L231; research/crystal-capabilities.md:L10] |
| 热路径值类型化/可测性 | Geometry/Constraints/DrawCmd 等优先 `struct`；布局/绘制缓冲复用 | 降低 GC 压力 | `GC.stats` 前后对比可测分配差异（方法学证据）：10,000 元素 struct 阶段 `bytes_since_gc 0→81584`；class 阶段 `0→243776` 且 `heap_size 262144→524288`。**仅作方法学证据，不得写成性能结论**。探针：`crystal run %TEMP%\tessell-probe\probe_struct_class.cr` | [来源: architecture.md:L40,L187; 仓库:src/tessell/geometry.cr:L5-L142; research/crystal-capabilities.md:L11] |
| GC 实现认定 | 不在源码层断言 | 避免误引 | `flag?(:gc_boehm)=false`、`flag?(:gc_none)=false`，`GC.responds_to?(:malloc)=true` 仅为接口侧证；GC 是否为 Boehm **未能从运行时直接证实**（照抄未验证） | [来源: research/crystal-capabilities.md:L10,L18] |
| 帧时间分布 | P50/P95/P99 分布，非平均 FPS | M2/M3 验收 | 帧计时埋点与统计脚本（Windows 具体工具待补实测） | [来源: architecture.md:L219,L223; 未验证] |
| 分配率 | 每帧/每秒分配趋势 | 与零分配一致 | 基于 `GC.stats` 采样或平台工具（待实测） | [来源: architecture.md:L223; 未验证] |
| 输入延迟 | 输入到呈现延迟分布 | M2 起基线 | 时间戳打点（实现后） | [来源: architecture.md:L223; 未验证] |

> 不设定具体 ms/FPS 数值门限（architecture.md 未给出，本计划不编造）[来源: architecture.md:L223；未验证]。

### A.5 错误处理与降级策略

| 场景 | 处理 | 降级 | 可观测/可执行验收 | 来源 |
|---|---|---|---|---|
| 窗口/上下文初始化失败 | 显式错误并中止 UI loop | 退回离线内核/DrawList 探针 | 日志+退出码；Isolated/Channel 基线可用探针：`crystal run %TEMP%\tessell-probe\probe_exec7.cr` 观测 `diff_from_main=true`、`cross_iso=42` | [来源: architecture.md:L217; research/crystal-capabilities.md:L9,L14; 推演] |
| 图形后端不可用 | 能力探测选后端 | **M0-Windows 首选 OpenGL/WGL**；失败可离线验证 | 打印后端与失败链；Windows FFI 基线可执行：`crystal run %TEMP%\tessell-probe\probe_ffi.cr`（本机样本 `SM_CXSCREEN=1920`/`SM_CYSCREEN=1080`，支撑 user32/gdi32 直连 FFI 路径可行性） | [来源: architecture.md:L101; research/ecosystem.md:L34-L41; research/crystal-capabilities.md:L13] |
| 文本 FFI（HarfBuzz/FreeType）不可用 | 能力标记+跳过 | M0 最小 ASCII/度量探针；M2 前未验证则定位降级为工具 UI | 能力标志与测试原因；**文本栈前置验证**为高风险项（结论不变） | [来源: architecture.md:L179-L182,L232; research/ecosystem.md:L43-L58,L111] |
| IME/复杂脚本异常 | 隔离模块错误 | 基础输入保底；不达标不宣称生产可用 | 用例与样例记录 | [来源: architecture.md:L182,L209] |
| 跨 context 通信异常 | 有界 Channel + 背压/丢弃策略（待定） | 保护 UI 响应性 | 队列/丢弃计数（未实现） | [来源: architecture.md:L123; 未验证] |
| 非法几何值 | 校验/clamp，debug 断言 | 安全默认并记录 | 日志/断言；`crystal spec` 覆盖几何基线 | [来源: 仓库:src/tessell/geometry.cr:L136-L140; spec/geometry_spec.cr:L1-L49] |

### A.6 测试策略（可执行验收项优先）

| 层级 | 范围 | 方法与可执行验收 | 通过判据 | 来源 |
|---|---|---|---|---|
| 环境/基线 | 工具链与仓库基线 | 执行 `crystal --version`、`crystal spec` 并记录输出 | 版本可识别；现有 geometry 用例通过或有失败证据 | [来源: 仓库:spec/geometry_spec.cr:L1-L49; research/crystal-capabilities.md:L3] |
| 内核纯函数单测 | Geometry、Layout、脏矩形、缓存键 | `crystal spec` 增量用例 | 通过；布局内核不依赖 widget 树 | [来源: architecture.md:L156,L218] |
| 线程/通信探针 | Isolated、Channel、Mutex | `crystal run %TEMP%\tessell-probe\probe_exec7.cr`（或等价仓内探针）观测 `diff_from_main=true`、`cross_iso=42`、`mutex_val=4`；记录 `Parallel.new(name,size,&)` 编译期报错“not expected to be invoked with a block”；`migrated_any=false` 仅为样本 | 行为与证据一致，无误写为“不会迁移” | [来源: research/crystal-capabilities.md:L9,L14,L15,L18] |
| 内存/零分配探针 | 稳态帧路径 | `GC.collect`→`GC.disable`→前后 `GC.stats.bytes_since_gc` 比较；`crystal run %TEMP%\tessell-probe\probe_gc.cr` 复核方法；`probe_struct_class.cr` 仅作方法学对照 | 稳态场景差值为 0（按 A.4.2 口径） | [来源: architecture.md:L218,L231; research/crystal-capabilities.md:L10,L11] |
| FFI/平台探针 | Win32/OpenGL 绑定可行性 | `crystal run %TEMP%\tessell-probe\probe_ffi.cr` 验证 `@[Link("user32")]` 调用（样本 SM_CXSCREEN/SM_CYSCREEN）；窗口+WGL/GLFW 最小提交探针按 roadmap C.3 | FFI 调用成功；窗口/提交可观测或有阻塞证据 | [来源: research/crystal-capabilities.md:L13; research/ecosystem.md:L34-L41] |
| 宏/编译体验采样 | DSL 展开可行性 | `crystal run %TEMP%\tessell-probe\probe_macro.cr` 观测输出与单次耗时量级（样本 5053ms，非泛化） | 可编译运行；耗时仅作样本记录 | [来源: research/crystal-capabilities.md:L12] |
| Golden/像素回归 | DrawList/离屏 | 固定场景图像对比（harness 待建） | 容差内一致（容差待定义） | [来源: architecture.md:L223; 未验证] |
| 帧时间分布与分配率 | 静态/滚动/虚拟列表 | 分位数与分配采样脚本（待建，见 M0-WP5m）；泛型/单态化开销未系统测量 [未验证: capabilities 未探泛型开销] | M1 零分配零重绘；M2 以分布判定 | [来源: architecture.md:L218-L219,L223] |
| 文本正确性 | CJK/Emoji/RTL/IME | 样例集（待建） | M2 门禁通过率达定义 | [来源: architecture.md:L182,L219,L223; 未验证] |

### A.7 方案小结表

| 子项 | 结论 | 来源 |
|---|---|---|
| 主架构 | Retained 树 + 事件驱动帧 + 两遍布局内核 + DrawList/脏矩形 | [来源: architecture.md:L25-L26,L72,L137-L145] |
| 线程 | UI Isolated；Default 业务；Parallel Worker；本机已证 Isolated 独占线程样本、Channel/Mutex 跨 context | [来源: architecture.md:L116-L126; research/crystal-capabilities.md:L9,L14,L15] |
| 内存 | struct 热路径与缓冲复用；零分配以 `GC.disable`+`GC.stats.bytes_since_gc` 前后为 0 度量；GC 实现未在源码层证实 | [来源: architecture.md:L28,L187,L231; research/crystal-capabilities.md:L10,L11,L18] |
| 文本 | HarfBuzz+FreeType FFI，前置验证仍是关键风险 | [来源: architecture.md:L179-L182,L232; research/ecosystem.md:L43-L58] |
| M0 平台现实 | Windows 先行（OpenGL/WGL，P-WIN-2 user32 FFI 可行性已实证为首选），不动摇自绘定案 | [来源: architecture.md:L57,L76-L81,L217; research/ecosystem.md:L34-L41; research/crystal-capabilities.md:L13; roadmap.md C.3] |

---

## B. 规划（WBS：M0–M4）

> M0–M4 定义对应 [architecture.md](architecture.md):213-223。工作包验收标准须可执行（命令）或可观测（判据）。时间/依赖细排见 [roadmap.md](roadmap.md)；首轮执行任务见 [plan-execution.md](plan-execution.md)。

### B.1 M0 技术验证

| 编号 | 目标 | 交付物 | 验收标准（命令/可观测） | 依赖 | 预估（pd，单人全职） | 风险/证据 |
|---|---|---|---|---|---|---|
| M0-WP1 | 本机基线与可复现命令 | 基线记录（版本、spec 结果） | `crystal --version` 可执行并记录；`crystal spec` 通过现有 geometry 用例或记录失败证据 | 无 | 0.5–1 | 版本已知 1.22.1 [来源: research/crystal-capabilities.md:L3]；spec 本轮未复跑 [未验证] |
| M0-WP2 | Isolated UI 执行上下文可行性 | `examples/m0_isolated.cr`（规划）+ 记录 | 可执行：`crystal run %TEMP%\tessell-probe\probe_exec7.cr` 复核 `Isolated.new(name,&)`、Channel `cross_iso=42`、`diff_from_main=true`；仓内探针验证 UI 循环与默认 context 心跳/收发 | M0-WP1 | 1–2 | API/线程样本已证 [来源: research/crystal-capabilities.md:L9,L14]；`Parallel.new(name,size,&)` 不接受 block；重载未穷举 [来源: research/crystal-capabilities.md:L9,L18] |
| M0-WP3 | M0-Windows 窗口+图形上下文+最小提交 | 最小窗口探针（P-WIN-2 user32/gdi32+WGL 首选，P-WIN-1 GLFW+OpenGL 3.3 跨平台备选，备选 P-WIN-3；降级 P-WIN-4，见 roadmap C.3） | 可执行：`crystal run %TEMP%\tessell-probe\probe_ffi.cr` 验证 user32 FFI（样本 1920x1080）→ 实现窗口创建/消息循环/GL 上下文/清屏或最小三角矩形至少 1 帧可观测 | M0-WP2 | 2–4 | user32 FFI 可行性已证 [来源: research/crystal-capabilities.md:L13]；窗口库/DLL/绑定未实测 [来源: research/ecosystem.md:L34-L41,L85-L89; 未验证] |
| M0-WP4 | 文本 FFI 最小可行（FreeType/HarfBuzz） | `examples/m0_text_probe.cr`（规划）+ 字体/库路径说明 | 可观测：加载库并返回度量/字形或位图信息（ASCII 最小集；CJK 目标）或产出阻塞证据 | M0-WP1 | 2–4 | 生态绑定薄/Windows 分发未核实 [来源: architecture.md:L179; research/ecosystem.md:L43-L58,L111]；Windows IME 前置验证见 M0-WP4-IME |
| M0-WP4-IME (M-1) | Windows IME/复杂文本可行性探针（ASCII 之外） | IME 可行性记录（触发方式、预编辑/候选窗可否获取、最小样例） | 可观测：记录 Windows IME 可否触发、预编辑（composition）可否获取；不可行须明确写为 M2 No-Go 输入证据并给出替代/降级建议 | M0-WP3 | 0.5–1 | Windows IME 平台行为未实测 [来源: 推演; 未验证]；与 M2 IME 风险联动 [来源: architecture.md:L182] |
| M0-WP5m (M-3) | 帧时间/分配计数采集工具链 spike | 工具链选型/脚本雏形记录（Windows） | 给出可执行采集方式（命令/脚本/采样口径）覆盖帧时间分位数与分配计数；**无工具则 M1 门禁不可判定 → 触发 S2**（见 roadmap/plan-execution 裁剪） | M0-WP1 | 0.5–1.5 | 场景化采样尚待建 [来源: architecture.md:L223; research/crystal-capabilities.md:L10; 未验证] |
| M0-WP5 | M0 证据与 Go/No-Go 输入 | 证据记录（通过/失败/阻塞、命令摘要；含 M-1/M-3 结果） | 三类探针各有状态与来源标注；引用 capabilities/ecosystem 行号；M0-WP4-IME 与 M0-WP5m 结果纳入门禁输入 | M0-WP2~WP4,M0-WP4-IME,M0-WP5m | 0.5–1 | 证据不足风险 [来源: 推演] |

### B.2 M1 核心

| 编号 | 目标 | 交付物 | 验收标准（命令/可观测） | 依赖 | 预估（pd） | 风险 |
|---|---|---|---|---|---|---|
| M1-WP1 | 两遍布局内核（纯函数） | `Tessell::Layout` + spec | `crystal spec` 布局用例通过；内核不依赖 widget 树 | M0-WP1 | 3–5 | 约束模型复杂度 [来源: architecture.md:L151-L156] |
| M1-WP2 | 文本测量接口与缓存 | `TextMeasurer` 抽象、缓存键/桩 | 缓存命中/失效单测通过 | M1-WP1 | 1–2 | 与真实 shaping 语义偏差 [来源: architecture.md:L155] |
| M1-WP3 | Retained 树与失效传播 | Core 节点、`Invalidation`、脏传播 | 单测验证最小失效；静态无脏 | M1-WP1 | 3–5 | 过度失效 [来源: architecture.md:L160-L161] |
| M1-WP4 | DrawList + 最小批处理 | DrawList、批次、脏矩形合并 | 探针后端可提交命令流；脏矩形可计算 | M1-WP3,M0-WP3 | 3–5 | 结构影响后续后端 [来源: architecture.md:L172-L174] |
| M1-WP5 | 稳态零分配/零重绘验证 | 度量用例与缓冲复用 | 可执行：静态场景在 `GC.disable` 下 `GC.stats.bytes_since_gc` 前后差值为 0（口径见 A.4.2）；零重绘可观测；依赖 M0-WP5m 工具链结论 | M1-WP1~WP4,M0-WP5m | 1–3 | GC 实现细节未证实、工具链待补 [来源: research/crystal-capabilities.md:L10,L18] |

### B.3 M2 交互与文本

| 编号 | 目标 | 交付物 | 验收标准（命令/可观测） | 依赖 | 预估（pd） | 风险 |
|---|---|---|---|---|---|---|
| M2-WP1 | 输入、命中测试、焦点 | 事件分发与焦点模型 | 交互样例可命中/聚焦 | M1-WP3 | 2–4 | 平台差异 [来源: architecture.md:L138,L219] |
| M2-WP2F (M-2) | 字体获取/回退/许可确认 | 字体清单 + 回退链 + 许可证风险记录 | 明确 CJK/Emoji 等目标字体来源与回退顺序；明确分发许可/不可再分发时替代方案；未验证项显式标注 | M0-WP4 | 0.5–1 | 字体来源与分发许可风险 [来源: 推演; research/ecosystem.md:L111; 未验证] |
| M2-WP2 | 文本栈集成 | shaping/栅格/atlas/测量 | CJK/Emoji 样例正确显示与测量（目标），按 M2-WP2F 字体与回退链执行 | M0-WP4,M1-WP2,M1-WP4,M2-WP2F | 7–12 | 字体回退/复杂脚本；原估低估，按 ecosystem.md:L52-L53 自估 FreeType 最小层 1–2 周 + HarfBuzz 基础 1–2 周 = 10–20 pd 重估 [来源: architecture.md:L179,L219; research/ecosystem.md:L52-L53,L111] |
| M2-WP3 | IME 与复杂文本 | 预编辑、候选窗位置、RTL/组合字符 | 定义样例集通过；须引用 M0-WP4-IME (M-1) 证据作为可行性输入/No-Go 判定依据 | M2-WP2,M0-WP4-IME | 3–6 | IME 复杂度 [来源: architecture.md:L182] |
| M2-WP4 | 滚动与虚拟列表 | `CompositeOnly` 路径、虚拟化容器 | 万行级以帧时间分布判定 | M1-WP3,M1-WP4,M1-WP5 | 3–5 | 复用缺陷 [来源: architecture.md:L160,L168,L219] |
| M2-WP5 | 无障碍最小同步 | a11y 树/节点模型 | 最小可检视/可遍历树 | M2-WP1 | 2–4 | 投入不足 [来源: architecture.md:L182,L235] |

### B.4 M3 平台与渲染

| 编号 | 目标 | 交付物 | 验收标准（命令/可观测） | 依赖 | 预估（pd） | 风险 |
|---|---|---|---|---|---|---|
| M3-WP1 | 后端抽象与脏矩形提交巩固 | Backend 接口、GL 路径优化 | 脏矩形部分提交可观测生效 | M1-WP4 | 2–4 | 驱动差异 [来源: architecture.md:L162,L174] |
| M3-WP2 | macOS 对齐 | macOS 后端与输入/IME | 补齐 architecture.md M0 原始显示条件（环境可用时） | M1,M2,macOS 环境 | 4–7 | 环境不可得 [来源: architecture.md:L217,L220; 待证据] |
| M3-WP3 | Linux 后端 | 窗口/输入后端 | 样例可运行并视觉对比 | M3-WP1 | 3–6 | 显示服务器差异 [待证据] |
| M3-WP4 | 路径 stencil/cover（可选） | 复杂矢量路径 | 典型用例正确；不阻塞核心 UI | M3-WP1 | 4–8 | 工期膨胀 [来源: architecture.md:L233] |
| M3-WP5 | DPI/主题/一致性 | 缩放策略、主题 token | 可用平台视觉一致性检查 | M3-WP1~WP3 | 2–4 | 字体/渲染差异 [来源: architecture.md:L220] |

### B.5 M4 交付

| 编号 | 目标 | 交付物 | 验收标准（命令/可观测） | 依赖 | 预估（pd） | 风险 |
|---|---|---|---|---|---|---|
| M4-WP1 | DSL 与状态 API 定稿 | 宏/Signal 文档与实现 | 示例可用 DSL 构建主要界面；关注编译耗时（样本秒级，非泛化） | M2 | 3–5 | 编译时间 [来源: architecture.md:L234; research/crystal-capabilities.md:L12] |
| M4-WP2 | 打包与分发 | 构建/分发说明、资源内嵌 | 目标平台可运行产物或明确 DLL 依赖清单 | M3 | 2–4 | 原生依赖分发 [来源: research/ecosystem.md:L80-L95] |
| M4-WP3 | 文档与真实示例应用 | 教程/API/示例 | 示例应用跑通 | M4-WP1,WP2 | 3–6 | 文档滞后 [来源: architecture.md:L221] |
| M4-WP4 | 质量门禁与指标固化 | CI/指标清单、复盘模板 | DoD 与度量可执行、可追溯 | 全阶段 | 1–2 | 自动化不足 [来源: architecture.md:L223] |

### B.6 规划小结表

| 阶段 | 工作包 | 预估合计（pd，机械求和） | 核心验收锚点 | 来源 |
|---|---|---|---|---|
| M0 | 7 (含 M0-WP4-IME/M0-WP5m) | 7–14.5 | 上下文/窗口提交/文本 FFI/IME 可行性/度量工具链 spike 证据（含已实证的 Isolated/Channel/user32 FFI/GC 方法） | [来源: architecture.md:L217; research/crystal-capabilities.md:L9-L14] |
| M1 | 5 | 11–20 | 布局单测、稳态零分配/零重绘 | [来源: architecture.md:L218] |
| M2 | 6 (含 M2-WP2F) | 17.5–32 | 文本正确性与帧时间分布；IME 证据引用 M0-WP4-IME；M2-WP2 按 ecosystem.md:L52-L53 重估 | [来源: architecture.md:L219,L223; research/ecosystem.md:L52-L53] |
| M3 | 5 | 15–29 | 多平台与提交优化 | [来源: architecture.md:L220] |
| M4 | 4 | 9–17 | DSL/打包/示例可用 | [来源: architecture.md:L221] |
| **合计** | **27 个工作包** | **59.5–112.5** | — | [来源: 上表机械求和] |

---

## 附：待证据并入与剩余未验证

| 项目 | 状态 | 说明 | 来源 |
|---|---|---|---|
| crystal-capabilities.md（ExecutionContext/GC/struct-class/宏/FFI/Channel-Mutex/Parallel 样本） | **已并入** | 引用 research/crystal-capabilities.md:L1-L19；关键限制照抄（重载未穷举、`migrated_any=false` 仅样本不得写成“不会迁移”、GC 实现仅接口侧证） | [来源: research/crystal-capabilities.md:L7-L18] |
| `crystal spec` 本机当前通过性 | 未复跑 | M0-WP1 需实测记录 | [未验证] |
| M0 窗口+GL 上下文+提交探针（P-WIN-2/P-WIN-1/P-WIN-3/P-WIN-4 路径） | 未实测 | user32 FFI 可行性已证（首选 P-WIN-2），但窗口/消息循环/WGL 或 GLFW 路径未落地验证 | [来源: research/crystal-capabilities.md:L13; research/ecosystem.md:L34-L41; 未验证] |
| Windows IME 可触发/预编辑可获取性 (M-1) | 未实测 | M0-WP4-IME 前置探针待执行；不可行须作为 M2 No-Go 输入 | [来源: 推演; 未验证] |
| HarfBuzz/FreeType 在 Windows 的绑定/库/DLL 与 CJK 实测 | 未实测 | ecosystem.md 多项未核实；capabilities 未覆盖 | [来源: research/ecosystem.md:L43-L58,L97-L105; 待证据] |
| 字体清单/回退链/分发许可 (M-2) | 未确认 | M2-WP2F 待执行 | [未验证] |
| 帧时间/分配计数采集工具链 spike (M-3) | 未完成 | M0-WP5m 待执行；无工具则 M1 门禁不可判定 → 触发 S2 | [未验证] |
| 帧时间/分配率场景化自动化采集（实现态） | 未验证 | 已有 `GC.stats` 方法学基础，场景化采样脚本待建 | [来源: research/crystal-capabilities.md:L10; 未验证] |
| Crystal 泛型/宏编译时长与单态化开销未系统测量 | 未验证 | capabilities 未探泛型开销；宏仅单次 run 样本 5053ms（非泛化） | [来源: research/crystal-capabilities.md:L12; 未验证] |
| macOS/Linux 后端、IME/a11y 平台细节与一致性 | 待证据/待环境 | 非本机环境 | [待证据] |

*（文末）*