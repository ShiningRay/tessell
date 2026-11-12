# M0-WP4-IME 探针证据：IMM32 挂接 + IME 消息计数（W2-4 / task-11, M-1）

- 采集时间（本地）：2026-11-12 16:56:00 +08:00（实测时段；探针输出未内嵌时间戳，时间来自本次会话记录）
- HEAD：`1b0d832220f3017e9efd6f42d59b5d7fab6b09f3`
- OS：`Microsoft Windows NT 10.0.26300.0`，ARCH=`AMD64`
- Crystal：`C:\msys64\ucrt64\bin\crystal.exe`，`Crystal 1.22.1 [23828b0a40] (2026-10-23) LLVM 23.1.3 Default target x86_64-w64-windows-gnu`
- 前置：task-9 完成（文本探针可用）；`examples/m0_window_probe.cr` 作为结构基线复制，原文件未修改。
- 任务：`task-11`「W2-4：IME 探针（IMM32 挂接 + 消息计数，M-1）」
- 写入范围：`examples/m0_ime_probe.cr`、`docs/evidence/M0-WP4-ime.md`（未改 `src/`、`spec/`、`shard.yml`、`README`、`docs/plan*`、`docs/roadmap.md`）

## 1) 实现摘要（`examples/m0_ime_probe.cr`）

- 基于 `examples/m0_window_probe.cr` 复制结构：Isolated UI 线程创建窗口/消息循环/WGL 上下文，`PeekMessageW` 非阻塞泵，`--frames=N`（默认 60）自动退出；新增 `@[Link("imm32")]` FFI。
- IMM32：
  - `CreateWindowExW` + `ShowWindow/UpdateWindow` 后调用 `ImmGetContext(hwnd)` 取得 HIMC，记录 `imm_context` 地址。
  - 若 HIMC 非空：`ImmAssociateContext(hwnd, himc)`（记录返回值）、`ImmSetOpenStatus(himc, TRUE)`、`ImmGetOpenStatus(himc)` 读回；尝试 `ImmSetCompositionWindow(himc, &COMPOSITIONFORM{dwStyle=CFS_POINT, ptCurrentPos=(10,10), rcArea=(0,0,w,h)})`。
  - 若 HIMC 为空：`imm_available=false`，记录 `imm_error="ImmGetContext_null win32_error=<GetLastError>"`，仍运行窗口/消息循环与渲染至 frames 结束后打印 token 并 `exit 0`（按任务书：失败须显式打印 false 并 exit 0，不得打印成功字样）。
- 消息计数（WndProc 中按消息号累加）：`WM_IME_STARTCOMPOSITION(0x010D)`、`WM_IME_COMPOSITION(0x010F)`、`WM_IME_ENDCOMPOSITION(0x010E)`、`WM_IME_SETCONTEXT(0x0281)`、`WM_IME_NOTIFY(0x0282)`；`ime_messages` = 五类计数之和（输出 token）。
- `--ime-test` 模式：窗口/IMM32 初始化完成后通过 `SendMessageW(hwnd, WM_IME_SETCONTEXT, 1, 0)` 注入一次合成 `WM_IME_SETCONTEXT` 以证明消息路径可达 WndProc 并计数；标记 `ime_test_injected`。**此为合成消息，非真实输入法输入。**
- 真实输入自动化：未执行（脚本无法可靠自动打字；SendKeys 依赖前台焦点且不稳定，本次不做）。真实 IME 组合输入 **[未验证]**，需人工手测（见 §5）。
- 输出 token：`imm_available=true/false`、`imm_open_status=`、`ime_messages=`、`imm_error=`；另输出明细 `ime_start/ime_composition/ime_end/ime_setcontext/ime_notify/ime_test_injected`、`hwnd`、`imm_context`、`imm_associate_ret`、`imm_set_open_ret`、`imm_set_comp_ret`、`iso_tid/main_tid`、`frames`。

## 2) 命令与原始输出

### 2.1 基线运行（无合成注入）

命令：
```powershell
$env:PATH = "C:\msys64\ucrt64\bin;" + $env:PATH
Push-Location "C:\Users\ShiningRay\projects\ShiningRay\tessell"
& "C:\msys64\ucrt64\bin\crystal.exe" run examples/m0_ime_probe.cr -- --frames=60 2>&1
"EXITCODE=$LASTEXITCODE"
Pop-Location
```

原始输出：
```
ime_start=0 ime_composition=0 ime_end=0 ime_setcontext=1 ime_notify=3 ime_test_injected=0
imm_available=true imm_open_status=1 ime_messages=4 imm_error=none hwnd=0x14200a2 imm_context=0x2d060505 imm_associate_ret=0x2d060505 imm_set_open_ret=1 imm_set_comp_ret=1 iso_tid=2645221391408 main_tid=2645221392032 frames=60
EXITCODE=0
```

### 2.2 合成消息路径验证（`--ime-test`）

命令：
```powershell
$env:PATH = "C:\msys64\ucrt64\bin;" + $env:PATH
Push-Location "C:\Users\ShiningRay\projects\ShiningRay\tessell"
& "C:\msys64\ucrt64\bin\crystal.exe" run examples/m0_ime_probe.cr -- --frames=60 --ime-test 2>&1
"EXITCODE=$LASTEXITCODE"
Pop-Location
```

原始输出：
```
ime_start=0 ime_composition=0 ime_end=0 ime_setcontext=2 ime_notify=3 ime_test_injected=1
imm_available=true imm_open_status=1 ime_messages=5 imm_error=none hwnd=0x14300a2 imm_context=0x1fa80a53 imm_associate_ret=0x1fa80a53 imm_set_open_ret=1 imm_set_comp_ret=1 iso_tid=2812554722352 main_tid=2812554722976 frames=60
EXITCODE=0
```

## 3) 关键事实

- `ImmGetContext` 返回值（HIMC）：基线 `imm_context=0x2d060505`，`--ime-test` `imm_context=0x1fa80a53`，均非空；`imm_available=true`。
- IMM32 状态：`ImmAssociateContext` 返回 `0x2d060505` / `0x1fa80a53`（与当前上下文一致），`ImmSetOpenStatus(..., TRUE)` 返回 1，`ImmGetOpenStatus` 读回 `imm_open_status=1`，`ImmSetCompositionWindow` 返回 `imm_set_comp_ret=1`。
- 消息计数（真实运行基线，无人工输入）：`ime_setcontext=1`、`ime_notify=3`、`ime_start=0`、`ime_composition=0`、`ime_end=0`、`ime_messages=4`。
- 合成路径验证：`--ime-test` 注入 1 次 `WM_IME_SETCONTEXT`（`ime_test_injected=1`），WndProc 计数 `ime_setcontext` 从 1 增至 2、`ime_messages` 从 4 增至 5，证明消息路径可达且计数来自真实回调增量（非硬编码）。
- 线程：`iso_tid` 与 `main_tid` 不同，IMM32 调用与窗口/消息循环均在 Isolated UI 线程执行。

## 4) 真实/合成边界

- **已实证（合成/系统消息）**：窗口创建过程中系统产生的 `WM_IME_SETCONTEXT`/`WM_IME_NOTIFY` 可被 WndProc 捕获计数；通过 `SendMessageW` 注入的 `WM_IME_SETCONTEXT` 可被捕获计数。
- **未实证（真实 IME 组合）**：未进行真实输入法输入；`WM_IME_STARTCOMPOSITION` / `WM_IME_COMPOSITION` / `WM_IME_ENDCOMPOSITION` 在本次自动运行中均为 0。真实 IME 组合输入 **[未验证]**。

## 5) 人工验证步骤（M-1 手测，未执行）

1. 启动探针并保持窗口前台焦点：`$env:PATH="C:\msys64\ucrt64\bin;"+$env:PATH; crystal run examples/m0_ime_probe.cr -- --frames=600`（延长帧数以便操作）。
2. 切换到微软拼音（或其他中文 IME），确保输入法开启。
3. 在探针窗口内输入 `nihao` 并选词/上屏得到「你好」。
4. 观察退出后输出：`ime_start`、`ime_composition`、`ime_end` 应从 0 变为 >0（具体次数取决于 IME 实现与组合过程）；`ime_messages` 相应增加。
5. 可选：切换不同 IME（如微软五笔/日文 IME）重复，记录差异。
6. 记录：实际计数、输入法名称/版本、是否出现候选窗位置异常（与 `ImmSetCompositionWindow` CFS_POINT (10,10) 的关系）。

## 6) [未验证] 清单

- 真实 IME 组合输入（中文/日文等）下 `WM_IME_STARTCOMPOSITION`/`WM_IME_COMPOSITION`/`WM_IME_ENDCOMPOSITION` 的实际计数与内容。**[未验证]**
- `ImmSetCompositionWindow` 对候选窗/组合窗位置的实际生效效果（需人工观察）。**[未验证]**
- TSF（Text Services Framework）路径下的行为（现代 Windows IME 多走 TSF，IMM32 为兼容层）；IMM32 消息是否完整反映 TSF 输入。**[未验证]**
- 不同输入法、不同 DPI/多显示器下行为。**[未验证]**
- 在非 Isolated 线程或主线程创建窗口时 IMM32 行为差异（本次仅验证 Isolated 线程）。**[未验证]**

## 7) M-1 结论

- **IMM32 可用性（Isolated UI 线程，自动化可证）**：`ImmGetContext` 返回非空 HIMC，`ImmAssociateContext`/`ImmSetOpenStatus`/`ImmGetOpenStatus`/`ImmSetCompositionWindow` 调用均返回成功值（1/非空），窗口过程可接收系统 IME 消息（`WM_IME_SETCONTEXT`/`WM_IME_NOTIFY`）及合成注入消息并正确计数；无 HIMC 为空或调用异常。
- **M-1 判定：部分可用（IMM32 挂接与消息路径可用），真实 IME 组合输入待人工验证。** 当前证据足以证明 FFI 挂接与消息通路在 Isolated 线程窗口上成立；M-1 “形成 IME 最小可行结论”中，真实组合（START/COMPOSITION/END）需按 §5 人工手测补证后方可完全关闭。
- **补救建议（若人工手测异常）**：如发现真实组合消息缺失/候选窗位置无效，优先排查 TSF-to-IMM32 兼容层行为、窗口类/样式与焦点；必要时评估在 UI 主线程承载 IME 窗口或引入 TSF 路径（超出本探针范围，另行立项）。
