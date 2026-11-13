# M2-WP3 IME 探针证据（imm32 注入尝试 + 回读 + 候选探测）

- 任务：`task-65` M2-WP3：IME 探针与证据
- 时间：2026-11-13（Asia/Shanghai）
- 环境：Windows，Crystal 1.22.1（`C:\msys64\ucrt64\bin`），HEAD `fdb797c`（工作区未 commit）
- 探针：`examples/m2_ime_probe.cr`（纯 FFI `kernel32/user32/imm32`；复用 `m0_ime_probe`/`m0_window_probe` 窗口+消息泵模式）
- 约束遵守：未改 `src/tessell/input/*`、`src/tessell/render/*`、`src/tessell/text/*`；未 commit；无临时脚本残留
- 2026-11-13 修订（按 lead m01181）：修正候选计数字段语义（`candidate_list_bytes`/`candidate_list_count_raw`/`candidate_list_entries`）、修正期望/实测长度标签（`*_expected_len`/`*_got_len`）、增强前台焦点与 HKL 激活/查询并输出 `kl_*`/`imm_is_ime`/`ime_injection`、补充渲染管线关联证据。

## 原始输出（关键行）

```text
$env:PATH="C:\msys64\ucrt64\bin;$env:PATH"; crystal build examples/m2_ime_probe.cr -o bin/m2_ime_probe.exe
BUILD_EXIT=0

$env:PATH="C:\msys64\ucrt64\bin;$env:PATH"; .\bin\m2_ime_probe.exe --frames=60
ime_injection=blocked ime_injection_reason=imm_set_composition_rejected ime_present=false ime_desc= ime_file= imm_available=true imm_is_ime=true imm_open_status=1 imm_set_open_ret=1 imm_set_str_ret=0 imm_set_str_preedit_ret=0 imm_set_str_result_ret=0 preedit_roundtrip=false preedit_text= preedit_expected_len=5 preedit_got_len=-1 result_roundtrip=false result_text= result_expected_len=2 result_got_len=-1 candidate_list_bytes=144 candidate_list_count_raw=0 candidate_list_entries=0 cand_pos=not_triggered ime_messages_setcontext=1 ime_messages_start=0 ime_messages_composition=0 ime_messages_end=0 ime_messages_notify=3 kl_count=2 kl_ids=0x8040804,0x4090409 active_hkl=0x8040804 activated_hkl=0x8040804 IMM_ERR=ImmSetCompositionStringW_rejected_preedit_ret=0_result_ret=0_win32_error=0 frames=60 hwnd=0x1c0880 himc=0x2be05a5
IME_PROBE_EXIT=0
RUN_EXIT=0
```

（初版同机对照，已修正误导标签：`candidate_list_count=144 candidate_list_bytes=0` 实为字节数语义混用；`preedit_len=5/result_len=2` 仅为期望值而非回读实测，现改为 `preedit_expected_len=5 preedit_got_len=-1`、`result_expected_len=2 result_got_len=-1`。）

## 渲染管线关联证据（不改 src，CPU 侧）

使用现有 `FtMeasurer` + `GlyphAtlas` + `Rasterizer` + `TextRenderer`（`C:/Windows/Fonts/msyh.ttc`，24px，800x600）分别构建“预编辑串”与“已提交串”四边形（临时脚本执行后删除）：

```text
preedit_text=nihao preedit_quads=5 preedit_batches=1 preedit_pen_end=104.47656
commit_text=你好 commit_quads=2 commit_batches=1 commit_pen_end=88.0
IME_RENDER_PIPE_EXIT=0
```

结论：**预编辑文本与提交文本均可进入现有文本渲染管线并产出可计数的四边形/批次**（IME 事件接线前的可本地证明链路）。

## 一、已证 / 未证 / 手测（三栏结论）

- **已证（一行）**：窗口/消息泵与 HIMC 生命周期可用（`imm_available=true`、`ShowWindow/SetForegroundWindow/SetFocus`+HKL 枚举/激活路径已执行，`kl_count=2 kl_ids=0x8040804,0x4090409`、`imm_is_ime=true`、`imm_open_status=1`），候选探测 API 可调用并返回字节证据（`candidate_list_bytes=144 candidate_list_count_raw=0 candidate_list_entries=0`），IME 系统消息可达（`ime_messages_setcontext=1 ime_messages_notify=3`），预编辑/提交文本可经 `Rasterizer+TextRenderer` 生成四边形（`nihao`→5 quads，`你好`→2 quads）。
- **未证（一行）**：程序化 `ImmSetCompositionStringW(SCS_SETSTR)` 在本机被拒（`ime_injection=blocked ime_injection_reason=imm_set_composition_rejected`，preedit/result ret=0、`*_roundtrip=false`、`*_got_len=-1`），因此真实键盘预编辑不丢字、候选窗真实定位（`cand_pos=not_triggered`）、多 IME 切换及 composition/start/end 实际内容流转 **C2 仍开放**。
- **手测（一行）**：须在有可用中文输入法的桌面前台手测（见下表）：验证 `WM_IME_STARTCOMPOSITION → WM_IME_COMPOSITION(GCS_COMPSTR，逐键不丢字如 n/ni/nih/niha/nihao) → WM_IME_COMPOSITION(GCS_RESULTSTR=你好) → WM_IME_ENDCOMPOSITION` 顺序、候选窗定位通知与多 IME 切换；探针不伪造 roundtrip。

## 二、已证（明细）

| 项目 | 证据 | 结论 |
|---|---|---|
| 窗口/焦点/帧循环 | `ShowWindow+UpdateWindow+SetForegroundWindow+SetFocus`，`frames=60`，`IME_PROBE_EXIT=0`，BUILD/RUN EXIT=0 | 前台焦点与消息泵路径已执行 |
| HKL 枚举与激活 | `kl_count=2 kl_ids=0x8040804,0x4090409 active_hkl=0x8040804 activated_hkl=0x8040804` | 已枚举并尝试激活非 US/差异布局后再取上下文 |
| HIMC/IME 状态 | `imm_available=true imm_is_ime=true imm_open_status=1 imm_set_open_ret=1 himc=0x2be05a5` | `ImmGetContext/ImmAssociateContext/ImmSetOpenStatus/ImmIsIME` 可用 |
| IME 描述/文件 | `ImmGetDescriptionW/ImmGetIMEFileNameW` 已调用，`ime_desc=` `ime_file=`（空） | 查询路径可执行；本机返回空描述原样记录 |
| 程序化注入（正攻重试） | `imm_set_str_preedit_ret=0 imm_set_str_result_ret=0 imm_set_str_ret=0`，`IMM_ERR=ImmSetCompositionStringW_rejected_preedit_ret=0_result_ret=0_win32_error=0` | `SCS_SETSTR + PostMessage(WM_IME_COMPOSITION)` 回读流程已执行但被拒，`preedit/result_roundtrip=false`，`preedit_text/result_text` 为空，`*_got_len=-1`（未伪造） |
| 候选探测（语义修正） | `candidate_list_bytes=144 candidate_list_count_raw=0 candidate_list_entries=0`（`ImmGetCandidateListCountW` 返回字节数；entries 经 `ImmGetCandidateListW.dwCount` 读取，bytes>0 但本次 entries=0 原样记录） | 计数与字节/条目语义分离，不再误标 |
| 消息路径 | `ime_messages_setcontext=1 ime_messages_notify=3 ime_messages_start=0 ime_messages_composition=0 ime_messages_end=0` | 系统通知可达；因注入被拒未形成有效 composition 内容 |
| 渲染管线 | `nihao`→`quads=5 batches=1`，`你好`→`quads=2 batches=1` | 预编辑/提交文本可进入现有 `Rasterizer+TextRenderer`（IME 落地前可证链路） |

## 三、未证（C2 开放）

| 未证项 | 原因/现状 | 影响 |
|---|---|---|
| 真实键盘预编辑不丢字 | `ime_injection=blocked reason=imm_set_composition_rejected`，无有效 `GCS_COMPSTR` 回读 | C2 未关闭 |
| 真实候选窗定位 | `cand_pos=not_triggered`（未收 `IMN_SETCANDIDATEPOS` 有效坐标） | C2 未关闭 |
| 多 IME 切换一致性 | 仅本机当前 HKL 集合一次探测 | C2 未关闭 |
| 程序化 roundtrip | preedit/result 注入均被拒，`*_got_len=-1` | 本机程序化注入不可用（阻塞证据），非伪造 |

> 明确结论：**本机程序化注入被拒（`ime_injection=blocked ime_injection_reason=imm_set_composition_rejected`），C2 条件仍开放；须在有可用中文输入法的桌面进行真实键盘手测。** 探针全程不伪造 `ime_present=true`/`*_roundtrip=true`。

## 四、手测清单（按键序列 + 期望）

前提：系统启用可用中文 IME（建议微软拼音），探针窗口在前台并获焦点。

| 步骤 | 操作 | 期望消息/数据 | 不丢字与顺序判据 |
|---|---|---|---|
| 1 启动 | `crystal run examples/m2_ime_probe.cr -- --frames=300` | `imm_available=true`，`IME_PROBE_EXIT=0`，`kl_*`/`ime_injection` 输出正常 | 探针常驻可收消息 |
| 2 预编辑输入 | 切中文 IME，依次按 `n,i,h,a,o` | `WM_IME_STARTCOMPOSITION` → 多次 `WM_IME_COMPOSITION(GCS_COMPSTR)`，回读依次体现 `n/ni/nih/niha/nihao`（或等价） | **不丢字**：每键均反映，串单调增长且字符序正确 |
| 3 候选与定位 | 观察候选窗/移动 caret（若 IME 支持） | `WM_IME_NOTIFY`（含 `IMN_OPENCANDIDATE/IMN_SETCANDIDATEPOS`）触发，`cand_pos` 有效 | 候选窗位置随组合/插入点合理 |
| 4 提交 | 按 `Space` 或 `1` 确认 `你好` | `WM_IME_COMPOSITION(GCS_RESULTSTR)="你好"` → `WM_IME_ENDCOMPOSITION` | 提交文本与预期一致、无残留/错字 |
| 5 取消 | 重新输入后按 `Esc` | end/cancel 路径，composition 清空 | 无脏预编辑残留 |
| 6 多 IME 切换 | 切换其他 IME 重复 2-4 | `ime_desc/ime_file/imm_is_ime` 或行为随布局变化 | 各 IME 均可完成 start→compstr→resultstr→end |

**期望顺序（核心）**：`WM_IME_STARTCOMPOSITION` → `WM_IME_COMPOSITION(GCS_COMPSTR)`×n（预编辑逐步更新、不丢字）→ `WM_IME_COMPOSITION(GCS_RESULTSTR)`（提交）→ `WM_IME_ENDCOMPOSITION`。

## 五、M2-WP3 待落地建议（不改实现）

现状：`src/tessell/input/event.cr` 的 `Kind` 无 IME kind。建议后续新增 `ImeStart`/`ImePreedit(text,cursor)`/`ImeCommit(text)`/`ImeEnd`，由平台层将 `GCS_COMPSTR/RESULTSTR/CURSORPOS` 映射并**仅投递给 FocusManager 当前焦点控件**（preedit 为可替换中间态，commit 落确定文本后清理）；候选窗定位由平台层按 caret 调 `ImmSetCompositionWindow`。本任务未改 `event.cr`。

## 六、与 m01014 缓解关系（信息性）

同批已落地 GC 探针失败重试缓解（5 探针 + `tools/zero_alloc_frame.cr` + `docs/evidence/M2-WP2c-zero-alloc-criterion.md`），与 WP3 IME 探针独立；未改 `input/render/text` 源码。
