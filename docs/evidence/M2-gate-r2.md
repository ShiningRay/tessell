# M2 门禁第二轮复评（task-84）

- 时间：2026-11-13 13:15 +08:00（Asia/Shanghai）
- 仓库：`C:\Users\ShiningRay\projects\ShiningRay\tessell`
- HEAD：`4cc928a3f53d02032d4f2ac1d1f28a160c50ff06`；`origin/main` 同值
- 方法：只读核验 + 独立重跑；唯一写入本文件。临时探针 `bin/_g_emoji.cr` 用后已删；未改源码/证据、未 commit。

## 0. 结论

**Go-with-conditions：M3 暂不开放，C2、C3 关闭后放行；C6 在 M3-WP5 前以书面 waiver 关闭。**

进入 M3 前必须满足的硬条件：

1. **C2**：在 HEAD `4cc928a` 重跑 `verify-M2-WP2b.md` 的 99 行契约探针，或把 `M2-WP2b.md` §4 的历史表改为“76ef5d6 历史 + 当前 HEAD 仅 spec 24”并删除“代码路径未变”的断言；证据：新输出 + 文件更新 + 提交。
2. **C3**：修正 `M2-summary.md:16,22,35,41,42` 的旧数与旧结论，`M2-summary.md:55` 的 P1-1 改为原文，C3/C8 两条恢复逐字照抄或明确标注“转述”；证据：`M2-summary.md` 新 diff + 提交。
3. **C6（M3-WP5 前，不阻断 M3 开工）**：书面 waiver 承认字面 `[0,0,0]` 未达，只按 A/B 判据放行；证据：waiver 入 plan/证据 + `bench_scroll` 复跑。

## 1. 独立重跑（7 项必跑 + 2 项补充；spec 计 2 次；全部 EXITCODE=0）

| # | 命令 | 关键输出 |
|---|---|---|
| 1 | `crystal spec`（第 1 次） | `186 examples, 0 failures, 0 errors, 0 pending`；探针 `text_ft delta_work=0`、`text_renderer=48 [48,48,48]`、`virtual_list=16 [0,16,0]` |
| 2 | `crystal spec`（第 2 次） | 同 186/0/0/0；`text_renderer=48 [48,48,48]`、`virtual_list=16 [0,16,0]` |
| 3 | `crystal build src/tessell.cr` | EXIT=0；`tessell.exe` 2,271,762B，已删 |
| 4 | `tools/bench_scroll.cr` | scroll `alloc=112 p50=110 p95=193 p99=234 windows=[112,112,112] delta=112 retried=false`；jump `alloc=112 p50=112 p95=205 p99=216 windows=[112,112,96] delta=112`；`GL_SCROLL_WINDOW=not_done` |
| 5 | `tools/zero_alloc_frame.cr` | static `alloc=16 criterion_ok=true windows=[0,16,0]`；paint1 `alloc=0 criterion_ok=true` |
| 6 | `m2_text_window --frames=60 --verify` | `text_pixels_nonbg=2801 ratio=1.0618 pixel_match=true p50=1.955 p95=3.328 p99=3.622 quads=14` |
| 7 | 补充：`m2_text_window --emoji --frames=30 --verify` | `emoji_pixels_nonbg=1171 emoji_pixel_match=true emoji_ratio=0.963 p50=2.077 frames=30 swapbuffers=30 emoji_quads=2` |
| 8 | `m2_ime_probe --frames=60` | `ime_injection=blocked reason=imm_set_composition_rejected available=false imm_is_ime=true candidate_list_entries=0 preedit/result_roundtrip=false` |
| 9 | 补充：`crystal spec spec/glyph_atlas_spec.cr spec/rasterizer_spec.cr` | `24 examples, 0 failures` |

补充探针（`bin/_g_emoji.cr`，已删）：`seguiemj gids=[2317] adv=[43.9375] notdef=false`；`msyh gids=[0] adv=[22.3125] notdef=true`。防冒充成立，非“同 gid 假绿”。

## 2. C1–C4 与 C6 逐条判定

### C1 — Emoji 样例 / 字体回退：**关闭**

- 交付齐备：`src/tessell/text/font_fallback.cr:1-59`、`spec/font_fallback_spec.cr:1-33`（6 it）、`spec/text_emoji_spec.cr:1-144`（5 it）、`examples/m2_text_window.cr:270-280` 的 `--emoji`、`docs/evidence/M2-WP2-emoji.md:89-103`。
- 独立复测：`emoji_pixels_nonbg=1171`、`emoji_pixel_match=true`、`emoji_ratio=0.963`；全量 spec 186/0。
- 防冒充：seguiemj `gid=2317` 有轮廓，msyh `gid=0` 为 `.notdef`；没有用 msyh 的 `.notdef` 冒充彩色 Emoji。
- 保留 P3：`font_fallback.cr` 尚未接入 renderer；`M2-WP2-emoji.md:112` 自认 example 直接用 seguiemj+msyh 两段。C1 只要求样例显示/测量，故不阻断；但“回退”目前是单测级，不是端到端。
- 彩色 COLR/CPAL 仍是 P2，按 plan 不阻断 M2 门禁。

### C2 — `M2-WP2b.md` 当前 HEAD 证据：**部分关闭，未达原验收**

- 文件存在（90 行），当前 `spec/glyph_atlas_spec.cr + rasterizer_spec.cr` 24/0；这部分够。
- 但 §4 标题写“历史基线 76ef5d6，需在 2a2b620 重验”，`:76` 自认“仅 spec 层，未重新采集底层探针”。
- 历史基线不可从 git 复现：`git cat-file -e 76ef5d6:src/tessell/text/glyph_atlas.cr`、`...rasterizer.cr`、`...verify-M2-WP2b.md`、`...M2-WP2b.md` 全部 `exists=False`；`verify-M2-WP2b.md:1-4` 也写“工作区含未跟踪 glyph_atlas 相关文件”。该 verify 是在未跟踪工作区跑的，不是 76ef5d6 的提交内容。
- `git diff --stat 76ef5d6..HEAD` 对 glyph_atlas/rasterizer/spec 为 1304 insertions；`rasterizer.cr` 新增 shaped-run 缓存，`M2-WP2b.md:76` “代码路径未变”不成立。
- 结论：**只靠 spec 层重跑 + 历史基线契约不够**。spec 能证当前契约，不能证历史探针；必须当前 HEAD 重跑 99 行 verify，或收窄契约表并删“代码路径未变”。

### C3 — `M2-summary.md` 刷新：**未关闭**

- 已修：基线 `2a2b620`、WP2F 单列（`:19`）、Emoji 三档（`:32-34`）、无“尚未提交/待裁断”状态矛盾。
- 未修（硬伤）：
  - `:16/:35/:41/:42` 仍写“真实帧 ~3.7–4.0KB/1000 帧、A 门未过、task-73 承接”；task-73 后实测 112–160B/1000、A/B 通过。旧结论直接与新证据冲突。
  - `:22` 仍用旧 `scroll alloc 3728 p50 1199µs、jump alloc 4016 p50 1195µs`；新值为 112/112、110/112µs。
  - `:55` 把 P1-1 写成“Emoji 彩色未实现 | 已关闭”；`M2-gate.md:223` 原文 P1-1 是“WP2 Emoji 验收未实现，summary 标已完成（完成度口径放大）”。这是把阻断项缩成彩色可选项，属实质改写。
- §4.2 九行见 §3。

### C4 — BOM 例外：**关闭**

- `17814ca` 仍为 BOM（原始首字节 `EF BB BF`），未 rewrite；`M2-summary.md` §5 记为不可变例外。
- 后续三支：`9159f35` 首字节 `66 65 61 74`，`5814393`/`4cc928a` 为 `64 6F 63 73`；均非 BOM。
- 结论：历史例外有书面记录、未伪造、新提交干净，可关闭；发布时保留该例外说明。

### C6 — 真实 CPU 帧零分配：**判据通过，字面未达；需 waiver，不能算“关闭”**

- `bench_scroll`：scroll `alloc=112 windows=[112,112,112]`，jump `alloc=112 windows=[112,112,96]`；1000 帧 delta 112B（7×16B），A/B 判据通过（112<1000、<=256），但字面 `[0,0,0]` 未达。
- `M2-WP4-virtual-list.md:63-85` 已把 task-71 旧段（p50 1269/1775）与 task-73 新段（p50 102/101、112/144B）分节标注；`:98-101` 明确“A/B 通过但严格全零未达”。**该文件本身没有再拿旧数冒充新结论**；重复的 `## 7`（`:96`/`:109`）是排版问题。
- 真正过时的是 `M2-summary.md:22` 仍用旧数（见 C3），不是 WP4 主文。
- 结论：C6 不能判“已关闭”；必须写“waiver + 承认字面未达标”，M3-WP5 前关闭。它不阻断 M3 开工，但阻断 M3-WP5 验收。

## 3. §4.2 九行与 `M2-gate.md:287-295` 逐格 diff

- 逐字节一致（7/9）：C1、C2、C4、C5、C6、C7、C9。
- C3：仅弯引号 `“”` → 直引号 `""`，`first_diff_at=67`；语义未变。
- C8：仅弯引号 `“”` → 直引号 `""`，`first_diff_at=61`；语义未变。
- 判定：**不是九行全一致**。按“原文九行照抄”的字面要求，C3/C8 是改写；若接受“无语义变化的标点转写”，可视为等价，但 summary 应加一句“引号转写”或恢复弯引号。

## 4. 残余 C5/C7/C8/C9（现状、阻塞谁、责任人）

| 条件 | 现状 | 阻塞谁 | 责任人 |
|---|---|---|---|
| C5 数字区间 | 本次 text p95/p99=3.328/3.622，证据为 8.16/9.00；jump p50=112，证据 1775；仅 1 次复跑，未给 3 次区间 | 不阻断 M3；影响证据可信度 | M2-WP4 |
| C7 IME C2 | 程序化注入仍 `blocked`；真实键盘 start/composition/end、预编辑、候选窗未测 | 阻断 M3-WP3 | M2-WP3 |
| C8 UIA/GL 滚动 | UIA 未做；`GL_SCROLL_WINDOW=not_done` | 阻断 M3 对应 WP 验收 | M2-WP5 / M2-WP4 |
| C9 WP2F 许可 | `docs/research/font-fallback.md:48,57-60,91-92` 仍为 `[未验证 下载]`；OFL 全文/哈希/可分发字体未落库 | 阻断发布打包，不阻断 M3 编码 | M2-WP2F |

## 5. 本轮缺陷

- **P1-1（C3，阻断）**：`M2-summary.md:55` 把上轮 P1-1 从“Emoji 样例未实现/完成度放大”改写为“Emoji 彩色未实现”，并标“已关闭”；`:16/:35/:41/:42` 仍保留 A 门未过旧结论，与 task-73 的 112–160B/1000、A/B 通过冲突。
- **P2-1（C2，阻断）**：`M2-WP2b.md:55-76` 的历史基线 76ef5d6 在 git 中无 glyph_atlas/rasterizer/verify 文件，verify 只能来自未跟踪工作区；`:76` “代码路径未变”被 1304 insertions + shaped-run 缓存否定。
- **P2-2（C6，非阻断）**：A/B 通过但字面全零未达，尚无书面 waiver；`M2-WP4-virtual-list.md:96/109` 重复 `## 7`，易误读。
- **P3-1**：§4.2 的 C3/C8 引号被转写，未达“逐字照抄”。
- **P3-2**：`font_fallback.cr` 未接入 renderer；`M2-WP2-emoji.md:112` 已自认，但 summary 未提“单测级回退”。
- **P3-3**：`M2-WP2-emoji.md:30` 写 182 examples，当前 186；历史数字未标注。
- **P3-4**：`M2-summary.md:22` 旧 p50 未删，与 §5 数字对账表并存。

## 6. 审计限制

- 未做真实键盘 IME 手测；未做 UIA/屏幕阅读器；未做 GL 滚动上屏；未做 macOS/Linux。
- 分位数为单次本机采样，受 CPU 频率/负载影响；只证明“本机可复现趋势”，不证明跨环境恒定。
- 未读 `M2-WP2-emoji.md` 全文逐行，只抽查关键结论与行号；未重新实现 Emoji 渲染路径。
- 本报告不评价 M2 代码质量本身；结论只针对门禁条件与证据一致性。
