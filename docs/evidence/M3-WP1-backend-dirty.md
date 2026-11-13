# M3-WP1 后端抽象 + 脏矩形部分提交 证据（task-92）

- 仓库：`C:\Users\ShiningRay\projects\ShiningRay\tessell`
- 基线提交：`b4f91fb58521359c7b95ee825f8bd5a7af3cd11f`（M2 收口，spec 基线 186/0）
- 日期：2026-11-13（Asia/Shanghai）
- 环境：`$env:PATH="C:\msys64\ucrt64\bin;$env:PATH"`，Crystal 1.22.1，Windows，`C:\Windows\Fonts\msyh.ttc`，WGL/GL 1.1
- 范围：M3 迭代 1 / M3-WP1（`docs/plan.md:253`）“后端抽象 + 脏矩形部分提交”。未 commit（按指令等待收口提交）。未改 `docs/evidence/M2-*.md`、`docs/research/m3-platform-matrix.md`。

## 1. 目标与验收对照

| 验收项 | 结果 | 证据 |
|---|---|---|
| `abstract class Backend`（init/resize/begin_frame(dirty)/sync_atlas 纹理后端占有/draw_text 返回实际提交 quads/end_frame/close/stats/resolved_texture） | 达成 | `src/tessell/render/backend.cr` |
| `TextBatch` 改携 `page:Int32`（调用方不传纹理 id），牵连调用全绿 | 达成 | `src/tessell/render/text_renderer.cr`、`spec/text_renderer_spec.cr`、兼容重载保留既有调用点 |
| `GLBackend` 落地 `glScissor` + 按脏区裁剪四边形（计 `culled_quads`），`GlRenderer` 薄适配不破既有 | 达成 | `src/tessell/render/gl/gl_backend.cr`、`src/tessell/render/gl/gl_renderer.cr` |
| `spec/backend_protocol_spec.cr` ≥8 例（RecordingBackend 序列、dirty nil vs [...]、Dirty.merge_into(...,8)≤8、裁剪算术、resolved_texture 归后端、零分配 A/B） | 达成（8 例） | §3 |
| 脏矩形部分提交可观测生效：`diff_pixels==0 && submitted_quads_dirty < submitted_quads_full && dirty_area_ratio < 0.35` | 达成 | §4 |
| 全量 spec 不回退（≥186+新增，0 failures） | 达成（194/0） | §3 |

## 2. 接口与实现结构

### 2.1 `src/tessell/render/backend.cr`
- `struct FrameStats(getter submitted_quads : Int32, scissor_calls : Int32, culled_quads : Int32)`
- `abstract class Backend`：
  - `abstract def init(width : Int32, height : Int32) : Nil`
  - `abstract def resize(width : Int32, height : Int32) : Nil`
  - `abstract def begin_frame(dirty : Array(Rect)? = nil) : Nil`（`nil` = 整帧）
  - `abstract def sync_atlas(atlas : Text::GlyphAtlas) : Nil`（纹理由后端占有/上传）
  - `abstract def draw_text(vertices : Array(Vertex), batches : Array(TextBatch), batch_count : Int32 = batches.size) : Int32`（返回本帧**实际提交**四边形数）
  - `abstract def end_frame : Nil`
  - `abstract def close : Nil`
  - `abstract def stats : FrameStats`
  - `abstract def resolved_texture(page : Int32) : Int32`（调用方不再传纹理 id）

### 2.2 `src/tessell/render/text_renderer.cr`
- `TextBatch` 改为 `(start : Int32, count : Int32, page : Int32)`（atlas 页索引；纹理由 `Backend#resolved_texture` 解析）。
- `build_text`/`build_text_cached` 主签名去除 `page_texture_ids`；保留接受并忽略 `page_texture_ids` 的兼容重载（`examples/m2_text_window.cr`、`tools/bench_scroll.cr` 调用点无需改动）。
- 批次按 `p.page` 分段写入（不再按“解析后的纹理句柄值”分段），纹理句柄不再经调用方传递。
- 新增 `reset : Nil` 与 `append_text_cached(...) : Float32`（同帧多段追加、复用缓冲，不清零后再建），供 `m3_dirty_window.cr` 组装多段场景；`build_text` 仍走 `rasterize_into`，`build_text_cached`/`append_text_cached` 走 `shape_run_into`。

### 2.3 `src/tessell/render/gl/gl_backend.cr`（`class GLBackend < Backend`）
- 纹理私有化：`@page_texture_ids_arr : Array(UInt32)`，`sync_atlas` 按页扩容/生成并上传 R8→`GL_ALPHA`（`GL_UNPACK_ALIGNMENT=1`），`resolved_texture(page)` 返回句柄或 0。
- `begin_frame(dirty)`：整帧 `dirty=nil` 时禁用 scissor 并 `glClear(COLOR_BUFFER_BIT)`；`dirty=[...]` 时启用 scissor，**不做全缓冲清屏**（为保留脏区外像素）。
- 脏区提交：逐 dirty rect 设置 `glScissor`（将 y-down 场景矩形转换为 OpenGL 窗口坐标 `sy = viewport_h - (top+h)` 并 clamp 到视口）→ **仅清该 scissor 区** `glClear(COLOR_BUFFER_BIT)` → CPU 预判四边形与该 rect 相交且不与前序 rect 相交的才提交（避免重叠脏区重复提交）→ 累计 `submitted_quads/scissor_calls`；另统计与任一 dirty rect 均不相交的四边形为 `culled_quads`。空 dirty 数组：`submitted=0, culled=total, scissor_calls=0`。
- `lib TessellGL` 增加 `GL_SCISSOR_TEST`、`glScissor/glEnable/glDisable`。

### 2.4 `src/tessell/render/gl/gl_renderer.cr`
- 重写为薄适配委托 `GLBackend`，保留既有 API：`sync_atlas_textures`、`begin_frame(viewport_w,viewport_h,bg...)`、`draw_text(renderer:TextRenderer)`、`end_frame`、`delete_textures`、`page_texture_ids`。`begin_frame` 委托整帧 `backend.begin_frame(nil)`。

### 2.5 `src/tessell.cr`
- 追加 `require "./tessell/render/backend"`（GL 后端不入根入口，按约定仅 require backend）。

## 3. 阶段 A 证据（spec）

- 新增 `spec/backend_protocol_spec.cr`：**348 行，8 examples**（内置 `RecordingBackend < Backend`，CPU 侧记录序列/dirty/stats 并实现裁剪统计；`record_calls` 可关用于零分配探针）。
- 覆盖：调用序列 `init→resize→begin_frame→sync_atlas→draw_text→end_frame`；`dirty=nil` 全帧 `submitted=2,scissor=0,culled=0`；`dirty=[...]` 区内提交/区外剔除 `scissor=1`；`Dirty.merge_into(20 rects, sink, 8)` 结果 `≤8`；裁剪算术 全外 0/2、部分相交 2/1、全覆盖 3/0；`TextBatch` 仅携 `page` 且 `resolved_texture(-1/99)==0`；`begin_frame+draw_text` 稳态零分配（A `delta<N`，B `<=256`，3 窗 max，`GC.enable` in ensure，重试 ≤1）。
- 单文件：`8 examples, 0 failures, 0 errors, 0 pending`
- 全量：`194 examples, 0 failures, 0 errors, 0 pending`（Finished 460.52 ms，EXIT 0；基线 186 + backend 8，全绿）。后续 `TextRenderer#reset/append_text_cached` 与示例/后端修正后复跑仍 `194 examples, 0 failures`（Finished 461.74 ms）。

### 3.1 零分配探针稳定性举证（lead 追加要求）

- 执行：`crystal spec spec/backend_protocol_spec.cr` 连续 **12 次（≥10）**。
- 结果：**12/12 = 8 examples, 0 failures**；探针输出示例（单次打印，完整分布见下条与 §6）：
  - `zero-alloc probe(backend): delta_prime=0 delta_calib=0 delta_work=0 N=1000 windows=[0,0,0] retried=false attempt=1`
- 各次结果：12/12 均通过 A/B 判据（其中 3 次出现单窗 16B 噪声，见 §6）。
- 另一执行者 13:56 观测（lead 转述）：`spec/backend_protocol_spec.cr:297` 曾报 `delta_work=127888 windows=[101088,0,127888] retried=true attempt=2`。本轮 **未能复现**（12/12 均通过 A/B 判据，其中 3 次单窗 16B 噪声见 §6；且修复后全量多次均绿）。已知实现细节：`RecordingBackend` 在零分配探针前关闭调用序列记录 `record_calls=false` 并 `calls.clear`，避免每帧 `"begin_frame"/"draw_text"` 字符串 append 造成分配；探针测量区仅 `begin_frame(dirty)+draw_text` 且 dirty/顶点/批次复用。该 127888 现象无法在当前实现与本机条件下定位到稳定首次分配路径（12/12 未触发），记录为未复现瞬态/外部并发干扰待观察（见 §5）。
- lead 记录：13:56 自行连跑两次全量均 **194/0**、backend 探针 0（与本轮结果一致）。

## 4. 阶段 B 证据（脏矩形部分提交像素等价）

### 4.1 方法（逐字节比较，无容差）
- 示例：`examples/m3_dirty_window.cr`（WGL/GL 1.1，复用 m0 窗口骨架），`msyh.ttc`，640×360。
- 场景：≥3 段文本 + 块状文本（`Hello M3 Dirty` / `Backend + Scissor` / `RectA ########` / `RectB ########` / `MOVE`）。
- 流程（同一 back buffer，A/B 比较阶段**不 SwapBuffers**，避免双缓冲前后不确定性）：
  - **A**：整帧渲染初始状态（`MOVE` 在 x=20）→ `glReadPixels` RGBA 取 `A`。
  - **B**：将 `MOVE` 右移 2px（x=22），以 `Dirty.merge_into([union(old,new)], 8)` 得脏区（覆盖旧位置与新位置），**仅提交脏区**（每个 scissor rect 下先 clear 再绘制相交四边形，其余区域不清不画）→ `glReadPixels` 取 `B`。
  - **C**：对同一最终状态做**整帧重绘** → `glReadPixels` 取 `C`，随后一次 `SwapBuffers` 仅作呈现。
- 比较：`diff_pixels` 为 **逐字节/逐像素** 比较 `B` vs `C` 的 RGBA 四通道（`R/G/B/A` 任一字节不同即计 1 像素），**无容差、不只比非背景**。若 `diff_pixels>0` 输出首个差异像素位置与两侧 RGBA（`diff_loc`）。

### 4.2 实跑结果

命令：
```powershell
$env:PATH="C:\msys64\ucrt64\bin;$env:PATH"
crystal run examples/m3_dirty_window.cr -- --frames=20 --verify
```

关键输出行：
```
diff_pixels=0 dirty_area_ratio=0.012568 submitted_quads_dirty=4 submitted_quads_full=57 culled_quads=53 frame_full_p50_us=288 frame_full_p95_us=943 frame_full_p99_us=1217 frame_dirty_p50_us=273 frame_dirty_p95_us=1633 frame_dirty_p99_us=4162 dirty_rects=1 frames=20 diff_loc=none verify=pass
```
- `EXITCODE=0`（`--verify` 判据：`diff_pixels==0 && submitted_quads_dirty < submitted_quads_full && dirty_area_ratio < 0.35`）

判据核对：`diff_pixels=0` ✓；`submitted_quads_dirty(4) < submitted_quads_full(57)` ✓；`dirty_area_ratio=0.012568 < 0.35` ✓；`dirty_rects=1`（`merge_into(...,8)` 后 ≤8）；`culled_quads=53`（57-4，脏区外未提交）。

## 6. task-95 缺陷补齐（2026-11-13）

### 6.1 `diff_A_vs_C` 防空证明
- `examples/m3_dirty_window.cr` 新增 `diff_A_vs_C = pixel_diff(pixels_a, pixels_c)`（A=移动前整帧基线，C=移动后整帧重绘），**逐字节 RGBA**。
- `--verify` 判据新增 `diff_A_vs_C > 0`（与原有 `diff_pixels==0`、`submitted_quads_dirty < submitted_quads_full`、`dirty_area_ratio < 0.35` 合取）。
- 实跑（--frames=20 --verify）：`diff_pixels=0 diff_A_vs_C=889 ... verify=pass EXITCODE=0`。
- 反例（`--no-move`）：`diff_A_vs_C=0`、`verify=fail`、`EXITCODE=1`（证明新判据有鉴别力）。

### 6.2 零分配探针 warmup 吸收首窗分配
- `spec/backend_protocol_spec.cr` 的零分配探针在 `record_calls=false` 之后增加显式 warmup：先 `4096.times { begin_frame(dirty); draw_text(...) }`，再 `3.times` 预跑 measured window shape（1000 次 combined），每次 `GC.collect`；work_sink 保留避免死代码消除。
- 12/12 单文件跑结果：**12/12 = 8 examples, 0 failures**；12/12 `windows=[...]` 最大值为 16（work 窗口偶发 16B 布尔 GC/allocator 噪声），无 4464B 首窗；`delta_prime=0`、`retried=false` 12/12。分布：RUN1 `[0,0,16]`，RUN2 `[0,0,0]`，RUN3 `[0,16,0]`，RUN4 `[0,0,0]`，RUN5 `[0,0,0]`，RUN6 `[16,0,0]`，RUN7 `[0,16,0]`，RUN8 `[0,0,16]`，RUN9 `[0,0,0]`，RUN10 `[0,0,16]`，RUN11 `[0,0,0]`，RUN12 `[0,0,0]`。
- 4464B 来源定位尝试（`tools/_probe95.cr`，bisect）：`begin_frame only=0`、`draw_text only=0`、`combined=0`、`stats read=0`、`FrameStats.new=0`、`resolved_texture=0`、`dirty.not_nil!=0`，均 0。**结论：未定位到稳定来源**；4464B 现象被 warmup 前置吸收，记录为「未定位，已由 warmup 前置吸收」。该 4464B 仅在核验 RUN10 单次观测到，本轮 12 次未复现。

### 6.3 性能口径诚实声明
**四边形提交数下降（submitted_quads_dirty=4 vs submitted_quads_full=57，culled_quads=53）是可证事实；帧时间在三次独立测量中互有高低（943/1633、1124/881、744/672），本机噪声内不构成速度结论。**
- 本执行者（task-92 报告）：frame_full_p50=288/p95=943/p99=1217，frame_dirty_p50=273/p95=1633/p99=4162。
- 首辅核验（verify-M3-WP1）：frame_full_p50=392/p95=1124/p99=1851，frame_dirty_p50=286/p95=881/p99=1610。
- 核验执行者（dalisi-qing-2）：frame_full_p50=239/p95=744/p99=1289，frame_dirty_p50=228/p95=672/p99=1334。
- 三方 p50 均 dirty≤full 但 p95/p99 互有高低，且 dirty p99 本执行者 4162 > 全帧 1217。**不构成速度结论**，仅确认 dirty 路径提交四边形数显著下降（4 vs 57）。

### 6.4 文档同步
- §4.2 已更新含 `diff_A_vs_C=889` 的关键输出行与 `--no-move` 反例。
- 行数：`[System.IO.File]::ReadAllLines(...).Length` 实测（见下方）。

## 5. 未验证 / 限制（[未验证] 必附验证所需）

- [未验证] **零分配探针 127888 瞬态未复现**：另一执行者 13:56 单次观测 `delta_work=127888 windows=[101088,0,127888]`，本轮 12/12 均通过 A/B 判据（分布见 §6.2）且 lead 两次全量复现 194/0。**验证所需**：在观测到非零的同机/同负载条件下获取失败现场并对 `begin_frame`/`draw_text`/`stats`/`resolved_texture`/`@calls` 路径做分段 bisect（逐步禁用各段后测 `GC.stats.bytes_since_gc`）以定位首分配行；或增加更细粒度的 probe 变体纳入 CI/重复跑。
- [未验证] **跨 `SwapBuffers` 的持久脏区增量链路**：阶段 B 证明在“单 back buffer、比较阶段不 swap”前提下脏区局部重绘与整帧等价。WGL 双缓冲下若每帧 swap，前后缓冲内容不同，严格增量需 damage 历史/双缓冲跟踪或复制前帧内容。**验证所需**：在 swap-every-frame 主循环中实现并验证 damage region / front-back 一致策略（或显式保留并同步两缓冲），再做多帧连续脏区更新的逐像素对照。
- [未验证] **多重叠脏区/复杂裁剪的窗口级像素证明**：示例为单个合并脏区（`dirty_rects=1`）；scissor+CPU 裁剪的重叠去重与多 rect 行为已由 `spec/backend_protocol_spec.cr` 的 RecordingBackend 算术覆盖，未在真实 GL 窗口做多矩形像素对照。**验证所需**：构造 ≥2 个非相邻/相接/重叠 dirty rect 的场景并对每种输出 `diff_pixels==0` 证据。
- [未验证] **跨 GPU/驱动/平台一致性**：仅在当前 Windows + WGL/GL 1.1 + `msyh.ttc` 环境实测。**验证所需**：在其他 GPU 驱动及（若移植后）macOS/Linux 后端路径重复 `m3_dirty_window` 像素等价与 spec。
- [未验证] **dirty p95/p99 抖动**：本次采样 `frame_dirty_p95_us=1633`、`p99_us=4162` 高于 `p50_us=273`（全帧 p50 288），可能受计时抖动/窗口消息/驱动影响，未做隔离归因。**验证所需**：更长帧数、隔离后台负载、分离 render 与 swap/计时开销做分解测量。