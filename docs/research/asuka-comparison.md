# asuka（egoist）对照调研：特性、思路、架构、算法与可借鉴点

- 产出：docs/research/asuka-comparison.md（纯文档，只写本文件）
- 时间：2026-11-14（Asia/Shanghai）；HEAD=f807b17（tessell v0.2.0）
- 调研对象：github.com/egoist/asuka（快照 commit e86683f，2026-11-14 clone --depth 50）；站点 asuka.egoist.dev/zh
- 口径：asuka 事实标 `asuka/路径:行`（源码实读；行号经抽查核实）；tessell 事实标本仓 `路径:行`；[未验证]=静态调研未编译运行 asuka 示例；[推断]=推演
- 方法：通读 asuka DESIGN.md（3874 行）与 README，三路源码深读（signal/ui、layout/ops、工具链/测试），对照本仓架构画像
- 关联 issue：#33–#42（可借鉴清单逐条立项）；记忆库 95114470（调研结论存档）

## 0) 结论先行

- C1 定位对极：asuka 是 Go 六平台**原生控件**框架（UIKit/AppKit/Win32/GTK4/DOM），自绘是明文非目标（DESIGN.md:13-14）；tessell 是**全自绘**桌面框架。互不可替代，tessell-sheet-demo 类 canvas 应用 asuka 做不了，tessell 也无意绑原生控件。
- C2 骨架同构：编译语言 + retained 树 + 声明式 builder + 细粒度更新 + GC 压力工程，两框架方法论同一档次（文档诚信、单作者纪律）。借鉴几乎单向流动：asuka 的响应式内核、布局缓存工程、测试金字塔、开发者工具链值得 tessell 抄；tessell 的像素级自绘能力是 asuka 放弃的领域。
- C3 P0 三项已立项：Signal(T) 内核（#33）、布局增量缓存（#34）、Fake PlatformHost（#35）。
- C4 单向最值得抄的一件：alien-signals 算法内核 571 行（graph.go 238 + signal.go 333），宿主语言无关，Crystal 可直接移植，对应 docs/architecture.md:166 既有规划。

## 1) asuka 是什么

- Go 编写的跨平台应用框架，v0.1.0 alpha，MIT，单作者（EGOIST）。移动优先：iOS/Android 先行，桌面（macOS/Windows/Linux）与 Web 后至，同一核心。
- 立场与自绘派相反：用各平台自己的控件，核心只发 op。每平台一个宿主（Swift+UIKit / Kotlin+Views / purego+AppKit / syscall+Win32 / purego+GTK4 / wasm+DOM）。
- 架构四层（DESIGN.md:44-60）：signal（响应式）→ ui（组件树/flush）→ layout（CSS block/flex/grid）→ ops（二进制协议），宿主接口 `Host{Apply,Measure,Post,Environment}`。
- 组件函数只跑一次返回 Node；可变 prop 全是 `Accessor[T]`；更新 = signal 写 → 只重跑读了它的 effect → 每 effect 追加恰好一条 SetProp。无虚拟树、无全树 diff。

## 2) 四个算法层面

### 2.1 signal 响应式内核（最精华）

- alien-signals 算法移植（push dirty flag / pull value，glitch-free）+ Solid ownership 模型。
- **侵入式双向链表依赖图**：deps/subs 挂节点上的链表而非 map（graph.go:40-47）；重跑按读取顺序命中旧 link 即复用并盖 run 版本戳，endTracking 只摘尾部没走到的 link，link 走 free list（graph.go:62-171）——动态依赖 + 稳态零分配的全部成本来源。
- **两级脏标**：写时对直接订阅者 push dirty、下游 push 廉价 pending 并剪枝（graph.go:182-196）；memo 惰性重算，被 pull 时 checkDirty 先验证上游真变（graph.go:212-233）；派生值相等即截断传播。菱形依赖一轮 flush effect 只跑一次，无需拓扑排序。
- **有界 flush**：循环消化 effect 写 effect 的级联，100 pass 后 panic 并用 runtime 符号点名肇事 effect（signal.go:278-333）；render effect 先于 user effect、同级按创建序。
- **Owner 树**：显式 dispose、LIFO cleanup、幂等；effect 每次重跑先 clean 上一轮创建的子作用域。Show/For/Dynamic = 存 dispose 闭包切换销毁重建，不 diff；For keyed 行 = 每行两个可写 signal（item/index），reconcile 只 Set 不重建 + LIS 决定移动（ui/control.go:185-298，实读 `lis` 函数）。
- 测试：26 个测试 + 5 个基准，覆盖 glitch-free 菱形、memo 截断、动态依赖、dispose、稳态零分配（AllocsPerRun==0 断言）。

### 2.2 layout 引擎

- CSS 语义按规范实现：flexbox §9（freeze 循环）、grid §8+§12、block §2 margin 折叠，约 3660 行（block.go 251 / flex.go 924 / grid.go 1364 / node.go 706 / style.go 415）。
- **正确性 oracle = 1615 条 Taffy 的 Chrome 生成 fixtures**（layout/testdata/css/，实数 1615 个 XML）表驱动测试 + known_failures.txt（283 条，修好自动提醒移除）。
- **每节点双层缓存**（node.go:71 起，`const measureSlots = 8`）：final 单槽 + 8 槽测量环形缓冲，键=完整输入（NaN 相等、1e-4 容差）；MarkDirty 沿父链上迁遇已脏祖先早停（node.go:191-216）。
- **共享内容键控测量缓存**（ui/measure.go，85 行）：每 root 两代各 1024 条，键含 kind/文本/字体/行数/缩放/约束 float 位；old 命中提升回 cur。列表行回收、重复标签不重复问宿主。
- **Pass scratch 零分配**：全部暂存住可复用 layout.Pass（node.go:280-295），稳态重布局 AllocsPerRun==0 进 CI。
- 像素对齐：发送边界 snap，被测叶子尺寸向上取整（两边都取整会让 label 窄一像素换行，同 Yoga）。

### 2.3 ops 协议工程

- schema.go（470 行）单一事实源：10 op code / 38 kind / 57 事件 / 35 命令，每条带文档注释；`go generate` 产出 Swift/Kotlin/JS 三端解码器。
- **一套 golden 二进制锁四端**：Go 生成 golden.bin，三语言解码器各测同一数据必须打印同一结果（ops/testdata/）。
- Batch 用 arena+buf 复用，编码零分配（TestEncodeAllocatesNothing）；**嵌套 flush spare batch**：宿主在 Apply 期间回调核心时写进备用批，正在 apply 的批绝不被二次发送（ui/root.go:219-238，TestFlushWhileApplying 精确断言）。
- 一次 flush 固定两次跨界：apply props 批 → 布局 → apply frames 批。

### 2.4 测试金字塔（无显示器跑通一切）

| 层 | 内容 | 规模 |
|---|---|---|
| host/fake | 记录 op、固定规则测量、违规 op panic；ui 全部测试跑其上 | fake.go 约 1900 行 |
| uitest | 按用户所见驱动（只有可见的能命中、tap 只达最顶层）、settle 绝不 sleep、泄漏检查、golden 文本树 | 约 1900 行 |
| conformance | 品红注册标记定位+算 px/pt；Probe 测量像素量而非对比参考图：边缘 0.5 交叉（容差 1 设备像素）、阴影 σ、混合比；DPI/宿主无关 | 898 行 |
| e2e | 真机 GUI 测试，同一套测试跑 iOS/Android，有界等待 | 3327 行 |
| bench | 同一 app 三遍（asuka/SwiftUI/Compose），共用同一 Meter 文件测主线程 busy time，交错取中位数 | 见 bench/results/ |

- bench 数字（模拟器，官方自认仅横向对比用）：iOS update-all 6.39 vs 62.4ms（掉帧 2 vs 120）；Android mount 反输 Compose（539 vs 444ms，自认「造 View 比 Compose 布局节点贵」）。双向诚实。
- 性能断言只用计数（op 数/measure 数/分配数），从不用 wall-clock。

## 3) 工具链与治理

- **asuka dev 热重载**：Go 跑在开发机，op 流过 socket 到设备播放器。状态保留 = 重启进程 + signal 值按 AST 生成的源码位置名序列化回填（internal/devstate + signal/keep.go/places.go）；control socket 把新进程启动开销藏进旧画面；fd 继承让重连零拒绝。
- **RFC 0003 否决进程内代码补丁**：闭包打不了补丁（UI 全是闭包）、双语义、类型变更反正重启，增量 build 实测 0.44s。论证逐条适用 Crystal。
- **vet 三 analyzer**（1563 行）：reads（建树期未追踪读）/ mainthread（goroutine 直接 Set）/ memowrites；哲学「只报从代码能确定的——乱报的检查会被关掉」，每条带修法与出口。
- **asuka build/publish**：纯 CLI 签名、公证、直调 App Store/Play API，build 号自动取商店最高+1。
- **AGENTS.md**（144 行）：硬规则全是可机械验证的架构不变量（cgo 只许在 mobile/、核心不 import 宿主、一次 flush 两次跨界、每加一个产生 owner 的构造都要测 dispose）+ 意图→命令速查表 + 「先读成熟框架实现再发明」。
- 治理：DESIGN.md 单一事实源（每个决策带 why）；RFC 目录留否决推理；文档 en/zh/ja 三语同步；commit 系列化（一个跨栈特性每宿主一 commit）。里程碑完结条件 = examples 跑起来 + 测试进 CI。

## 4) 逐轴对比

| 轴 | asuka | tessell | 判 |
|---|---|---|---|
| 定位 | 移动优先六平台、原生观感 | 桌面自绘、像素自由 | 异极，不可互替 |
| 渲染 | 外包给平台，无像素控制 | 全栈自有：atlas/批/脏区/GL+Software 双后端 | tessell 独有 |
| 响应式 | alien-signals 内核 571 行，零分配硬断言 | 空白：Signal(T) 仅规划（docs/architecture.md:166） | asuka 大幅领先 |
| 布局 | CSS 语义 + Chrome oracle + 增量双层缓存 | 两遍 measure/arrange 纯函数内核，无外部 oracle，缓冲复用挂 TODO（src/tessell/layout.cr:4,14） | asuka 领先 |
| GC 压力工程 | 零分配断言遍布 signal/layout/ops | 零分配探针、稳态批复用、三级失效 | 打平 |
| 测试 | fake host/uitest/conformance 探针/计数断言/golden 锁四端 | golden PNG 像素 oracle（asuka 没有）、263+100 specs；无 CI 矩阵、依赖真实窗口 | 各有强项，asuka 更体系化 |
| DX | 热重载保状态/vet/build+publish 全 CLI | 无热重载、无发布链、gate.ps1 仅 Windows | asuka 完胜 |
| 文档治理 | DESIGN.md 单源 + RFC 否决留痕 + 三语 | 证据驱动 + 75 份核验文件 + 未验证降级表述 | 打平；缺 AGENTS.md |

## 5) 可借鉴清单（issue 对应）

| # | 优先级 | 项 | issue |
|---|---|---|---|
| 1 | P0 | Signal(T) 内核按 alien-signals 移植（五机制） | #33 |
| 2 | P0 | 布局增量缓存（final+8 槽、父链早停、共享测量缓存） | #34 |
| 3 | P0 | Fake PlatformHost，UI 测试脱离窗口进 CI | #35 |
| 4 | P1 | 性能断言计数化，弱化 wall-clock | #36 |
| 5 | P1 | golden PNG 升级注册标记+量测探针 | #37 |
| 6 | P1 | 补 AGENTS.md | #38 |
| 7 | P1 | 重启式热重载（依赖 #33） | #39 |
| 8 | P2 | 跨后端 golden（Software vs GL） | #40 |
| 9 | P2 | 建树期读响应式值静态检查（依赖 #33） | #41 |
| 10 | P2 | Runner/宿主 apply 重入隔离 spare batch | #42 |

不借鉴：原生控件路线本身（与自绘使命冲突）；bench 对标（无同量级参照物，对标对象应是自家探针基线）。

## 6) 遗留缺口与未验证项

- [未验证] 全部结论来自源码静态阅读与 DESIGN.md 交叉核对，未编译运行 asuka 任何示例；bench 数字引自 bench/results/*.md（模拟器口径）。
- [未验证] asuka host/fake 行数约 1900（多文件合计，未逐文件复核）。
- [推断] alien-signals 移植到 Crystal 的分配行为（GC 差异、struct 装箱）需探针验证；Crystal 无 AllocsPerRun 等价物，需复用 tools/zero_alloc_frame.cr 思路。
- [推断] hot reload 的源码位置名可用 Crystal 宏生成，可行性未探针。
- asuka 本体缺口（借鉴其诚实标注）：无 API 稳定性承诺（alpha）；Android mount 落后 Compose；Go runtime 常驻内存约 11MB 自认短板。
