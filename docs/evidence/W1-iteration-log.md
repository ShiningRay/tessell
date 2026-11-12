# W1 迭代记录

- 迭代编号：W1-iter1
- 记录人：翰林院编修（hanlin-bianxiu）；task-7 收口更新：工部尚书（gongbu-shangshu）
- 记录时间：2026-11-12 16:27:13 +08:00（收口更新会话时间，非全部任务精确时间戳）
- 基线文档提交（task-1）：`981e7a9f0d401170472eb1e52d90b8338dc4d577`（`docs: 纳入 M0–M4 规划与调研文档（plan/roadmap/execution/research）`，已推送 origin/main）
- M0-WP2/WP3 探针与证据收口提交（task-7）：`<PENDING_COMMIT_HASH>`（提交后回填）
- 推送结果：task-1 已推送；task-7 见下方执行记录（待完成）

## 本轮任务状态表（T1–T7）

| 任务 | 描述 | 状态 | 备注 |
| --- | --- | --- | --- |
| T1 (task-1) | 提交并推送 docs 规划文档基线（W1 文档入库） | completed | commit `981e7a9f0d401170472eb1e52d90b8338dc4d577`，HEAD/origin/main 一致 |
| T2 (task-2) | M0-WP1 本机基线记录（crystal --version / crystal spec） | completed | `docs/evidence/M0-WP1-baseline.md` |
| T3 (task-3) | M0-WP2 Isolated+Channel 仓内探针 examples/m0_isolated.cr | completed | `examples/m0_isolated.cr`、`docs/evidence/M0-WP2-isolated.md`；本机实测通过 |
| T4 (task-4) | M0-WP3 最小窗口+WGL 提交探针 examples/m0_window_probe.cr | completed | `examples/m0_window_probe.cr`、`docs/evidence/M0-WP3-window.md`；P-WIN-2，pixel_match=true |
| T5 (task-5) | 独立核验 W1 交付物（M0-WP1/WP2/WP3） | completed / PASS | `docs/evidence/verify-W1.md`，裁定 PASS（无缺陷） |
| T6 (task-6) | W2 前置调研：FreeType/HarfBuzz 依赖与 CJK/Emoji 字体路径（EX-W1-05） | completed | `docs/evidence/M0-WP4-deps.md` |
| T7 (task-7) | W1 迭代收口：提交并推送 M0-WP2/WP3 探针与证据 | in_progress | 本次收口：提交 examples/ 与 docs/evidence/ 并推送 origin/main；hash 回填待完成 |

## 核验裁定

- 核验方：大理寺卿（见 `docs/evidence/verify-W1.md`）
- 裁定：**PASS**（无缺陷）
- 核验范围：task-2/3/4 交付物（M0-WP1/WP2/WP3）及证据可复现性/真实性/完整性/边界

## 备注

- task-1 仅入库 5 个 docs 文件：`docs/plan.md`、`docs/roadmap.md`、`docs/plan-execution.md`、`docs/research/ecosystem.md`、`docs/research/crystal-capabilities.md`；未改文档内容。
- task-7 计划提交范围：`examples/`、`docs/evidence/`（含本次更新的 `W1-iteration-log.md`、`M0-WP1-baseline.md`、`M0-WP2-isolated.md`、`M0-WP3-window.md`、`M0-WP4-deps.md`、`verify-W1.md`）；`bin/` 受 .gitignore 不入库。禁止 `git add -A`，禁止改 src/spec/shard.yml/README/docs/plan* /docs/roadmap.md。
- hash 回填策略：按任务书，若采用 amend+force-with-lease，提交后回填 hash 再 amend 并 `git push --force-with-lease origin main`；具体所选路径与理由将在回报中说明。
