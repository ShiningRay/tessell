# M2 门禁终审报告（左都御史）

- 报告人：zuodu-yushi（左都御史）
- 仓库：`C:\Users\ShiningRay\projects\ShiningRay\tessell`
- 审计时 HEAD：`2a2b620958c65c72ad41b7fedcb6b9e5e93b9536`（= `origin/main` = `git ls-remote`）
- 工作区：仅 `?? docs/research/m3-backends.md`（他人产物，未触碰）
- 写入范围：仅本文件 `docs/evidence/M2-gate.md`；未修改源码/证据/测试，未提交，未改 git 状态
- 裁定：**No-Go（不开放 M3）**
- 阻断项：**P1-1 — M2-WP2 的 Emoji 样例验收未实现，而 `M2-summary.md:14` 将其标为“已完成并提交”；按 lead 给定的 WP2 验收口径，构成完成度口径放大**
- 未发现伪造：独立重跑 7/7 条命令均 `EXITCODE=0`；未发现“把失败写成通过”的伪造。问题在**验收覆盖缺失 + 完成度表述放大 + 证据文档缺失/陈旧**。

> 口径说明：本报告按 lead 指示，以 `docs/plan.md` 的 M2-WP2 验收“CJK/Emoji 样例正确显示与测量（目标）”为准（`docs/plan.md:244`，Select-String 行号；该文件存在 CR/LF 混用，`Get-Content` 行号会偏移，正文以内容为准）。若首辅书面把 WP2 范围改为“CJK 必达、Emoji 延后”，则可转 Go-with-conditions；该变更属于计划变更，不是本次门禁可以自行放宽的事项。

---

## 1. 审计方法与边界

1. 只读核验：`docs/evidence/` 下 9 份任务书指定文档 + 额外 `verify-M2-WP2b.md`；逐份抽查数字、口径、未验证项。
2. 独立重跑：不采信任何人的数字；命令与输出见 §2、附录 A。
3. 提交卫生：`git log --oneline -10`、`git show --stat`、subject 原始字节检查、`git status --short`。
4. 对账重点：簿记路径 0 分配 vs 整帧零分配；低频 ~4KB/1000 帧 vs “已清零”；程序化注入不可用 vs “IME 已验”；UIA/GL 滚动是否被写成完成。
5. 约束：预算 ≤40 次工具调用；同一失败重试 ≤2 次；不修改 live 配置；不删除他人证据。

证据清单核对：

- 任务书列的 `docs/evidence/M2-WP2b.md` **不存在**（`Test-Path=False`）；实际存在的是 `verify-M2-WP2b.md`（独立核验报告，非实现证据）。
- 其余存在：`M2-summary.md`、`M2-iteration-log.md`、`M2-WP2c-zero-alloc-criterion.md`、`M2-WP3-ime.md`、`M2-WP3-p3-arabic-msyh.md`、`M2-WP4-virtual-list.md`、`M2-WP5-a11y-tree.md`、`verify-M2-iteration5.md`、`verify-M2-WP2b.md`。

---

## 2. 独立重跑结果（全部由本报告作者执行）

环境：`PATH=C:\msys64\ucrt64\bin;...`；Crystal 1.22.1；Windows ucrt64。

| # | 命令 | EXITCODE | 关键输出（原始 token） |
|---|---|---|---|
| 1 | `crystal spec`（第 1 次） | 0 | `171 examples, 0 failures, 0 errors, 0 pending`；`render_dirty delta_work=0 [0,0,0]`；`text_ft delta_work=16 [0,16,0]`；`text_renderer delta_work=32 [48,64,32]`；`virtual_list delta_work=16 [16,0,0]`；均 `retried=false attempt=1` |
| 2 | `crystal spec`（第 2 次） | 0 | `171 examples, 0 failures, 0 errors, 0 pending`；`text_ft 16 [16,0,0]`；`text_renderer 48 [48,48,48]`；`virtual_list 16 [16,0,0]` |
| 3 | `crystal build src/tessell.cr` | 0 | 产物 `tessell.exe` 2267235 B；已删除，根目录无残留 |
| 4 | `crystal run tools/bench_scroll.cr` | 0 | scroll：`alloc_bytes=3952 p50=1227 p95=1891 p99=2150 frames=2000 windows=[0,0,3952]`；jump：`alloc_bytes=4016 p50=1218 p95=1865 p99=2124 windows=[0,0,4016]`；`GL_SCROLL_WINDOW=not_done` |
| 5 | `crystal run tools/zero_alloc_frame.cr` | 0 | `static frames=200 nodes=205 alloc_bytes=16 criterion_ok=true windows=[0,16,0]`；`paint1 alloc_bytes=0 criterion_ok=true` |
| 6 | `crystal run examples/m2_text_window.cr -- --frames=60 --verify` | 0 | `text_pixels_nonbg=2801 cpu_coverage_sum=2638 ratio=1.0617892342683852 pixel_match=true frames=60 swapbuffers=60 p50=1.8354 p95=3.499 p99=3.723 quads=14 batches=1` |
| 7 | `crystal run examples/m2_ime_probe.cr -- --frames=60` | 0 | `ime_injection=blocked reason=imm_set_composition_rejected available=false`；`imm_available=true imm_open_status=1`；`preedit_roundtrip=false result_roundtrip=false`；`candidate_list_bytes=144 candidate_list_entries=0` |

补充观察：

- 两次 `crystal spec` 全绿，但零分配探针窗口**不是全 0**：`text_ft`/`text_renderer`/`virtual_list` 在 16–64 B 范围波动，属于 WP2c 的 A/B 判据窗口，不是“绝对零分配”。
- `bench_scroll` 真实 CPU 帧路径 `alloc_bytes=3952/4016`（1000 帧合计），与证据的 3920/4000/3728/4016 同一量级；**A 门未过**（>1000）。
- `zero_alloc_frame` 的 `static` 本次为 16，证据为 0；`criterion_ok=true` 仍成立，但说明该探针存在环境性抖动。
- `text_window` 只验证了“Hello 你好 Tessell”，**没有 Emoji 字符**；见 §4.1。
- `ime_probe` 明确 `blocked`，与证据一致；这是诚实失败，不是伪造。

---

## 3. 提交卫生

### 3.1 每迭代两支提交

`git log --oneline -10` 显示 5 组 feat + docs 回填：

| 迭代 | feat | docs 回填 |
|---|---|---|
| 1 | `17814ca feat(m2): 输入事件、命中测试、焦点与路由 + 字体回退/图集预研` | `78ee3af docs: 回填 M2 迭代 1` |
| 2 | `1025373 feat(m2): FreeType/HarfBuzz 绑定与真实文本测量（M2-WP2a）` | `76ef5d6 docs: 回填 M2 迭代 2` |
| 3 | `77f42d8 feat(m2): 字形图集、光栅化与可判定零分配判据（M2-WP2b/WP2c）` | `fdb797c docs: 回填 M2 迭代 3` |
| 4 | `6520dca feat(m2): 文本上屏（CPU 四边形+GL 后端+像素回读）与 IME 探针（M2-WP2d/WP3)` | `7cfb44f docs: 回填 M2 迭代 4 提交 hash` |
| 5 | `a280169 feat(m2): 虚拟列表与无障碍最小树（M2-WP4/WP5）` | `2a2b620 docs: 回填 M2 迭代 5 提交 hash` |

结论：5 个迭代均有两支提交，成立。`a280169` 同时包含源码、spec、tools 与 `M2-summary.md`/`M2-iteration-log.md`；`2a2b620` 仅回填 hash。该“feat 内含文档”不违反“feat + hash 回填”两支结构，但会让 summary 与 feat 同批提交，见 §6 P2-3。

### 3.2 subject 首字节 BOM

- `17814ca` 的 subject 原始字节（`git show -s --format=%s` 重定向到临时文件后 `[IO.File]::ReadAllBytes`）：
  - `len=87 first6=EF BB BF 66 65 61` → `EF BB BF` + `fea`，**确认 BOM**。
- `M2-iteration-log.md:84-93` 已自认 `first16=EF BB BF 66 65 61 74...`，并称“已知瑕疵、不 rewrite”。
- 其余 9 支 subject 首字节为 `64`/`66`（`d`/`f`），无 BOM。
- 结论：**不满足“subject 首字节非 BOM”**；属历史提交，无法无损修改。详见 P2-2。

### 3.3 工作区

`git status --short`：仅 `?? docs/research/m3-backends.md`。无 tracked 改动，无 build 产物。符合“除 m3 文档外干净”。

---

## 4. 证据对账（逐份）

### 4.1 `M2-summary.md`（40 行）— **P1/P2/P3**

关键原文：

- `:5`：“迭代 5……代码与证据已在工作区落地并通过本地 spec，**尚未提交**，待 dalisi verify-M2-iteration5.md 裁断与首辅放行。”
- `:14`：`M2-WP2 ... | 已完成并提交；存在核验缺陷项/后续项`。
- `:16`：`M2-WP4 ... | 实现与簿记指标达标；真实 CPU 帧零分配未达标（残余证据化，task-73 承接）`。
- `:17`：`M2-WP5 ... | M2 最小目标达成（J1–J9）；UIA provider 未做`。
- `:28`：“迭代 5 全覆盖：**待 dalisi verify-M2-iteration5.md 裁断**（冻结等待中）。”
- `:32`：“真实 CPU 帧路径零分配未达成……A 门未通过（3920>1000）……由 task-73 承接。”
- `:36`：“其他未达/未验证：**Emoji COLR/CPAL 彩色**、GL 着色器路径、delete_textures、ratio 非逐像素、S-AR-LA 仅 arial……”
- `:40`：“verify-M2-iteration5 裁断已放行（PASS-WITH-DEFECTS）……docs 回填提交 hash 待……补记。”

对账结论：

1. **WP2 完成度放大（P1-1）**：`:14` 标“已完成并提交”，但 `docs/plan.md:244` 的 WP2 验收是“CJK/Emoji 样例正确显示与测量（目标）”。本次在 `spec/`、`src/`、`examples/` 全量搜索 `😀|EMOJI|Emoji|emoji|1F600|1f600`，**除 `spec/rasterizer_spec.cr:172-173` 的 `\u{10FFFF}`（非 Emoji）外无任何命中**；唯一的文本窗口样例是 `examples/m2_text_window.cr:189 text_str = "Hello 你好 Tessell"`（`:186 FONT_PATH="C:/Windows/Fonts/msyh.ttc"`），不含 Emoji。`:36` 只列“Emoji COLR/CPAL 彩色”，会让人误以为灰度 Emoji 已做；实际上 Emoji 样例整体未实现/未测量。**这是完成度口径放大，不是单纯“彩色未做”。**
2. **陈旧/自相矛盾（P2-3）**：`:5`/`:28` 说迭代 5 未提交、待裁断；`:40` 又说已放行、hash 待补。实际 HEAD 已是 `2a2b620`，包含 `a280169` feat 与 `2a2b620` docs 回填，`verify-M2-iteration5.md` 已存在。summary 生成于迭代 5 提交前，未刷新。
3. **基线过期（P3-7）**：`:4` 基线 HEAD 写 `7cfb44f`（迭代 4），不是审计 HEAD `2a2b620`；读者会误以为 summary 对应最终提交。
4. **WP2F 漏项（P3-2）**：summary 五 WP 表（`:13-17`）没有 M2-WP2F 行；但 `docs/research/font-fallback.md` 存在，`verify-M2-WP1.md:19-25` 已复核字体清单/COLR/CPAL/OFL URL。属于汇总遗漏，不是实现缺失。

### 4.2 `M2-iteration-log.md`（241 行）— **基本诚实，P3**

- `:84-93` 主动记录 `17814ca` subject BOM（`EF BB BF`），未隐瞒。
- `:112-127` 记录 WP2c 首轮 FAIL → 判据 A/B、盲区与重试；未把“判据通过”写成“绝对零分配”。
- `:180-186` 明列未验证：IME 手测、Emoji 彩色、GL shader、delete_textures、ratio、B 门盲区。
- `:200-220` 迭代 5：spec 171、bench scroll `alloc=3920 windows=[3920,0,3712] p50=1269`、jump `alloc=4000 windows=[0,4000,0] p50=1775 delta_prime=3888`。
- `:227-229` 明确“真实 CPU 帧 A 门未过、残余 ~4KB/1000 帧、task-73”。
- `:237-241` 提交 hash。
- 结论：对未达成项**没有**写成已完成；可作为诚实的辅助证据。BOM 是已披露瑕疵，不构成伪造。

### 4.3 `docs/evidence/M2-WP2b.md` — **缺失（P2-1）**

- `Test-Path docs/evidence/M2-WP2b.md` = `False`。
- task-77 将 `M2-WP2b.md` 列入 9 份证据；实际只有 `verify-M2-WP2b.md`。
- `verify-M2-WP2b.md:47-53` 有 glyph_atlas 5 次 spec + 3×1000 lookup `delta=0`；`:68`/`:93` 记录超大字形失败遗留空页 P3；`:96-98` 裁定 PASS-WITH-DEFECTS。该报告仍是**历史基线 `76ef5d6`**，不是当前 HEAD 的实现证据。
- 结论：缺少一份“实现侧”WP2b 证据；验收链只能用 verify 报告补齐，不能算 9 份齐全。

### 4.4 `M2-WP2c-zero-alloc-criterion.md`（40 行）— **诚实**

- `:3-5` 判据 A `delta_work < N`（N=1000）、B `delta_work <= 256`、3 窗 max、`GC.enable` in ensure、失败重试。
- `:8-16` 噪声 16/1536。
- `:30-34` 明确“不能证绝对零分配”；dalisi 1 次/1000 `delta_work=32`、5 次/1000 `delta_work=160` 均 `PASSED_BLIND`。
- `:36-40` 重试边界。
- 结论：判据本身诚实，但**只能证明“低于阈值”**；任何“整帧零分配”表述都不能引用它。

### 4.5 `M2-WP3-ime.md`（87 行）— **诚实**

- `:17` 原始输出 `ime_injection=blocked`。
- `:38-40` 分“已证/未证/手测”三栏；C2 真实键盘手测开放。
- `:55-64` 真实键盘预编辑/候选窗/多 IME 未证；程序化注入被拒。
- `:83` 建议 IME event kinds 未实现。
- 结论：没有“IME 已验”的放大；WP3 只能判部分完成。

### 4.6 `M2-WP3-p3-arabic-msyh.md`（42 行）— **诚实**

- `:20-28` msyh `"لا"` HB glyph_ids `[0,0]`、`drawable=false`；arial/times `gid=1019` 单 ligature。
- `:37` 样例字体改用 arial；定性为字体覆盖/映射与 gid=0 策略，不是绑定 bug。
- 结论：诚实；S-AR-LA 只在 arial 样例成立，msyh 仍不可绘制。

### 4.7 `M2-WP4-virtual-list.md`（82 行）— **诚实，无整帧放大**

- `:53` 全帧 f 段 `delta_work=3952`。
- `:65-66` bench 与 summary 一致（scroll 3920/p50 1269；jump 4000/p50 1775）。
- `:73` “已清零/显著改善”明确仅指数组/闭包/查表，不是整帧。
- `:74-76` `alloc 3920/4000` 为 1000 帧合计、~3.9 B/帧均摊、低频重复 ~4KB、A 门未过、只覆盖 VirtualList 簿记路径、task-73。
- `:80-81` GL 滚动未做；帧时间为 CPU 侧，不含 GPU present。
- 结论：这是**正确口径**的范本；与 summary `:16` 一致。

### 4.8 `M2-WP5-a11y-tree.md`（80 行）— **基本诚实，P3**

- `:40-44` J1–J9 spec 10/0、全量 171/0、J9 `delta=0`。
- `:52` 称“31 可见 → 32 节点”；verify 实测“30 可见 → 31 节点”。两者是边界差异，不是放大；均 ≤32。
- `:63-64` UIA 未做。
- `:66-73` UIA/屏幕阅读器/DPI/双树一致性/焦点回收未验证。
- `:78` 残余 task-73。
- 结论：M2 最小树目标成立，UIA 未做已披露。

### 4.9 `verify-M2-iteration5.md`（62 行）— **PASS-WITH-DEFECTS，但 P2-4**

- `:4` 裁定 PASS-WITH-DEFECTS（P0/P1/P2 无，P3×2，未发现伪造）。
- `:10` 万行 emit 31 节点（1+30）；`:13` Meta 删除后残留。
- `:30-32` 两轮全量 171/0；探针 `text_renderer 64`。
- `:35-36` bench scroll `alloc3728 p50 1199`、jump `alloc4016 p50 1195`。
- `:43-48` P3-1 draw_list 尾残留、P3-2 a11y Meta 泄漏。
- `:50-56` UIA/DPI/并发/负 pitch/alloc 归因/GL 文本未验证。
- `:58-59` 未发现伪造。
- 问题（P2-4）：它把“P0/P1/P2 无”与“真实帧 alloc 未归零”分开，只在未验证清单提到 alloc 归因；按 lead 的 A 门口径，真实 CPU 帧未达零分配应作为**明确的 P1/阻断可见项**，而不是仅 P3/未验证。否则读者会以为 M2 五 WP 已全部通过。该报告没有伪造，但**门禁可见度不足**。

### 4.10 `verify-M2-WP2b.md`（99 行）— **历史基线 PASS-WITH-DEFECTS**

- `:47-53` glyph_atlas 5 次 spec + 3×1000 lookup `delta=0`。
- `:68`/`:93` 超大字形失败遗留空页 P3。
- `:96-98` PASS-WITH-DEFECTS。
- 结论：只能证明 `76ef5d6` 时点；不能替代当前 HEAD 的 `M2-WP2b.md` 实现证据。

### 4.11 M2-WP2F / 字体回退

- `docs/research/font-fallback.md` 存在；`verify-M2-WP1.md:19-25` 复核：seguiemj.ttf 12934920 B、COLR+CPAL 存在、NotoColorEmoji 缺失、OFL URL 200、字体字节一致。
- 但 `M2-summary.md:13-17` 没有 WP2F 行；且 `verify-M2-WP1.md` 只验“URL 200”，未下载/核验 OFL 文本，也未做分发方案。故 WP2F 是“文档层面有条件通过”，不是完全关闭。

---

## 5. 数字对账（证据 vs 本次重跑）

| 指标 | 证据值 | 本次重跑 | 判定 |
|---|---|---|---|
| `crystal spec` | 171 examples / 0 fail | 171 / 0（两次） | 一致 |
| Build | 0 | 0；exe 2267235 B 已删 | 一致 |
| text p50 | 1.81 ms | 1.8354 ms | 同量级 |
| text p95 | 8.16 ms | 3.499 ms | 差异大（环境/采样） |
| text p99 | 9.00 ms | 3.723 ms | 差异大 |
| text `pixel_match` | true | true | 一致 |
| scroll alloc | 3920 | 3952 | +32（可接受） |
| scroll p50 | 1269 µs | 1227 µs | 同量级 |
| scroll p95/p99 | 2031/2688 | 1891/2150 | 本次更低 |
| jump alloc | 4000 | 4016 | +16（可接受） |
| jump p50 | 1775 µs | 1218 µs | 差异大 |
| jump p95/p99 | 3669/4421 | 1865/2124 | 本次更低 |
| zero static | 0 | 16 | 抖动；`criterion_ok=true` |
| zero paint1 | 0 | 0 | 一致 |
| IME injection | blocked | blocked | 一致 |
| IME preedit/result | false | false | 一致 |
| `visible_avg`/pool | 30.95/32 | 30.95/32 | 一致 |

结论：**核心功能 token 一致；性能分位数不完全可复现**。`text p95/p99` 与 `jump p50` 的差异足以说明 summary 中的分位数不能当作稳定基线；不构成伪造，但必须标注环境与采样差异（P3-1）。

---

## 6. 缺陷清单

### P0（伪造/硬编码凑绿）

无。未发现伪造、硬编码 token、删除失败证据或“失败写成通过”。

### P1（阻断）

**P1-1 — WP2 Emoji 验收未实现，summary 标“已完成并提交”（完成度口径放大）**

- 验收依据：`docs/plan.md:244`：“CJK/Emoji 样例正确显示与测量（目标），按 M2-WP2F 字体与回退链执行。”
- 事实：
  - `spec/`、`src/`、`examples/` 全量搜索 `😀|EMOJI|Emoji|emoji|1F600|1f600`，除 `spec/rasterizer_spec.cr:172-173` 的 `\u{10FFFF}` 外**无命中**。
  - `examples/m2_text_window.cr:189` 的样例是 `"Hello 你好 Tessell"`；`:186` 字体固定 `msyh.ttc`；无 Emoji。
  - 因此 Emoji 的“显示”和“测量”都没有被验收；不仅是彩色 COLR/CPAL 未做。
- 表述问题：`M2-summary.md:14` 写“已完成并提交；存在核验缺陷项/后续项”；`:36` 只列“Emoji COLR/CPAL 彩色”。这会让首辅/读者误判 WP2 只剩彩色未做。按 lead 口径，这是**口径放大**。
- 影响：M2-WP2 验收不成立；M3 的文本栈若在此基础上开工，会把缺失的 Emoji 路径带入后续阶段。

### P2（重要，需在归档/进 M3 前处理）

- **P2-1 — `docs/evidence/M2-WP2b.md` 缺失**：任务书列 9 份证据，实际无此文件；只有 `verify-M2-WP2b.md`（历史基线 `76ef5d6`）。证据链不完整。
- **P2-2 — `17814ca` subject 首字节 BOM**：原始字节 `EF BB BF 66 65 61`；违反“subject 首字节非 BOM”。已在 `M2-iteration-log.md:84-93` 自认；历史提交不可无损改。
- **P2-3 — `M2-summary.md` 陈旧/自相矛盾**：`:5`/`:28` 说迭代 5 未提交、待裁断；`:40` 说 verify 已放行；`:4` 基线 `7cfb44f` 不是 HEAD `2a2b620`。summary 未随最终两支提交刷新。
- **P2-4 — `verify-M2-iteration5.md` 门禁可见度不足**：`:4` 写“P0/P1/P2 无”，但真实 CPU 帧 A 门未过；只在 `:50-56` 未验证清单提 alloc 归因。按 lead 的 A 门口径，应显式列为 P1/阻断项，而不是仅 P3/未验证。

### P3（观察/文档卫生/环境差异）

- **P3-1 — 分位数不完全可复现**：text p95/p99 8.16/9.00 → 3.499/3.723；jump p50 1775 → 1218；zero static 0 → 16；alloc 3920/4000 → 3952/4016。需在 summary 标注“环境相关、非稳定基线”。
- **P3-2 — `M2-summary.md` 缺 WP2F 行**：`docs/research/font-fallback.md` 与 `verify-M2-WP1.md:19-25` 已有 WP2F 证据，但 summary 五 WP 表未列。
- **P3-3 — WP5 节点数口径**：`M2-WP5-a11y-tree.md:52` 写“31 可见 → 32 节点”，verify 实测“30 → 31”；边界差异，不是放大，但应统一。
- **P3-4 — 已披露的 P3**：`draw_list` 尾残留（`verify-M2-iteration5.md:43`）、a11y Meta 删除后泄漏（`:13`）、超大字形失败遗留空页（`verify-M2-WP2b.md:68`）。
- **P3-5 — 已披露的未达成**：真实 CPU 帧零分配（A 门未过，task-73）、IME C2 真实键盘、UIA、GL 滚动上屏、Emoji 彩色、GL shader、delete_textures、ratio 非逐像素、S-AR-LA 仅 arial、GPU 上传未纳入 GC 窗口。这些没有被写成“已完成”，但都是 M3 前必须继承的条件。
- **P3-6 — 文档行尾混用**：`docs/plan.md` 等文件存在 CR/LF 混用，`Get-Content` 与 `Select-String` 行号会偏移（例：M2-WP2 验收在 Select-String `:244`，Get-Content 显示为 `:213`）。本报告已尽量引用 Select-String 行号并给出原文，但后续审计应以内容检索为准。
- **P3-7 — summary 基线过期**：见 P2-3；单独列出是因为它影响“证据对应哪个 HEAD”的可审计性。

---

## 7. 未验证清单（本报告确认仍开放）

1. Emoji 灰度显示/测量（P1-1 阻断）；Emoji 彩色 COLR/CPAL（P2 可延后）。
2. 真实键盘 IME C2：`WM_IME_STARTCOMPOSITION → COMPOSITION → ENDCOMPOSITION`、预编辑不丢字、候选窗定位、多 IME 切换（`M2-WP3-ime.md:55-64`）。
3. UIA COM provider / 屏幕阅读器端到端 / COM 线程与导出形状（`M2-WP5-a11y-tree.md:63-73`）。
4. GL 滚动上屏 / `GL_SCROLL_WINDOW`（`M2-WP4-virtual-list.md:80-81`；bench `GL_SCROLL_WINDOW=not_done`）。
5. 真实 CPU 帧零分配（A 门未过；`M2-summary.md:32`；task-73）。
6. `M2-WP2F` 的 OFL 文本下载/核验与字体分发方案（`verify-M2-WP1.md:19-25` 只验 URL 200）。
7. 多 DPI、多显示器、长稳、跨平台（各证据未验证清单）。
8. GPU 纹理上传/`delete_textures` 生命周期、GL 文本着色器路径、负 pitch、并发（`verify-M2-iteration5.md:50-56`）。
9. `ratio` 非逐像素等价；S-AR-LA 仅 arial 样本；msyh 的 `لا` gid=0（`M2-WP3-p3-arabic-msyh.md:20-28`）。
10. `glyph_reuse` 场景与工具 token 扩展（`M2-WP2c-zero-alloc-criterion.md` 及 `docs/research/text-acceptance.md` 未验证清单）。
11. 本报告自身未做：真实键盘手测、UIA 对读屏器、GPU 侧呈现、跨平台；这些均标 `[未验证]`，不作为通过依据。

---

## 8. 裁定与条件

### 8.1 裁定

**No-Go（不开放 M3）**。

理由：

1. **P1-1**：M2-WP2 的 Emoji 样例验收未实现；按 `docs/plan.md:244`，WP2 不能判完成。`M2-summary.md:14` 的“已完成并提交”与事实不符，构成完成度口径放大。lead 明确要求“发现口径放大直接 No-Go”。
2. **P2-1**：9 份证据中 `M2-WP2b.md` 缺失，证据链不完整。
3. **P2-3**：summary 仍停留在迭代 5 提交前，且自相矛盾；不能作为最终门禁依据。
4. **P2-2**：提交卫生有一条 BOM 违规；虽为历史提交，但门禁要求未满足，需要书面豁免或历史修正授权。

说明：本裁定**不是**否定代码质量。7/7 重跑全绿，核心探针（隔离、窗口、文本、IME blocked、bench、zero-alloc 探针）均可运行；问题是“验收覆盖 + 完成度表述 + 证据完整性”，不是“代码跑不起来”。

### 8.2 条件（C1…C9）

| 编号 | 阻断? | 条件 | 关闭证据（必须可审计） | 责任 WP / 人 |
|---|---|---|---|---|
| C1 | 是 | 实现并验收 WP2 Emoji 样例：至少 R8 灰度显示+测量；彩色 COLR/CPAL 可另列 P2 | `spec/` 新增 S-EMOJI-1(a/b) 用例；`examples/m2_text_window.cr` 或新样例渲染 Emoji；`crystal spec` 0 fail；`--verify` 输出 Emoji 的 glyph 序列/宽度/pixel；summary 改为真实状态 | M2-WP2 / M2-WP2F（工部） |
| C2 | 是 | 补齐 `docs/evidence/M2-WP2b.md`，或在 task-77 书面修订证据清单并说明替代链 | 文件存在且含当前 HEAD 的 atlas/rasterizer 证据；`verify-M2-WP2b` 在 `2a2b620` 重跑；`git status` 干净 | M2-WP2b / 翰林 |
| C3 | 是 | 刷新 `M2-summary.md`：HEAD `2a2b620`、迭代 5 已提交、verify 已放行；删除“未提交/待裁断”矛盾；补 WP2F 行；把 Emoji 未实现写清楚 | summary diff；`Select-String` 无“尚未提交/待裁断”；五 WP+WP2F 表完整；docs 提交 | M2 汇总 / 翰林 |
| C4 | 是（或书面豁免） | 提交卫生：后续 subject 首字节非 BOM；对 `17814ca` 记录不可变例外，或经授权 rewrite | `git log --format=%s` 逐条字节检查（首字节非 `EF`）；`git status` 干净；例外记录 | lead / 发布 |
| C5 | 否（M3 前） | 性能数字可复现：固定环境、至少 3 次，报告 p50/p95/p99 范围；解释 text p95/p99 与 jump p50 差异 | 3 次 bench 原始输出；summary 改为区间；环境记录 | M2-WP4 |
| C6 | 否（M3-WP5 前） | 真实 CPU 帧零分配：task-73 关闭 A 门，或书面 waiver 并承认未达标 | `bench_scroll` 真实帧 `alloc=0`（A/B 判据）；或 waiver + plan 变更 | task-73 / M2-WP4 |
| C7 | 否（M3-WP3 前） | IME C2 真实键盘手测：start/composition/end、预编辑、候选窗、多 IME；不可用则按 plan 写 No-Go | 手测日志/截图；`ime_messages` 与 preedit/result 完整；或 No-Go 记录 | M2-WP3 |
| C8 | 否（M3 前决策） | UIA 与 GL 滚动：实现或书面延后并修改 plan；不得在 summary 写成“已完成” | UIA COM 输出/读屏器验证；GL 滚动 on-screen 帧；或 plan 变更记录 | M2-WP5 / M2-WP4 |
| C9 | 否（M3 打包前） | WP2F 许可：下载/核验 OFL 文本，明确可再分发与替代字体方案 | OFL 文本哈希/路径；分发清单；不可再分发替代方案 | M2-WP2F |

### 8.3 M3 入口

- **C1–C4 关闭前，M3 不开放**（No-Go）。
- C5–C9 可与 C1–C4 并行，但分别阻塞 M3-WP5（零分配）、M3-WP3（IME）、M3-WP5/UIA（无障碍）、M3 打包（字体许可）。
- 若首辅决定把 Emoji 降级为“M3 条件”，必须先在 `docs/plan.md` 做书面范围变更，并由首辅/用户确认；本报告不自行放宽。

---

## 9. 审计限制

1. 本报告只代表当前机器（Windows ucrt64、Intel Iris Xe）与当前 HEAD；未做跨平台、长稳、真实 GPU 呈现、真实键盘 IME、UIA 读屏器手测。
2. 性能数字受环境/采样影响；本次与证据的分位数差异已列明，不能把任一组当作稳定基线。
3. 未修改源码；未运行 `git checkout/commit/rewrite`；未删除任何证据。
4. `docs/plan.md` 等文件存在 CR/LF 混用，行号可能因工具不同偏移；关键结论均附原文，便于按内容复核。
5. 本报告不构成对 M2 代码质量的最终否定；No-Go 的直接原因是 WP2 Emoji 验收缺失 + 完成度口径放大 + 证据链缺口，而非“核心探针不可运行”。

---

## 附录 A：关键原始输出

### A.1 spec

```text
171 examples, 0 failures, 0 errors, 0 pending
render_dirty delta_work=0 [0,0,0]
text_ft delta_work=16 [0,16,0]
text_renderer delta_work=32 [48,64,32]
virtual_list delta_work=16 [16,0,0]
retried=false attempt=1
```

第二次：

```text
171 examples, 0 failures, 0 errors, 0 pending
text_ft 16 [16,0,0]
text_renderer 48 [48,48,48]
virtual_list 16 [16,0,0]
```

### A.2 bench_scroll

```text
scenario=scroll_plus1px visible_avg=30.95 fetched_per_frame_avg=30.95 cmds_avg=61.9
batches_avg=1.0 quads_avg=247.6 alloc_bytes=3952 frame_cpu_p50_us=1227 p95=1891 p99=2150
frames=2000 alloc_windows=[0,0,3952] delta_prime=0 delta_calib=0 retried=true attempt=2
pool_size=32 created=32

scenario=jump_fixed_seed seed=12345 visible_avg=30.9555 alloc_bytes=4016
p50=1218 p95=1865 p99=2124 frames=2000 alloc_windows=[0,0,4016]
delta_prime=0 retried=true attempt=2 pool_size=32 created=32

GL_SCROLL_WINDOW=not_done reason=optional_not_implemented_in_task70
BENCH_SCROLL_EXIT=0
```

### A.3 zero_alloc_frame

```text
scenario=static frames=200 nodes=205 alloc_bytes=16 criterion_ok=true
delta_prime=0 windows=[0,16,0] retried=false attempt=1
scenario=paint1 alloc_bytes=0 criterion_ok=true windows=[0,0,0]
```

### A.4 text window

```text
text_pixels_nonbg=2801 cpu_coverage_sum=2638 ratio=1.0617892342683852
pixel_match=true frames=60 swapbuffers=60 frame_p50_ms=1.8354 p95=3.499 p99=3.723
pen_end_x=300.96875 quads=14 batches=1
gl_path=GL1.1_compat R8->GL_ALPHA glPixelStorei(GL_UNPACK_ALIGNMENT,1)
```

### A.5 IME probe

```text
ime_injection=blocked ime_injection_reason=imm_set_composition_rejected
ime_injection_available=false ime_hkl_is_ime=true imm_available=true imm_is_ime=true
imm_open_status=1 imm_set_open_ret=1 imm_set_str_ret=0
preedit_roundtrip=false result_roundtrip=false preedit_got_len=-1 result_got_len=-1
candidate_list_bytes=144 candidate_list_count_raw=0 candidate_list_entries=0
cand_pos=not_triggered ime_messages_setcontext=1 start=0 composition=0 end=0 notify=3
kl_count=2 kl_ids=0x8040804,0x4090409 active_hkl=0x8040804 activated_hkl=0x8040804
IMM_ERR=ImmSetCompositionStringW_rejected_preedit_ret=0_result_ret=0_win32_error=0
frames=60 hwnd=0x300f8 himc=0x97d080b
```

### A.6 BOM 检查

```text
len=87 first6=EF BB BF 66 65 61
```

### A.7 Emoji 搜索

```text
Pattern: 😀|EMOJI|Emoji|emoji|1F600|1f600
spec/src/examples 命中：仅 spec/rasterizer_spec.cr:172-173 的 \u{10FFFF}（非 Emoji）
examples/m2_text_window.cr:189 text_str = "Hello 你好 Tessell"
```
