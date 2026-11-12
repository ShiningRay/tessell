# W2 迭代记录

- 迭代编号：W2-iter1
- 记录人：工部尚书（gongbu-shangshu），task-15 收口
- 记录时间：2026-11-12 17:36:49 +08:00（收口会话时间，非全部任务精确时间戳）
- 基线 HEAD（W1 收口后）：`1b0d832220f3017e9efd6f42d59b5d7fab6b09f3`
- W2 主提交（task-15）：`<TBD-W2>`（`feat(m0): W2 文本/IME/度量探针与布局预研`，待 push）
- hash 回填提交（task-15，第二提交）：`<TBD-W2-backfill>`（`docs: 回填 W2 提交 hash`，待 push）
- 推送结果：待执行（主提交 + 回填提交均普通 push，禁止无 --force-with-lease 强推）

## 本轮任务状态表（T8–T12，T13–T14，T17–T20）

| 任务 | 描述 | 状态 | 备注 |
| --- | --- | --- | --- |
| T8 (task-8) | W2-1：安装 FreeType/HarfBuzz 并验证 FFI 动态加载 | completed | `mingw-w64-ucrt-x86_64-freetype 2.15.0-1`、`mingw-w64-ucrt-x86_64-harfbuzz 15.1.0-1`；`examples/m0_ffi_load.cr`、`docs/evidence/M0-WP4-text-deps.md`；`ft_version=2.15.0`、`hb_version=15.1.0`，EXITCODE=0 |
| T9 (task-9) | W2-2：文本 FFI 探针（FreeType 光栅 + HarfBuzz shaping，含复杂脚本） | completed | `examples/m0_text_probe.cr`、`docs/evidence/M0-WP4-text.md`；初版 task-13 裁定 PASS-WITH-DEFECTS（D1/D2），由 task-17 修复、task-18 复验 PASS |
| T10 (task-10) | W2-3：M1 两遍布局内核接口草案与零分配验收口径（EX-W1-08） | completed | `docs/research/layout-two-pass.md` |
| T11 (task-11) | W2-4：IME 探针（IMM32 挂接 + 消息计数，M-1） | completed | `examples/m0_ime_probe.cr`、`docs/evidence/M0-WP4-ime.md`；`imm_available=true`、`imm_open_status=1`、`ime_messages=4`（基线）/`5`（`--ime-test`），EXITCODE=0；真实 IME 组合 [未验证] |
| T12 (task-12) | W2-5：帧时间/分配度量工具链 spike（P50/P95/P99 + GC 采样，M-3） | completed | `tools/bench_frame_time.cr`、`tools/bench_frame_time.ps1`、`docs/evidence/M0-WP5m-metrics.md`；task-14 裁定 PASS 附缺陷 D1（判据口径），由 task-19 修复、task-20 复验 PASS |
| T13 (task-13) | W2-核验1：文本依赖与 FFI 探针独立核验（task-8/9） | completed | `docs/evidence/verify-W2-text.md`；裁定 **PASS-WITH-DEFECTS**（D1：FT_Bitmap 布局/offsetof 偏差风险；D2：阿拉伯文 shaping 证据强度不足）→ 由 task-17 修复、task-18 复验 PASS 关闭 |
| T14 (task-14) | W2-核验2：IME 探针与度量工具链独立核验（task-11/12） | completed | `docs/evidence/verify-W2-ime-metrics.md`；裁定 **PASS 附缺陷**（D1：default workload 每帧分配，alloc 非 0 不得作为 M1-WP5「稳态差值=0」判据）→ 由 task-19 修复、task-20 复验 PASS 关闭 |
| T17 (task-17) | W2-修复：修正 FT_Bitmap 布局（D1）并强化阿拉伯文 shaping 证据（D2） | completed | 修改 `examples/m0_text_probe.cr`、`docs/evidence/M0-WP4-text.md`；FT_Bitmap sizeof=40、bitmap_left@144/top@148 sentinel 断言通过；lam-alef 多字体：tahoma/arial/times glyph_count=1（连字生效），segoeui glyph_count=2（未合并但 contextual substitution）；既有 token 不变，EXITCODE=0 |
| T18 (task-18) | W2-复验：D1 布局修复与 D2 shaping 证据复验（task-17） | completed | `docs/evidence/verify-W2-text-fix.md`；裁定 **PASS**（D1/D2 关闭） |
| T19 (task-19) | W2-修复2：度量工具补零分配稳态场景与 M1-WP5 判据协议 | completed | 修改 `tools/bench_frame_time.cr`、`tools/bench_frame_time.ps1`、`docs/evidence/M0-WP5m-metrics.md`；新增 `--steady`（预分配+索引写入）、协议 `collect→disable→采样→enable`、`scenario/alloc_bytes_steady/alloc_delta_zero/gc_stable_start`；steady 3 次 `alloc_bytes_steady=0`、`alloc_delta_zero=true`，EXITCODE=0；default 保留且明确不得用于零分配判据 |
| T20 (task-20) | W2-复验2：度量工具 steady 场景与判据映射复验（task-19） | completed | `docs/evidence/verify-W2-metrics-fix.md`；裁定 **PASS**（度量判据 D1 关闭） |

## 核验裁定与缺陷处置

- **task-13（文本依赖与 FFI 探针）**：`docs/evidence/verify-W2-text.md`，裁定 **PASS-WITH-DEFECTS**。
  - D1（文本布局）：FT_Bitmap 声明与 offsetof 偏差（pad 导致 sizeof 48≠40，bitmap_left/top 偏移错位风险）→ **task-17 修复**（按 C 语义重声明 sizeof=40，sentinel 双向验证 bitmap_left@144/top@148，`ft_layout_assert=pass`），**task-18 复验 PASS**，关闭。
  - D2（shaping 证据强度）：`ar_shaping_diff=false` 不足以证明连写生效 → **task-17 修复**（多字体 lam-alef 测试：tahoma/arial/times 单 glyph 连字证据；segoeui 未合并但 ids_differ_from_isolated=true，修正结论与 [未验证] 替代路径），**task-18 复验 PASS**，关闭。
- **task-14（IME 探针与度量工具链）**：`docs/evidence/verify-W2-ime-metrics.md`，裁定 **PASS 附缺陷**。
  - D1（度量判据）：默认 workload 每帧分配（`alloc_bytes=5779056`）不得作为 M1-WP5「稳态差值=0」判据 → **task-19 修复**（新增 `--steady` 零分配稳态场景+协议，明确 default 不得用于判据），**task-20 复验 PASS**，关闭。
- **W2 两处缺陷全部关闭**：D1 文本布局（含 D2 shaping 证据补强）与 D1 度量判据均经修复与复验 PASS。

## 未验证清单

- IME 真实组合输入：`WM_IME_STARTCOMPOSITION/COMPOSITION/END` 在真实 IME 输入下的计数与候选窗行为未自动验证（探针仅系统消息与 `--ime-test` 合成注入），需人工手测（切微软拼音输入「你好」观察计数，步骤见 `docs/evidence/M0-WP4-ime.md`）。[未验证]
- M-3 真实窗口集成与 GC 语义：steady 零分配为纯逻辑 spike 结果；嵌入 `examples/m0_window_probe.cr`（SwapBuffers 前后真实帧）后的分位数/分配表现 [未验证]；`GC.disable` 期间 `GC.stats.bytes_since_gc` 跨 GC 后端/版本语义一致性 [未验证]；steady 在其他编译器优化级别/后端/复杂 workload 下是否恒为 0 [未验证]。
- GSUB 跨字体深度：lam-alef 连字在 tahoma/arial/times 证为单 glyph，在 segoeui 未合并；更细粒度 GSUB feature/其他复杂脚本（Devanagari/Thai/emoji ZWJ 等）与 nominal-vs-shaped 深比较 [未验证]。
- 字体分发许可：Windows 系统字体（msyh/segoeui/tahoma/arial/times 等）不可随应用再分发；M2 需选用可再分发替代（如 Noto）并验证。[未验证]
- DLL 解析/分发：运行时依赖 `C:\msys64\ucrt64\bin`（libfreetype-6.dll/libharfbuzz-0.dll 等），干净环境 PATH/复制 DLL/静态链接方案 [未验证]。

## 遗留观察（M3 工具改进项）

- `GC.enable` 未在 `ensure`：`tools/bench_frame_time.cr` 在采样后调用 `GC.enable`，未包裹于异常安全的 `ensure`；若采样循环/统计路径抛异常可能导致 GC 保持禁用状态。记为遗留，建议 M3 工具改进时以 `begin ... ensure GC.enable end` 保护。[观察，非本轮阻塞]

## 提交与回填

- 主提交：`feat(m0): W2 文本/IME/度量探针与布局预研`（范围：`examples/`、`docs/evidence/`、`docs/research/layout-two-pass.md`、`tools/`），hash 待回填。
- 回填提交：`docs: 回填 W2 提交 hash`（第二小提交，普通 push；不 amend 已推送历史，与 W1 同策），hash 待回填。
- 约束：禁止 `git add -A`；`bin/` 受 .gitignore 不入库；禁止无 `--force-with-lease` 强推；未改 `src/`、`spec/`、`shard.yml`、`README`、`docs/plan*`、`docs/roadmap.md`。
