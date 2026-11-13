# M2-WP2c 零分配探针判据（Windows/Boehm）

## 判据（4 探针统一：core_node / render_dirty / text_ft / glyph_atlas + tools/zero_alloc_frame.cr）
- 窗口：warmup → prime(诊断) → calib(N 次空迭代, 诊断) → 3 个 work 窗口；`GC.enable` 均在 `ensure`；`delta_work = max(work1,work2,work3)`。
- **A (硬判据)**：`delta_work < N`（N=1000）。任意 per-call 分配 ≥1B/次 ⇒ 每窗 ≥1000B，必失败。
- **B (噪声上限)**：`delta_work <= 64`。允许 Boehm 间歇簿记噪声，仍能抓 ≥100B 的固定次数分配。
- 失败必打印：`delta_work / delta_calib / delta_prime / N / windows=[w1,w2,w3]`（诊断量不参与断言）。

## 为何严格 `== 0` 不可判定
- rasterize_into 全缓存命中 1000 次 × 20 窗口 delta 序列（task-59 取证，`_delta20_rasterize_into.cr`，N=1000）：`0,0,0,0,16,0,16,0,0,16,0,0,16,0,16,0,0,16,0,0`（DELTA20_EXIT=0）。+16B 间歇出现、非每窗，故非 per-call（否则每窗≈16000B），属 Boehm `GC.stats.bytes_since_gc` 一次性簿记噪声，可落任意窗口。
- 全量 20 次 flake（step1）：run1,3-7,9-17,19-20 EXIT=0 `138 examples, 0 failures`；  
  run2 EXIT=1 `138 examples, 2 failures` — `spec\glyph_atlas_spec.cr:151` `Expected 0 got 16`；`spec\render_dirty_into_spec.cr:90` `delta_steady.should eq 0` Expected 0 got 16 (Finished 100.44ms)。  
  run8 EXIT=1 `138 examples, 1 failures` — `spec\glyph_atlas_spec.cr:151` Expected 0 got 16 (Finished 137.08ms)。  
  run18 EXIT=1 `138 examples, 1 failures` — `spec\core_node_zero_alloc_spec.cr:109` `delta_steady should eq 0` Expected 0 got 16 (Finished 142.42ms)。未复现 text_ft_zero_alloc_spec.cr:12；glyph_atlas:151 原为旧单窗口 `delta.should eq 0_u64`。

## 强度论证
- N=1000 下 A 保证检出 **1B/次** 的 per-call 分配（最坏每窗 1000B ≥ N）；B 将常数噪声容忍上限固定在 64B（实测 16B 的 4×），仍可检出 **≥100B** 的固定次数分配/泄漏；`max(3 窗口)` 降低单窗漏检概率。

## 稳定性验收（本次修改后）
- 全量 `crystal spec` 连跑 10 次：10/10 绿（逐次见回报统计）。
- 4 探针单跑各 10 次：40/40 绿（逐次见回报统计）。

## 残余风险
- 单次噪声若 >64B 会误报失败；>64B 且 <N 的固定分配可能被 B 误放行（仍受 A 约束：≥1B/次 per-call 必失败）。若未来观测到 >64B 噪声，升级为「扣除 calib 的分位法/多窗统计」判据。A/B 不证明“绝对 0 分配”，仅在 Boehm 噪声下提供可判定的强下界检测。