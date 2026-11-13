# M4-WP4 一键质量门禁与 DoD 固化

- 任务：task-123（M4-WP4），HEAD `1161e53`，本地 clean 基线
- 产物：`tools/gate.ps1`、`docs/evidence/M4-WP4-gate.md`
- 运行：2026-11-13 20:22 CST PASS；20:23 CST fail_probe 反证
- 命令：`powershell -NoProfile -ExecutionPolicy Bypass -File tools/gate.ps1`
- 约束：未改 `src/`/`spec/`/`examples/`/`tools/package.ps1`，未 commit

## 1. 门禁项表（本次 PASS，14 项）

| 项 | 命令/对象 | 判据(关键) | 耗时ms |
|---|---|---|---:|
| spec | crystal spec | 233 ex,0 fail | 5044 |
| build | crystal build src/tessell.cr | EXIT 0 | 2105 |
| m2_text | m2_text_window --verify | pixel_match=true | 2957 |
| m2_emoji | m2_text_window --emoji --verify | emoji_pixel_match=true | 3083 |
| m3_dirty | m3_dirty_window --verify | diff=0,A_vs_C=889,pass | 3340 |
| dpi_light | m3_dpi_theme light --verify | verify=pass | 3418 |
| dpi_dark | m3_dpi_theme dark --verify | verify=pass | 3462 |
| scroll_dy20 | m3_scroll --verify --dy=20 | diff=0,A_vs_C=3101,pass | 7736 |
| scroll_dy600 | m3_scroll --verify --dy=600 | diff=0,A_vs_C=3415,pass | 5022 |
| zero_alloc | zero_alloc_frame.cr --json | criterion_ok=2,false=0 | 2311 |
| bench | bench_scroll.cr (记录,不判) | alloc/p50/p95/p99 记录 | 3828 |
| atlas | atlas_raster_verify.cr | EXIT 0,9 checks ok | 2298 |
| package | package.ps1 -OutDir dist\gate | PACKAGE_OK+bare verify | 8963 |
| hygiene | git status/log | 白名单,status_ok=true | 163 |

注：atlas 实测 9 个 check（任务描述写 8，此处按工具输出记）。

## 2. DoD 逐条对照

| DoD/要求 | 证据与引用 | 状态 |
|---|---|---|
| 一键门禁可复跑 | tools/gate.ps1，PASS 14/14 | 满足 |
| 零分配判据可测 | item10, docs/plan.md:162-173, M2-WP2c:5-6 | 满足 |
| 帧/滚动指标记录 | item11, docs/plan.md:169,197 bench仅记录 | 满足 |
| 测试策略/verify | item3-9,12, docs/plan.md:186-198 | 满足 |
| 打包裸PATH可用 | item13, docs/plan.md:264 bare_exit=0 | 满足 |
| 门禁与卫生 | item14 白名单, docs/plan.md:266 | 满足 |

## 3. 指标清单（本次实测）

- spec: 221 examples, 0 failures, 0 errors, 0 pending
  （M4 迭代 5 起全量为 233 examples，见 PROJECT-final-gate.md）
- bench(CPU,us): p50=97 p95=175 p99=218 alloc_bytes=112
- bench alloc_windows: [112,96,112] delta_prime=112 delta_calib=0
- zero_alloc: criterion_ok=true_count=2 false_count=0 (--json,200帧)
- scroll dy20: diff_pixels=0 diff_A_vs_C=3101 quads_full=141 quads_dirty=5
  alloc_windows=[0,0,0] culled=136 visible_avg=30.0000 verify=pass
- scroll dy600: diff_pixels=0 diff_A_vs_C=3415 quads_full=150 quads_dirty=150
  alloc_windows=[96,48,64] verify=pass
- dirty: diff_pixels=0 diff_A_vs_C=889 quads_dirty=4 quads_full=57
- m2: pixel_match=true quads=14; emoji emoji_pixel_match=true ratio=0.9630
- package: PACKAGE_OK out_dir=...\dist\gate bare_exit=0 verify=pass

## 4. 本次运行摘录

- PASS: `GATE_RESULT=PASS`, `GATE_EXIT=0`（14 门禁+记录项全 PASS）
- hygiene token:
  `status_ok=True unexpected=[] subj_first6=[100 111 99 115 58 32]`
  `allowed_untracked=[docs/evidence/M3-gate-r4.md,`
  `examples/app_demo.cr,tools/gate.ps1]`
- 反证: `[FAIL] fail_probe exit=1 ms=1.3`
  `FailProbe='C:\nonexistent\path\for_fail_probe' exists=False`
  `GATE_RESULT=FAIL`（其余 14 项仍 PASS）

## 5. 故意失败反证

- 命令: `tools/gate.ps1 -FailProbe "C:\nonexistent\path\for_fail_probe"`
- 结果: `GATE_RESULT=FAIL`, `FAILPROBE_EXIT=1`（非零）
- 未改仓库文件；记录: `$env:TEMP\gate_task123_failprobe_final.txt`

## 6. 复盘模板（六字段）

| 字段 | 内容 |
|---|---|
| 时间/人 | 2026-11-13 / gongbu-shangshu-4 |
| 目标 | 落地 M4-WP4 门禁脚本与 DoD 固化文档 |
| 结果 | PASS 14/14；反证 FAILPROBE_EXIT=1 |
| 问题 | PS `$args` 自动变量遮蔽参数，--verify/--dy 未传入 |
| 修复/决策 | 参数改 `$exArgs`；hygiene 改白名单(lead m00662) |
| 后续 | CI 接入/跨机基线/GPU计时/覆盖率待补 [未验证] |

## 7. [未验证]

- `[未验证]` CI 未接入：门禁未在 CI runner 自动执行与留档。
- `[未验证]` 跨机器基线：不同 CPU/GPU/驱动下耗时与 alloc 可能波动。
- `[未验证]` GPU 计时：指标为 CPU 侧/工具口径，非 GPU 帧时间。
- `[未验证]` 覆盖率：未产出 spec/示例的行或分支覆盖率报告。
- `[未验证]` 并行 app_demo：`examples/app_demo.cr` 他人并行开发，未纳入门禁。
- `[未验证]` 字体许可：沿用既有证据，本门禁不重复断言。
