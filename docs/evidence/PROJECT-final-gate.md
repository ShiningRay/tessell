# 项目终审门禁报告（M0–M4，Windows 本机 S1）

行数：126（实测）
HEAD：abf1eb3（首版）；cffe071（feat）+ 0f86db3（docs）（r2）。
范围：`docs/plan.md` M0–M4 计划内、Windows 本机；不扩到 macOS/Linux/跨机。
方法：独立重跑 + 文档对账；未改 src/spec/examples/tools，未 commit。

## 0. 总体裁定

**Go-with-conditions（S1，Windows 本机）**。不是 M0–M4 全量完成/跨平台完成。
- 14/14 gate PASS（abf1eb3 时点）；spec 233→246（r2）；build 0；3 个 example verify 通过。
- P1/P2：无；P3：3 条（见 §6）。
- 未关闭项见 §5；Emoji 彩色已按 §8 关闭（带限定）。

## 1. 独立重跑

首版（abf1eb3）独立重跑；r2 新增 spec/Emoji 复核见 §8。

| 项 | EXIT | 关键结果 |
|---|---:|---|
| crystal spec | 0 | 233 examples, 0 failures, 0 errors, 0 pending |
| crystal build src/tessell.cr | 0 | 2,278,930B；产物已删 |
| app_demo --frames=120 --verify | 0 | a11y_nodes=34；alloc [0,0,0]；attempt=1；pass |
| m3_scroll_window --dy=20 --verify | 0 | alloc [0,0,0]；diff=0；pass |
| m3_dpi_theme --dpi=1.5 --verify | 0 | J1 1605/3079/5094；J5 diff=0；pass |
| tools/gate.ps1 | 0 | GATE_RESULT=PASS；14/14 |

## 2. gate.ps1 SUMMARY（14 项，abf1eb3 时点）

```text
PASS | spec | 233 examples, 0 failures
PASS | build_src | ok
PASS | ex_m2_text_verify | pixel_match=true frames=120
PASS | ex_m2_text_emoji_verify | emoji_pixel_match=true
PASS | ex_m3_dirty_verify | diff=0 dirty 4<57 ratio=.012568
PASS | ex_m3_dpi_light | verify=pass alloc=[48,80,48]
PASS | ex_m3_dpi_dark | verify=pass alloc=[32,64,64]
PASS | ex_m3_scroll_dy20 | alloc=[0,0,0] diff=0 pass
PASS | ex_m3_scroll_dy600 | alloc=[64,64,80] diff=0 pass
PASS | zero_alloc_frame | criterion_ok=2 false=0
PASS | bench_scroll | alloc=96 p50=89 p95=146 p99=188
PASS | atlas_raster_verify | ATLAS_RASTER_VERIFY_EXIT=0
PASS | package_bare_path | PACKAGE_OK bare_exit=0 verify=pass
PASS | file_hygiene | status_ok=true unexpected=[]
GATE_RESULT=PASS
```

## 3. M0–M4 完成度对账

| 里程碑 | 要求/交付 | 证据 | 判定 |
|---|---|---|---|
| M0 | 7 WP：上下文/窗口/文本/IME/度量 | `M0-gate.md` | 达成（带条件）：C2 IME→C7；C5 字体/GSUB 部分 |
| M1 | 5 WP：布局/DrawList/稳态零分配 | `M1-iteration-log.md` | 达成（带遗留）：真实 GPU/IME 未接 |
| M2 | 6 WP：文本/IME/滚动/a11y | `M2-gate-r3.md`、`M2-summary.md` | 部分：Emoji 灰度+彩色过（限定）；IME/UIA 未全 |
| M3 | 5 WP：后端/多平台/DPI | `M3-gate-r4.md` | 部分（S1）：WP2 No-Go、WP3/WP4 未做 |
| M4 | 4 WP：DSL/打包/示例/门禁 | `verify-M4-WP1-S3.md`、`M4-WP2-packaging.md`、`M4-WP4-gate.md` | 达成（本机）：安装器/签名/C9 未 |

- M4-WP1：DSL/状态 API 已落地；D1–D6 见 §4。
- M4-WP2：`tools/package.ps1` + `MANIFEST.txt` + 16 DLL；裸 PATH `PACKAGE_OK`。
- M4-WP3：`examples/app_demo.cr`、`docs/usage.md`、`README.md`；`verify-M4-WP3-WP4` PASS-WITH-DEFECTS（P3）。
- M4-WP4：`tools/gate.ps1` 14/14；`M4-WP4-gate.md` 记录 fail_probe 反证（本轮未重跑）。

## 4. M4-WP1 D1–D6 判据

| 判据 | 证据 | 判定 |
|---|---|---|
| D1 幂等脏集 | `spec/ui_builder_spec.cr:49-72`；S1-r2 `IDEMPOTENT count=0 empty=true` | 达成 |
| D2 脏集最小 | `verify-M4-WP1-S1.md:29-31`：layout 3 节点、paint-only 1 节点 | 达成 |
| D3 不增节点 | `spec/ui_builder_spec.cr:108-133`；S1 `same_object=true` | 达成 |
| D4 零分配帧 | S3 `zero_alloc` static 16B/paint1 0；app_demo `[0,0,0]` attempt=1 | 达成（A/B，非严格 0） |
| D5 a11y 同步 | S3 探针 A–E；app_demo `a11y_nodes=34` | 达成 |
| D6 事件单入口 | S3 grep 19 命中，仅 `input/router.cr`/`focus.cr` 写入 | 达成 |

- D4 口径：A `delta<1000`、B `<=256`；`[0,0,0]` 不是普适保证。
- 交叉观测：`verify-M4-WP3-WP4.md:26` 的 app_demo dpi1.5 曾 `attempt=2` 才过。

## 5. 未关闭项（条件台账）

| 项 | 证据 | 阻断/责任 |
|---|---|---|
| C7 真实键盘 IME 手测 | `M4-iteration-log.md:92` | 阻断 IME 验收；人工 |
| C9 字体许可法务复核 | `M4-WP2-licensing.md:42-51` | 阻断分发；法务 |
| M3-WP2 macOS | `M3-gate-r4.md:70` | 阻断跨平台；外部环境 |
| M3-WP3 Linux | `M3-gate-r4.md:69-73` | 阻断全量；工程 |
| M3-WP4 stencil/cover | `docs/plan.md:256` | 可选未做；工程 |
| UIA provider | `M3-iteration-log.md:233` | 范围缩减非完成；工程 |
| 安装器/代码签名/干净 VM | `M4-WP2-packaging.md:165-172` | 阻断分发；工程 |
| 跨机/CI/覆盖率/GPU 计时 | `M4-WP4-gate.md:83-89` | 阻断泛化；外部 |
| C6 waiver 仅 M3-WP5 | `M3-gate-r4.md:60` | 不覆盖全域；记录 |
| 真实窗口人工目视 | `M2-WP2-emoji-color.md:53` | 不阻断数值验收；人工 |

## 6. 口径审计与 P3

- A/B 判据非严格零；`M3-C8-gl-scroll.md:340` 已明确 `[0,0,0]` 非普适。
- dy600 多观测：`[96,80,0]`(:331)、`[80,80,80]`(:332)、`[96,48,64]`(:333)、
  `[0,0,0]`(:337)、本轮 `[64,64,80]`；均在 A/B 内，单次全零不得外推。
- P3-1：`M4-WP4-gate.md:13,43` 仍写 221 examples；当前 r2 为 246（陈旧）。
- P3-2：`M3-gate-r4.md:44` 的 dy600 P2 已被 `M3-C8` 多观测段修正；
  保留为历史记录，不再据此判当前缺陷。
- P3-3：`M4-WP4-gate.md:83-89` 的 CI/跨机/GPU/覆盖率仍未验证。

## 7. 限制

- 仅本机 Windows/WGL/GL1.1 单驱动；不得泛化到其他 GPU/平台。
- M0/M1/M2 历史证据未逐条重跑；本报告只对当前 HEAD 的 6 项命令负责。
- `M4-WP4-gate.md` 的 fail_probe 反证本轮未重跑，引用其记录。

## r2 复核（彩色 Emoji 关闭）

- 关闭项：M2「Emoji 彩色」由未完成 → **已完成（带限定）**。限定：**Windows +
  `C:/Windows/Fonts/seguiemj.ttf` 单一样例 + COLRv0/CPAL + glReadPixels 数值回读**；
  R8 灰度路径保留，旧 `--emoji` 1171 像素无回退。
- 禁写：「Emoji 全域支持」「跨平台彩色」「严格零分配」。
- 证据链：`verify-M2-WP2-emoji-color.md`（80 行，PASS-WITH-DEFECTS，P1 无）+
  `M2-WP2-emoji-color.md`（61 行，P2-1 零分配窗口待修）+ 反证：
  灰度 `colored=0`，彩色 `colored=1256/1257`，`dominant=255,176,46`，batches=1。
- 数字刷新：全量 spec 233 → **246**（+13：`color_glyph_spec` 6 +
  `text_emoji_color_spec` 7）；`--emoji-color` 1347/1257；旧 `--emoji` 1171；
  三项 M3 回归 pass；`zero_alloc_frame` static 16B/paint1 0。
- 未关闭项（10）：C7 真实键盘 IME 人工手测；C9 字体许可法务确认；
  M3-WP2 macOS；M3-WP3 Linux；M3-WP4 stencil；UIA provider；
  安装器/代码签名/干净 VM；跨机基线；C6 waiver 仅 M3-WP5；
  真实窗口人工目视（`M2-WP2-emoji-color.md:53`）。
- 本轮改动（13 文件 + 核验报告）**尚未提交**；终审结论以回填提交 hash 为准
  （cffe071 feat + 0f86db3 docs）。P2-1 修文档后再宣称“已完成”；当前可称“已完成（带限定）”。
- 裁决：可宣布 M2-WP2 关闭（带限定）；不得写成全量/跨平台完成。

## r3 复核（M3-WP4 关闭）

- 裁定：M3-WP4 路径 stencil/cover **关闭（带限定）**：even-odd only、单几何
  样例像素对拍；不得外推跨平台/任意几何。
- 证据链：工部报告 `M3-WP4-stencil-cover.md`（71 行）+ 核验
  `verify-M3-WP4.md`（78 行，PASS-WITH-DEFECTS，P3×3）+ stencil 反证
  7794→0（去 INVERT）与负例 8450（fan 填星心）。
- 数字：全量 spec 246 → **263**（+17：polygon 9 + path_gl 6 +
  backend_protocol +2）；正例 `diff_pixels=0 fill_pixels_gl==cpu==7794`。
- 未关闭清单 10 → **9**：删除「M3-WP4 stencil/cover」；其余 9 项原样保留
  （C7 人工 IME、C9 法务、macOS、Linux、UIA、安装器/签名/干净 VM、跨机基线、
  C6 waiver 仅覆盖 M3-WP5、真实窗口人工目视）。
- 提交：feat `98360f2`（M3-WP4 代码/规格/工具/example）；docs `26dddf5`（证据/核验/迭代日志/README/final-gate）。

## r4 复核（截图证据）

- 截图证据：`M2-WP5-visual-check.md`（75 行）+ `docs/evidence/shots/` 6 PNG（合计 107,195 B）；像素统计复核见该报告 `## lead 复核（像素统计）`；**无人眼 QA 签字，也不存在人眼观察记录**。
- 未关闭项仍 **9** 条，其中「真实窗口人工目视」改写为「人工 QA 签字未做（已有 6 张截图 + 像素统计复核，见 `docs/evidence/M2-WP5-visual-check.md`）」；其余 8 项原样。
- spec 数不变：**263**（截图开关/转换不增删用例）；本轮提交 hash：feat `c57ebdc`、docs `6f1e5ff`。

## r5 复核（0.2.0 分发包独立复验）

- 包：`dist/tessell-0.2.0-win64.zip`，7,757,194 B，25 entries，SHA256 `625c2fc838a5698f4b639d016cfc07a3bfada8f4adcbad76ae21052a4d6bbc06`；提交 `c356253`。3 exe：`app_demo.exe` 4,018,412 B、`m3_dpi_theme.exe` 3,776,423 B、`m3_path_window.exe` 2,615,520 B。
- lead 独立复验（洁净解压 + 裸 PATH `C:\Windows\System32;C:\Windows`，`--frames=20 --verify`）：
  - `app_demo` EXIT=0：`frames=20 rows=10000 visible_avg=30.0000 quads_dirty=159 quads_full=171 culled=12 diff_pixels=0 diff_A_vs_C=3113 diff_theme=0 diff_theme_roundtrip=0 alloc_windows=[0,0,0] retried=false attempt=1 a11y_nodes=34 verify=pass`
  - `m3_dpi_theme` EXIT=0：`verify=pass`
  - `m3_path_window` EXIT=0：`mode=stencil_cover stencil_bits=8 fill_pixels_gl=7794 fill_pixels_cpu=7794 diff_pixels=0 alloc_windows=[64,80,80] retried=false attempt=1 negative_holds=true verify=pass`
- 口径声明：包内 3 个 exe 均在本机洁净解压 + 裸 PATH 下自证 `verify=pass`；未在其它机器/其它驱动/Windows 10 上验证。
- 规模（现算，HEAD `c356253`）：提交 **60**；`git ls-files src` **31 文件 / 5,792 行**；spec **32 文件**；example **15**；`docs/evidence/*.md` **73**；`docs/evidence/shots` **6**。
- 未关闭清单保持 **9 条**：C7 真实键盘 IME 人工手测；C9 字体许可法务复核（D-C9 已决策）；M3-WP2 macOS No-Go；M3-WP3 Linux 无显示/未运行；UIA provider 延后；安装器/签名/干净 VM（便携 zip 已提供 3 个示例 + 依赖闭包，裸 PATH 可跑；仍无安装器与代码签名）；跨机基线；C6 waiver 仅 M3-WP5；人工 QA 签字未做。
- 裁决：维持 **Go-with-conditions（S1，仅 Windows 本机 msys2/Intel 驱动）**；本轮无新增缺陷、无判据改动。

## r6 复核（C8 以 plan 变更关闭）

- 变更记录：`docs/plan.md:298` CR-1（2026-11-14）将 M2-WP5 的 a11y 交付范围限定为「A11yNode 树 + 与 FocusManager 同步 + 虚拟列表不物化」；Windows UIA COM provider 层不在 M0–M4 范围，**UIA provider 未实现；不是「实现但未验证」**，门禁条件 C8 由此条变更关闭。
- 依据：`docs/plan.md` `## 变更记录`（CR-1；`:296-302`）；`docs/evidence/M2-gate.md`（C8 原文）；`docs/evidence/verify-M4-WP1-S3.md`；`src/tessell/a11y/tree.cr`、`src/tessell/ui/apply.cr:369-380`。
- 未关闭清单 9 → **8 条**：C7 真实键盘 IME 人工手测；C9 字体许可法务复核；M3-WP2 macOS No-Go；M3-WP3 Linux 无显示/未运行；安装器/签名/干净 VM；跨机基线；C6 waiver 仅 M3-WP5；人工 QA 签字未做。
- 裁决：维持 **Go-with-conditions（S1，仅 Windows 本机 msys2/Intel 驱动）**。本轮为范围/文档变更，未改代码与判据，spec 263/0 与 gate 15/15 不受影响。
