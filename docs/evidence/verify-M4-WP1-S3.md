# M4-WP1 S3 独立核验（左都御史）

行数：67（实测）
HEAD：5547fac（=origin/main）；对象：工作区未提交 task-129 变更；未 commit。
范围：`src/tessell/ui/{builder,apply}.cr`、`src/tessell/a11y/tree.cr`、
`examples/app_demo.cr`、新 `spec/ui_a11y_spec.cr`、新 `spec/router_single_entry_spec.cr`；
`README.md`、`docs/evidence/M4-WP2-licensing.md` 为并行产物，未审。
## 0. 结论

**PASS。P0/P1/P2：无；P3：3 条（残余记录，不阻断）。**
- 全量 spec 两次均 233/0；新增 spec 7/0、5/0；既有 ui_builder_spec 14/0。
- app_demo 三组 verify 均 `a11y_nodes=34`、`alloc_windows=[0,0,0]`、`attempt=1`。
- 自建探针 A–E 全过；删除节点后 emit 3→2，meta_gone=true。
## 1. 必跑证据

| 检查 | EXIT | 关键 token |
|---|---|---|
| crystal spec #1 | 0 | 233 examples, 0 failures, 0 errors, 0 pending（321.55ms） |
| crystal spec #2 | 0 | 233 / 0 / 0 / 0（317.72ms） |
| ui_a11y_spec ×2 | 0 | 7 examples, 0 failures（11.9/11.71ms） |
| router_single_entry_spec ×2 | 0 | 5 examples, 0 failures（173/172µs） |
| ui_builder_spec ×2 | 0 | 14 examples, 0 failures（18.3/17.8ms） |
| crystal build src/tessell.cr | 0 | 2,278,930B；产物已删 |
| build app_demo | 0 | 3,848,823B；产物已删 |
| app_demo base/dark/dpi | 0 | a11y=34；alloc [0,0,0]；attempt=1；pass |
| zero_alloc --json | 0 | static 0B；paint1 16B；criterion_ok=true |
| 回归 text/dirty/scroll | 0 | 2801/1.061789；diff=0；[0,0,0] |
## 2. 自建探针（bin/_v_s3.cr，已删）

```text
A_FIELDS ok=true role=Button name=greeting value=hi focusable=true enabled=false
B_DELETE before=3 after=2 meta_gone=true
C_EMIT count=3 bounds=true idx=0,1
D_VLIST n1=32 vis1=30 n2=32 vis2=30 offset=4000 ok=true
E_DEFAULTS omitted={1, 1, 1} explicit={1, 1, 1} same=true
E_DEEP tree_same=true dirty_same=true
```

- A：role/name/value/focusable/enabled 五字段逐个与 Decl 一致。
- B：删除后 emit 节点数 3→2；不依赖 remove_meta 返回值。
- C：emit 数=Node 树 3；bounds/index/children_count 一致。
- D：10000 行仅 32 节点（容器+30 可见）；scroll_to(4000) 后 offset=4000。
- E：省略与显式默认值的 Node 树逐节点、脏集逐节点一致。
## 3. D6 事件单一入口

grep `@hover|@pressed|@focused|\.focus\(|def focus`（`src/**/*.cr`）共 19 命中：
- `src/tessell/input/router.cr:24,25,30,31,39,41,44,48`：hover/pressed 写入。
- `src/tessell/input/focus.cr:19,24,27,29,33,37,38,42,45,76`：focused 写入。
- `src/tessell/a11y/tree.cr:92`：仅 `focused?` 读取，非写。
无 app_demo/其他第二写入点；D6 通过。spec 注释未作为证据。
## 4. Diff 审计

- `git diff --stat`：5 files，342 insertions/43 deletions；含 README（未审）。
- `git diff --stat -- spec/` 为空；`spec/ui_builder_spec.cr` 未被改动。
- 零分配判据 `delta_work < n && delta_work <= 256` 保留（如 `ui_a11y_spec.cr:265`）。
- `git diff --check` EXIT 0；未发现模糊断言或放宽判据。
## 5. 回归

- `m2_text_window --frames=60 --verify`：2801/ratio 1.061789/pixel_match=true。
- `m3_dirty_window --frames=20 --verify`：diff=0、4<57、ratio .012568、pass。
- `m3_scroll_window --frames=60 --dy=20 --verify`：alloc [0,0,0]、diff=0、pass。
## 6. 未验证/残余风险

- P3-1：仅本机 Windows/WGL/GL1.1 验证；macOS/Linux 未覆盖。
- P3-2：app_demo verify 的 `scroll=0`；虚拟滚动仅由合成探针覆盖。
- P3-3：README 与 M4-WP2-licensing 不在范围，未审；未做跨机复现。
- 三组 app_demo verify 均 attempt=1；未观察到 attempt2。
