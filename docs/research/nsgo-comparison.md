# NSGo 对照 Tessell：架构、交付面与可借鉴点

- 核查日：2026-11-19（Asia/Shanghai）
- NSGo 基线：main `9296af5b0564189da92b53e213101a1e75a629c7`；当日最新 release v0.2.0，tag 对应 commit `b74fe5ae4e7bac6204960482a5b3f425af4924e6`
- Tessell 基线：本机 main `65f3857867c2392881578ef5625285400a49bbb4`，shard v0.4.1；该 commit 已由 GitHub API 核实存在
- 证据口径：NSGo 为官方原始文档 + 定点源码；本机未编译/运行 NSGo，性能和平台结论不升级为本次实测。Tessell 源码在本机复跑了两组 spec。

## 0. 结论与建议

**两者同为“编译型语言 + retained/细粒度更新”，但终态不是同一类产品。**

NSGo 是 Go 的**原生视图应用引擎**：响应式图、shadow tree、样式、布局、文本准备在 engine goroutine；每次 commit 产出一个 `MountBatch`；平台主线程把差异挂到 native view，常规动画在平台帧钟推进，无需每帧经过 engine（`requestAnimationFrame` 等仍有回调）。它延续 NSH（Rust/Native Shell）的架构，用 Go 重写核心并增配 TSX、i18n、打包与系统服务。

**不是纯系统控件绑定**：macOS 文本/Canvas 可委托绘制到自有 CALayer，Windows 使用 D3D11/DXGI + Direct2D/DirectWrite，watchOS 走 SwiftUI 节点 + Core Graphics；应称“native view + 平台绘制 API 的混合模型”。

Tessell 是 Crystal 的**自绘 retained GUI 框架**：组件/布局/输入自管，FreeType + HarfBuzz + OpenGL/软件后端，像素与帧路径可控，以三桌面平台为目标，明确不做移动/Web/原生控件绑定。

**判断：**
1. 若目标是尽快做 Go 的桌面/移动/Web 业务应用，NSGo 的产品面、系统集成、组件面、测试与打包链显著更完整；它仍是早期、API 不稳定项目，不等于生产成熟。
2. Tessell 应坚持自绘路线。改追 NSGo 的原生控件路线会丢掉 Crystal 自绘空位与像素自由，并把工作量转为多个原生后端的长期追赶。
3. NSGo 最值得借鉴的不是平台数量或 TSX，而是**增量提交的全量重排 oracle、原生对象创建节流、跨线程性能计量、同一套用户语义测试在 headless/真机复用**。
4. 当前最大差距是**验证与可交付闭环**，不是响应式内核。Tessell 已有 Signal、布局双层缓存、FakeHost，无需因 NSGo 再造一轮。

## 1. 逐轴对比

| 轴 | NSGo | Tessell | 研判 |
| --- | --- | --- | --- |
| 语言/生态 | Go 1.27.3；Go + TSX/goja；Go 工具与包生态 | Crystal >=1.21；纯 Crystal DSL/组件；FT/HB FFI | NSGo 开发生态优势；Tessell 面向 Crystal 空位 |
| 渲染 | native view 与平台绘制混合：AppKit/UIKit、Android Views、D3D11/DXGI+Direct2D/DirectWrite、GTK4、DOM；macOS 文本/Canvas 可绘入自有 layer | 自绘 DrawList、GL/Software backend、atlas、脏区、路径 stencil/cover | NSGo 原生行为占优；Tessell 像素一致性与自绘自由度占优 |
| 组件更新 | Component.Render 只运行一次；signal 驱动 binding；Show/Each/Dynamic/Catch region 局部重建 | Signal(T) + Kit watch/effect + decl diff + retained 树；`src/tessell/signal.cr` | 骨架接近；NSGo 的公共组件接口更产品化 |
| 布局 | Taffy 0.15 算法的 Go 移植；block/flex/grid；fixtures 对照 | 独立两遍 measure/arrange + final/8 槽缓存/父链早停；`src/tessell/layout.cr` | NSGo CSS 覆盖面更广；Tessell 适合工具 UI 的受控布局范围 |
| 线程 | engine goroutine 拥有 graph，不加锁；外界 `Scope.Post`；平台主线程 apply/动画 | UI 主循环 `Fiber::ExecutionContext::Isolated`；业务 default context；`src/tessell.cr:38-43` | 两者都隔离 UI；NSGo 明确“主线程不等待 engine”并有排队延迟计量 |
| 性能 | 有 frame/commit、app/core、mount item、hop latency、CPU/GPU/MEM 运行时观测；有同机 NSH 对照 | 稳态零分配、op/计数门禁；离线 frame/scroll bench | NSGo 可观测性和跨平台样本领先；不能直接比较绝对数字 |
| 测试 | `nsgotest` 同 API headless 与平台输入；真实窗口、截图、原生 IME/按键；测试模式全量重排校验增量漏发 | 组件契约/合成事件、DrawList/op 计数、golden 像素、FakeHost、平台专项 spec | Tessell 的像素与计数纪律强；NSGo 端到端用户路径与平台矩阵更完整 |
| 组件与系统服务 | DataTable/编辑器/富文本/终端/图表/流程图；窗口/菜单/权限/分享/支付/更新等 | Kit 八类基础组件 + VirtualList/Overlay；示例 calculator/text editor/stock/sheet | NSGo 产品广度大幅领先；Tessell 应避免横向铺开 |
| 分发与 DX | `nsgo dev/test/check/build`；热重载/DevTools/安装包/更新 | `crystal spec`、Windows gate/package、文档站；跨平台 gate/CI 未完成 | NSGo 明显领先 |
| 平台边界 | macOS/iOS/tvOS/watchOS/Android/Windows/Linux/Web 声明 Runs；HarmonyOS Preview；小程序 Experimental，未在厂商工具验证且有 2MB 限制 | Windows 证据最完整，macOS SDL2/GL 示例已有证据；Linux GUI 未验证；平台 IME/a11y provider 未完成 | 不能把 NSGo 的“Runs”读成生产成熟；Tessell 也不应把 headless 当跨平台完成 |
| 许可 | LICENSE 为 Apache-2.0 原文，另带 NOTICE；GitHub 仓库元数据显示 Other/NOASSERTION | MIT | 借鉴算法思想与源码复制的许可/NOTICE 义务须分开处理 |
| 社区快照（GitHub API，非质量指标） | 583 stars、36 forks、166 open issues（含 PR）；当日持续提交 | 0 stars、0 forks、5 open issues；最新 release v0.4.1 | NSGo 关注度与迭代活跃度更高；issue 数不能直接当 bug 数 |

## 2. NSGo 的真实优势与代价

### 优势

- **职责分离明确**：engine 不碰主线程 UI 对象，主线程不等待 engine（macOS resize 有最多 16ms 特例）；commit 一次发送差异；常规动画在平台帧钟推进、空闲停止，但 rAF 回调和布局动画提交仍可能进入 engine。依据：NSGo `ARCHITECTURE.md:88-99,110-116`，`docs/architecture/animation.md:3-19`。
- **测试不是只测内部树**：headless model 消费与真实平台一致的 mount batch，selector 面向用户可见 label/text/role；真机/桌面走原生输入与截图。依据：`docs/architecture/testing.md:3-24`、`.github/workflows/test.yml:19-56,58-146`。
- **性能计量覆盖线程边界**：`PerfMonitor` 同时记录 engine commit、主线程 frame、app/core 分项、mount item 数与 hop latency；源码：`internal/engine/perf.go:1-27,49-68,114-160`。
- **有控制长尾的机制**：列表与 scroll view 中屏幕外原生 view 按帧创建；单批超过 64 后延迟屏幕外内容，后续每批最多 32 个或 4ms，但可见节点优先、sticky/overlay/动画/焦点等不走延迟。源码：`core/pace.go:11-45,98-135`。
- **原生能力的复利**：IME、滚动、菜单、选择、系统无障碍、嵌入 WebView/Video 等直接以平台能力为底，而不是自己重做。

### 代价与风险

- **平台差异没有消失**：每个后端仍需实现挂载、文本、输入、样式、canvas/shader 与服务；它模仿 Liquid Glass 等平台特性，也增加跨端一致性成本。
- **原生 view 的数量与属性更新是性能瓶颈**：官方记录 Apple 上 600 个每帧变更文本约 88–90fps/120Hz，主线程约 80%，Go 只占约六分之一，Core Animation 是大头；这说明“Go 内核快”并不自动等于“整帧快”。依据：`docs/architecture/performance.md:66`（文档自述，未本次复测）。
- **不是零运行时/零依赖承诺**：Go runtime、goja、purego、esbuild 等已进入 go.mod；Apple/Windows/Linux/Web 的系统组件另有要求。Tessell 也不等于真正无依赖，需 FT/HB 等动态库。
- **成熟度仍有限**：README 明示 early、API unstable；roadmap 仍列 Windows/iOS/Web 的部分性能复核、音频跨平台、远程推送等缺口；小程序未在厂商工具验证。
- **CI 配置不等于全绿**：复核指定 main commit 的 GitHub Actions run `44557280056`：Windows、test（Linux）、Gallery(web)、apple-simulator、android 成功；Apple 桌面 job 失败、Gallery(macOS) 随后未给出 conclusion。失败根因未读取日志，不能推断是产品缺陷还是流水线问题。
- **借鉴不是直接拿来即可用**：Apache-2.0 + NOTICE 与 Tessell MIT 不同；复制源码需保留许可、变更标识及适用 NOTICE，不能只复制算法文件。

## 3. Tessell 的借鉴优先级

| 优先级 | 建议 | 为什么/边界 |
| --- | --- | --- |
| P0 | 在 debug/test Runner 加“强制全量布局+全量 emit，对比增量提交漏发”oracle | 对应 NSGo `core/commit.go:178-205`。复用现有 DrawList/op 流，不需要窗口/GPU，不破坏计数门禁 |
| P0 | 先完成 X0–X3：跨平台字体/测试分层、可选 SDL Host、CI 矩阵、真实窗口证据 | 本轮实测暴露该问题：macOS 全量 `crystal spec` 在 `spec/text_emoji_color_spec.cr:3-10` 直接打开 Windows 字体而异常；推荐子集 229 绿 |
| P1 | 增加 frame/commit 双视角运行时指标：layout/paint/present、提交命令数、invalidate→present 延迟 | NSGo 的 hop latency 思路适用于 Tessell；保持“门禁看计数、优化看分布” |
| P1 | 将 `nsgotest` 的 selector + settle + headless/target 同测试思想映射为 Kit 用户路径测试 | 复用现有 FakeHost 和平台 Host，勿在 CI 用 sleep 等动画 |
| P1 | 若真实应用出现“大批 mount 长尾”，在 Host/mount 边界加可取消的 screen-off 创建节流 | 只限滚动/虚拟列表屏幕外内容；可见性、焦点、overlay、动画必须立即创建；不能照抄 32/4ms 常量 |
| P2 | UI 侧闭式组合动画：opacity/translation/scale 走 CompositeOnly，manual clock、owner 清理、无动画停帧 | NSGo 动画模型值得借鉴；保持 Isolated UI，不照搬 engine/main 双线程，不把 rAF 说成零 Go 开销 |
| P2 | 布局增加 Taffy/CSS fixtures 作为外部 oracle，known-failures 自动收口 | 仅在确实需要 flex/grid 兼容时做；不把 CSS 全兼容扩张成反目标 |
| 不做 | 改原生控件、引入 goja/TSX、追全平台服务清单、拿 NSGo 数字直接宣称 Tessell 更快 | 路线不符、生态不匹配、口径不可比 |

## 4. 本机复验

环境：macOS arm64，Crystal 1.21.1，Tessell HEAD `65f3857`，工作区最初无未提交输出。

- `crystal spec`：**失败（启动异常，不是断言失败）**；`FtMeasurer.open: font file not found: C:/Windows/Fonts/seguiemj.ttf`，路径见 `spec/text_emoji_color_spec.cr:3-10`。与 [README.md](../README.md) 所记“通用 spec 仍有 Windows 字体路径依赖”一致。
- `crystal spec spec/apps spec/text_unix_smoke_spec.cr spec/kit`：**229 examples / 0 failures / 0 errors / 0 pending**，119.17ms。
- 本次未运行 NSGo，未复测其 gallery、平台测试或 benchmark。完整 clone/归档受网络中断，改为固定 commit 的 GitHub API/原始文件读取。

## 5. 已立项 issue

| issue | 方向 | 优先级 |
| --- | --- | --- |
| #58 | 增量提交的全量重放 oracle | P0 |
| #59 | 跨宿主用户操作测试 | P1 |
| #60 | 帧/提交分段性能观测 | P1 |
| #61 | X0–X3 跨平台测试与真实窗口 L1 | P0 |
| #62 | 屏幕外创建节流，先实证长尾 | P1 |
| #63 | CompositeOnly 组合动画 | P2 |
| #64 | 布局 Taffy/CSS fixtures 正确性 oracle | P2 |

既有 #48 已覆盖 SDL 宿主/字体发现的外部消费者摩擦；#49 已覆盖 flex/grow 诉求。本研究不重复创建对应 issue。#64 是独立正确性 oracle，不要求先完成 #49。

## 6. 复核与覆盖边界

- 已覆盖：官方 README/架构/NSH 关系/roadmap、提交核心、view pacing、性能监测、用户语义测试、CI 工作流、go.mod、许可文本、仓库与 release API。
- 关键缺口：未实机验证 NSGo 的多平台能力与性能；未全面审查每个平台后端实现；社区快照不代表质量。
- **独立复核通过（修正后）**：独立核查纠正“原生控件渲染”为 native view + 平台绘制 API 混合模型；补充 Apple 桌面 CI 失败事实；确认 P0 全量重放 oracle、跨宿主用户测试、分段计量为有效建议。未再发现会改变“坚持 Tessell 自绘路线”这一结论的证据。
- 未覆盖项仍保留：未实机验证 NSGo 的多平台能力与性能；未全面审查每个平台后端实现；社区快照不代表质量。
