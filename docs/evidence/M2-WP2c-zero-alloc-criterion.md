# M2-WP2c 零分配探针判据（Windows/Boehm）

## 判据（5 探针统一：core_node / render_dirty / text_ft / glyph_atlas / text_renderer + tools/zero_alloc_frame.cr）
- 窗口：warmup → prime(诊断) → calib(N 次空迭代, 诊断) → 3 个 work 窗口；`GC.enable` 均在 `ensure`；`delta_work = max(work1,work2,work3)`。
- **A (硬判据，不放宽)**：`delta_work < N`（N=1000）。任意 per-call 分配 ≥1B/次 ⇒ 每窗 ≥1000B，必失败。
- **B (噪声上限)**：`delta_work <= 256`（按 lead 裁断：`max(128, 4×实测最大窗)=max(128,256)=256`；text_renderer 稳态 20 窗实测最大 64B，见下）。允许 Boehm 间歇簿记噪声聚合，仍能抓 ≥257B 的固定次数分配/泄漏。
- 失败必打印：`delta_work / delta_calib / delta_prime / N / windows=[w1,w2,w3]`（诊断量不参与断言）。

## 噪声分布证据（task-63 stage 1 补证，N=1000，20 窗，临时脚本 `_tmp_text_renderer_dist.cr` / `_tmp_baseline_dist.cr`，已删）
- build_text 稳态（`TextRenderer#build_text` + `rasterize_into` 复用 sink/buffer，"Hello World" 16px，800x600，全缓存命中）：
  - `build_text_windows=[32,48,48,48,48,48,48,48,32,64,32,48,48,48,48,48,32,64,32,48]`
  - `build_text_nonzero_windows=20/20`，`build_text_max=64`
- 空循环基线（不调 build_text，仅 N 次空迭代+可观测累加，GC.collect/disable 同协议）：
  - `baseline_windows=[0,1536,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]`
  - `baseline_nonzero_windows=1/20`，`baseline_max=1536`
- 对比：`max_build=64 / max_base=1536`。build_text 窗内噪声为 32/48/64B 小簇（16B 事件聚合，非 per-call）；基线出现 1536B 单窗尖峰证明 GC 簿记噪声可远大于 build_text 路径且与业务调用无关，A 门（<N）仍对 per-call 分配有效，B 上限按实测聚合抬升以避免 flake。

## 为何严格 `== 0` 不可判定（历史取证保留）
- rasterize_into 全缓存命中 1000 次 × 20 窗口 delta 序列（task-59，`_delta20_rasterize_into.cr`）：`0,0,0,0,16,0,16,0,0,16,0,0,16,0,16,0,0,16,0,0`（DELTA20_EXIT=0）。+16B 间歇出现、非每窗，故非 per-call（否则每窗≈16000B），属 Boehm `GC.stats.bytes_since_gc` 一次性簿记噪声，可落任意窗口。
- 全量 20 次 flake（step1）：run1,3-7,9-17,19-20 EXIT=0 `138 examples, 0 failures`；
  run2 EXIT=1 `138 examples, 2 failures` — `spec\glyph_atlas_spec.cr:151` `Expected 0 got 16`；`spec\render_dirty_into_spec.cr:90` `delta_steady.should eq 0` Expected 0 got 16 (Finished 100.44ms)。
  run8 EXIT=1 `138 examples, 1 failures` — `spec\glyph_atlas_spec.cr:151` Expected 0 got 16 (Finished 137.08ms)。
  run18 EXIT=1 `138 examples, 1 failures` — `spec\core_node_zero_alloc_spec.cr:109` `delta_steady should eq 0` Expected 0 got 16 (Finished 142.42ms)。

## 强度论证
- N=1000 下 A 保证检出 **1B/次** 的 per-call 分配（最坏每窗 1000B ≥ N）；B 将常数噪声容忍上限固定在 256B（4×build_text 20 窗实测最大 64B），仍可检出 **≥257B** 的固定次数分配/泄漏；`max(3 窗口)` 降低单窗漏检概率。
- 与基线 1536B 单窗尖峰对比：该尖峰来自 GC/运行时簿记而非被测 work loop 的每次迭代；若 work 窗出现同类大尖峰，B 可能误报失败（保守）但 A 仍是 per-call 核心硬门。text_renderer 实测 20/20 窗落在 32-64B。

## 判据能证明什么 / 不能证明什么
- **能证明：无 per-call（每次迭代）分配。** 由 A 门（硬判据 `delta_work < N`，N=1000）保证：若被测循环存在 ≥1B/次 的 per-call 分配，则 1000 次迭代的任一 work 窗口增量必然 ≥1000B，必被 A 抓住（不依赖 B，不受重试放水）。
- **不能证明：绝对零分配。** B 门（`delta_work <= 256`）为噪声上限而非“0”，因此 ≤256B 的**稀疏/间歇**分配可被放过。dalisi-qing-2 对抗实证（`bin/_negctl.cr` 等价构造，N=1000，每次分配 1 个 8B payload 对象但仅在稀疏次数触发）：
  - 1 次/1000 触发分配 → `delta_work=32`，窗口序列示例 `[32,0,0]`（3 窗 max），判定 **PASSED_BLIND**（A：32<N；B：32<=256）。
  - 5 次/1000 触发分配 → `delta_work=160`，窗口序列示例 `[160,0,0]`（3 窗 max），判定 **PASSED_BLIND**（A：160<N；B：160<=256）。
  结论：当前判据对“绝对 0 分配”不完备；其目标是可靠拦截 per-call 分配与较大常数级分配，而非穷尽所有稀疏小分配。

## 残余风险与缓解（m01014 落地）
- **残余 flake 风险**：1536B 级 GC/运行时簿记尖峰可能落入 work 窗口（基线 20 窗观测到 `baseline_max=1536`，见上文分布证据），造成与业务 per-call 无关的误报失败；build_text 路径实测簇为 32/48/64B，但判据无法从单窗字节数区分“尖峰噪声”与“同量级业务分配”。
- **噪声去噪重试（已落地）**：5 个 GC 探针 spec（`spec/core_node_zero_alloc_spec.cr`、`spec/render_dirty_into_spec.cr`、`spec/glyph_atlas_spec.cr`、`spec/text_ft_zero_alloc_spec.cr`、`spec/text_renderer_spec.cr`）与 `tools/zero_alloc_frame.cr` 统一实现——当 3 个 work 窗口判定失败时，**在测试/测量内部最多重试 1 次整套三窗测量**（第一次失败不算最终失败，第二次仍失败才失败）；诊断行打印 `retried=true attempt=2`（首次 `retried=false attempt=1`），失败消息同样携带 `retried/attempt`。**缓解效果与边界**：重试可吸收偶发 1536B 级尖峰带来的 flake；但 **A 门仍会抓住真实 per-call 分配且不再放大**（per-call 分配每次迭代都产生增量，重试后的每窗同样 ≥1000B 必失败），重试不构成对 A 的放水。**唯一例外**：仅限整套三窗重测，不得跳过断言、不得改 A/B 判据。
- 单次噪声若 >256B 仍可能误报失败（重试后仍失败则最终失败）；>256B 且 <N 的固定分配可能被 B 误放行（仍受 A 约束：≥1B/次 per-call 必失败）。
- 若未来观测到更高稳定噪声或重试后仍偶发误报，升级为「扣除 calib 的分位法/多窗统计」判据并同步常量与证据。
