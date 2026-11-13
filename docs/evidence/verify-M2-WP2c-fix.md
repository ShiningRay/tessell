# verify-M2-WP2c-fix（M2-WP2c 修复复核：task-59 rasterizer 三缺陷 + task-58 零分配判据）

- 任务：task-60（复核 task-59/task-58，工作区未提交，HEAD=76ef5d6）
- 核验人：dalisi-qing-2（只读核验 + 重跑 + 本报告；未修改 src/spec/tools/其它 docs，未 commit）
- 时间：2026-11-13（Asia/Shanghai，会话内执行）
- 环境：Windows, Crystal 1.22.1；`$env:PATH="C:\msys64\ucrt64\bin;$env:PATH"`；字体 `C:/Windows/Fonts/msyh.ttc`/`tahoma.ttf`/`arial.ttf`/`times.ttf`
- 元信息：最终行数 54（read 工具口径）；本报告由 dalisi-qing-2 产出

## A. D1 空白字形（`src/tessell/text/rasterizer.cr`）
### A1 代码分支确认（真实分支，非特判样本）
- `src/tessell/text/rasterizer.cr:128-131` lookup 命中直接返回 placement（统计 hits）。
- `:136-139` `gid==0` → 返回零位图 placement（w=h=0, uv=0, 保留 HB advance），**不插入图集、不计 miss/rasters**（在 `:141-142` 之前 return）。
- `:141-142` `@misses += 1; @rasters += 1` 后 `FT::Lib.load_glyph(..., LOAD_RENDER)` `:145`，取 `bitmap_left/top` `:154-155`。
- `:160-163` `w <= 0 || h <= 0`（如 space/tab/空白 bitmap）→ 返回零位图 placement（正确 bearing/advance），**不插入图集**（未达 `:165 insert`）；但该路径位于 `:141-142` 之后，**miss/rasters 计数会增加**（与 used_pixels 不增并存，属统计口径事实，见 A2 证据）。
- `:165-167` 仅可绘制 bitmap 才 `@atlas.insert` + `copy_bitmap_to_atlas`；`copy_bitmap_to_atlas :170-198` 处理正/负 pitch。

### A2 独立重跑（`crystal run bin/_vfix.cr` EXIT=0，临时脚本已删；placements==HB glyph 数，Σadvance 与 measure/HB 差 ≤0.5px，空白不占图集）
| case | placements | HB glyphs | Σadvance | measure | diff_meas | used_delta | rasters_delta | misses_delta | 备注 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---|
| `"a b"` | 3 | 3 | 35.6953125 | 35.6953125 | 0.0 | 390 | 3 | 3 | zero_bitmap_placements=1（空格不占图集） |
| `"   "` (3 空格) | 3 | 3 | 21.3046875 | 21.3046875 | 0.0 | 0 | 3 | 3 | 纯空白不增 used_pixels |
| `"\t\n"` | 2 | 2 | 33.46875 | 33.46875 | 0.0 | 0 | 0 | 0 | 不增 used_pixels |
| `""` | 0 | 0 | 0.0 | 0.0 | 0.0 | 0 | 0 | 0 | 不抛异常 |
| `" 中文 空格 "` | 7 | 7 | 117.3046875 | 117.3046875 | 0.0 | 2140 | 7 | 7 | 含空白字形，空白位不占图集 |
- `D1_EXCEPTIONS=none`；Σadvance 与 HB sum 亦一致（"a b" hb_sum=35.6953125 diff_hb=0.0）。

## B. D2 RTL 与反向用例（同一独立脚本，msyh/16px 等）
| case | font | count | HB | Σadvance | HB sum | measure | diff_meas | diff_hb |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| `"لا"` | msyh.ttc | 2 | 2 | 22.3125 | 22.3125 | 22.3125 | 0.0 | 0.0 |
| `"لا"` | tahoma.ttf | 1 | 1 | 9.7421875 | 9.7421875 | 9.7421875 | 0.0 | 0.0 |
| `"لا"` | arial.ttf | 1 | 1 | 8.703125 | 8.703125 | 8.703125 | 0.0 | 0.0 |
| `"لا"` | times.ttf | 1 | 1 | 8.703125 | 8.703125 | 8.703125 | 0.0 | 0.0 |
| `"abc"` (LTR) | msyh.ttc | 3 | 3 | 27.0859375 | 27.0859375 | 27.0859375 | 0.0 | 0.0 |
| `"لاabc"` (混排) | msyh.ttc | 5 | 5 | 49.171875 | 49.171875 | 49.171875 | 0.0 | 0.0 |
- msyh `"لا"` count==HB==2 且 advance 一致；tahoma/arial/times 均 count==1 且一致；LTR 与混排用例一致，未见硬编码特判。`D2_EXCEPTIONS=none`。

## C. D3 spec 可单跑与顺序无关性
### C1 逐文件单跑（正序，`spec/*.cr` 除 `spec_helper.cr`，共 15 文件）— 全部 EXIT=0
`core_node_detach_spec.cr 8/0f | core_node_spec.cr 13/0f | core_node_zero_alloc_spec.cr 6/0f | geometry_spec.cr 6/0f | glyph_atlas_spec.cr 13/0f | input_focus_spec.cr 8/0f | input_hit_test_spec.cr 8/0f | input_router_spec.cr 12/0f | layout_spec.cr 12/0f | rasterizer_spec.cr 11/0f | render_dirty_into_spec.cr 10/0f | render_draw_list_spec.cr 15/0f | text_ft_spec.cr 6/0f | text_ft_zero_alloc_spec.cr 1/0f | text_measurer_spec.cr 12/0f`

### C2 逆序单跑（Name 降序）— 全部 EXIT=0
与 C1 同集合结果对称全绿：`text_measurer 12/0f, text_ft_zero_alloc 1/0f, text_ft 6/0f, render_draw_list 15/0f, render_dirty_into 10/0f, rasterizer 11/0f, layout 12/0f, input_router 12/0f, input_hit_test 8/0f, input_focus 8/0f, glyph_atlas 13/0f, geometry 6/0f, core_node_zero_alloc 6/0f, core_node 13/0f, core_node_detach 8/0f`。

### C3 spec_helper 副作用检查
- `spec/spec_helper.cr:1-2` 仅 `require "spec"` 与 `require "../src/tessell"`（共 2 行），无全局状态初始化/测试注册副作用；C1/C2 两种顺序全绿，未发现顺序依赖。

## D. 零分配判据强度
### D1 探针与工具审查（断言/GC/窗口）
| 文件 | 判据断言 | GC.enable | 窗口/统计 | prime/calib |
|---|---|---|---|---|
| `spec/core_node_zero_alloc_spec.cr:139-144` | `delta_work < n && delta_work <= 64`（A+B） | `ensure` 关闭 GC：:102-104,:120-122,:136-138 均 `GC.enable` | 3 个 work 窗口取 `max`(:126-139, `seq` 打印) | prime/calib 仅采集打印，不参与断言 |
| `spec/render_dirty_into_spec.cr:120-125` | 同上 | ensure: :83-85,:101-103,:117-119 | 3 窗口 max(:107-120) | 仅诊断 |
| `spec/text_ft_zero_alloc_spec.cr:71-76` | 同上 | ensure: :34-36,:52-54,:68-70 | 3 窗口 max(:58-71) | 仅诊断 |
| `spec/glyph_atlas_spec.cr:192-197` | 同上 | ensure: :151-153,:169-171,:189-191 | 3 窗口 max(:175-192) | 仅诊断 |
| `tools/zero_alloc_frame.cr:194-196,205-211` | `alloc < frames && alloc <= 64`；`exit 1 unless static_ok && paint_ok`；输出 `criterion_ok`/`alloc_bytes` | ensure: :101-103,:119-121,:142-144 | `measure_scenario` 3 work 窗口取 max(:125-146) | prime/calib 仅诊断输出 |

### D2 对抗实验（必做，`bin/_negctl.cr`，N=1000，每次分配 1 个 8B payload 对象；已删除）
- 命令：`crystal run bin/_negctl.cr` → EXIT=0
- 结果：`NEGCTL delta_prime=34208 delta_calib=0 delta_work=31968 N=1000 windows=[28576,31968,31968] criterion_ok=false`，`RESULT=CAUGHT`
- 结论：**判据成功捕获**（delta_work 31968，既不 < N 也不 <= 64），未放水。

### D3 独立稳定性与对照
- 全量 `crystal spec` 5 次（独立）：`141 examples, 0 failures, 0 errors, 0 pending`，EXIT=0（run1-run5 全绿）。
- 4 探针各 5 次（共 20 次）：core_node_zero_alloc 6/0f×5、render_dirty_into 10/0f×5、text_ft_zero_alloc 1/0f×5、glyph_atlas 13/0f×5，全部 EXIT=0（20/20）。
- 对照：gongbu 报 10/10（全量）与 40/40（探针）；本次独立复核范围为 5/5 与 20/20，结果一致全绿（样本量按任务书执行）。

## E. 三件套重跑
- `crystal spec`：141 examples, 0 failures, 0 errors, 0 pending，EXIT=0（同 D3 run1）。
- `crystal build src/tessell.cr`：BUILD_EXIT=0，`tessell.exe deleted`。
- `crystal run tools/zero_alloc_frame.cr`（ZAF_EXIT=0）：
  - `scenario=static frames=200 nodes=205 alloc_bytes=0 criterion_ok=true delta_prime=0 delta_calib=0 windows=[0,0,0]`
  - `scenario=paint1 frames=200 nodes=205 alloc_bytes=16 criterion_ok=true delta_prime=0 delta_calib=0 windows=[0,0,16]`

## 缺陷清单
- P1：无（对抗实验 CAUGHT；D1/D2/C/E 均满足；未发现判据放水）。
- P2：无（5/5 全量、20/20 探针、三件套全部 EXIT=0）。
- P3-1（观察，非回归失败）：空白 bitmap 路径 `rasterizer.cr:141-142,160-163` 在返回零位图 placement 前已累计 `misses/rasters`（如 `"   "` rasters_delta=3, used_delta=0），与“gid==0 不计 miss/rasters”统计口径不完全一致，但满足“不入图集/不占 used_pixels 且 placements/advance 正确”。
- P3-2（观察）：`tools/zero_alloc_frame.cr` paint1 场景出现 `alloc_bytes=16`（windows `[0,0,16]`），仍在判据 A/B 内（<200 且 <=64，criterion_ok=true），非阻塞。

## 裁定
- **PASS**
- 理由：A D1 空白/空串/混排无异常且 placements==HB、Σadvance 与 measure/HB 一致、空白不占图集；B D2 `"لا"`(msyh count==2) 与 tahoma/arial/times(count==1) 及 `"abc"`/`"لاabc"` 反向用例 advance/count 全部一致；C 15 个 spec 文件正序/逆序单跑全绿（30/30），spec_helper 无副作用；D 4 探针+工具均为 `delta_work<N && delta_work<=64`、3 窗口 max、`GC.enable` 在 ensure、prime/calib 仅诊断，且对抗实验 **CAUGHT**(delta_work=31968, criterion_ok=false) 证明判据有效；E 全量 5/5、探针 20/20、build 与 zero_alloc_frame 两场景 criterion_ok=true 全绿。另有 P3 观察项 2 条不影响通过结论。
