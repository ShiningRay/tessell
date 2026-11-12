# Tessell 执行计划（D. Execution Plan）

> 文档职责：定义**当前与近期迭代如何执行**——首迭代 W1–W3 逐任务清单（≤3 人日）、DoD、度量指标、里程碑复盘制度、单人全职裁剪预案与分块安排。  
> 不负责什么：不展开模块/API 设计与完整 WBS 定义（见 [plan.md](plan.md)），不替代阶段门禁与平台路线决策（见 [roadmap.md](roadmap.md)）。  
> 与另两份的关系：任务绑定 [plan.md](plan.md) 的 `M*-WP*` 与 [roadmap.md](roadmap.md) 的 M0 门禁/轨道；执行中范围变化回写对应文档。

**执行口径**：单人全职（每周 5 天），相对周 `W1/W2…`，禁止绝对日期；工作量单位人日（pd）区间 [来源: 任务输入]。  
**证据规则**：`[来源: architecture.md:Lx]` / `[来源: research/ecosystem.md:Lx]` / `[来源: research/crystal-capabilities.md:Lx]` / `[本机实测 Crystal 1.22.1 / Windows ucrt64]` / `[来源: 任务输入]` / `[待证据]` / `[未验证]`；ecosystem 未核实项与 capabilities 限制性结论（GC 实现仅接口侧证、ExecutionContext 重载未穷举、Parallel 迁移 `migrated_any=false` 仅 24 样本）须照抄 [来源: research/ecosystem.md:L97-L105; research/crystal-capabilities.md:L18]。  
**当前前提**：`docs/research/ecosystem.md`、`docs/research/crystal-capabilities.md` 已到货并纳入；M0-Windows 路径与取舍见 [roadmap.md](roadmap.md) C.3（P-WIN-2 首选，不动摇 architecture.md 第 3 节自绘定案）。  
**本轮范围（规划态）**：本任务仅产出/修订三份 docs；本轮未执行探针、未新建 `examples/`、未改 `src/`/`spec/`。下表 DoD 为后续获授权写入代码/执行时的验收标准，非本轮完成证明；未执行项须标 `[未验证]`。

---

## D.1 首迭代 W1–W3 逐任务执行表（5 pd/周，≤3 人日/任务）

> 目标：推进 [plan.md](plan.md) `M0-WP1~WP5`（含 M-1/M-3），为 [roadmap.md](roadmap.md) M0 门禁产出证据。

| 周/日期（相对） | 任务 ID | 对应 WP | 任务内容 | 交付物（规划态） | DoD（后续获授权执行时，可执行/可观测） | 预估（pd） | 依赖 |
|---|---|---|---|---|---|---|---|
| **W1（块容量 5 pd，块内合计 3.5–6.0 pd；上限超容量 1.0 pd）** | — | — | **交付**：M0-WP1 基线 + M0-WP2 上下文复核 + M0-WP3 窗口/GL 最小提交证据。超容量部分按溢出规则顺延 W2-D1，不压缩窗口探针范围 | — | 块内任务按序推进；EX-W1-04 若超 5 pd 上限，明确「溢出顺延 W2-D1，不压缩窗口探针范围」 | — | — |
| W1-D1 | EX-W1-01 | M0-WP1 | 记录本机基线：`crystal --version`、`crystal spec` | 基线记录 | 命令输出可复现；spec 通过或失败有证据（版本已知 1.22.1 [来源: research/crystal-capabilities.md:L3]） | 0.5 | 无 |
| W1-D1~D2 | EX-W1-02 | M0-WP2 | 复核/实现 Isolated+Channel 探针并验证默认 context 心跳 | 探针与记录（规划；未落地） | 可执行：`crystal run %TEMP%\tessell-probe\probe_exec7.cr` 或仓内等价探针观测 `Isolated.new(name,&)`、`diff_from_main=true`、`cross_iso=42`、`mutex_val=4`；记录 `Parallel.new(name,size,&)` 编译期报错；`migrated_any=false` 仅样本 | 1.0–1.5 | EX-W1-01 |
| W1-D2 | EX-W1-03 | M0-WP3 | 选定窗口路径（优先 P-WIN-2 user32/gdi32+WGL 首选；跨平台备选 P-WIN-1 GLFW+OpenGL 3.3；备选 P-WIN-3 raylib-cr 探针；降级 P-WIN-4）并列原生依赖 | 选型与依赖清单 | 明确库/DLL/链接与阻塞；可执行基线：`crystal run %TEMP%\tessell-probe\probe_ffi.cr` 验证 user32 FFI（SM_CXSCREEN=1920,SM_CYSCREEN=1080）支撑 P-WIN-2 可行性；P-WIN-2 首选理由：user32 FFI 已本机实证，CrystGLFW Windows 支持未能核实且 2023-09-15 后无推送 [来源: research/crystal-capabilities.md:L13; research/ecosystem.md:L12] | 0.5–1.0 | EX-W1-02 |
| W1-D3~D5 | EX-W1-04 | M0-WP3 | 最小窗口+事件循环+GL 上下文+清屏或最小三角/矩形提交（按 EX-W1-03 选定路径） | `examples/m0_window_probe.cr`（规划；未落地）+ 记录 | 可观测：窗口显示/可关闭/至少 1 帧提交；UI 在 Isolated 线程运行；若超 5 pd 上限溢出顺延 W2-D1，不压缩窗口探针范围 | 1.5–2.5 | EX-W1-03 |
| **W2（块容量 5 pd，块内合计 2.5–5.0 pd）** | — | — | **交付**：文本依赖与最小 FFI 探针 + Windows IME 可行性证据 | — | 吸收 W1 可能溢出后按序推进 | — | — |
| W2-D1 | EX-W1-05 | M0-WP4 | 准备 FreeType/HarfBuzz 依赖与字体路径 | 依赖与路径记录 | 库可定位或记录阻塞（ecosystem 未核实项不升级） | 0.5–1.0 | EX-W1-01 |
| W2-D2~D4 | EX-W1-06 | M0-WP4 | 最小文本 FFI 探针（度量/字形/位图） | `examples/m0_text_probe.cr`（规划；未落地）+ 记录 | 可观测：ASCII 最小返回有效数据；CJK 目标未达成须记录 | 1.5–3.0 | EX-W1-05 |
| W2-D4~D5 | EX-W1-09 (M-1) | M0-WP4-IME | Windows IME 可行性探针（ASCII 之外最小样例） | IME 可行性记录 | 可观测：记录 Windows IME 可否触发、预编辑（composition）可否获取；不可行须写为 M2 No-Go 输入证据 | 0.5–1.0 | EX-W1-04 |
| **W3（块容量 5 pd，块内合计 1.5–4.0 pd + 缓冲 1–3.5 pd）** | — | — | **交付**：度量工具链 spike + M0 证据汇总/Go 输入 + Layout 预研草案；缓冲用于吸收 W1/W2 溢出 | — | 块内合计 1.5–4.0 pd，剩余容量作为缓冲 | — | — |
| W3-D1~D2 | EX-W1-10 (M-3) | M0-WP5m | 帧时间/分配计数采集工具链 spike | 工具链选型/脚本雏形记录 | 给出可执行采集方式（命令/脚本/采样口径）；无工具则 M1 门禁不可判定 → 触发 S2 | 0.5–1.5 | EX-W1-01 |
| W3-D3 | EX-W1-07 | M0-WP5 | 汇总 M0 证据与 Go/No-Go 输入（计划态） | 证据汇总（本轮可交付：按已有/待执行证据项列清单） | WP1~WP4、M0-WP4-IME、M0-WP5m 各有通过/失败/阻塞/未验证状态与命令摘要占位；引用 research 行号；本轮未执行项显式 `[未验证]` | 0.5–1.0 | EX-W1-04,EX-W1-06,EX-W1-09,EX-W1-10 |
| W3-D4~D5 | EX-W1-08 | M1 预研 | 草拟 Layout 节点/两遍求解接口与可测结构 | 设计草案（文本，入本文档/plan 附录或等价记录；不落 src） | 接口可单测（设计层可验证）；与 Constraints/Rect 对齐；零分配口径采用 `GC.disable`+`bytes_since_gc` 差值 0；**草案不落库代码** | 0.5–1.5 | EX-W1-01 |

**节奏**：EX-W1-04 阻塞超 2 次尝试按 roadmap C.3.3 切换备选并保留证据 [来源: roadmap.md C.3.3]。EX-W1-04 若超 5 pd 上限，溢出顺延 W2-D1，不压缩窗口探针范围。

## D.2 Definition of Done（DoD）

| 层级 | DoD 条目 | 适用范围 |
|---|---|---|
| 任务 DoD | 交付物产出；验收命令/可观测判据已执行并记录；阻塞写明“已做/卡点/需要什么”；未验证显式标注；规划态任务须明确“未执行/未落库” | D.1 所有任务 |
| 工作包 DoD | 满足 [plan.md](plan.md) `M*-WP*` 验收标准；依赖闭合或豁免；证据可追溯 | M0–M4 |
| 代码/测试 DoD | 相关 `crystal spec` 通过；无未记录崩溃；热路径变更附分配/帧时间影响说明 | 实现迭代 |
| 文档 DoD | 论断有来源；推演与实测分离；未核实/限制性结论照抄不升级；相对链接有效 | 三文档 |
| 里程碑 DoD | 满足 [roadmap.md](roadmap.md) Exit；Go/No-Go 有证据；风险更新 | M0–M4 |

## D.3 度量指标（可执行口径）

| 指标 | 定义 | 采集时机 | 目标/判据 | 可执行方法/来源 |
|---|---|---|---|---|
| 帧时间分位数 | P50/P95/P99 帧耗时分布 | M1 基线，M2/M3 验收 | 分布判定，禁用平均 FPS；阈值待基线 | 埋点脚本/工具链（M0-WP5m spike 待建）[来源: architecture.md:L219,L223; plan.md M0-WP5m] |
| 分配率 / 稳态零分配 | 稳态帧堆分配增量 | M1 起持续 | 静态场景稳态零分配、零重绘 | `GC.collect`→`GC.disable`→比较前后 `GC.stats.bytes_since_gc`（UInt64），差值 0；方法探针 `crystal run %TEMP%\tessell-probe\probe_gc.cr` [本机实测: research/crystal-capabilities.md:L10]；GC 实现未证实 [来源: research/crystal-capabilities.md:L18] |
| struct/class 分配可测性 | 方法学对照 | 需要时 | 不作性能结论 | `crystal run %TEMP%\tessell-probe\probe_struct_class.cr`（10k: struct 0→81584B, class 0→243776B, heap 262144→524288）[来源: research/crystal-capabilities.md:L11] |
| 输入延迟 | 输入到呈现延迟分布 | M2 起 | 建基线回归 | 时间戳打点（待实现）[来源: architecture.md:L223] |
| 文本正确性用例通过率 | CJK/Emoji/RTL/IME 样例集通过比例 | M2 验收 | 100% 目标样例集（待定义） | 用例集（待建）[来源: architecture.md:L182,L219,L223] |
| 布局/几何单测通过率 | `crystal spec` 相关通过比例 | 每迭代 | 100% | `crystal spec` [来源: spec/geometry_spec.cr:L1-L49] |
| M0 探针完成度 | Isolated/通信、窗口提交、文本 FFI、IME、度量工具链状态 | W3 末 | 各类均有证据状态（含 M-1/M-3） | `probe_exec7.cr`/`probe_ffi.cr` + 窗口/文本/IME/工具链记录 [来源: research/crystal-capabilities.md:L9,L13,L14] |

## D.4 里程碑复盘制度

| 频率/节点 | 参与角色 | 输入 | 输出 | 关注点 | 来源 |
|---|---|---|---|---|---|
| 每周（Wn 末） | 执行/技术负责人角色 | 任务表、证据、阻塞 | 周复盘：完成/偏差/Wn+1 计划 | 燃尽、阻塞、路径切换 | [来源: 推演] |
| 阶段门禁（M0–M4） | 同上 + 首辅（如需） | WP 证据、指标、风险 | Go/No-Go、范围调整、三文档回写 | 零分配、帧分布、文本、IME 证据、度量工具链、平台 | [来源: architecture.md:L215-L223; roadmap.md C.1] |
| 触发式复盘 | 相关角色 | No-Go 或连续阻塞 | S1/S2/S3 定位调整 | 降级决策 | [来源: architecture.md:L232,L236] |

**模板最小字段**：周期、目标、实际、证据摘要、指标、阻塞与决策、下周期动作。

## D.5 单人全职裁剪预案（最小可行路径）

| 级别 | 保留 | 推迟/放弃 | 触发条件 | 最低门禁 |
|---|---|---|---|---|
| **S1（默认）** | Windows + OpenGL；Layout/Core/DrawList 最小闭环；基础输入与少量控件；文本在可用范围声明限制；虚拟列表基础 | macOS Metal/Linux 全量、复杂路径、完整 a11y、DSL 完整形态 | 单人或 M2 风险显现 | 布局单测通过；稳态零分配可观测；帧分布可采集 |
| **S2** | Layout 纯函数、文本测量抽象/桩、DrawList 离线验证 | 实时窗口/IME 完整/多平台 | 窗口后端或 IME 长期阻塞；**或 M0-WP5m 无度量工具链致 M1 门禁不可判定** | 内核可测；非完整 GUI 定位明确 |
| **S3** | M0 探针与可行性报告 | GUI 产品化承诺 | M0/M1 No-Go | 证据完整，结论诚实 |

裁剪决策记录于复盘并同步 [roadmap.md](roadmap.md) [来源: architecture.md:L209,L236]。

## D.6 执行计划小结表

| 子项 | 内容 | 来源 |
|---|---|---|
| 首迭代 | W1–W3（5 pd/周）/ EX-W1-01~10（含 M-1/M-3），聚焦 M0 证据闭环与 capabilities 复核；本轮规划态 | [来源: plan.md B.1; roadmap.md C.1,C.3] |
| 粒度口径 | 每任务 ≤3 pd；单人全职、相对周；块容量与合计已定量 | [来源: 任务输入] |
| 质量控制 | 五级 DoD + 可执行度量 + 周/门禁复盘 | [来源: architecture.md:L223; research/crystal-capabilities.md:L9-L15] |
| 兜底 | S1/S2/S3，工具类窄切口优先 | [来源: architecture.md:L236] |

*（文末）*