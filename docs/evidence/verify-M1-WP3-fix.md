# M1-WP3 补丁核验：detach/remove_child 双向一致性 + M1 全量回归

核验方：大理寺卿 dalisi-qing（独立核验，只读+重跑，唯一写入本报告）。
任务书：task-37（ready，blockedBy task-36 已满足）。核验对象：task-36 补丁（`src/tessell/core/node.cr` add_child/remove_child/detach、`spec/core_node_detach_spec.cr`）+ M1 全量回归。

## 0. 环境与边界
- cwd `C:\Users\ShiningRay\projects\ShiningRay\tessell`；HEAD `0c4990c`；Crystal `1.22.1 [23828b0a40] (2026-10-23)` / LLVM 23.1.3 / x86_64-w64-windows-gnu；OS `Microsoft Windows NT 10.0.26300.0` AMD64；PATH 含 `C:\msys64\ucrt64\bin`。
- git status（核验前）：` M src/tessell.cr`（task-30 起即 require core/node，非本补丁语义改动）+ task-30/32/34/36 交付物 untracked（`src/tessell/core/`、`src/tessell/render/`、`spec/core_node_spec.cr`、`spec/core_node_detach_spec.cr`、`spec/core_node_zero_alloc_spec.cr`、`spec/render_draw_list_spec.cr`、`spec/render_dirty_into_spec.cr`、`tools/zero_alloc_frame.cr`、`docs/evidence/M1-WP5-zero-alloc.md` 等）。
- 边界：未改 `src/`、`spec/`、`tools/`、`docs/`；临时脚本 `bin/_verify_wp3_fix.cr` 运行后即删（bin/ gitignored）。

## 1. 代码语义（逐行核 `src/tessell/core/node.cr`，164 行）
- `add_child` :103-115：先取 `old_parent = child.parent`；若 `old_parent && old_parent != self` 则 `old_parent.remove_child(child)`（重挂载先从旧父移除，旧父 children 不留悬挂引用）；再 `@children.includes?(child)` 幂等（同父重复 add 不重复追加，仅重申 parent）；否则 `child.parent = self; @children << child`。返回 child。
- `remove_child` :119-128：`@children.index(child)`（O(n) index 查）；命中则 `delete_at(idx)` + `child.parent = nil` 返回 true；未命中返回 false；不改任何脏标记。
- `detach` :132-137：`parent = @parent`；有父则 `parent.remove_child(self)`（经由 remove_child 置 @parent=nil）；根节点（parent=nil）无副作用。
- 双挂/悬挂路径审计：
  - 双挂：add_child 先经旧父 remove_child（旧父 children 删除 + child.parent=nil），再加入新父；无节点同时出现在两父 children。
  - 悬挂：remove_child/detach 均同时清 child.parent；旧父 children 不含已移除节点。
  - 幂等：同父重复 add 走 includes? 分支，不重复追加、parent 不变。
  - 脏标记：add/remove/detach 均不改脏标记（与 WP3「 detach 不传播/清除脏」一致；注释 :101-102,:117-118,:130-131 写清）。
- 结论：语义正确，未发现双挂/悬挂引用路径。

## 2. 自建 4 层树实测（不只看 spec 绿）
脚本 `bin/_verify_wp3_fix.cr`（4 层 root→mid1/mid2→leaf→grandleaf，逐断言 PASS/FAIL 即即删）。关键实测：
- T1 重挂载：leaf1 从 mid1 挂到 mid2 → `old_parent_children_has_leaf1=false`、`new_parent_children_has_leaf1=true`、`new_parent_size=2`、`leaf1_parent=mid2`、`no_node_double_mounted=true`（全树节点最多出现在 1 个父 children）。
- T2 未挂载 remove：`remove_child(unattached)=false`、old_parent children size 不变、结构不变。
- T3 detach 中间节点：mid2 detach 后 `mid2.parent=nil`、root.children 不含 mid2、`mid2.children.size=2`（leaf2/leaf3 保留，子树完整）。
- T4 detach 根：`root.detach` 后 root.parent=nil、root.children.size 不变、无异常。
- T5 同父重复 add 幂等：`root.add_child(mid1)` 两次 → mid1.children.size=1、无重复槽位。
- T6 重挂载保留脏：
  - T6a Paint：leaf mark_dirty(Paint) → 旧父 root1.dirty?=nil（Paint 不上行传播）→ remove_child 后 leaf.paint_dirty?=true、dirty?=Paint、root1.dirty?=nil（脏保留且旧父不脏）。
  - T6b Layout：leaf2 mark_dirty(Layout) → root1.layout_dirty?=true（上行传播）→ detach leaf2 → leaf2.layout_dirty?=true（保留）、root1.layout_dirty?=true（祖先已标脏不因 detach 清除）→ 挂到 root2 → root2.layout_dirty?=false（新父无传播）→ 重新挂回 root1 后 root1.layout_dirty?=true（传播语义与 WP3 一致）。
- T7 dirty_subtree 边界：
  - T7a root 视角：leaf 脏 + detach 子树后 `root_dirty_ids=[]`（不含已 detach 子树）。
  - T7b detach 子树自身视角：`detached_dirty_ids=["leaf","grandchild"]`（子树自身仍含其脏节点）。
  - T7c 子树 clean! 后 `detached_clean_ids=[]`。
  - T7d 旧父视角：detach 脏中间节点 mid2 后 `root_dirty_ids=[]`（root 视角不含已 detach 子树）。
- T8 双挂终检：全树每个节点最多出现在 1 个父 children（`no_node_double_mounted=true`）。
- T9 悬挂终检：remove/detach 后 child.parent=nil、旧父 children 不含该 child（`no_dangling=true`）。
- 全部断言 PASS（脚本输出 `ALL_4LAYER_ASSERTIONS_PASS`，EXITCODE=0）。

## 3. dirty_subtree 边界与文档说明
- 语义：root 视角不含已 detach 子树（因 root.children 已无该节点，DFS 不达）；detach 子树自身视角仍含其脏节点（子树内部 parent/children 未变）。
- 文档说明：`node.cr:130-131` 注释「只改父子引用，不传播脏标记」「detach 本身不把子树标脏，也不碰祖先脏标记」；`:101-102`「只改父子引用，不传播/清除脏标记（与 detach 一致：脏失效由调用方负责）」；`:117-118`「不改任何脏标记（保留子树原脏状态，由调用方负责失效决策）」。注释写清「detach 不传播/清除脏」，满足任务书要求。

## 4. M1 全量回归（原始输出）
- `crystal spec`：
  `..................................................................................\nFinished in 56.6 milliseconds\n82 examples, 0 failures, 0 errors, 0 pending`，`SPEC_EXITCODE=0`（82/0/0/0，与 lead 所述一致）。
- `crystal build src/tessell.cr`：`BUILD_EXITCODE=0`；根目录 exe 已删（`REMOVED_EXE`），复核无残留。
- `crystal run tools/zero_alloc_frame.cr`：
  `scenario=static frames=200 nodes=205 alloc_bytes=0 delta_zero=true`
  `scenario=paint1 frames=200 nodes=205 alloc_bytes=0 delta_zero=true`
  `ZERO_EXITCODE=0`（两场景 alloc_bytes=0，token 原文如上）。
- layout/measurer/render 未被动：
  - `git status --short` 中 `src/tessell/layout.cr`、`src/tessell/text/measurer.cr`、`src/tessell/render/draw_list.cr`、`src/tessell/render/dirty.cr` 均不在修改列表（仅 ` M src/tessell.cr` require 行）。
  - mtime 佐证（UTC）：layout.cr `2026-11-12 11:20:59`、measurer.cr `12:06:19`、draw_list.cr `12:59:51`、dirty.cr `13:24:43`，均早于本补丁（node.cr/detach spec 为当晚交付）；`git diff -- src/tessell.cr` 仅 require `"./tessell/core/node"` 一行（task-30 起既有，非本补丁语义改动）。

## 5. 单测有效性
- `spec/core_node_detach_spec.cr` 112 行 8 it，断言具体（be_true/be_false/be_empty/eq/contain/size），无 `should_not be_nil` 式空泛断言；覆盖 remove 成功/失败、detach 中间/根、重挂载双向一致、同父幂等、脏保留、dirty_subtree 排除已 detach 子树。
- 用例 8（:94-111）用 Paint 而非 Layout 的理由成立：Layout 会沿 propagate_to_parent 上行污染 root（root.layout_dirty?=true），使「root 视角 dirty_subtree 应为空」的断言因 root 自身已脏而无法成立；Paint 仅标自身、不污染 root，才能干净验证「detach 后 root 视角不含子树、子树自身仍含脏节点」的边界语义。该选择隔离了 detach 语义与 WP3 传播语义，理由成立。
- 补充：用例 7（:80-92）直接断言 remove_child 后 `a.paint_dirty?`/`a.dirty?` 保留、`root.dirty?` 为 nil，覆盖「重挂载/移除保留 dirty」的 WP3 一致性。

## 6. 缺陷清单
- P1：无。
- P2：无。
- P3 观察（不阻断裁定）：
  1. `add_child` 未防环：若把祖先节点挂到其子孙下（如 root.add_child(leaf)），会形成环，dirty_subtree/collect_dirty 递归将栈溢出；M1 阶段由调用方保证树结构，建议后续加环检测或文档约束（`node.cr:103-115`）。
  2. detach 后无脏传播/清除：符合本补丁设计（注释已写清），但 retained 树重挂场景的失效决策完全落在调用方，易误用；建议 M2 窗口期补「重挂即 Layout 失效」策略或文档示例。
  3. `remove_child` 用 `@children.index(child)` O(n) 查 + `delete_at` O(n) 移，高频重挂场景为 O(n²)；M1 阶段可接受，M2 若热路径需索引化。
  4. `dirty_subtree`/`collect_dirty` 无上限/深度保护，深树（>数千层）递归有栈风险；当前 4 层实测无问题。
  5. `mark_layout_only` 为 public（:149-151），外部可绕过 mark_dirty 直接标 Layout 脏；属内部 API 暴露，建议后续收口为 private + 友元或保持文档约束。

## 7. 最终裁定
**PASS**

依据：task-36 补丁语义经逐行核与 4 层树 9 组实测全部通过（双挂/悬挂/幂等/detach 子树保留/根无副作用/dirty 保留/dirty_subtree 边界）；M1 全量回归 82 examples 0 failures（EXITCODE=0）、build EXITCODE=0（exe 已删）、zero_alloc 两场景 alloc_bytes=0（EXITCODE=0）；layout/measurer/render 未被本次修改（git status + mtime 佐证）；单测 8 it 断言具体、用例 8 用 Paint 理由成立；注释写清「detach 不传播/清除脏」。P3 观察 5 条均不阻断。
