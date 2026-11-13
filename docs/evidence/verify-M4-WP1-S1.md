# verify-M4-WP1-S1 (UI DSL builder/UiKey/apply)

- HEAD: 1f238b273990300382e946ef43e4a28715850769
- 环境: Windows/PowerShell, Crystal 1.22.1, PATH 含 `C:\msys64\ucrt64\bin`
- 核验对象(未提交): `src/tessell/ui/key.cr`(50), `builder.cr`(139), `apply.cr`(328), `spec/ui_builder_spec.cr`(376), `src/tessell.cr`(36,+require)；只读+重跑+探针 `bin/_v_ui.cr`(已删)，未 commit

## 重跑与自报对账
| 项目 | 自报 | 实测 | 结论 |
|---|---|---|---|
| spec/ui_builder_spec.cr | 11 examples,0 failures | 11 examples, 0 failures, 0 errors, 0 pending EXIT=0 | 一致 |
| crystal spec 全量 | 218 examples,0 failures | 218 examples, 0 failures, 0 errors, 0 pending EXIT=0 | 一致 |
| crystal build | - | `src\tessell.cr -o bin/_v_ui.exe` BUILD_EXIT=0(已删) | 通过 |
| 行数(k/b/a/spec/tessell.cr) | 50/139/328/376/36 | ReadAllLines: 50/139/328/376/36 | 一致 |
| ui_apply windows | [0,0,0] | 单文件 [0,0,0]；全量 [0,16,0]（均过判据） | 数值波动，判据通过 |
| ui_builder windows | [16,0,0] | 单文件 [0,0,0]；全量 [0,0,0]（均过判据） | 数值波动，判据通过 |

## 逐项结论
1. **P1 apply 吞外部脏**：**失败**。`src/tessell/ui/apply.cr:102-111` 帧起始无条件 `root.clean!` 且清理 `pool.active` 全部节点。探针：外部 `mark_dirty(Paint)` 后无变化 apply → `dirty_before_apply=Paint dirty_after_apply=nil swallowed=true`。会吞 VirtualList/Router/a11y 外部标脏。清理范围=root + 全部 active(map已激活)节点；pooled未激活不在 live/active 集。
2. **节点复用(对象身份/id)**：通过。删中间后同key再现 `same_object=true id_stable=true`；插入/删除/重排复用同对象且 id 不变。
3. **脏集最小性**：通过。改叶子 bounds(layout)→`leaf(Layout)+parent(Layout)+root(Layout)` DFS序(3)；仅改 paint→仅 `leaf(Paint)`(1)，父链/兄弟不脏。
4. **零分配真实性**：通过。spec 三窗取max、ensure GC.enable、N=1000、A<N 且 B<=256（引 `docs/evidence/M2-WP2c-zero-alloc-criterion.md`）；spec 原始行：ui_apply `[0,0,0]/[0,16,0]`，ui_builder `[0,0,0]`。**负例对抗变红(CAUGHT)**：builder 每次 `Array(Int32).new(1)`，`windows=[44144,47680,48240] criterion_ok=false`→重试 `[47760,48272,47760] criterion_ok=false`→`NEG_RESULT=CAUGHT`。
5. **无字符串 key / id_str 分配点**：通过。`src/tessell/ui/*.cr` 无 String-key 分支；`to_s` 仅 `src/tessell/ui/apply.cr:153`，在“brand new key”分支(:152-159)且非复用路径(:126-151)。
6. **自报对账**：spec/全量/build/行数一致；windows 仅数值波动(均合格)。

## 探针关键原始行(bin/_v_ui.cr,已删)
- `P1_EXTERNAL dirty_before_apply=Paint dirty_after_apply=nil swallowed=true`
- `REUSE_DELETE_REINSERT same_object=true id_stable=true id=15779274768647818215`
- `REORDER a=true b=true c=true` / `DELETE_MIDDLE a=true c=true b_pooled=true` / `INSERT_BACK a=true b=true c=true`
- `LAYOUT_LEAF_CHANGE count=3 set=[590684067820433389(Layout),17365562644410574267(Layout),2755958657826924008(Layout)]`
  `LDETAIL ... layout=true paint=false comp=false`(×3, DFS序 root→parent→leaf)
- `PAINT_ONLY_CHANGE count=1 set=[2755958657826924008(Paint)]` / `PDETAIL ... layout=false paint=true comp=false`
- `NEG_ADVERSARIAL delta_prime=51248 delta_calib=0 delta_work=48240 N=1000 windows=[44144,47680,48240] retried=false attempt=1 criterion_ok=false`
- `NEG_ADVERSARIAL delta_prime=51248 delta_calib=0 delta_work=48272 N=1000 windows=[47760,48272,47760] retried=true attempt=2 criterion_ok=false` / `NEG_RESULT=CAUGHT`

## 缺陷与裁定
| 级别 | 位置 | 复现/证据 | 影响 |
|---|---|---|---|
| P1 | src/tessell/ui/apply.cr:102-111 | 无变化 apply 吞外部 active 节点脏：`swallowed=true` | 吞 VirtualList/Router/a11y 脏标记，可能漏绘/漏处理 |

**裁定：FAIL**（存在 P1）。
