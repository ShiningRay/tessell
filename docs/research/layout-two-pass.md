# M1 两遍布局内核接口草案与零分配验收口径（EX-W1-08 / W2-3）

> 状态：**设计草案（未实现）**。本文件仅用于 M1-WP1 开工前评审与单测设计输入，不代表 `src/` / `spec/` 已落地实现。[来源: docs/plan.md:L232; 推断]  
> 对应：`docs/plan-execution.md` D.1 EX-W1-08；`docs/plan.md` M1-WP1/M1-WP2/M1-WP5。[来源: docs/plan.md:L232,L233,L236]  
> 写入范围：仅本文档；未修改 `docs/plan*.md`、`docs/roadmap.md`、`src/`、`spec/`。[来源: 任务书; 推断]  
> 证据标注：`[来源: docs/plan.md:Lx]` 引用规划断言；`[推断]` 为基于规划的设计推演；`[未验证]` 为尚未在本机/实现中证实的事项。

## 1. 两遍布局职责边界（Pass A / Pass B）

### 1.1 总体数据流定位

- 布局阶段位于帧流程“失效 → 布局（仅 Layout 脏子树）→ 绘制 → 提交”链路中：Constraints 下行 → Size/Rect 上行，仅对 Layout 脏子树执行。[来源: docs/plan.md:L130,L143,L144]
- 布局内核职责为“两遍布局（约束下行、尺寸上行）、纯函数求解、文本测量缓存接口”，依赖 Geometry 与抽象 `TextMeasurer`，禁止依赖 Widget 可变实例与平台/GPU C 调用。[来源: docs/plan.md:L41,L84,L232]
- 布局内核应可独立于 UI 树做单测与纯函数求解（输入输出为结构化数据/缓冲）。[来源: docs/plan.md:L41,L82,L232]

### 1.2 Pass A — Measure（自底向上：给定约束 → 期望尺寸，不写回几何）

- **输入**：父节点下发的 `Constraints`（min/max width/height）及节点自身布局属性（Dimension/padding/子引用/测量请求等纯数据）。[来源: docs/plan.md:L76,L82]
- **过程**：沿树自底向上计算。叶子/文本节点在约束内调用文本测量接口获取期望尺寸；容器节点先向子节点分发/派生约束并收集子节点期望尺寸，再按容器规则（Stack/Row/Padding 等）汇总自身期望尺寸。[来源: docs/plan.md:L82,L84,L85,L233; 推断]
- **输出**：节点期望 `Size`（及必要的中间测量结果，可缓存）。[来源: docs/plan.md:L71,L83,L85]
- **约束**：Pass A **不写回**最终几何位置/矩形，不产生可见副作用；结果应可由同一输入确定性复现（纯函数语义目标）。[来源: docs/plan.md:L41,L84,L232; 推断]

### 1.3 Pass B — Arrange（自顶向下：给定最终矩形 → 写回位置）

- **输入**：父节点为当前节点分配的最终矩形/原点与可用尺寸（由上层约束求解与对齐策略确定）。[来源: docs/plan.md:L83,L130; 推断]
- **过程**：沿树自顶向下，将最终 `Rect`/偏移写回布局结果缓冲；容器按主/交叉轴对齐与子节点 measure 结果分配子矩形。[来源: docs/plan.md:L83; 推断]
- **输出**：`LayoutBox`/几何结果（`Rect`/`Size`、子偏移）写入预分配缓冲以降低每帧分配。[来源: docs/plan.md:L83,L166]
- **约束**：Arrange 仅在需要更新几何的（dirty）子树重跑；内容与约束未变时不应触发无意义写回。[来源: docs/plan.md:L130,L160,L234; 推断]

### 1.4 为何单向/单遍 measure 不足

| 场景 | 单向 measure 的不足 | 两遍解法（草案） | 标注 |
|---|---|---|---|
| 文本换行 | 文本首选高度依赖可用宽度；父容器可用宽度可能由兄弟/约束在布局中才确定，单次自底向上无法同时“先知宽度再得高度”并稳定回传。 | Pass A 在给定约束宽度下测量换行后高度；Pass B 在最终分配宽度确定时使用匹配约束的缓存或受控重测。 [来源: docs/plan.md:L85,L130,L233] | [推断] |
| 百分比/弹性尺寸 | 子节点百分比尺寸依赖父节点最终可用空间；自底向上单遍无法在未知父最终尺寸时给出确定子尺寸。 | Pass A 产出期望/弹性意图；Pass B 基于父最终矩形解析百分比与剩余空间分配。 [来源: docs/plan.md:L75,L130] | [推断] |
| 约束对齐与拉伸 | 对齐（居中/末端/拉伸）需要父在主/交叉轴上的最终分配区间；单遍难以同时满足“子要求”与“父裁决”。 | Pass A 汇报期望尺寸；Pass B 按对齐与 `Constraints.constrain` 语义落位。 [来源: docs/plan.md:L76,L130] | [推断] |

结论：两遍（measure + arrange）是满足“约束下行、尺寸/位置上行后再落位”的最小清晰分解；具体容器算法细节待 M1-WP1 实现与单测收敛。[来源: docs/plan.md:L130,L232; 推断]

## 2. Crystal 接口草案（可直接编译的思路，未实现）

> 以下为**接口形态草案**，用于评审命名与依赖方向；实际 API 以 M1 实现与 `crystal spec` 为准。[来源: docs/plan.md:L232,L233,L236; 推断]

### 2.1 与现有 Geometry / 规划术语对齐

- `Point` / `Size` / `Rect` / `Insets` / `Constraints` / `Dimension` 已作为 Geometry 值类型/契约存在或规划；布局草案应复用而非重复定义不一致语义。[来源: docs/plan.md:L40,L70-L77,L82,L83]
- 布局求解入口规划为 `module Tessell::Layout; def self.solve(...)`，输入节点/结果可为 `LayoutNode` / `LayoutBox` 等纯数据或预分配缓冲。[来源: docs/plan.md:L82-L84]
- 文本测量缓存键规划为 `(font_id,size,text_hash,max_width)`，`TextMeasurer` 为可替换抽象。[来源: docs/plan.md:L85,L233]

### 2.2 基础类型与可测量接口草案

```crystal
# 草案（未实现）。与 docs/plan.md:L70-L77,L82-L85 对齐；命名可在实现阶段微调。[推断]
module Tessell
  module Layout
    # 复用 Geometry: struct Size/Rect/Point/Insets/Constraints, alias Dimension (docs/plan.md:L71,L72,L73,L75,L76)
    # 若需显式 record 形态（思路等价）：
    # record Constraints, min_w : Float32, max_w : Float32, min_h : Float32, max_h : Float32
    # record Size, width : Float32, height : Float32

    abstract class Measureable
      abstract def measure(constraints : Constraints) : Size
    end

    abstract class Node < Measureable
      # 子节点容器建议预分配/复用，稳态避免增长分配（docs/plan.md:L83,L166,L236）[推断]
      getter children : Array(Node)

      abstract def measure(constraints : Constraints) : Size
      abstract def arrange(final_rect : Rect) : Nil

      # 组合入口草案：先 measure（可命中缓存）再 arrange（docs/plan.md:L130,L232）[推断]
      def layout(constraints : Constraints, origin : Point) : Size
        # 未实现：返回 Size 或写入 LayoutBox 缓冲（docs/plan.md:L83）
        Size.new(0_f32, 0_f32)
      end
    end
  end
end
```

### 2.3 文本节点、容器与 Padding 签名草案

```crystal
# 草案（未实现）。文本测量依赖抽象 TextMeasurer 与缓存键 (font_id,size,text_hash,max_width)
# （docs/plan.md:L85,L233）。[推断]
module Tessell::Layout
  abstract class TextMeasurer
    abstract def measure(font_id : UInt32, font_size : Float32, text_hash : UInt64,
                         max_width : Float32) : Size
  end

  class TextNode < Node
    def initialize(@text_hash : UInt64, @font_id : UInt32, @font_size : Float32,
                   @measurer : TextMeasurer)
    end

    def measure(constraints : Constraints) : Size
      # 未实现：按 constraints.max_width 与换行策略查询/计算（docs/plan.md:L85）[推断]
      Size.new(0_f32, 0_f32)
    end

    def arrange(final_rect : Rect) : Nil
      # 未实现：写回文本绘制几何（docs/plan.md:L83）[推断]
    end
  end

  class Stack < Node # 垂直/水平堆叠容器草案（命名对齐 DSL/Widget 语义待定，docs/plan.md:L115）[推断]
    def measure(constraints : Constraints) : Size; Size.new(0_f32, 0_f32); end
    def arrange(final_rect : Rect) : Nil; end
  end

  class Row < Node
    def measure(constraints : Constraints) : Size; Size.new(0_f32, 0_f32); end
    def arrange(final_rect : Rect) : Nil; end
  end

  class Padding < Node
    def initialize(@child : Node, @insets : Insets); end # Insets: docs/plan.md:L73 [推断]
    def measure(constraints : Constraints) : Size; Size.new(0_f32, 0_f32); end
    def arrange(final_rect : Rect) : Nil; end
  end
end
```

说明：以上签名仅表达“可测量节点 + 容器组合 + 文本测量依赖”方向；是否采用 `abstract class`/`module`/`struct` 及 `Array(Node)` 具体形态需结合零分配与 API 易用性在 M1-WP1 落地验证。[来源: docs/plan.md:L232; 未验证]

## 3. Measure 缓存与失效传播

### 3.1 Measure 结果缓存键

- 规划基线键：`(font_id, size, text_hash, max_width)` 用于文本测量缓存。[来源: docs/plan.md:L85,L155,L233]
- 草案扩展键（覆盖约束与版本维度，避免错误命中）：`(constraints 或规范化约束, font_id, font_size, text_hash/content_version, font_version, max_width)`。[推断]
  - `content_version`：文本/内容变更版本号，避免仅靠 hash 在碰撞或增量编辑场景下语义不清。[推断]
  - `font_version`：字体加载/atlas/度量参数变更版本，用于全局或按字体失效。[推断]
- 缓存命中与失效需有单测覆盖（M1-WP2 验收方向）。[来源: docs/plan.md:L233]

### 3.2 失效传播（父链 dirty 标记）

- Core 规划包含 retained 节点、`Invalidation` 失效传播与脏标记；失效级别至少区分 `Layout` / `Paint` / `CompositeOnly`。[来源: docs/plan.md:L42,L91,L234]
- 草案：当节点内容、样式、子结构或可影响布局的输入变化时，标记本节点 Layout dirty 并沿父链向上传播直至根或已标记边界，保证祖先可在 Pass A 重新汇总子尺寸。[来源: docs/plan.md:L130,L234; 推断]
- `mark_dirty(kind : Invalidation)` 为最小范围传播目标；仅 Layout 脏子树参与布局求解。[来源: docs/plan.md:L92,L130,L234]

### 3.3 Arrange 仅在 dirty 子树重跑

- 帧流程要求“仅对 Layout 脏子树做…（约束下行、尺寸上行）”与“仅对 Paint 脏子树生成 DrawList”；静态/无变更场景应不执行无意义步骤。[来源: docs/plan.md:L130,L132,L144,L236]
- 草案：若子树无 Layout dirty 且父分配矩形/约束未变化，可跳过该子树 arrange 写回；若父最终矩形变化但子树 measure 结果可复用，仍需对受影响子树执行 arrange（写回位置）但可避免重测。[来源: docs/plan.md:L130; 推断]

### 3.4 与 M1-WP3 retained 失效的衔接点

- M1-WP3 交付 Core 节点、`Invalidation`、脏传播，验收“单测验证最小失效；静态无脏”。[来源: docs/plan.md:L234]
- 布局内核（M1-WP1）应作为纯数据/缓冲求解器被 Core 调用：Core 负责判定 dirty 子树与调度 layout；Layout 负责在给定输入下产出确定结果并支持缓存查询/写入接口。[来源: docs/plan.md:L41,L232,L234; 推断]
- 衔接契约草案：`Layout.solve`/`Node.layout` 接受“脏根/脏集合视图 + 约束/原点 + 可复用结果缓冲 + 测量缓存句柄”，返回/更新受影响区域的布局结果；具体签名待 M1-WP1/M1-WP3 联调。[来源: docs/plan.md:L83,L84,L234; 推断]

## 4. 零分配口径（对齐 M1-WP5）

### 4.1 口径定义与测法（强制顺序）

- 稳态零分配定义：在**无结构变更、无新资源加载、无文本重排/重测**的稳定场景下，目标热路径执行前后堆分配增量为 0；启动/首帧/资源加载/结构变化帧不计入。[来源: docs/plan.md:L166]
- 可执行测法（本机方法学基线）：`GC.collect` 归零观测基线 → `GC.disable` → 记录 `GC.stats.bytes_since_gc`（及必要时 `total_bytes`）→ 执行目标路径 → 再记录 → 判定 `bytes_since_gc` 前后差值为 0。[来源: docs/plan.md:L166,L193,L236]
- M1-WP5 验收：静态场景在 `GC.disable` 下 `bytes_since_gc` 前后差值为 0，并结合零重绘可观测与 M0-WP5m 工具链结论。[来源: docs/plan.md:L236]

### 4.2 稳态 layout 不分配的条件（草案）

- **预分配数组/缓冲并复用**：子节点列表、布局结果（`LayoutBox`/Rect 数组）、DrawList/中间 scratch 容量在稳态前准备，热路径仅 `clear/reuse` 不增长。[来源: docs/plan.md:L83,L101,L166,L167]
- **可复用 scratch**：遍历栈、临时约束派生缓冲、行/列累计器等使用对象池或成员 scratch，避免每帧 `new`。[来源: docs/plan.md:L166; 推断]
- **避免闭包捕获**：热路径内避免创建捕获外部变量的 Proc/闭包对象（尤其在迭代与回调中）。[来源: docs/plan.md:L166; 推断]
- **避免 String 拼接/插值与临时字符串**：缓存键与日志/调试字符串不得进入稳态热路径；文本内容使用 hash/id 与版本号传递。[来源: docs/plan.md:L85,L166; 推断]
- **值类型优先**：Geometry/Constraints/命令等热路径数据优先 struct 值语义以减少堆分配压力（需结合实测）。[来源: docs/plan.md:L70-L77,L100,L167]

### 4.3 三个易破功点与检测方法

| 易破功点 | 破坏方式（示例） | 检测方法 | 标注 |
|---|---|---|---|
| 容器动态增长 | `Array` 在遍历/收集子结果时超出 capacity 触发扩容；临时 `Array` 每帧新建。 | 按 4.1 口径：`GC.collect`→`GC.disable`→记录 `bytes_since_gc`→执行 N 帧稳态 layout→比较差值；差值非 0 则二分定位到分配点（结合 `GC.stats` 采样与代码审计）。[来源: docs/plan.md:L166,L193] | [推断] |
| 闭包与迭代器分配 | `each { |x| ... }` 捕获局部变量、`map/select` 生成新集合、Proc 作为参数传递产生对象。 | 同上口径做前后差值；对可疑路径替换为索引循环/预分配缓冲后复测差值归零。 [来源: docs/plan.md:L166] | [推断] |
| 字符串/装箱与隐式临时对象 | 字符串插值、`to_s`、异常路径外的格式化、union/装箱导致的堆对象（视实现而定）。 | 稳态热路径禁用日志与格式化；用 `bytes_since_gc` 差值门禁捕获回归；对文本路径仅传 `text_hash`/id。 [来源: docs/plan.md:L85,L166] | [推断] |

补充：`GC.stats` 字段与在 `GC.disable` 下的行为细节需以目标运行时实测为准；M0 已建立方法学样本但不等同于所有场景结论。[来源: docs/plan.md:L166,L168; 未验证]

## 5. 单测计划（≥8 条，M1-WP1 可落地）

> 以下为**计划用例**（未实现）。每条均应可在纯布局内核（不依赖 Widget/平台）中以结构化输入驱动。[来源: docs/plan.md:L41,L232]

### 用例 1：固定尺寸叶子节点
- **输入**：单个固定尺寸节点（如 Fixed 100x20），`Constraints` 为宽松/限定范围。
- **期望**：Pass A 返回 Size(100,20)（在约束允许内）；Pass B 将节点放置于指定 origin，`Rect` 为 (origin, 100x20)。
- **判据**：尺寸与位置字段逐值相等；稳态重复 layout 结果一致。[来源: docs/plan.md:L76,L232; 推断]

### 用例 2：文本单行测量与布局
- **输入**：`TextNode` + 桩/抽象 `TextMeasurer`，单行文本，`max_width` 足够；缓存键含 `(font_id,size,text_hash,max_width)`。
- **期望**：measure 返回与 measurer 一致的 Size；同输入重复 measure 命中缓存（可观测调用次数或等价指标）。
- **判据**：尺寸正确；缓存命中/未命中行为符合 M1-WP2 方向；无平台/FFI 依赖。[来源: docs/plan.md:L85,L233; 推断]

### 用例 3：文本换行（受限宽度）
- **输入**：`TextNode` 长文本，`Constraints.max_w` 小于单行宽度；measurer 按 max_width 返回换行后高度。
- **期望**：Pass A 在给定约束下返回更大高度与受限宽度；Pass B 使用最终宽度对应的布局结果写回正确 Rect。
- **判据**：高度随 max_w 收紧而增加（在用例设定下）；换行结果与 measurer 约定一致。[来源: docs/plan.md:L85,L130; 推断]

### 用例 4：百分比/弹性尺寸容器（依赖父最终空间）
- **输入**：容器内子节点含百分比或弹性 Dimension；父在 Pass B 给定最终宽度（如 200）。
- **期望**：Pass A 产出可解析的期望/约束；Pass B 将 50% 子项解析为 100（示例）并正确分配剩余空间。
- **判据**：子 Rect 尺寸与父最终尺寸及规则一致；无负尺寸/越界（除非用例定义裁剪）。[来源: docs/plan.md:L75,L130; 推断]

### 用例 5：嵌套 Padding
- **输入**：`Padding(insets)` 包裹子节点，多层嵌套；子节点固定或可测尺寸。
- **期望**：Pass A 累加 `Insets.horizontal/vertical` 影响期望尺寸；Pass B 子节点 origin 内缩、Rect 尺寸符合 insets。
- **判据**：每层偏移与尺寸符合 `Insets` 语义；与手算期望一致。[来源: docs/plan.md:L73,L83; 推断]

### 用例 6：约束冲突与 clamp 行为
- **输入**：子节点期望尺寸超出 `Constraints`（min/max 冲突或过大/过小）；使用 `Constraints.constrain` 语义。
- **期望**：输出尺寸被 clamp 到约束范围内；布局结果确定且不产生 NaN/负尺寸（除非类型允许并显式定义）。
- **判据**：`constrain` 后尺寸在 `[min,max]` 内；边界值用例可重复。[来源: docs/plan.md:L76; 推断]

### 用例 7：失效重算与缓存复用
- **输入**：两节点树，首次 layout 后仅标记其中一子树 Layout dirty；另一子树输入与约束不变。
- **期望**：仅 dirty 子树重新 measure/arrange；非 dirty 子树复用缓存/结果且几何不变（在父分配不变前提下）。
- **判据**：可通过计数器/桩 measurer 调用次数或结果对象版本验证“最小失效/局部重算”。[来源: docs/plan.md:L130,L234,L236; 推断]

### 用例 8：稳态零分配（layout 热路径）
- **输入**：固定结构与输入的静态场景，预热后进入稳态循环执行 layout（无结构变更、无新资源加载、无文本重排/重测）。
- **期望**：按口径 `GC.collect`→`GC.disable`→记录 `bytes_since_gc`→执行→再记录，前后差值为 0。
- **判据**：差值 == 0（在定义的稳态窗口内）；若非 0 则定位违反 4.2 条件的分配点。[来源: docs/plan.md:L166,L193,L236; 推断]

### 用例 9（补充）：浮点确定性 / epsilon 比较
- **输入**：包含 Fraction/百分比或非整数运算的布局，重复执行相同输入。
- **期望**：同一输入多次 layout 结果位级一致或在定义 epsilon 内一致；比较使用明确容差而非直接 `==`（若涉及浮点累积）。
- **判据**：`(a - b).abs <= eps`（eps 在用例中固定，如 `1e-5_f32`）或序列化几何完全一致；跨运行确定性 `[未验证]`。[来源: docs/plan.md:L232; 推断]

## 6. 风险与未决问题（≥5）

1. **Crystal 值类型 struct 传参/拷贝开销**：`Constraints/Size/Rect` 等 struct 在深层递归 measure/arrange 中的传参与返回成本、是否引入意外拷贝或栈压力，需结合目标版本与优化级别实测。`[未验证]` [来源: docs/plan.md:L167,L232]
2. **`GC.stats.bytes_since_gc` 在 `GC.disable` 期间的行为边界**：禁用 GC 后统计口径、并发/多 context 下采样一致性，以及是否存在实现差异导致误判，需在 CI/本机环境复核。`[未验证]` [来源: docs/plan.md:L166,L168,L236]
3. **measure 缓存键的完备性与失效粒度**：`(font_id,size,text_hash,max_width)` 是否足以覆盖字体 fallback、DPI/缩放、换行模式等因素；`content_version`/`font_version` 的生成与传播成本待设计。`[未验证]` [来源: docs/plan.md:L85,L233]
4. **文本换行与双向文本的测量-布局耦合**：复杂脚本/RTL/Bidi 换行可能要求在特定宽度下多次 shaping/测量，易与“零分配稳态”目标冲突并影响缓存策略。`[未验证]` [来源: docs/plan.md:L85,L244,L245]
5. **浮点布局的确定性与 epsilon 策略**：百分比、分数像素与累积误差可能导致跨平台/跨编译器结果差异；单测比较容差与像素对齐策略需统一定义。`[推断]` [来源: docs/plan.md:L232]
6. **Arrange 脏区与父分配变化的判定条件**：父最终矩形变化但子树 measure 未变时的最小重排范围、以及与 Paint/CompositeOnly 失效的交互边界，需在 M1-WP1/M1-WP3 接口中明确。`[未验证]` [来源: docs/plan.md:L130,L234]

---
（文末）