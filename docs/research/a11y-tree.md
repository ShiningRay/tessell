# M2-WP5 无障碍（a11y）最小树设计稿（schema / 焦点同源 / UIA FFI 可行性 / 可测判据）

- 产出：docs/research/a11y-tree.md（task-69，翰林院编修 hanlin-bianxiu，仅写本文件）
- 时间：2026-11-13 10:25 +08:00；HEAD=7cfb44f（task-69 任务书口径）
- 边界：只写本文档；未改 src/spec/tools/examples，未改 plan/roadmap，未 commit，他人文件未触碰
- 口径：事实标 `文件:行` 或命令输出；[未验证]=未实测（禁凑数）；[推断]=推演
- 依据：task-69 任务书 6 项必含；与 virtual-list-a11y.md §5/§6 口径一致

## 0) 结论先行

- C1 最小树与 retained 树并行维护（只读镜像），不改 Node 类（同 focus.cr:9 纪律）
- C2 focused 单一真相：a11y 只读 FocusManager.focused，不另存焦点状态
- C3 虚拟列表 a11y 只暴露可见窗口节点，children_count 表达总量，禁万节点
- C4 UIA 纯 FFI：M2 不做 COM provider；留 A11yNode 接口形状，M3 评估接入
- C5 a11y 构建零分配不作 M2 门禁判据（理由见 §6 J9，criterion「能/不能证明」口径）

## 1) 最小树 schema（M2 最小集）

- 节点类型：record A11yNode（非 class，避免继承层级；字段全只读）
- role : A11yRole（enum，M2 最小集见下列 8 值）
- A11yRole 最小集：window / group / text / button / list / listitem / scrollview / scrollbar
- name : String（显示名；来源见 §6 J6）
- value : String?（可空；文本内容或滚动位置字符串）
- bounds : Rect（直接复用 Node#bounds，同坐标系，见 §2）
- focusable : Bool（谓词委托 FocusManager#focusable?，不另存）
- focused : Bool（= FocusManager#focused?(node) 实时查询，不存字段）
- enabled : Bool（M2 默认 true；禁用态来源未实现 [推断]）
- children : Array(A11yNode)（M2 物化可见子集；懒加载视图列 M3 [未验证]）
- index_in_parent : Int32（由 parent.children.index(self) 派生，不落库）
- children_count : Int32（虚拟列表专用：逻辑总行数，非物化数）
- scroll_offset : Int32（虚拟列表首可见行索引）
- window_size : Int32（可见窗口行数；三元组 children_count/scroll_offset/window_size）
- 枚举外 role（checkbox/slider 等）列 M3，M2 不实现 [未验证]

## 2) 与 node.cr 现有字段逐条对照（映射表）

- Node 已有：id : String（node.cr:27）→ a11y name 的默认候选来源
- Node 已有：bounds : Rect（:28）→ a11y bounds 同值同坐标系（hit_test.cr:6 root 坐标系）
- Node 已有：children : Array(Node)（:30）→ a11y children 的遍历数据源
- Node 已有：parent : Node?（:29）→ index_in_parent 派生依据
- Node 已有：三级脏标记（:35-37,53-63）→ a11y 镜像失效触发（变化时重建视图）
- Node 无、新增于 A11yNode：role / value / enabled（Node 类不污染）
- Node 无、只读委托：focusable/focused（源在 FocusManager，见 §3）
- Node 无、新增于 A11yNode：children_count/scroll_offset/window_size（虚拟列表三元组）
- 不改 Node 类的理由：focus.cr:9「本包不修改 Node 类」先例 + 零分配热路径不染指
- 映射结论：schema 9 基础字段中 4 复用 Node（id/bounds/children/parent），5 新增于 A11yNode

## 3) 焦点单一真相（FocusManager 是唯一源）

- focused 语义：FocusManager#focused : Node?（focus.cr:14,:33-35）是唯一真相
- a11y focused 属性 = focus_manager.focused?(node)（focus.cr:37-39）实时查询
- 禁止：a11y 层缓存/镜像焦点字段 ⇒ 双份真相会漂移（违反 task 书第 2 条）
- InputRouter 投递同源：PointerDown→focus(target)（router.cr:36-42）与 a11y 同一 @focused
- 键盘事件同源：Key/Text→focused（router.cr:52-53）；Blur→blur()（router.cr:56-58）
- 导航同源：next/prev 前序 DFS+回绕（focus.cr:50-78）即 a11y 遍历顺序依据
- 单节点规则：root 无子且可聚焦时环仅 root（focus.cr:62-65）a11y 须同语义
- detach 节点不入环（focus.cr:6-8 注释）⇒ 焦点节点被移除后 focused 回落 nil/他移
- 焦点变化可观察：M2 仅暴露「查询式」；事件/回调机制 [未验证]（未见既有实现）

## 4) 虚拟列表联动（万行不得生成万节点）

- 表达法：a11y 列表节点携带 (children_count, scroll_offset, window_size) 三元组
- children_count = 逻辑总行数（如 10000），非物化节点数
- scroll_offset = 首可见行索引；window_size = 可见行数（视口行+缓冲行）
- 物化规则：仅 window_size + 缓冲行实例化 A11yNode；复用池同虚拟列表（virtual-list-a11y.md §1）
- 禁物化：遍历 API 对 [scroll_offset, scroll_offset+window_size) 之外的行不建节点
- 判据锚点：virtual-list-a11y.md §6 判据 3（10000 行 → instantiated ≤ viewport+buffer）
- 滚动时 a11y 视图随 CompositeOnly 失效重建可见窗口（virtual-list-a11y.md §2）
- 行内容变化走 fetch(index) 回调（virtual-list-a11y.md §1），a11y 只读不缓存内容 [推断]
- 焦点落在被回收行时：焦点回落规则 [未验证]（focus.cr 环语义见 §3，未与池联动实现）

## 5) Windows UIA 纯 FFI 可行性（结论：M2 不做）

- 实测：UIAutomationCore.dll 存在 System32 7.2.26100.1 / SysWOW64 7.2.26100.9818（Test-Path）
- 未实测：DLL 导出符号清单（无 dumpbin，未解析 PE 导出表）[未验证]
- 涉及 API：UiaReturnRawElementProvider / UiaHostProviderFromHwnd / IRawElementProviderSimple
- M3 最小导出（若做）：UiaHostProviderFromHwnd、UiaReturnRawElementProvider [未验证]（导出名未核实）
- IRawElementProviderSimple 6 成员（4 方法+2 属性，公开接口惯例列举，本机未核 [未验证]）：
- GetPatternProvider(patternId : Int32) : Void*（返回 pattern 接口对象）
- GetPropertyValue(propertyId : Int32) : Void*
- GetHostRawElementProvider() : Void*（返回 host provider）
- SetFocus() : Void
- BoundingRectangle : Rect（属性，非方法）[未验证]
- ProviderOptions : UInt32（属性，非方法）[未验证]
- COM vtable 手写成本：QueryInterface/AddRef/Release + IUnknown GUID + stdcall 约定 [未验证]
- Crystal 侧：lib 声明 + 函数指针 struct 手工布局；本仓库无 COM 先例 [未验证]
- 不做理由 1：task 书范围=M2 最小树；provider 接入属 M3/M4 风险面（architecture.md:181 后置）
- 不做理由 2：vtable/生命周期/线程模型均未实测，贸然写入=编造（纪律禁）
- 留下接口形状：A11yNode 字段不变；未来 provider 适配层以 A11yNode 为数据源（to_provider() [推断]）
- M3 接入路径：先做 WM_GETOBJECT + UiaReturnRawElementProvider 探针（最小验证）[推断]

## 6) 可测判据（≥7，含边界；零分配结论见 J9）

- J1 空树：root 无子 ⇒ 遍历返回空序列、不 raise、children_count=0
- J2 单节点：root 即唯一节点；index_in_parent=0；bounds==root.bounds
- J3 焦点同源：focus(node) 后 a11y.focused(node)==true 且 == focus_manager.focused?(node)
- J4 焦点节点被移除：remove_child 后 a11y focused 回落（nil 或端点，focus.cr:66-77）
- J5 可见行裁剪：10000 行场景物化 a11y 节点 ≤ 32（视口+缓冲，virtual-list-a11y.md §6 判据 3）
- J6 name/value 来源：name 默认取 Node#id；value 只读（scroll_offset/可见区间/总行数）
- J7 遍历顺序：a11y 前序 == FocusManager.collect_descendants 前序 DFS（focus.cr:80-90）
- J8 bounds 一致：a11y.bounds == Node#bounds（同 Rect 值，root 坐标系 hit_test.cr:6）
- J9 a11y 构建零分配：不作 M2 门禁判据（结论；理由如下两条）
- J9 理由 1：criterion「能证明无 per-call / 不能证明绝对零分配」（M2-WP2c:29-34）
- J9 理由 2：a11y 视图重建含字符串/数组，M2 无稳态基线；先观测记录后定 [推断]

## 7) 风险（≥6）

- R1 UIA 回调线程模型：COM STA/UI 线程亲和，跨线程回调崩溃面 [未验证]
- R2 COM 生命周期：AddRef/Release 手工配对，泄漏/悬垂 [未验证]
- R3 每帧重建 a11y 视图成本：万行滚动时 view 重建 O(window) 仍需压测 [未验证]
- R4 屏幕阅读器兼容（NVDA/Narrator）无法自动测，需人工/CI 外手段 [未验证]
- R5 Windows 字体/语言：UIA name 字符串编码（UTF-16）与 CJK 覆盖 [未验证]
- R6 DPI：bounds 单位物理像素 vs DIP；96 vs 144 未测 [未验证]
- R7 双树一致性：retained 树增删子树时镜像同步遗漏 [推断]（virtual-list-a11y.md §7）
- R8 焦点谓词注入：focusable 谓词变更时 a11y focusable 视图需同步刷新 [未验证]

## 8) M3 延展（M2 决策不留死）

- macOS NSAccessibility：Objective-C runtime messaging，FFI 形态不同 [未验证]
- Linux AT-SPI：D-Bus 接口，非 COM [未验证]
- M2 决策不留死：树模型平台无关；provider 层抽象为可替换接口 [推断]
- architecture.md:181「macOS 走 NSAccessibility，其他平台后置」= 官方排序依据

## 9) 与既有口径对齐

- virtual-list-a11y.md §5：a11y 并行树/只读镜像/焦点复用 FocusManager —— 本稿沿用
- virtual-list-a11y.md §6 判据 1/2/3/7：遍历序/焦点可观察/万行裁剪/复用命中 —— J1-J8 对齐
- virtual-list-a11y.md §3：scenario=scroll/jump 零分配协议 —— J9 观测口径同源
- plan.md:247 M2-WP5：最小可检视/可遍历树；依赖 M2-WP1；风险「投入不足」
- plan.md:118 虚拟列表视口实例化+复用/禁一次性超大节点集 —— §4 同口径
- M2-WP2c-zero-alloc-criterion.md:29-34「能/不能证明」—— J9 结论依据
- architecture.md:181 无障碍树与 widget 树同步维护；:177-181 §5.5 最高风险前置验证

## 10) 证据锚点

- src/tessell/core/node.cr:27-38（字段）, :53-63（dirty?）, :103-137（add/remove/detach）
- src/tessell/input/focus.cr:14-15, :27-47, :50-78, :80-90
- src/tessell/input/router.cr:34-60（投递）, :11（不分配每事件 Array）
- src/tessell/input/hit_test.cr:6（bounds 视为 root 坐标系）
- docs/research/virtual-list-a11y.md:58-68（§5 a11y 最小树）, :70-80（§6 判据）
- docs/plan.md:247（M2-WP5）, :118（虚拟列表）, :91（Invalidation）
- docs/architecture.md:177-181（§5.5）, :181（同步维护/NSAccessibility）
- docs/evidence/M2-WP2c-zero-alloc-criterion.md:29-34（能/不能证明）
- UIAutomationCore.dll 存在性：Test-Path 输出（System32/SysWOW64，版本见 §5）

## 11) 结论摘要（5 条）

1. schema：A11yNode record；9 基础字段中 4 复用 Node（id/bounds/children/parent），5 新增
2. 焦点：FocusManager 唯一源，a11y 只读查询，InputRouter 投递同源
3. 虚拟列表：(children_count, scroll_offset, window_size) 三元组，禁万节点
4. UIA：M2 不做 COM provider；DLL 存在已实测，导出/vtable 成本 [未验证]
5. 判据：J1-J9（含空树/单节点/焦点移除边界）；a11y 零分配不作 M2 门禁

## 12) 边界

- 仅本文档；未写 src/spec，未改 plan/roadmap，未 commit；他人工作区文件未触碰
- [未验证] 均真实未测；[推断] 为推演；无编造 API/数值
