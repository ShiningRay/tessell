# verify-M2-WP1.md — M2-WP1 / M2-WP2F 独立核验（task-41）

- 核验人：大理寺卿 dalisi-qing；采集时间：2026-11-12 23:44–23:58 +08:00（flake 连跑至 2026-11-13 00:00）
- HEAD：`a74823b`；Crystal `1.22.1 [23828b0a40] (2026-10-23)` / LLVM 23.1.3 / x86_64-w64-windows-gnu；OS `Microsoft Windows NT 10.0.26300.0` AMD64
- 边界：只读 + 重跑；唯一写入为本报告。git status 基线 = task-39 交付（` M src/tessell.cr` require 行、`?? src/tessell/input/`、`?? spec/input_{hit_test,focus,router}_spec.cr`）+ task-40 交付（`?? docs/research/font-fallback.md`）+ 并行交付物 `?? docs/research/glyph-atlas.md`（非本核验产生）。未改 src/spec/docs 其他文件；临时脚本 `bin/_verify_m2wp1.cr`、`bin/_font_tables.py`、`bin/_flake20.txt` 运行后即删；根目录无 exe。

## A. 代码核验（`src/tessell/input/{event,hit_test,focus,router}.cr` + 三 spec + `src/tessell.cr`）

### A1 命中测试 — 通过
自建 3 层树 + 重叠兄弟脚本（`bin/_verify_m2wp1.cr`，即删）实测 13 项全 PASS：嵌套最深、后加兄弟 z-order 优先（`hit_test.cr:19-26` 逆序 DFS）、仅含先者点返回先者、边界点含（`Rect#contains?` `geometry.cr:48-50` 双侧含：原点/子 min 边/子 max 边/root max 边）、root 外 nil、root 内无子返回 root、100 次命中后结构/父子/脏标记不变（`A1 tree unmodified`）。
首跑 2 处 FAIL 经复核为**脚本期望错误**非代码缺陷：① 期望「仅先者含」时 a/b 写了同坐标矩形，点同时落入两者，z-order 判 later-added 正确；② (90,90) 角点同时被后代 sib 覆盖，deepest 返回 sib 正确。修正期望后全 PASS；官方 spec 对应用例（`spec/input_hit_test_spec.cr:32-39` z-order、`:41-48` earlier-only、`:50-57` 边界含、`:59-63` miss）在全量回归中通过。

### A2 焦点 — 通过
脚本 16 项全 PASS：焦点环=后代前序（有子时 root 不入环）、单节点规则（root 无子且可聚焦→环含 root）、next/prev 前序移动+双向回绕、当前焦点不在环时回绕端点（detach/外部设定）、detach 节点排除出环但焦点保留（`focus.cr:59-77`）、注入谓词排除、谓词仅作用本实例不污染其它 FocusManager、无候选返回 nil、`focus` 返回旧焦点、`blur` 清空。

### A3 路由 — 通过
脚本 10 项全 PASS，与 `router.cr:34-57` 实现一致：down 命中可聚焦→focus+pressed+返回目标；down 命中不可聚焦→**返回目标但不抢焦点**（`router.cr:38-42` 有 guard，与任务书「与实现一致核对」相符）；move→hover；up→返回最近 pressed 不重新命中；wheel→hover||focus；key/text→focus；resize→nil 且焦点不变；blur→nil 且清焦点；连续 down 替换 pressed/focus 无残留。

### A4 断言有效性 — 通过
25 it（hit 8 + focus 8 + router 9，与任务书一致）逐条看：断言均为具体 eq/be_true/be_false/be_nil/be<=，无 `should_not be_nil` 式空泛断言（miss/旧焦点 nil 用例用 `be_nil` 是有效负断言）。未覆盖（记录）：事件冒泡、enabled/可见性门控、绝对坐标换算（`hit_test.cr:6` 自述 bounds 视为 root 坐标系、换算留 M2）、无焦点时 key/text（实现返 nil，spec 未测）、pressed 残留语义（见 P3-1）。

### A5 官方重跑 — 通过
- `crystal spec` → `107 examples, 0 failures, 0 errors, 0 pending` / `Finished in 68.28 milliseconds` / `SPEC_EXITCODE=0`
- `crystal build src/tessell.cr` → `BUILD_EXITCODE=0`（exe 已删，根目录复核 `NO_EXE_IN_ROOT`）
- `crystal run tools/zero_alloc_frame.cr` → `scenario=static frames=200 nodes=205 alloc_bytes=0 delta_zero=true` / `scenario=paint1 ... alloc_bytes=0 delta_zero=true` / `ZERO_EXITCODE=0`
- grep：input 四文件仅 require geometry/core/node，无 `@[Link]`/`LibC`/`Platform`/FFI 实际调用；事件为 struct+enum 值类型（`event.cr:10-100`）。

### A6 GC 探针 flake 定性（重点）— 不可复现
`crystal spec spec/render_dirty_into_spec.cr` 连跑 20 次：每次 `10 examples, 0 failures, 0 errors, 0 pending`、`exit=0`；20/20 未出现 `got: 16` / `allocates zero bytes` 失败文本（逐次原始计数行存于当次运行输出，汇总 `RUN01..RUN20` 全绿）。全量 `crystal spec`（含该文件）亦通过。仓库 `docs/` grep `got: 16|allocates zero bytes|flake|Flake` **无命中**——症状串仅见于 lead 转述，证据文件未记录原文。
定性：**当前 HEAD a74823b 本机不可复现（单文件 0/20、全量 0/2 上下文），非确定性缺陷**。可能来源：修复前版本（`dirty.cr:30` 曾用保留字 `out`、sink 语义旧版）或首跑 GC 状态差异。探针本身（`spec/render_dirty_into_spec.cr:68-83`）协议正确（warmup→GC.collect→disable→before→1000 次→after→enable，`eq 0`），当前代码下稳态成立。建议：若再现，保全首次/单跑/全量三上下文完整输出再定性。

## B. 文档核验（`docs/research/font-fallback.md`，实测 117 行；任务书描述 77 行，偏差记 P3-6）

5 项事实抽查全部复算一致（命令：`Get-ChildItem C:\Windows\Fonts` + 自写 Python 表目录解析 `bin/_font_tables.py`，即删）：
1. seguiemj.ttf = **12934920** 字节、ttf、**COLR+CPAL** 存在、无 CBDT/CBLC/sbix ✓ 文档 :31
2. NotoColorEmoji 不存在：`*NotoColorEmoji*`=0、`*emoji*`=0、`*Noto*`=2 ✓ :40
3. msyh.ttc = **19704352** 字节、ttc/2、GSUB/GPOS=true ✓ :24
4. OFL URL `https://scripts.sil.org/OFL` → HEAD **200**（跳转 `https://openfontlicense.org/`）✓ :48
5. 回退链文件全部存在且字节一致：segoeui 960076 / tahoma 919260 / arial 1045720 / NotoSansSC-VF 17773244 / msyh.ttc / simsun.ttc / **mingliub.ttc 37112128** ✓ :65-67
附加复算：总文件数 391 ✓ :4；simsun GSUB=true GPOS=false ✓ :27；simkai/simfang GSUB=true GPOS=false ✓；Noto VF fvar/STAT/gvar=true ✓ :37-38。
`[未验证]` 诚实性：TTC 内嵌序号/cmap 逐字覆盖 :42、OFL 文本未下载 :48、Noto 下载校验 :86-92、Noto emoji 表结构 :43 均如实标注，未把「应可用」写成已实测。
与 `docs/evidence/M0-WP4-deps.md` 冲突核对：9 个共同文件字节数全部一致（msyh.ttc 19704352、msyhbd 16883552、msyhl 12189612、simsun 18316748、simhei 9745792、seguiemj 12934920、arial 1045720、NotoSansSC-VF 17773244、NotoSerifSC-VF 25129160）；NotoColorEmoji 缺失结论一致。deps 文档 :86-101 列 simsun* 3 文件而本文档只列 simsun.ttc，属范围差异非冲突。**无冲突**。

## 缺陷清单
- P1：无。P2：无。
- P3-1（中低，语义未定义）`src/tessell/input/router.cr:46-47`：PointerUp 不清 `@pressed` → 无中间 down 的连续 up 返回旧目标（实测 OBS `up-after-up returns stale pressed: true`）；spec 未覆盖。建议明确语义（up 后清 pressed，或文档说明按压目标保持到下次 down）。
- P3-2 `src/tessell/input/focus.cr:60-66`：`step` 每次新建 Array + 递归收集；焦点导航非零分配（M2 阶段可接受，留零分配口径时复查）。
- P3-3 `src/tessell/input/hit_test.cr:17-27`：递归 DFS，深树栈风险（与 node.cr 同源观察）。
- P3-4 `src/tessell/input/focus.cr:27-31`：`focus` 不校验注入谓词（可直接 set 被排除节点）；Router 侧有 guard（`router.cr:38`），语义自洽但公开 API 可绕过，注释未声明。
- P3-5 覆盖缺口：冒泡、enabled/可见性门控、绝对坐标换算（`hit_test.cr:6` 自述留 M2）、无焦点 key/text。
- P3-6 文档卫生：font-fallback.md 实测 117 行（任务书描述 77 行）；`docs/evidence/M1-iteration-log.md:49` 记 render_dirty_into_spec「11 it」实测 10（本核验 20 次连跑计数行佐证）；行数以实测为准。

## 最终裁定：**PASS**
A 段语义全部实测通过且与文档/实现一致；B 段 5 项字体事实复算一致、与 M0-WP4-deps.md 无冲突；flake 定性为不可复现（非当前 HEAD 确定性缺陷）；无 P1/P2，P3 观察 6 条已列。
