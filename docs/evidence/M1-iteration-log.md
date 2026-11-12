# M1 迭代记录（WP1/WP2 + WP3/WP4/WP5 + 补丁）— 提交推送收口

## 范围

本轮迭代涵盖 M1 第一轮：M1-WP1 两遍布局内核 + M1-WP2 文本测量接口与缓存 + M1-WP3 retained 节点树三级失效 + M1-WP4 DrawList 批处理/脏矩形合并 + M1-WP5 稳态零分配 + WP3 补丁（detach/重挂载一致性）。
M0 门禁已裁定 PASS-WITH-CONDITIONS，M1-WP1 GO（docs/evidence/M0-gate.md）。

## T25 — M1-WP1：两遍布局内核

- 交付：`src/tessell/layout.cr`（206 行）、`spec/layout_spec.cr`（14 examples）
- 能力：Pass A measure（约束下行、尺寸上行）、Pass B arrange（主轴排列、Fixed/Auto/Fraction）；纯函数、无全局状态；注入 `Measurer` 可选参数
- 核验：docs/evidence/verify-M1-WP1.md（PASS）
- P3 观察：热路径 Array 缓冲待 M1-WP5 消除（TODO 标注）；margin 未参与计算；用例 2/3/7/8 留待后续
- 未验证：Margin 语义、零分配

## T27 — M1-WP2：文本测量接口与缓存

- 交付：`src/tessell/text/measurer.cr`（115 行）、`spec/text_measurer_spec.cr`（12 examples）
- 能力：Measurer 抽象、MeasureKey（FNV-1a 64 位，hash 返回 UInt64）、CachingMeasurer（hits/misses/evictions/invalidate_font/clear）、StubMeasurer（确定性桩）
- 契约：measure(font_id, size, text_hash, max_width) : Size；缓存 key (font_id, size, text_hash, max_width)
- 核验：docs/evidence/verify-M1-WP2.md（PASS）
- 修复记录：hash 返回类型 UInt64（lead 诊断：Crystal 1.22 Object#hash 返回 UInt64）
- 注入：layout.cr 新增 `measurer : Text::Measurer? = nil` 可选参数，默认 nil 等价原行为
- 未验证：真实 FreeType/HarfBuzz shaping（属 M2）

## T26 / T28 — 核验裁定

- T26 (verify-M1-WP1.md)：PASS — 纯函数性/两遍语义/手算 2 例均过
- T28 (verify-M1-WP2.md)：PASS — FNV-1a 正确性/缓存语义/布局注入兼容性

## T30 — M1-WP3：retained 节点树与三级失效

- 交付：`src/tessell/core/node.cr`（交付时 99 行，verify-M1-WP3 实测；T36 后 164 行）、`spec/core_node_spec.cr`（179 行，13 it）、`src/tessell.cr` require 行
- 能力：`enum Invalidation`（Layout/Paint/CompositeOnly）+ 三独立 Bool；`dirty?` 显式优先级 Layout > Paint > CompositeOnly > nil；`mark_dirty(Layout)` 自身+祖先链传播（propagate_to_parent 只标 Layout，不上染 Paint）；`mark_dirty(Paint/CompositeOnly)` 仅自身；`dirty_subtree`/`collect_dirty` DFS 收集
- 核验：docs/evidence/verify-M1-WP3.md（PASS；手写 5 层树 44 项逐节点断言全 PASS；P1/P2 无，P3 观察 6 条）
- P3 观察 6 条（verify-M1-WP3.md §7）：观察-1 detach/remove_child/重挂载缺失（→ T36 补丁关闭）；观察-2 三 Bool 非位掩码；观察-3 mark_layout_only public；观察-4 dirty_subtree 每次新分配（→ T34 collect_dirty 复用 sink 关闭）；观察-5 行数描述偏差（99/179 以实测为准）；观察-6 核验期间并行 render 目录（如实记录）
- 未验证：深树（>数千层）递归栈风险（P3 观察，见 verify-M1-WP3-fix §6-4）

## T32 — M1-WP4：DrawList 复用缓冲 + 最小批处理 + 脏矩形合并

- 交付：`src/tessell/render/draw_list.cr`（121 行）、`src/tessell/render/dirty.cr`（交付时 87 行；T34 后 110 行）、`spec/render_draw_list_spec.cr`（153 行，15 it）、`src/tessell.cr` require 行
- 能力：DrawCmd/Batch struct；DrawList clear 不释放容量、push 复用槽位、build_batches 相邻同 atlas_id+同 clip 合批（kind/color 不参与批键；空 list 0 批）、reserve/自控容量语义（物理槽位=@commands.size，只增不减）；Dirty.merge/merge_into（重叠/相接合并、超限贪心、不产空矩形、空输入空输出）
- 核验：docs/evidence/verify-M1-WP4.md（初判 FAIL：P1 `dirty.cr:30` 参数名 `out` 为 Crystal 保留字，spec/build 全局编译阻断；DrawList 15 例与 Dirty 语义经自含式重跑 44+ 断言全 PASS）→ 修复 `out`→`sink` 后 docs/evidence/verify-M1-WP4-WP5.md 复验 PASS（官方 spec 74/0/0、build 0；P1 关闭，grep 无 `def ... out :` 残留）
- P3 观察（verify-M1-WP4 §6）：DrawCmd 无 z-order/blend/UV 字段；build_batches 不合并 clip（仅按 clip 相等切批）；Dirty 热路径非通用零分配；行数描述偏差；并行交付物记录
- spec 计数演进：30 → 43（T30 +13）→ 58（T32 +15）→ 74（T34 +16）→ 82（T36 +8）

## T34 — M1-WP5：稳态零分配（collect_dirty / merge_into / zero_alloc_frame）

- 交付：`Node.collect_dirty(root, sink)`（sink.clear + while 索引 DFS，无闭包捕获）；`Dirty.merge_into(rects, sink, max_regions)`（原地 union + delete_at）；`merge` 委托 `merge_into`；`tools/zero_alloc_frame.cr`（162 行，205 节点 3 层树，场景 static/paint1，GC 协议 warmup→collect→disable→N 帧→after→enable，ensure 恢复 GC）；`spec/core_node_zero_alloc_spec.cr`（106 行，5 it）、`spec/render_dirty_into_spec.cr`（84 行，11 it）
- 实测：`scenario=static frames=200 nodes=205 alloc_bytes=0 delta_zero=true` / `scenario=paint1 frames=200 nodes=205 alloc_bytes=0 delta_zero=true`（EXITCODE 0；`--json` 可解析；三次可重复）
- 核验：docs/evidence/verify-M1-WP4-WP5.md §4/§5（P1 关闭确认；merge_into 与 merge 6 组等价且顺序一致；sink 复用 1000 次无残留且 size 稳定；工具诚实性核过：无硬编码 0、N 来自 CLI、GC.enable 在 ensure、paint1 每帧真实 mark_dirty+clean!）
- 局限：不含布局重算/文本 shaping/GPU 提交；DrawList 命令重建按缓存 bounds 预付槽位；GC.stats 语义仅 ucrt64 Crystal 1.22.1 有效；paint1 单帧脏节点数上限 node_count+1；容量不足时 `<<` 仍会扩容（调用方需预分配）

## T36 — WP3 补丁：remove_child/detach 与重挂载一致性

- 交付：`add_child` 重挂载先从旧父移除（旧父≠自己时，不产生双挂）+ 同父重复 add 幂等；`remove_child(child):Bool`（移除+`parent=nil`，不改脏标记）；`detach:Nil`（根无副作用）；注释写明 detach 不传播/清除脏标记、由调用方负责失效；`spec/core_node_detach_spec.cr`（112 行，8 it）
- 核验：docs/evidence/verify-M1-WP3-fix.md（PASS：逐行核 + 4 层树 9 组实测，双挂/悬挂/幂等/dirty 保留/dirty_subtree 边界全过；M1 全量回归 82/0/0；P3 观察 5 条：add_child 未防环、detach 后无脏传播策略、remove_child O(n²)、深树栈风险、mark_layout_only public）
- 一处如实修正：detach spec 用例 8 初版用 `Invalidation::Layout` 失败（Layout 沿父链传播使 root 变脏，detach 不清脏属预期语义）→ 改用 `Invalidation::Paint`（不向上传播），断言与 WP3 语义一致（verify-M1-WP3-fix.md §5 认可该选择）

## T31 / T33 / T35 / T37 — 核验裁定汇总

- T31 verify-M1-WP3.md：PASS（43 examples 0/0/0）
- T33 verify-M1-WP4.md：FAIL（P1 `out` 保留字编译阻断；语义自含式重跑 PASS）
- T35 verify-M1-WP4-WP5.md：PASS（P1 关闭；74 examples 0/0/0；零分配三次可重复）
- T37 verify-M1-WP3-fix.md：PASS（82 examples 0/0/0；补丁双向一致性核清）

## 未验证清单（M1 末）

- 真实 FreeType/HarfBuzz shaping（M2-WP2F）
- Margin 语义（M1-WP3 或 M2）
- GSUB 跨字体深度（M2）
- 真实 GPU 提交未接（M2 渲染后端）
- 布局多节点零分配未做（当前零分配证据为 collect/merge/命令重建路径）
- z-order/blend/UV 字段与 clip 合并优化留 M2（verify-M1-WP4 P3 观察-1/2）
- 真实 IME 手测留 M2-WP3 前（M0-WP4-ime 证据：真实组合输入 [未验证]）
- 深树（>数千层）递归栈风险（P3 观察）

## 已知缺口（提交前如实记录）

- add_child 未防环（P3，M2 补：祖先挂子孙会成环，递归栈溢出风险）
- 真实 GPU 提交未接（DrawList 批处理尚未对接后端）
- 布局多节点零分配未做
- z-order/blend/UV 与 clip 合并留 M2
- 真实 IME 手测留 M2-WP3 前

## 自检结果

- `crystal spec`：82 examples, 0 failures, 0 errors, 0 pending（EXITCODE 0）
- `crystal build src/tessell.cr`：EXITCODE 0
- 根目录无 tessell.exe（已清理）
- `.gitignore` 含 `/*.exe`
- `crystal run tools/zero_alloc_frame.cr`：static/paint1 两场景 alloc_bytes=0 delta_zero=true（EXITCODE 0）

## 提交 hash

- 主提交：（回填）
- 回填提交：（回填）
