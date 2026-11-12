# M1-WP5 稳态零分配证据（task-34）
#
# 口径：plan.md:167/238 —— warmup → GC.collect → 记录 GC.stats.bytes_since_gc
#       → GC.disable → N 帧 → after → GC.enable；差值 = after - before = 0 为通过。
# 仅 steady/static/paint1 场景；不含布局重算、文本 shaping、GPU 提交。

## 1. 交付物与改动

- `src/tessell/core/node.cr`：新增 `Node.collect_dirty(root, sink)` + `collect_dirty_impl`（while 索引，无闭包）；
  保留 `dirty_subtree`（测试用）。`out` 为 Crystal 保留字，故参数名改为 `sink`。
- `src/tessell/render/dirty.cr`：新增 `Dirty.merge_into(rects, sink, max_regions)`（while 索引 +
  原地 union + delete_at）；`merge` 内部委托 `merge_into`。
- `spec/core_node_zero_alloc_spec.cr`：collect_dirty 与 dirty_subtree 集合一致（root 自脏/深树/
  全净空）；sink 复用不残留；GC 零分配探针 bytes_since_gc 差值 0。
- `spec/render_dirty_into_spec.cr`：merge_into 与 merge 6 组输入相等（含顺序）；max_regions 贪心；
  不产空矩形；GC 零分配探针 bytes_since_gc 差值 0。
- `tools/zero_alloc_frame.cr`：≥200 节点 3 层树（205 节点：root + 4 mid + 200 leaves）；
  场景 static（全净树：collect_dirty + DrawList.clear + 全量命令重建 + merge_into）；
  场景 paint1（每帧 1 节点 mark_dirty(Paint) → 收集 → 仅该节点重建 → clean!）；
  支持 `--frames=N` 与 `--json`。
- `src/tessell.cr`：require 行 unchanged（core/node 与 render/dirty 已 require）。

## 2. GC 协议（tools/zero_alloc_frame.cr）

```
warmup 10 帧
GC.collect
before = GC.stats.bytes_since_gc
GC.disable
  200 帧（static 或 paint1）
after = GC.stats.bytes_since_gc
GC.enable  # ensure 保证异常路径恢复
alloc_bytes = after - before
```

## 3. 实测 token（2026-11-12，ucrt64 Crystal 1.22.1，ucrt64）

命令：`crystal run tools/zero_alloc_frame.cr`

```
scenario=static  frames=200 nodes=205 alloc_bytes=0 delta_zero=true
scenario=paint1  frames=200 nodes=205 alloc_bytes=0 delta_zero=true
EXITCODE=0
```

JSON：`crystal run tools/zero_alloc_frame.cr -- --json`

```
{"scenario":"static","frames":200,"nodes":205,"alloc_bytes":0,"delta_zero":true}
{"scenario":"paint1","frames":200,"nodes":205,"alloc_bytes":0,"delta_zero":true}
```

## 4. 局限（[未验证]）

- 不含布局重算（Layout.measure/arrange）；不包含文本 shaping（M2）；不包含 GPU 提交与 SwapBuffers；
  本证据只证「脏收集 + DrawList 复用 + 脏矩形合并」稳态路径零分配。
- DrawList 命令重建按缓存 bounds 预付槽位；若节点数增长超过预付槽位，reserve 会一次性扩容（非稳态）。
- GC.stats.bytes_since_gc 语义以 Crystal 1.22 ucrt64 为准；其它运行时/编译器版本 [未验证]。
- paint1 场景 dirty_buf 预填 node_count+1 槽位；若未来单帧脏节点数超 node_count+1，需扩容（非稳态）。
- `out`/`in`/`end`/`type` 等保留字已自查：node.cr 仅 `sink`/`buffer`（无保留字）；
  dirty.cr 仅 `sink`；specs/tools 无保留字参数。

## 5. 自检

- `crystal spec` → 74 examples, 0 failures, 0 errors, 0 pending, EXITCODE 0。
- `crystal build src/tessell.cr` → EXITCODE 0（tessell.exe 已删）。
- `crystal run tools/zero_alloc_frame.cr` → EXITCODE 0，两场景 alloc_bytes=0 delta_zero=true。
- grep FFI/Platform/LibC/@\[Link 于新文件：无命中。
