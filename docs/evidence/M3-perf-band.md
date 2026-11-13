# M3-perf-band — C5 性能区间证据（bench_scroll×5 + dirty_window×5 + zero_alloc_frame×3）

## §1 环境与命令原文

- 仓库：`C:\Users\ShiningRay\projects\ShiningRay\tessell`
- HEAD：`c364223`（`git rev-parse --short HEAD`）
- 平台：Windows 11 x64（本机）
- Crystal 版本首行：`Crystal 1.22.1 [23828b0a40] (2026-10-23)`
- PATH（实跑）：`$env:PATH="C:\msys64\ucrt64\bin;$env:PATH"`
- 基线引用：`docs/evidence/M2-summary.md` §3.1（C5/C6）、`docs/evidence/M2-WP2c-zero-alloc-criterion.md`（判据 A `<N`、B `<=256`，`delta_work = max(3 work windows)`）

### 命令原文

```powershell
$env:PATH="C:\msys64\ucrt64\bin;$env:PATH"
cd C:\Users\ShiningRay\projects\ShiningRay\tessell

# bench_scroll：构建一次后连跑 5 次（默认 frames=2000, n_alloc=1000）
crystal build tools/bench_scroll.cr -o tmp_bench_scroll.exe
for ($i=1; $i -le 5; $i++) { .\tmp_bench_scroll.exe }
Remove-Item tmp_bench_scroll.exe

# m3_dirty_window：连跑 5 次
for ($i=1; $i -le 5; $i++) { crystal run examples/m3_dirty_window.cr -- --frames=20 --verify }

# zero_alloc_frame：连跑 3 次（每次输出 static + paint1 两场景）
for ($i=1; $i -le 3; $i++) { crystal run tools/zero_alloc_frame.cr }
```

## §2 原始输出（逐行）

### 2.1 bench_scroll（5 次）

#### RUN 1（EXIT=0）
```
bench_scroll config row_count=10000 row_h=20 viewport_h=600 viewport_w=800 frames=2000 n_alloc=1000 font=C:/Windows/Fonts/msyh.ttc label="row 12345"
scenario=scroll_plus1px visible_avg=30.95 fetched_per_frame_avg=30.95 cmds_avg=61.9 batches_avg=1.0 quads_avg=247.6 alloc_bytes=128 frame_cpu_p50_us=101 frame_cpu_p95_us=190 frame_cpu_p99_us=295 frames=2000 alloc_windows=[112,128,112] delta_prime=144 delta_calib=0 retried=false attempt=1 pool_size=32 created=32
scenario=jump_fixed_seed seed=12345 visible_avg=30.9555 fetched_per_frame_avg=30.9555 cmds_avg=61.911 batches_avg=1.0 quads_avg=247.644 alloc_bytes=144 frame_cpu_p50_us=104 frame_cpu_p95_us=184 frame_cpu_p99_us=237 frames=2000 alloc_windows=[128,144,128] delta_prime=128 delta_calib=0 retried=false attempt=1 pool_size=32 created=32
GL_SCROLL_WINDOW=not_done reason=optional_not_implemented_in_task70
BENCH_SCROLL_EXIT=0
```

#### RUN 2（EXIT=0）
```
bench_scroll config row_count=10000 row_h=20 viewport_h=600 viewport_w=800 frames=2000 n_alloc=1000 font=C:/Windows/Fonts/msyh.ttc label="row 12345"
scenario=scroll_plus1px visible_avg=30.95 fetched_per_frame_avg=30.95 cmds_avg=61.9 batches_avg=1.0 quads_avg=247.6 alloc_bytes=144 frame_cpu_p50_us=105 frame_cpu_p95_us=179 frame_cpu_p99_us=220 frames=2000 alloc_windows=[96,144,96] delta_prime=112 delta_calib=0 retried=false attempt=1 pool_size=32 created=32
scenario=jump_fixed_seed seed=12345 visible_avg=30.9555 fetched_per_frame_avg=30.9555 cmds_avg=61.911 batches_avg=1.0 quads_avg=247.644 alloc_bytes=128 frame_cpu_p50_us=97 frame_cpu_p95_us=172 frame_cpu_p99_us=217 frames=2000 alloc_windows=[96,96,128] delta_prime=96 delta_calib=0 retried=false attempt=1 pool_size=32 created=32
GL_SCROLL_WINDOW=not_done reason=optional_not_implemented_in_task70
BENCH_SCROLL_EXIT=0
```

#### RUN 3（EXIT=0）
```
bench_scroll config row_count=10000 row_h=20 viewport_h=600 viewport_w=800 frames=2000 n_alloc=1000 font=C:/Windows/Fonts/msyh.ttc label="row 12345"
scenario=scroll_plus1px visible_avg=30.95 fetched_per_frame_avg=30.95 cmds_avg=61.9 batches_avg=1.0 quads_avg=247.6 alloc_bytes=176 frame_cpu_p50_us=99 frame_cpu_p95_us=170 frame_cpu_p99_us=207 frames=2000 alloc_windows=[96,128,176] delta_prime=128 delta_calib=0 retried=false attempt=1 pool_size=32 created=32
scenario=jump_fixed_seed seed=12345 visible_avg=30.9555 fetched_per_frame_avg=30.9555 cmds_avg=61.911 batches_avg=1.0 quads_avg=247.644 alloc_bytes=144 frame_cpu_p50_us=98 frame_cpu_p95_us=162 frame_cpu_p99_us=210 frames=2000 alloc_windows=[112,144,112] delta_prime=96 delta_calib=0 retried=false attempt=1 pool_size=32 created=32
GL_SCROLL_WINDOW=not_done reason=optional_not_implemented_in_task70
BENCH_SCROLL_EXIT=0
```

#### RUN 4（EXIT=0）
```
bench_scroll config row_count=10000 row_h=20 viewport_h=600 viewport_w=800 frames=2000 n_alloc=1000 font=C:/Windows/Fonts/msyh.ttc label="row 12345"
scenario=scroll_plus1px visible_avg=30.95 fetched_per_frame_avg=30.95 cmds_avg=61.9 batches_avg=1.0 quads_avg=247.6 alloc_bytes=144 frame_cpu_p50_us=100 frame_cpu_p95_us=191 frame_cpu_p99_us=259 frames=2000 alloc_windows=[144,144,112] delta_prime=144 delta_calib=0 retried=false attempt=1 pool_size=32 created=32
scenario=jump_fixed_seed seed=12345 visible_avg=30.9555 fetched_per_frame_avg=30.9555 cmds_avg=61.911 batches_avg=1.0 quads_avg=247.644 alloc_bytes=144 frame_cpu_p50_us=99 frame_cpu_p95_us=176 frame_cpu_p99_us=231 frames=2000 alloc_windows=[144,112,112] delta_prime=112 delta_calib=0 retried=false attempt=1 pool_size=32 created=32
GL_SCROLL_WINDOW=not_done reason=optional_not_implemented_in_task70
BENCH_SCROLL_EXIT=0
```

#### RUN 5（EXIT=0）
```
bench_scroll config row_count=10000 row_h=20 viewport_h=600 viewport_w=800 frames=2000 n_alloc=1000 font=C:/Windows/Fonts/msyh.ttc label="row 12345"
scenario=scroll_plus1px visible_avg=30.95 fetched_per_frame_avg=30.95 cmds_avg=61.9 batches_avg=1.0 quads_avg=247.6 alloc_bytes=144 frame_cpu_p50_us=99 frame_cpu_p95_us=176 frame_cpu_p99_us=240 frames=2000 alloc_windows=[112,144,112] delta_prime=96 delta_calib=0 retried=false attempt=1 pool_size=32 created=32
scenario=jump_fixed_seed seed=12345 visible_avg=30.9555 fetched_per_frame_avg=30.9555 cmds_avg=61.911 batches_avg=1.0 quads_avg=247.644 alloc_bytes=144 frame_cpu_p50_us=99 frame_cpu_p95_us=178 frame_cpu_p99_us=255 frames=2000 alloc_windows=[144,96,96] delta_prime=112 delta_calib=0 retried=false attempt=1 pool_size=32 created=32
GL_SCROLL_WINDOW=not_done reason=optional_not_implemented_in_task70
BENCH_SCROLL_EXIT=0
```

### 2.2 m3_dirty_window --frames=20 --verify（5 次）

#### RUN 1（EXIT=0）
```
diff_pixels=0 diff_A_vs_C=889 dirty_area_ratio=0.012568 submitted_quads_dirty=4 submitted_quads_full=57 culled_quads=53 frame_full_p50_us=249 frame_full_p95_us=551 frame_full_p99_us=719 frame_dirty_p50_us=202 frame_dirty_p95_us=370 frame_dirty_p99_us=486 dirty_rects=1 frames=20 no_move=false diff_loc=none verify=pass
```

#### RUN 2（EXIT=0）
```
diff_pixels=0 diff_A_vs_C=889 dirty_area_ratio=0.012568 submitted_quads_dirty=4 submitted_quads_full=57 culled_quads=53 frame_full_p50_us=428 frame_full_p95_us=984 frame_full_p99_us=8905 frame_dirty_p50_us=285 frame_dirty_p95_us=928 frame_dirty_p99_us=956 dirty_rects=1 frames=20 no_move=false diff_loc=none verify=pass
```

#### RUN 3（EXIT=0）
```
diff_pixels=0 diff_A_vs_C=889 dirty_area_ratio=0.012568 submitted_quads_dirty=4 submitted_quads_full=57 culled_quads=53 frame_full_p50_us=250 frame_full_p95_us=657 frame_full_p99_us=730 frame_dirty_p50_us=216 frame_dirty_p95_us=419 frame_dirty_p99_us=468 dirty_rects=1 frames=20 no_move=false diff_loc=none verify=pass
```

#### RUN 4（EXIT=0）
```
diff_pixels=0 diff_A_vs_C=889 dirty_area_ratio=0.012568 submitted_quads_dirty=4 submitted_quads_full=57 culled_quads=53 frame_full_p50_us=288 frame_full_p95_us=776 frame_full_p99_us=912 frame_dirty_p50_us=242 frame_dirty_p95_us=732 frame_dirty_p99_us=1772 dirty_rects=1 frames=20 no_move=false diff_loc=none verify=pass
```

#### RUN 5（EXIT=0）
```
diff_pixels=0 diff_A_vs_C=889 dirty_area_ratio=0.012568 submitted_quads_dirty=4 submitted_quads_full=57 culled_quads=53 frame_full_p50_us=223 frame_full_p95_us=785 frame_full_p99_us=950 frame_dirty_p50_us=200 frame_dirty_p95_us=562 frame_dirty_p99_us=568 dirty_rects=1 frames=20 no_move=false diff_loc=none verify=pass
```

### 2.3 zero_alloc_frame（3 次，每次 static + paint1）

#### RUN 1（EXIT=0）
```
scenario=static frames=200 nodes=205 alloc_bytes=16 criterion_ok=true delta_prime=0 delta_calib=0 windows=[0,0,16] retried=false attempt=1
scenario=paint1 frames=200 nodes=205 alloc_bytes=16 criterion_ok=true delta_prime=0 delta_calib=0 windows=[0,0,16] retried=false attempt=1
```

#### RUN 2（EXIT=0）
```
scenario=static frames=200 nodes=205 alloc_bytes=16 criterion_ok=true delta_prime=0 delta_calib=0 windows=[0,16,0] retried=false attempt=1
scenario=paint1 frames=200 nodes=205 alloc_bytes=0 criterion_ok=true delta_prime=0 delta_calib=0 windows=[0,0,0] retried=false attempt=1
```

#### RUN 3（EXIT=0）
```
scenario=static frames=200 nodes=205 alloc_bytes=16 criterion_ok=true delta_prime=0 delta_calib=0 windows=[16,0,16] retried=false attempt=1
scenario=paint1 frames=200 nodes=205 alloc_bytes=0 criterion_ok=true delta_prime=0 delta_calib=0 windows=[0,0,0] retried=false attempt=1
```

## §3 区间统计表（min / median / max）

**声明：本机单次会话内测量，跨会话/跨机器不可外推。**

### 3.1 bench_scroll scroll_plus1px（N=1000，frames=2000，5 次）

| 指标 | min | median | max |
|---|---:|---:|---:|
| alloc_bytes（delta_work=max 3 窗） | 128 | 144 | 176 |
| frame_cpu_p50_us | 99 | 100 | 105 |
| frame_cpu_p95_us | 170 | 179 | 191 |
| frame_cpu_p99_us | 207 | 240 | 295 |

### 3.2 bench_scroll jump_fixed_seed seed=12345（N=1000，frames=2000，5 次）

| 指标 | min | median | max |
|---|---:|---:|---:|
| alloc_bytes（delta_work=max 3 窗） | 128 | 144 | 144 |
| frame_cpu_p50_us | 97 | 99 | 104 |
| frame_cpu_p95_us | 162 | 176 | 184 |
| frame_cpu_p99_us | 210 | 231 | 255 |

### 3.3 m3_dirty_window --frames=20 --verify（5 次）

| 指标 | min | median | max |
|---|---:|---:|---:|
| diff_pixels（B vs C） | 0 | 0 | 0 |
| diff_A_vs_C | 889 | 889 | 889 |
| dirty_area_ratio | 0.012568 | 0.012568 | 0.012568 |
| submitted_quads_dirty | 4 | 4 | 4 |
| submitted_quads_full | 57 | 57 | 57 |
| culled_quads | 53 | 53 | 53 |
| frame_full_p50_us | 223 | 250 | 428 |
| frame_full_p95_us | 551 | 776 | 984 |
| frame_full_p99_us | 719 | 912 | 8905 |
| frame_dirty_p50_us | 200 | 216 | 285 |
| frame_dirty_p95_us | 370 | 562 | 928 |
| frame_dirty_p99_us | 468 | 568 | 1772 |

### 3.4 zero_alloc_frame（frames=200，3 次）

| 场景 | 指标 | min | median | max |
|---|---|---:|---:|---:|
| static | alloc_bytes | 16 | 16 | 16 |
| static | criterion_ok | true | true | true |
| paint1 | alloc_bytes | 0 | 0 | 16 |
| paint1 | criterion_ok | true | true | true |

## §4 判据映射（对齐 M2-summary §3.1 / M2-WP2c-zero-alloc-criterion.md）

判据（`docs/evidence/M2-WP2c-zero-alloc-criterion.md`）：A（硬判据）`delta_work < N`（N=1000）；B（噪声上限）`delta_work <= 256`；`delta_work = max(3 work windows)`。bench_scroll `alloc_bytes` 字段即报告的 `delta_work`（max 窗），`N=n_alloc=1000`。

| 项目 | 判据/条件 | 观测（§2 原始行） | 结论 |
|---|---|---|---|
| bench_scroll scroll_plus1px alloc | A: `<1000`，B: `<=256` | 5 次 `alloc_bytes`=[128,144,176,144,144]，`alloc_windows` 各窗均 ≤176，`retried=false attempt=1` | **达标**（5/5 满足 A、B） |
| bench_scroll jump_fixed_seed alloc | A: `<1000`，B: `<=256` | 5 次 `alloc_bytes`=[144,128,144,144,144]，各窗 ≤144，`retried=false attempt=1` | **达标**（5/5 满足 A、B） |
| zero_alloc_frame static | A/B + criterion_ok | 3 次 `alloc_bytes=16`，`windows` 含 [0,0,16]/[0,16,0]/[16,0,16]，`criterion_ok=true` | **达标**（3/3） |
| zero_alloc_frame paint1 | A/B + criterion_ok | 3 次 `alloc_bytes`=[16,0,0]，`criterion_ok=true` | **达标**（3/3） |
| m3_dirty_window 正确性/verify | `--verify` pass，`diff_pixels==0`，`diff_A_vs_C>0`，`submitted_quads_dirty < submitted_quads_full`，`dirty_area_ratio < 0.35` | 5 次均 `diff_pixels=0 diff_A_vs_C=889 dirty_area_ratio=0.012568 submitted_quads_dirty=4 submitted_quads_full=57 culled_quads=53 verify=pass EXIT=0` | **达标**（5/5） |
| bench_scroll 帧时间（p50/p95/p99） | 区间事实记录（M2-summary §3.1：C5 要求固定环境多次报告范围） | scroll_plus1px p50/p95/p99 区间 [99,105]/[170,191]/[207,295] µs；jump [97,104]/[162,184]/[210,255] µs | **记录事实，不判收益** |
| dirty_window 帧时间（full/dirty） | 区间事实记录 | full p50/p95/p99 [223,428]/[551,984]/[719,8905] µs；dirty [200,285]/[370,928]/[468,1772] µs（存在高尾延迟样本，如 run2 full p99=8905、run4 dirty p99=1772） | **记录事实，不判收益** |

说明：帧时间仅报区间事实，**不写「更快」或任何性能收益结论**；dirty/full 帧时间在本机单次会话内有明显抖动与尾延迟尖峰（见 §2 RUN2/RUN4），仅作为区间观测记录。

## §5 C5 关闭结论

- bench_scroll（2 场景 × 5 次）：全部 `alloc_bytes` ∈ [128,176]，满足 A `<1000` 且 B `<=256`，`retried=false attempt=1`（无一次不达标）。
- zero_alloc_frame（2 场景 × 3 次）：全部 `criterion_ok=true`，`alloc_bytes` ∈ {0,16}（无一次不达标）。
- m3_dirty_window（5 次）：全部 `verify=pass`、`diff_pixels=0`、`diff_A_vs_C=889`、`submitted_quads_dirty(4) < submitted_quads_full(57)`、`dirty_area_ratio=0.012568 < 0.35`（无一次不达标）。

**C5 关闭（依据本节 §2 原始行）。**

## §6 未验证清单（≥3 条，附验证所需）

1. **跨机器/跨会话稳定性未验证**：本次为本机单次会话内连续测量（声明见 §3），未覆盖重启后、不同电源计划/后台负载、不同 Windows 版本或不同 CPU/GPU 驱动组合下的区间漂移。*验证所需*：在 ≥2 台机器、≥3 个独立会话（含重启）重复 §1 全套协议并对比区间重叠。
2. **GPU 侧时间未验证**：`frame_*_p50/p95/p99_us` 为 CPU 侧/`Time.instant` 计时（bench_scroll 标注 `frame_cpu_p50_us`；dirty_window 含 WGL 交换但未拆分 GPU 执行/呈现阶段），无法证明 GPU 管线、Present/合成器等待或驱动层延迟特征。*验证所需*：引入 GPU timestamp query（或 PresentMon/DXGI 帧计时）拆分 CPU/GPU/呈现时间并在同协议下多次采集。
3. **高负载/低电量/不同驱动下的抖动未验证**：§2 中已观测到单次会话内尾延迟尖峰（如 dirty_window RUN2 full p99=8905 µs、RUN4 dirty p99=1772 µs），但未在 CPU/IO 高负载、节能/低电量、不同显卡驱动版本或高 DPI/多显示器切换下系统性施压。*验证所需*：在受控负载（如后台 stress）、AC/电池与省电策略、不同驱动与显示配置下重复测量并记录环境矩阵与抖动分布。