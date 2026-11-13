# M4 迭代 4 日志（M4-iter4）

- 任务：task-127；HEAD `1161e53`；记录日 2026-11-13；执行者 gongbu-shangshu-4
- 范围：只建本文件；禁改其它文件、禁 commit；数字均实跑或标来源
- 行数口径：`[System.IO.File]::ReadAllLines` 实测；token 照录（折行仅插换行）

## 1. 任务表

| 任务 | 内容 | 执行者 | 状态 |
|---|---|---|---|
| task-122 | M4-WP3 app_demo.cr + docs/usage.md | gongbu-shangshu-3 | in_progress |
| task-123 | M4-WP4 门禁 tools/gate.ps1 + DoD 文档 | gongbu-shangshu-4 | completed |
| task-124 | M3 收口门禁终审 r4（M3-gate-r4.md） | zuodu-yushi | completed |
| task-125 | 证据口径修正（P2-1/P2-2/P3 三文档） | dalisi-qing-2 | completed |
| task-126 | 独立核验 M4-WP3/WP4 | dalisi-qing-2 | in_progress |

## 2. 交付物清单 + 实测行数

| 交付物 | 行数 | 备注 |
|---|---:|---|
| examples/app_demo.cr | 912 | task-122，在审 |
| docs/usage.md | 91 | task-122，在审 |
| tools/gate.ps1 | 245 | 14 项门禁 + `-FailProbe` |
| docs/evidence/M4-WP4-gate.md | 90 | task-123 证据 |
| docs/evidence/M3-gate-r4.md | 103 | task-124 终审，重建版 |
| docs/evidence/verify-M4-WP3-WP4.md | 47 | task-126 完成 |
| M3-C8-gl-scroll.md | 377→382 | task-125 修正后实测 382 |
| M3-WP1-backend-dirty.md | 126→126 | 修正后实测 126 |
| M3-iteration-log.md | 259→262 | 修正后实测 262 |

- 备注：verify-M4-WP3-WP4.md=47 行；task-126 核验完成，裁定 PASS-WITH-DEFECTS（P1/P2 无，P3×2）。

## 3. 实测证据照录（原始 token 行）

- app_demo 三组（bin/app_demo.exe 本日实跑，均 EXIT=0）：
  light：`frames=120 rows=10000 row_h=20 viewport=800x688`
  `list_viewport=800x600 theme=light dpi=1.0 text_size=16`
  `visible_avg=30.0000 quads_dirty=159 quads_full=171 culled=12`
  `diff_pixels=0 diff_A_vs_C=3113 diff_theme=0 diff_theme_roundtrip=0`
  `alloc_windows=[0,0,0] retried=false attempt=1 scroll=0 verify=pass`
  dark：`frames=120 rows=10000 row_h=20 viewport=800x688`
  `list_viewport=800x600 theme=dark dpi=1.0 text_size=16`
  `visible_avg=30.0000 quads_dirty=158 quads_full=170 culled=12`
  `diff_pixels=0 diff_A_vs_C=3102 diff_theme=0 diff_theme_roundtrip=0`
  `alloc_windows=[0,0,0] retried=false attempt=1 scroll=0 verify=pass`
  dpi1.5：`frames=120 rows=10000 row_h=20 viewport=800x704`
  `list_viewport=800x600 theme=light dpi=1.5 text_size=24`
  `visible_avg=30.0000 quads_dirty=168 quads_full=171 culled=3`
  `diff_pixels=0 diff_A_vs_C=6092 diff_theme=0 diff_theme_roundtrip=0`
  `alloc_windows=[0,0,0] retried=false attempt=1 scroll=0 verify=pass`
- 如实声明：`retried=false attempt=1` 为本次运行观测；核验者独立复跑曾各
  观测一次 `ALLOC_ATTEMPT1` 首窗 3792B 失败 → `attempt=2` 通过
  （`--dpi=1.5` 与 `crystal run` 形式），属判据允许的 ≤1 次重试，故非普适。
- gate（transcript `$env:TEMP\gate_task123_pass_final.txt`）：
  `PASS | spec | exit=0 | ms=5044 | 221 examples, 0 failures`
  `GATE_RESULT=PASS`（14/14，`GATE_EXIT=0`）
  scroll dy20：`... alloc_windows=[0,0,0] retried=false attempt=1`
  `frames=120 verify=pass GL_SCROLL_WINDOW=done`
  scroll dy600：`... alloc_windows=[96,48,64] retried=false attempt=1`
  `frames=120 verify=pass GL_SCROLL_WINDOW=done`（非全零，在 B 内）
  `PASS | package_bare_path | exit=0 | PACKAGE_OK ... bare_exit=0`
  `verify=pass`
  hygiene：`status_ok=True allowed_untracked=[docs/evidence/M3-gate-r4.md,`
  `examples/app_demo.cr,tools/gate.ps1] unexpected=[]`
  `subj_first6=[100 111 99 115 58 32]`
  反证（`-FailProbe` 不存在路径）：`[FAIL] fail_probe exit=1`
  `FailProbe='C:\nonexistent\path\for_fail_probe' exists=False`
  `GATE_RESULT=FAIL`，`FAILPROBE_EXIT=1`
- 零分配口径（唯一合法）：A `delta_work<1000`、B `delta_work<=256`
  （`M2-WP2c-zero-alloc-criterion.md:5-6`），非严格 0。dy600 四组观测
  （均 verify=pass）：`[0,0,0]`（:337）、`[96,80,0]`（:331）、
  `[80,80,80]`（:332）、`[96,48,64]`（gate 本轮）；16–96B 簿记噪声。
- 如实声明：`alloc_windows=[0,0,0]` 仅为观测值；本机 16–96B 及以上一次性
  分配可达 3.7–3.9KB 且可落首窗（合法判据仍为 A/B）。

## 4. 事故台账（如实）

- `docs/evidence/M3-gate-r4.md` 曾被并行 agent（本人）误移到
  `$env:TEMP\task123_moved_M3-gate-r4.md`；原作者随后重建（现 103 行）。
  本人未覆盖重建件；TEMP 副本保留，待 lead/原作者处置。
- 由此红线（lead m00662）：禁 `git clean`/`checkout -- .`/`reset --hard`/
  `stash`/`restore .`；净区只许删本人临时产物或上报 lead。
- `tools/gate.ps1` `file_hygiene` 由「status 必空」改白名单判定：允许 5 个
  未跟踪路径；其余未跟踪或 tracked 变更逐条打印并 FAIL。

## 5. 门禁条件台账（C5–C9）

| 条件 | 状态 | 来源 |
|---|---|---|
| C5 | 关闭 | M3-iteration-log.md:144-146,233 |
| C6 | waiver 仅覆盖 M3-WP5 | :170,228,234；M2-summary.md:47-52 |
| C7 | 未关闭（真实键盘 IME 手测需人工） | M3-iteration-log.md:235 |
| C8 | 部分（GL 滚动已做；UIA provider 未实现，lead 裁断缩减） | :236-239 |
| C9 | 未关闭（字体许可） | M3-iteration-log.md:237 |

## 6. 未验证清单（带验证所需）

1. 跨机器/跨 GPU 性能与零分配基线 — 验证所需：第二台机器重跑 gate。
2. macOS/Linux 后端 — 验证所需：非 Windows 环境（M3-WP2 本机 No-Go）。
3. CI 平台接入 — 验证所需：CI runner 与凭证。
4. 覆盖率采集 — 验证所需：覆盖率工具接入 spec 流程。
5. app_demo `T` 键真实键盘交互 — `KeyCode` 无 `KeyT`（event.cr:20-33），
   走 `text_input`（examples/app_demo.cr:527）— 验证所需：人工真机手测。
6. 字体许可文本与 Noto 获取 — 验证所需：网络与授权（沿用 M4-WP2 证据）。

## 7. 下一步

- M4-WP2 安装器/代码签名/干净 VM 未做（M4-WP2-packaging.md [未验证]）。
- C7 需人工键盘手测；C9 需 lead 决策许可策略。
- M3-WP3 Linux 验证、M3-WP4 stencil/cover（可选）。
## 8. 提交（M4 迭代 4）

- 4e061c6 feat(m4): 真实示例应用与一键质量门禁（M4-WP3/M4-WP4）
- f06cb3f docs: M3 收口门禁终审、独立核验与零分配口径修正
- （见提交 3 本身）docs: 回填 M4 迭代 4 提交 hash
- 推送：已 push 到 origin/main（HEAD == origin/main，见验证）

# M4 迭代 5 收口日志（M4-iter5）

- 任务：task-129（S3）+ task-128（README/C9）+ task-130（独立核验）；
  HEAD `5547fac` 起；执行者 gongbu-shangshu-4；记录日 2026-11-13。
- 范围：S3 代码 + 两个新 spec + app_demo 接入 + README 一行事实修正；
  未动 docs/ 与 tools/（除本日志与既有证据件），未做破坏性 git 操作。

## 1. 任务表

| 任务 | 内容 | 执行者 | 状态 |
|---|---|---|---|
| task-128 | README 重写 + C9 许可决策 | gongbu-3 | completed |
| task-129 | M4-WP1 S3（a11y 同步 + D6） | gongbu-shangshu-4 | completed |
| task-130 | S3 独立核验 | zuodu-yushi | PASS（67 行） |

- 注：task-130 原派 dalisi-qing-2，上下文耗尽无产出，改派 zuodu-yushi。

## 2. 交付物实测行数（ReadAllLines）

| 交付物 | 行数 |
|---|---:|
| README.md | 80 |
| docs/evidence/M4-WP2-licensing.md | 51 |
| spec/ui_a11y_spec.cr | 273 |
| spec/router_single_entry_spec.cr | 85 |
| docs/evidence/verify-M4-WP1-S3.md | 67 |

## 3. 证据

- spec：`233 examples, 0 failures`（基线 221，新增 12）。
- 三组 `--verify` 均 `a11y_nodes=34 verify=pass alloc_windows=[0,0,0]`
  `retried=false attempt=1`；`diff_A_vs_C=3113/3102/6092`。
- `zero_alloc_frame --frames=200 --json`：static `windows=[0,16,0]`、
  paint1 `[0,0,0]`，均 `criterion_ok=true`。
- 探针 A：五字段一致；B：删除后 emit 3→2；C：10000 行仅 32 节点且
  scroll_to(4000) offset=4000；D：默认值 tree_same/dirty_same 均 true；
  E：D6 自 grep 19 命中只有 router.cr/focus.cr 写入。

## 4. 缺陷台账

- S3 无 P0/P1/P2。
- P3×3：仅本机 Windows/WGL；app_demo `--verify` 滚动为 0，虚拟滚动只
  在合成探针覆盖；README/许可文件未在核验范围。

## 5. 条件台账更新

- C5 关闭（前轮）；C6 waiver 仅覆盖 M3-WP5；C7 仍未关闭（真实键盘
  IME 手测需人工）；M3-WP2 macOS No-Go、M3-WP3 Linux 本机不可验证。
- C9 → 决策已定（D-C9：不随包分发 Windows 字体、推荐 Noto OFL），
  法务复核项列为未验证。

## 6. 未验证

1. 跨机器/跨 GPU 基线 — 需第二台机器重跑 gate。
2. CI 接入 — 需 runner 与凭证。
3. 覆盖率采集 — 需工具接入 spec 流程。
4. 法务复核（OFL 文本/DLL 条款）— 需法务。
5. 真实键盘 IME 手测（C7）— 需人工真机。

## 7. 下一步

- 最终项目门禁（全量 gate + 法务复核 + C7 手测 + 跨机器基线）。

## 8. 提交（M4 迭代 5）

- d1407a3 feat(m4): DSL 无障碍同步与事件单一入口（M4-WP1 S3）
- d258207 docs: README 重写、C9 字体许可决策与 S3 独立核验
- （见提交 3 本身）docs: 回填 M4 迭代 5 提交 hash
- 推送：已 push 到 origin/main（HEAD == origin/main，见验证）
