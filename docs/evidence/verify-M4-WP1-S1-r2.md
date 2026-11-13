# M4-WP1 S1 P1 修复复核（task-115, r2）
- 元信息：HEAD 1f238b273990300382e946ef43e4a28715850769；工作区未提交（含 task-113/r1 变更）；报告 65 行（read/UTF-8）；核验时间 2026-11-13T18:30:34+08:00 (Asia/Shanghai)。

## 1) clean! 全文 grep（apply.cr）
- `Select-String -Path src\tessell\ui\apply.cr -Pattern 'clean!'`：仅 **`203:      nodes.unsafe_fetch(i).clean!`**（`UI.consume` :199-206 内，清传入节点）。`UI.apply` (:97-193) 全文无 `clean!`。

## 2) 独立探针 bin/_v_ui2.cr（非复用 spec，正常态）
- `P1_R2 dirty_before_apply=Paint dirty_after_apply=Paint swallowed=false`（外部 mark_dirty 后无变化 apply 仍脏）。
- `CONSUME_PARTIAL n1_after=nil n2_after=Layout n1_cleared=true n2_kept=true`（consume 后清且仅清传入，未传入脏节点保持脏）。
- `IDEMPOTENT count=0 empty=true`（完整帧幂等：apply→collect_dirty→consume→同帧 apply→collect_dirty 为空）。
- `NEG_ADVERSARIAL delta_prime=52240 delta_calib=0 delta_work=47808 N=1000 windows=[43872,47792,47808] retried=false attempt=1 criterion_ok=false` → 重试 `delta_work=48448 windows=[48448,47808,47808] retried=true attempt=2 criterion_ok=false` → **`NEG_RESULT=CAUGHT`**，`ALL_OK=true`，EXIT=0。

## 3) 鉴别力反证（临时回归→变红→恢复→无残留）
- 注入：在 Pass 1 前临时加入 `root.clean!` + 遍历 `pool.active` 清理（注入后 grep：`REGRESS_LINE:103:root.clean!`、`REGRESS_LINE:110:rn.clean! if rn`、`REGRESS_LINE:215:nodes.unsafe_fetch(i).clean!`）。
- 回归探针（同 bin/_v_ui2.cr）：`P1_R2 dirty_before_apply=Paint dirty_after_apply=nil swallowed=true` → `P1_R2_RESULT=FAIL`，**REGRESS_PROBE_EXIT=1**（探针变红，证明确有鉴别力）。
- 恢复：移除注入块后 grep 仅 **`RESTORE_LINE:203:nodes.unsafe_fetch(i).clean!`**；`git diff --stat -- src/tessell/ui/apply.cr` 无输出（RESTORE_DIFF_EXIT=0），无残留。

## 4) 必跑
- `crystal spec spec/ui_builder_spec.cr`：**14 examples, 0 failures, 0 errors, 0 pending** EXIT=0。含 `P1_EXTERNAL external dirty mark preserved across no-change apply... swallowed=false`；probes `zero-alloc probe(ui_apply): delta_prime=0 delta_calib=0 delta_work=0 N=1000 windows=[0,0,0]`、`zero-alloc probe(ui_consume): ... delta_work=16 N=1000 windows=[0,16,0]`、`zero-alloc probe(ui_builder): ... delta_work=0 N=1000 windows=[0,0,0]`。
- `crystal spec`（全量）：**221 examples, 0 failures, 0 errors, 0 pending** EXIT=0。含 `P1_EXTERNAL ... swallowed=false`；ui_apply `[0,0,0]`、ui_consume `[0,0,0]`、ui_builder `[0,0,0]`、virtual_list `[0,16,0]`。
- `crystal build src/tessell.cr -o bin/_v_ui2.exe` BUILD_EXIT=0（产物已删除）。

## 裁定
- **PASS**（P1 已关闭）。**P1 已关闭（证据）**：①`UI.apply` 无 `clean!`（仅 consume:203）；②独立探针证明外部 mark_dirty(Paint) 经无变化 apply 后保持 dirty（swallowed=false）、`UI.consume` 仅清传入、完整帧幂等为空；③回归注入 clean! 后同探针立即变红（swallowed=true, EXIT=1），恢复后仅 :203 且 `git diff --stat` 无残留；④零分配负例对抗 CAUGHT（3 窗 max+≤1 次重试仍失败）。禁 commit；未碰 C8 `examples/m3_scroll_window.cr`；`bin/_v_ui2.cr` 已删除。