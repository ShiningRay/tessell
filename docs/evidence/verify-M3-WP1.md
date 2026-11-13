# verify-M3-WP1.md — M3-WP1 后端抽象 + 脏矩形部分提交 独立核验（dalisi-qing-2, task-94）

## §0 元信息
- HEAD：`ef8903a6b9b6558fb82a1d49479bd6a2920bf3af`（`git rev-parse HEAD`）；日期 2026-11-13 Asia/Shanghai；核验方 dalisi-qing-2。**只读声明**：未改 `src/`、`spec/`、`examples/`，未 commit；仅写本报告与临时脚本 `bin/_v_yflip.cr`（已执行并删除）。
- 环境：`$env:PATH="C:\msys64\ucrt64\bin;$env:PATH"`，Crystal 1.22.1，`C:\Windows\Fonts\msyh.ttc`。
- 命令清单：`git status/diff --stat/rev-parse`；代码/文档读审（`backend.cr`/`gl_backend.cr`/`gl_renderer.cr`/`text_renderer.cr`/`m3_dirty_window.cr`/`backend_protocol_spec.cr`/`M3-WP1-backend-dirty.md`）；`rg -n page_texture_ids|resolved_texture src examples`；`crystal spec`；`crystal run examples/m3_dirty_window.cr -- --frames=20 --verify`；`crystal spec spec/backend_protocol_spec.cr`×10；`crystal run bin/_v_yflip.cr`（垂直位移 A/B/C）。

## §1 重跑原始结果
- `crystal spec`：**194 examples, 0 failures, 0 errors, 0 pending**（591.5ms）`EXIT=0`。探针含：`zero-alloc probe(text_ft): delta_prime=0 delta_calib=0 delta_work=0 N=1000 windows=[0,0,0] retried=false attempt=1`；`zero-alloc probe(text_renderer): delta_prime=48 delta_calib=0 delta_work=80 N=1000 windows=[64,80,80] retried=false attempt=1`；`zero-alloc probe(virtual_list): delta_prime=0 delta_calib=0 delta_work=16 N=1000 windows=[16,0,0] retried=false attempt=1`。
- `m3_dirty_window --frames=20 --verify`（`EXIT=0`）：`diff_pixels=0 dirty_area_ratio=0.012568 submitted_quads_dirty=4 submitted_quads_full=57 culled_quads=53 frame_full_p50_us=303 frame_full_p95_us=744 frame_full_p99_us=816 frame_dirty_p50_us=236 frame_dirty_p95_us=672 frame_dirty_p99_us=894 dirty_rects=1 frames=20 diff_loc=none verify=pass`
- 垂直位移独立脚本（y+3，A/B/C，`bin/_v_yflip.cr`，`EXIT=0`）：`diff_A_vs_C=835 diff_pixels=0 dirty_area_ratio=0.013277 submitted_quads_dirty=4 submitted_quads_full=57 culled_quads=53 dirty_rects=1 move_y0=240.0 move_y1=243.0`
- `spec/backend_protocol_spec.cr` ×10：RUN1-7,9 `8/0f, windows=[0,0,0] retried=false`；RUN8 `8/0f, windows=[0,0,16] delta_work=16 retried=false`；RUN10 `8/0f, windows=[4464,0,0] delta_work=4464 ... retried=false attempt=1` 后 `windows=[0,0,0] ... retried=true attempt=2`（最终通过）。

## §2 逐条结论（1–9）
| # | 结论 | 证据 |
|---|---|---|
| 1 重跑 | **通过**：全量 194/0；example `diff_pixels=0 dirty=4 full=57 culled=53` EXIT=0。 | §1 原始输出 |
| 2 `diff_pixels=0` 是否空证明 | **空证明风险（P2）**：(a) example 捕获 `pixels_a` 但**未计算/打印 A-vs-C 差异**（`examples/m3_dirty_window.cr:379-394` 仅 `pixel_diff(pixels_b,pixels_c)`），不能由脚本自身证明“MOVE 真的动了”。独立 y-flip 脚本证实同法可得 `diff_A_vs_C=835>0`，说明示例缺失该证据输出。(b) 比较为逐字节 RGBA 精确相等（`pixel_diff` `:247-259`，`a[i]!=b[i]` 四通道，无容差、非仅背景）。 | `examples/m3_dirty_window.cr:379,390,393,457`；`bin/_v_yflip.cr` 输出 |
| 3 y 翻转 | **未发现翻转错误**：垂直移动 y+3 时 `diff_pixels(B vs C)=0` 且 `diff_A_vs_C=835`，`culled=53` 不变。scissor 换算 `sy = (@viewport_h.to_f32 - (sy_top + sh_f)).floor.to_i`（y-down→GL 窗口坐标）与 `glOrtho(0,w,h,0,-1,1)`/`glScissor+glClear` 路径一致。 | `src/tessell/render/gl/gl_backend.cr:158,274-279,293,296`；§1 y-flip |
| 4 脏区覆盖 | **覆盖正确**：`dirty_union = old_rect.union(new_rect)` 且 `Dirty.merge_into(...,8)`（`examples/m3_dirty_window.cr:369-376`）；dirty 路径每 rect `glScissor`+`glClear(COLOR_BUFFER_BIT)` 仅清脏区（`:293,296`），脏区外未 clear/未 draw（A 内容保留，B==C 证实）。 | `examples/m3_dirty_window.cr:369-376`；`gl_backend.cr:167-176,264-297` |
| 5 提交数诚实性 | **成立且为实际提交计数**：`4+53==57`。`@submitted_quads` 在实际发射四边形时 `+=1`（`gl_backend.cr:322`）；全帧路径 `+= b.count//4`（`:258`）；`culled_quads` 单独按“与任一 dirty rect 无交集”统计（`:334-357`），dirty+culled 对全量 57 一致。 | `gl_backend.cr:223-224,258,322,334-357`；§1 |
| 6 纹理归属 | **后端占有/按 page 解析成立**：`Backend` 注释与 `resolved_texture` 抽象（`backend.cr:3-4,30`）；`GLBackend` 私有 `@page_texture_ids_arr` 并在 draw 中 `resolved_texture(b.page)`（`gl_backend.cr:100,205-208,246,302`）；`TextBatch.page` 全链路（`text_renderer.cr:39`，`write_batch(...,page)` `:210-216`）。兼容：`build_text/build_text_cached` 接受并忽略 `page_texture_ids`（`text_renderer.cr:127-156`）；旧 `GlRenderer` 仍暴露 `sync_atlas_textures/page_texture_ids/delete_textures` 并委托后端（`gl_renderer.cr:10,24-27,51-53`），`examples/m2_text_window.cr` 多处残留旧调用（非 M3 提交路径）。 | `rg` 结果；上述 path:line |
| 7 零分配探针 | **10 次全绿但存在抖动**：10/10 最终 `8 examples 0 failures`；RUN8 `[0,0,16]`、RUN10 首窗 `[4464,0,0]` 触发内置重试后过关（`retried=true attempt=2`）。探针预先 `backend.record_calls=false; calls.clear`（`backend_protocol_spec.cr:315-316`），测量区仅 `begin_frame+draw_text`（`:359-364`）且 dirty/顶点/批次复用，规避字符串记录分配；首窗/GC 噪声风险由 3 窗 max+≤1 次重试吸收，但非“绝对无分配”证明。 | `backend_protocol_spec.cr:299-376`；§1 10-run |
| 8 性能口径 | **无结论**：本次 `full_p95=744 dirty_p95=672`、lead `1124/881`、工部 `943/1633`，跨运行交叉/抖动明显，**不能据此声称脏区更快**。`m3_dirty_window.cr`/`docs/evidence/M3-WP1-backend-dirty.md` 未出现“更快/优化/faster/speedup”措辞（`rg` 无匹配），但帧时间数据易被误读——建议文档显式写明“四边形提交数下降，帧时间在本机噪声内无结论”。 | §1；`rg`；`M3-WP1-backend-dirty.md:102` |
| 9 `[未验证]` 诚实性 | **基本满足**：§5 四项均为 `[未验证]` 且各附“验证所需”。另建议补：示例缺 `diff_A_vs_C` 输出作为移动生效证据（对应本表 #2）。 | `docs/evidence/M3-WP1-backend-dirty.md:96-102` |

## §3 缺陷
| 级别 | 位置 | 描述 | 证据 |
|---|---|---|---|
| P2 | `examples/m3_dirty_window.cr:379-394,457` | 像素等价示例缺“元素确实移动”的自证：仅输出 `diff_pixels`(B vs C)，未计算/输出 `diff_A_vs_C`；`pixels_a` 未用于差异度量，`diff_pixels==0` 在移动未生效时可成空证明。 | 读码；独立复现 `diff_A_vs_C=835`（§1） |
| P3 | `docs/evidence/M3-WP1-backend-dirty.md:90-95,102`；`examples/m3_dirty_window.cr:456-472` | 帧时间（p50/p95/p99）跨运行抖动大且方向不稳定，易诱导“脏区更快”误读；文档未显式给出“帧时间在本机噪声内无结论，仅四边形提交数下降可观测”的口径声明。 | §1 三组数据；`rg` 无 speed 词 |
| P3 | `spec/backend_protocol_spec.cr:299-376`（实现侧吸收抖动） | backend 零分配探针 10 次中出现 `[0,0,16]` 与首窗 `[4464,0,0]` 后重试过关，说明存在 GC/计数噪声窗；重试机制掩盖瞬态但不能证明稳态绝对 0。 | §1 RUN8/10 |

## §4 裁定
**PASS-WITH-DEFECTS**（P1 无，P2×1，P3×2）。

**M3-WP1 验收判据（脏矩形部分提交可观测生效）是否达成**：在已验证前提下**达成**——提交数下降可观测（4 < 57，culled 53）、脏区/裁剪/scissor 路径与纹理后端归属实现一致，且水平与垂直位移下 `diff_pixels(B vs C)=0`；但示例自身缺 `diff_A_vs_C` 自证属证据链缺口（P2），帧时间不得解读为性能收益。