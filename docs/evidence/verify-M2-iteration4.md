# verify-M2-iteration4（M2 迭代 4 证据集核验）

- 任务：task-66（lead m00657 指派）
- 核验人：dalisi-qing-2（只读核验 + 重跑 + 本报告；禁改源码、禁 commit）
- 仓库：`C:\Users\ShiningRay\projects\ShiningRay\tessell`
- 时间：2026-11-13 09:56:10 +08:00（Asia/Shanghai，会话内执行）
- 环境：Windows, Crystal 1.22.1；`$env:PATH="C:\msys64\ucrt64\bin;$env:PATH"`
- 元信息：最终行数 53（read/UTF-8 行数口径）
- 范围：证据诚实性 + 文档一致性（IME 探针标签、Arabic 定性复算、零分配判据文档；加分 gl-text-renderer 3 点对照）

## 1. IME 探针诚实性（`examples/m2_ime_probe.cr` / `bin/m2_ime_probe.exe`）

- 复跑：`bin/m2_ime_probe.exe` 已存在（2466089B，2026/11/13 9:49:31），直接执行 `.\bin\m2_ime_probe.exe --frames=60`（未重 build；源码 `examples/m2_ime_probe.cr` 20169B 2026/11/13 9:49:27 早于 exe）；`RUN_EXIT=0`，输出含 `IME_PROBE_EXIT=0`。
- 实测关键标签：`ime_injection=blocked ime_injection_reason=imm_set_composition_rejected ime_present=false imm_available=true imm_is_ime=true imm_open_status=1 imm_set_open_ret=1 imm_set_str_ret=0 imm_set_str_preedit_ret=0 imm_set_str_result_ret=0 preedit_roundtrip=false preedit_text= preedit_expected_len=5 preedit_got_len=-1 result_roundtrip=false result_text= result_expected_len=2 result_got_len=-1 candidate_list_bytes=144 candidate_list_count_raw=0 candidate_list_entries=0 cand_pos=not_triggered ime_messages_setcontext=1 ime_messages_start=0 ime_messages_composition=0 ime_messages_end=0 ime_messages_notify=3 kl_count=2 kl_ids=0x8040804,0x4090409 IMM_ERR=ImmSetCompositionStringW_rejected_preedit_ret=0_result_ret=0_win32_error=0 frames=60`

### 1.1 逐标签核对
- **`preedit_expected_len=5` vs `preedit_got_len=-1`（期望/实测分离）**：诚实分离。源码 `preedit_expected_len = "nihao".size`（`examples/m2_ime_probe.cr:412`）、`preedit_got_len` 初始 `-1`（:146），仅在 `WM_IME_COMPOSITION` 且 `preedit_posted && !preedit_seen && (lp & GCS_COMPSTR)!=0` 时由 `read_comp_string` 回写（:254-259）；而 `preedit_posted` 仅在 `imm_set_str_preedit_ret != 0` 时置真并 post 消息（:468-471）。本次两次注入 ret 均 0，故未触发回写，`-1` 表示“未实测到/未取得”，与 expected 独立。
- **`candidate_list_bytes=144` vs `candidate_list_entries=0`（API 语义）**：语义区分清楚，未混淆。源码调用 `candidate_list_bytes = IMM.ImmGetCandidateListCountW(himc, pointerof(candidate_list_count_raw))`（:449，API 返回所需字节数并写出候选列表数 `count_raw`）；仅当 `bytes>0` 时分配并读首列表取 `cl.dwCount` 作为 entries，否则 entries=0（:450-462）。实测 `bytes=144, count_raw=0, entries=0` 与“无候选列表但 API 报告结构/缓冲大小 144B”一致，不构成伪造或语义倒置。
- **`ime_injection=blocked reason=imm_set_composition_rejected` 是否有 `ret=0` 原始支撑**：有。`imm_set_str_preedit_ret=0 imm_set_str_result_ret=0 imm_set_str_ret=0` 且 `IMM_ERR=ImmSetCompositionStringW_rejected_preedit_ret=0_result_ret=0_win32_error=0`（:544）；判定逻辑 `programmatic_available = imm_available && (imm_set_str_preedit_ret != 0 || imm_set_str_result_ret != 0)`、否则在 `imm_available` 且 `imm_is_ime_flag` 分支置 `blocked/imm_set_composition_rejected` 并记录两 ret（:503,520-527）。
- **`imm_is_ime=true` 与 `ime_present=false` 并存**：**字面并存但谓词不同，非原始值矛盾；标签语义存在误导风险（判 P2，见缺陷清单）**。`imm_is_ime` 来自 `IMM.ImmIsIME(hkl_for_desc)` HKL 属性（:417,544）；`imm_available` 表示 `ImmGetContext(hwnd)` 非空（:399-401,544）；`ime_present` 由源码定义为“本次编程注入是否可用/成功”=`programmatic_available`（:503-504,544），而非“系统是否存在/安装 IME”。同时 `ime_desc/ime_file` 为空（`ImmGetDescriptionW` 长度 0，:422-430）但 HKL 报 IME，说明“HKL 具 IME 属性”与“描述可取/可编程注入”可分离；将该注入可用性命名为 `ime_present` 易被误读为“无 IME”，与 `imm_is_ime=true` 形成表观矛盾。**结论：原始支撑链（ret/err/hkl/imm_available/imm_is_ime）诚实可核，未伪造；`ime_present` 命名易误导解释（P2）。**

## 2. Arabic 定性复算（`"لا"` U+0644 U+0627）

- 独立复算脚本（临时 `bin/_v66_ar.cr`，HB shape + FtMeasurer/Rasterizer placements，`$env:PATH="C:\msys64\ucrt64\bin;$env:PATH"; crystal run` EXIT=0，脚本已删除）：
  - **msyh** `C:/Windows/Fonts/msyh.ttc`：16px `glyph_ids=[0,0] advances_px=[11.15625,11.15625] meas_w=22.3125 placements=2 drawable=0`；24px `[0,0] [16.734375,16.734375] meas_w=33.46875 drawable=0`；32px `[0,0] [22.3125,22.3125] meas_w=44.625 drawable=0` —— **确认 16/24/32 均为 `[0,0]`、不可绘制**。
  - **arial** `C:/Windows/Fonts/arial.ttf`：16px `glyph_ids=[1019] advances_px=[8.703125] meas_w=8.703125 placements=1 drawable=1`；24px `[1019] [13.0546875]`；32px `[1019] [17.40625]` —— **确认 `[1019]`**。
  - **times** `C:/Windows/Fonts/times.ttf`：16/24/32px 同 arial（`[1019]`，8.703125/13.0546875/17.40625，drawable=1）—— **确认 `[1019]`**。
- `docs/research/text-acceptance.md` 核对：S-AR-LA 段（:44-53）将 `arial.ttf` 明确为验收样例字体（1 glyph, `glyph_id=1019`，16/24/32 drawable）并如实记录 msyh 在 16/24/32 下 `glyph_ids=[0,0]`、drawable=false 且注明“字体覆盖/映射问题、当前渲染策略对 gid=0 不产可见位图，验收不以 msyh 为样例字体”，证据指向 `docs/evidence/M2-WP3-p3-arabic-msyh.md`；同时 :49-52 仍保留按字体差异断言（tahoma/arial/times=1 glyph，segoeui=2 glyph）的一般性口径，未将 lam-alef 强行规定为单一 glyph 数。**结论：仅调整样例字体并补充 msyh 限制说明，未降低验收强度**（仍要求支持字体下 shaping/连字/advance/drawable 正确，且保留跨字体差异与不支持情形的诚实记录）。

## 3. 判据文档一致性（`docs/evidence/M2-WP2c-zero-alloc-criterion.md`）

- **是否夸大为“绝对零分配”**：否，文档明确区分并反向声明。
  - `:5` A 硬判据 `delta_work < N`（per-call ≥1B/次必失败）；`:6` B 噪声上限 `<=256`。
  - `:30` “**能证明：无 per-call（每次迭代）分配。**”；`:31` “**不能证明：绝对零分配。**”；`:33-35` 明示 B 盲区与 dalisi-qing-2 对抗实证：1/1000→`delta_work=32`、`windows=[32,0,0]` **PASSED_BLIND**；5/1000→`delta_work=160`、`windows=[160,0,0]` **PASSED_BLIND**（A 仍满足、B≤256 放过）。
- **1536B 尖峰风险**：如实记录。`:14-16` 空循环基线 20 窗含 `1536` 单窗尖峰（`baseline_max=1536`）；`:36-37` 说明 1536B 级 GC/运行时簿记尖峰可落入 work 窗口导致与 per-call 无关的误报失败，且“无法从单窗字节数区分尖峰噪声与同量级业务分配”；`:39` 保留“单次噪声若 >256B 仍可能误报失败…”。
- **重试规则与代码一致性**：一致。
  - 文档：`:4` `GC.enable` 均在 `ensure`；`:38` 3 窗失败时**同一测试/测量内部最多重试 1 次整套三窗测量**，第二次仍失败才失败，打印 `retried=true attempt=2`（首次 `false/1`），失败消息携带 `retried/attempt`；仅整套三窗重测，不得跳过断言、不得改 A/B 判据。
  - 代码抽查：`spec/text_ft_zero_alloc_spec.cr:58-83`（`attempt=1`→整 3 窗 GC.collect/disable+ensure enable :70-72 → 判 `delta_work<N && <=256` → 首败设 `retried=true,attempt=2` 再跑全套 → `attempt>=2` 则 `fail` 并带字段；n=1000 不变）；`spec/core_node_zero_alloc_spec.cr:127-152`、`spec/render_dirty_into_spec.cr:107-132`、`spec/glyph_atlas_spec.cr:175-204`、`spec/text_renderer_spec.cr:207-233`（含末尾兜底断言 :233）同模式；`tools/zero_alloc_frame.cr:125-159,202-223` 同模式且输出/失败 note 含 retried/attempt，criterion `<frames && <=256`。
- **结论：判据文档未夸大，能力边界、盲区与尖峰风险表述与对抗实证/代码一致。**

## 4. 加分：`docs/research/gl-text-renderer.md` 与代码对照（3 条）

| 文档声称 | 代码实测 | 结论 |
|---|---|---|
| `glOrtho(0,w,h,0,-1,1)` y-down（`docs/research/gl-text-renderer.md:39,69,86`） | `src/tessell/render/gl/gl_renderer.cr:162` `TessellGL.glOrtho(0.0, viewport_w.to_f64, viewport_h.to_f64, 0.0, -1.0, 1.0)`（`begin_frame` 内，`glMatrixMode(PROJECTION)/LoadIdentity` 后，:159-165） | 一致 |
| 每页上传前强制 `glPixelStorei(GL_UNPACK_ALIGNMENT,1)`（:12,24,30,32） | `src/tessell/render/gl/gl_renderer.cr:137` `TessellGL.glPixelStorei(TessellGL::GL_UNPACK_ALIGNMENT, 1)`，位于 `sync_atlas_textures` 逐页循环内（:129-148），`glBindTexture`(:134) 后、纹理参数/`glTexImage2D`(:138-146) 前 | 一致（逐页上传前设置） |
| R8 页上传为 `GL_ALPHA` + 固定管线混合（:4-7,23,45-55,87,100） | `src/tessell/render/gl/gl_renderer.cr:143-145` `glTexImage2D(..., TessellGL::GL_ALPHA.to_i32, size,size,0, TessellGL::GL_ALPHA, GL_UNSIGNED_BYTE, page_data)`；:167-169 启用 `TEXTURE_2D`+`BLEND`，`glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA)`，黑色调制 | 一致 |

## 声称 vs 实测对照

| 项目 | 声称/期望（任务/文档） | 独立实测 |
|---|---|---|
| IME preedit 长度标签 | expected 与 got 分离，不混为一值 | `preedit_expected_len=5`，`preedit_got_len=-1`（未注入成功，回写未触发） |
| IME candidate 语义 | bytes(缓冲) 与 entries(条目) 区分 | `candidate_list_bytes=144`，`candidate_list_count_raw=0`，`candidate_list_entries=0` |
| IME blocked 原因支撑 | `imm_set_composition_rejected` 有 ret=0 证据 | `imm_set_str_preedit_ret=0`，`imm_set_str_result_ret=0`，`imm_set_str_ret=0`，`IMM_ERR=...ret=0...win32_error=0` |
| IME `imm_is_ime` vs `ime_present` | 需解释是否矛盾；`ime_present` 依注入可用性定义，`imm_is_ime` 为 HKL 属性 | `imm_is_ime=true`，`imm_available=true`，`ime_present=false`，`ime_injection=blocked`（谓词不同；标签名易误导→P2） |
| `"لا"` msyh 16/24/32 | `glyph_ids=[0,0]` | 16/24/32 均 `[0,0]`，drawable=0 |
| `"لا"` arial 16/24/32 | `glyph_ids=[1019]` | 16/24/32 均 `[1019]`，drawable=1 |
| `"لا"` times 16/24/32 | `glyph_ids=[1019]` | 16/24/32 均 `[1019]`，drawable=1（与 arial 一致） |
| 判据能力表述 | “无 per-call 分配”，非“绝对零分配”；盲区/1536 尖峰如实 | 文档 `:30-35,36-39` 明确声明并给 32B/160B PASSED_BLIND 与 1536B 风险；与代码/实证一致 |
| 重试规则 | 同 it、≤1 次、二次必败、`GC.enable` 在 ensure、打印 retried/attempt | 5 spec + `tools/zero_alloc_frame.cr` 代码一致（见 §3） |
| gl renderer 3 点 | glOrtho y-down、UNPACK_ALIGNMENT=1 每页上传前、GL_ALPHA 路径 | `gl_renderer.cr:162,137,143-145,168` 一致 |

## 缺陷清单（P0–P3，file:line）

| 级别 | 位置 | 缺陷 | 证据/影响 |
|---|---|---|---|
| P2 | `examples/m2_ime_probe.cr:503-504,520-527,544` | `ime_present` 命名易误导：其语义为“编程注入是否可用/成功”（`programmatic_available`），并非“系统/键盘布局是否存在 IME”；与 `imm_is_ime=true`（HKL 属性, :417）及 `imm_available=true` 同显时易被误读为“无 IME”，造成证据解释歧义。原始 ret/err/count/hkl 字段诚实且可支撑结论，**非伪造**。 | 实测：`imm_is_ime=true imm_available=true ime_present=false ime_injection=blocked reason=imm_set_composition_rejected imm_set_str_*_ret=0`；建议区分命名（如 `programmatic_injection_available`）或在文档中固定语义。 |
| P3 | `examples/m2_ime_probe.cr:449-462,544`（观察） | `candidate_list_bytes=144` 而 `count_raw=0/entries=0` 依赖 IME/API 行为；当前字段拆分已能表达，若无注释/文档读者仍可能误判“有 144 条候选”。 | 信息性；未构成错误断言。 |

- **P0**：无。**P1**：无。**未发现伪造证据**。

## 未验证清单

- 未重建 `bin/m2_ime_probe.exe`（仅运行现有 exe；源码时间戳早于 exe，但未做 bitwise/源码-二进制同源证明）。
- IME 真实人工输入闭环（微软拼音等）仍属 `[未验证]`（本次为程序化注入被拒场景）。
- Arabic 复算未逐 glyph 重取 FT bitmap/w/h/pixel_mode（本次核对 HB glyph_ids/advances/placements/drawable，与任务要求一致；位图细节此前 task-64 已证）。
- `gl-text-renderer.md` 其余论述（性能、core profile 移除风险、GL_LINEAR 影响等）未逐条运行验证，仅对 3 指定点做源码对照。
- 全量 spec / zero_alloc 探针本轮未重跑（本任务仅核验证据文档一致性；判据代码已静态对照，重试行为此前多轮实测为绿）。

## 裁定

- **裁定：PASS-WITH-DEFECTS**
- 理由：IME 复跑输出与源码原始支撑一致（expected/got 分离、candidate bytes/count/entries 语义拆分、blocked 原因有 ret=0/err 支撑），无伪造；Arabic `"لا"` 复算确认 msyh 16/24/32 为 `[0,0]`、arial/times 为 `[1019]`，`text-acceptance.md` 仅限定样例字体并保留差异/限制说明未降验收强度；`M2-WP2c-zero-alloc-criterion.md` 如实声明“无 per-call 分配”而非“绝对零分配”，盲区（32B/160B PASSED_BLIND）与 1536B 尖峰风险及重试规则（同 it 整窗重测、≤1 次、二次必败、ensure GC.enable、打印 retried/attempt）与代码一致；加分 3 点 `glOrtho`/`glPixelStorei` 位置/`GL_ALPHA` 与 `gl_renderer.cr` 一致。存在 **P2**：`ime_present` 标签语义易被误读与 `imm_is_ime` 表观矛盾（值诚实、谓词不同），建议澄清命名/文档。
