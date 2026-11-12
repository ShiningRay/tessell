# Tessell 路线图（C. Roadmap）

> 文档职责：定义阶段**顺序与门禁**（进入/退出/Go-No-Go）、**并行轨道**、**平台顺序与 Windows 冲突解法**、**技术债与押后项**、总工期区间（单人全职口径）。  
> 不负责什么：不重复 [plan.md](plan.md) 的模块/API 设计细节与 B 节工作包验收标准全文；不展开 W1 逐日任务与复盘模板细节（见 [plan-execution.md](plan-execution.md)）。  
> 与另两份的关系：门禁与轨道按 [plan.md](plan.md) 的 `M0–M4` / `M*-WP*` 编号引用；执行节奏与裁剪落地见 [plan-execution.md](plan-execution.md)。

**证据规则**：技术/选型论断标注 `[来源: architecture.md:Lx]`、`[来源: research/ecosystem.md:Lx]`、`[来源: research/crystal-capabilities.md:Lx]`、`[本机实测 Crystal 1.22.1 / Windows ucrt64]`、`[来源: 任务输入]`、`[来源: 推演]`、`[待证据]`、`[未验证]`。ecosystem.md 中“未能核实/未实测/许可证未确认”项**不得升级为已定案** [来源: research/ecosystem.md:L6,L28,L41-L42,L48-L49,L97-L105]。capabilities.md 中 GC 实现仅接口侧证、ExecutionContext 重载未穷举、Parallel 迁移 `migrated_any=false` 仅为 24 样本观测等限制须照抄 [来源: research/crystal-capabilities.md:L18]。时间用相对周 `W1/W2…`；工期单人全职（每周 5 天）。

---

## C.1 阶段顺序与门禁

| 阶段 | 进入条件（Entry） | 退出条件（Exit） | Go 判据 | No-Go 判据与动作 | 引用工作包 | 来源 |
|---|---|---|---|---|---|---|
| M0 技术验证 | 基线可运行；Windows+Crystal 1.22.1 环境可用 | Isolated/通信、窗口+图形上下文+最小提交、文本 FFI 最小调用、IME 可行性、度量工具链 spike 形成证据 | 探针可运行/可调用/可观测输出或可复现阻塞证据 | 关键探针不可行且无替代路径：降级为内核/离线原型并上报；文本不可行则收缩为工具 UI | M0-WP1~WP5,M0-WP4-IME,M0-WP5m | [来源: architecture.md:L217,L232; plan.md B.1] |
| M1 核心 | M0 Go；API 草案冻结；度量工具链可用或明确替代 | 布局内核单测通过；retained+失效+DrawList 闭环；静态稳态零分配/零重绘可观测（`GC.disable`+`GC.stats.bytes_since_gc` 前后为 0 口径） | 指标可采集且样例达标 | 零分配无改善路径：架构复审/No-Go；**无度量工具链则 M1 门禁不可判定 → 触发 S2**（M0-WP5m M-3） | M1-WP1~WP5 | [来源: architecture.md:L218,L231; plan.md A.4.2,B.2; research/crystal-capabilities.md:L10] |
| M2 交互与文本 | M1 Go；文本测量可用；字体清单/回退链/许可已确认或风险已记录 | 输入/焦点/IME/滚动/虚拟列表/最小 a11y；CJK/Emoji/RTL 样例；帧时间分布验收 | 文本与交互可用，分布判定性能 | 文本/IME 失控：No-Go（消费级 UI），转 S2/S3；**须引用 M0-WP4-IME (M-1) 证据**作为 IME 可行性输入 | M2-WP1~WP5,M2-WP2F | [来源: architecture.md:L219,L223,L232; plan.md B.3] |
| M3 平台与渲染 | M2 Go；绘制管线稳定 | 后端抽象与脏矩形提交；DPI/主题；平台对齐与一致性 | 至少 Windows + 1 非 Windows 平台样例可比对（目标，环境待证据） | 平台差异不可控：收敛支持范围 | M3-WP1~WP5 | [来源: architecture.md:L220] |
| M4 交付 | M3 Go；API 趋稳 | DSL 定稿、打包/分发、文档与工具类示例跑通 | 可复现交付；示例验收通过 | 资源不足：冻结窄切口 | M4-WP1~WP4 | [来源: architecture.md:L221,L236] |

**规则**：每阶段产出证据表；No-Go 不删证据 [来源: 推演]。

## C.2 并行轨道

| 轨道 | 内容（WP） | 可并行条件 | 同步点 | 来源 |
|---|---|---|---|---|
| T1 布局内核 | M1-WP1,WP2 | 独立于像素正确性 | 与 M1-WP3 树/失效接口对齐；EX-W1-08 提供预研输入 | [来源: architecture.md:L156; plan-execution.md EX-W1-08] |
| T2 文本栈 | M0-WP4,M0-WP4-IME,M2-WP2F,M2-WP2,M2-WP3 | 原生库可用或桩先行 | 测量键/字体抽象与 Layout/Render 对齐 | [来源: architecture.md:L155,L179] |
| T3 平台与后端 | M0-WP2,WP3,M3-WP1~WP3 | 选型确定（C.3） | DrawList/脏矩形接口冻结 | [来源: architecture.md:L101,L174] |
| T4 质量与度量 | M0-WP1,M0-WP5m,M1-WP5,M4-WP4 | 有可测对象 | 门禁前指标快照 | [来源: plan.md B.5] |

**串行硬依赖**：M2 依赖 M1 闭环；M3 路径渲染依赖稳定 DrawList；M4 依赖 M2/M3 [来源: architecture.md:L174,L219-L221]。

## C.3 平台顺序与「macOS 优先 vs 本机 Windows」冲突解法

### C.3.1 冲突事实
- architecture.md：macOS → Linux → Windows，M0 通过条件含“macOS 窗口显示中文与 Emoji” [来源: architecture.md:L57,L217]。
- 开发现实：仅 Windows + Crystal 1.22.1 [来源: 任务输入; research/crystal-capabilities.md:L3]。
- 生态：Windows M0 推荐 OpenGL/WGL；Vulkan/Metal 不作为 M0 默认/不可达 [来源: research/ecosystem.md:L34-L41]。

### C.3.2 解法原则与定案结论
1. **验证可达性优先**：在 Windows 完成与 M0 精神等价的可观测验证（Isolated 线程归属、窗口/事件/提交、文本 FFI 与 IME 最小调用）。  
2. **架构目标不变**：后端/平台抽象可替换，macOS 仍为 M3 对齐目标。  
3. **是否动摇第 3 节定案**：**不动摇**。第 3 节定案为“自绘而不是绑定”[来源: architecture.md:L76-L81]；Windows 先行仅调整验证顺序与 M0 探针后端/窗口载体选型，不采用 WebView/原生控件绑定作为主路线。若采用 raylib-cr 等高层封装作探针，须评估其对可控渲染/后端抽象的影响并记录为权衡，不得等同最终平台层定型 [来源: 推演]。

### C.3.3 M0-Windows 具体验证路径与取舍（含本机实证）

| 路径 | 方案 | M0 验证步骤（可执行/可观测） | 优点 | 代价/风险 | 证据/限定 |
|---|---|---|---|---|---|
| **P-WIN-2（user32/gdi32+WGL，首选）** | 纯 FFI 直连 Win32 窗口过程+消息循环+WGL/OpenGL 3.3 + 最小三角/矩形 | 1) 绑定 `RegisterClassEx/CreateWindowEx/PeekMessage/DispatchMessage`；2) `ChoosePixelFormat/SetPixelFormat/wgl*`；3) UI 线程渲染循环；4) 提交最小几何 | 无第三方窗口库；贴近 Windows 线程亲和；验证可达性最高 | 样板多、平台分叉大 | [本机实测 Crystal 1.22.1 / Windows ucrt64] `@[Link("user32")] fun GetSystemMetrics` 成功（`SM_CXSCREEN=1920`,`SM_CYSCREEN=1080`），支撑 M0-Windows 直连 FFI 路径可行 [来源: research/crystal-capabilities.md:L13]；完整窗口/WGL 链路**未实测** |
| **P-WIN-1（GLFW+GL3.3，跨平台备选）** | GLFW 窗口/输入 + OpenGL 3.3 Core + 最小三角/矩形 | 1) 准备 `glfw3` 等原生库；2) 在 Isolated context 初始化窗口/GL；3) 事件循环+`SwapBuffers`；4) 并行默认 context 心跳（已证 Channel 跨 context `cross_iso=42`）；5) 叠加文本/IME 探针 | 跨平台心智一致，后续复用潜力 | 绑定/分发未实测；CrystGLFW Windows 支持未能核实且 2023-09-15 后无推送 | [来源: research/ecosystem.md:L12,L28,L34-L41; research/crystal-capabilities.md:L9,L14]；**本机未实测** |
| **P-WIN-3（raylib-cr 探针）** | raylib 快速开窗绘制（一次性可行性探针） | 按 README 配置 `C:\raylib`/`LIB`/`PATH` 运行最小示例；评估与自有 DrawList/后端抽象整合 | 上手快；README 明确 64-bit Windows，Apache-2.0，pushed 2026-10-21（ecosystem 证据） | 抽象层可能限制可控渲染；与自绘管线整合待评估 | [来源: research/ecosystem.md:L15,L85-L86]；**本机未实测**，许可/活跃度为 research 记录非本计划复核 |
| **P-WIN-4（无窗口离线降级）** | Isolated + Layout/DrawList + 文本度量 CPU 路径 | 验证线程/内核/FFI 子集，不验证呈现 | 依赖最小 | 不满足窗口提交验收 | [来源: 推演] |

**取舍结论**：优先 P-WIN-2（user32 FFI 已本机实证 [来源: research/crystal-capabilities.md:L13 SM_CXSCREEN=1920/SM_CYSCREEN=1080]；CrystGLFW Windows 支持未能核实且 2023-09-15 后无推送 [来源: research/ecosystem.md:L12]；符合 C.3.2「验证可达性优先」）；P-WIN-2 受阻快速试 P-WIN-1（跨平台备选）[来源: 推演]；P-WIN-3 仅作一次性可行性探针；均失败则 P-WIN-4 并触发门禁评审 [来源: 推演]。

### C.3.4 平台顺序（调整后）

| 阶段 | 平台重点 | 备注 | 来源 |
|---|---|---|---|
| M0 | Windows（P-WIN-2 首选 / P-WIN-1 跨平台备选 / P-WIN-3；降级 P-WIN-4） | 补齐可观测证据；macOS M0 原始条件待环境补验 | [来源: architecture.md:L217; 任务输入] |
| M1–M2 | Windows 主验证，逻辑跨平台 | Core/Layout/Render 尽量平台无关 | [来源: architecture.md:L90-L109] |
| M3 | macOS 对齐 + Linux 扩展 | 需环境（待证据） | [来源: architecture.md:L220] |
| M4 | 已验证平台交付 | 未验证不宣称支持 | [来源: 推演] |

## C.4 技术债与押后项

| 项目 | 类别 | 说明 | 计划处理 | 来源 |
|---|---|---|---|---|
| 复杂矢量路径 stencil/cover | 押后 | 先批处理矩形/文本/图片 | M3-WP4 可选 | [来源: architecture.md:L174-L175,L233] |
| macOS Metal/a11y 完整对齐 | 平台债 | Windows 先行 | M3-WP2 | [来源: architecture.md:L217,L220] |
| 文本复杂脚本/字体回退完备性 | 风险债 | 绑定薄、分发未实测；文本栈前置验证结论不变；字体清单/回退/许可前置 | M0-WP4→M2-WP2F/M2-WP2/M2-WP3，必要时降级 | [来源: architecture.md:L232; research/ecosystem.md:L43-L58,L111] |
| Windows IME 可行性前置缺口 | 风险债 | M0 前置探针补证，失败作 M2 No-Go 输入 | M0-WP4-IME (M-1) | [来源: architecture.md:L182; plan.md B.1] |
| 帧/分配度量自动化 | 工具债 | `GC.stats` 方法已证，场景化采样与工具链 spike 待建；无工具则 M1 门禁不可判定 | M0-WP5m (M-3)→M1-WP5→M4-WP4 | [来源: research/crystal-capabilities.md:L10; architecture.md:L223] |
| 宏/泛型编译时间 | 体验债 | DSL 可行但单次 run 样本秒级（非泛化）；泛型/单态化开销未系统测量 | M4 前监控 | [来源: research/crystal-capabilities.md:L12; architecture.md:L234; 未验证] |
| 原生 DLL 打包/静态链接边界 | 分发债 | 完全静态受限 | M4-WP2 明确依赖清单 | [来源: research/ecosystem.md:L80-L95] |
| 对象池/arena | 条件性偿债 | 零分配不达标时 | M1 触发 | [来源: architecture.md:L231] |

## C.5 总工期区间（单人全职）

| 口径 | 区间 | 说明 | 来源 |
|---|---|---|---|
| 工作量机械求和 | 约 **59.5–112.5 pd** | M0 7–14.5 + M1 11–20 + M2 17.5–32 + M3 15–29 + M4 9–17 | [来源: plan.md B.6] |
| 相对周（5 天/周） | 约 **W1–W23（12–23 周）** 量级 | 未含阻塞/返工；单人并行轨道实为切换 | [来源: 推演；未验证] |
| 建议 | 优先 M0–M1 可验证内核 | 控制文本/平台/度量风险 | [来源: architecture.md:L231-L232] |

> 注：文本栈上限另有 +0~10 pd 风险缓冲未计入机械求和，对外承诺须单列。 [来源: plan.md B.3 M2-WP2; research/ecosystem.md:L52-L53; 推演]

## C.6 路线图小结表

| 维度 | 结论 | 来源 |
|---|---|---|
| 顺序 | M0→M1→M2→M3→M4 门禁驱动 | [来源: architecture.md:L215-L221] |
| 并行 | T1–T4 重叠有同步点；单人切换执行 | [来源: plan.md B] |
| 平台 | Windows 先行（P-WIN-2 首选 / P-WIN-1 跨平台备选 / P-WIN-3，降级 P-WIN-4；user32 FFI 已实证），M3 补齐 macOS/Linux；**不动摇“自绘”定案** | [来源: architecture.md:L57,L76-L81,L217,L220; research/crystal-capabilities.md:L13; research/ecosystem.md:L12] |
| 关键风险 | 文本栈/IME/字体许可、稳态零分配达成与度量工具链、平台/分发依赖；GC 实现/ExecutionContext 重载/Parallel 迁移仍有限制性证据 | [来源: architecture.md:L231-L236; research/crystal-capabilities.md:L18] |

*（文末）*