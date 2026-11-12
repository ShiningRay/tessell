# M0-WP3 最小窗口 + WGL 提交探针实测证据

- 任务：`task-4` / `M0-WP3`（对应 `docs/plan.md` B.1、`docs/roadmap.md` C.3.3、`docs/plan-execution.md` EX-W1-03/EX-W1-04）
- 仓库：`C:\Users\ShiningRay\projects\ShiningRay\tessell`
- 采集时间（本地，证据整理时记录）：`2026-11-12 16:15:09 +08:00`（同会话）；实跑时间以命令执行为准
- `HEAD`：`981e7a9f0d401170472eb1e52d90b8338dc4d577`
- 运行环境：Windows（ucrt64），Crystal `1.22.1 [23828b0a40] (2026-10-23), LLVM 23.1.3, Default target x86_64-w64-windows-gnu`（`C:\msys64\ucrt64\bin\crystal.exe`）

## 选型结论（EX-W1-03）

- 路径：**P-WIN-2（user32/gdi32+WGL，首选）**，纯 FFI，GL 1.1 immediate mode，无第三方窗口库/shard。
- 依据：`docs/roadmap.md` C.3.3/C.3.5 取舍结论（P-WIN-2 首选，user32 FFI 已本机实证）；`docs/research/crystal-capabilities.md:L13` 支撑 Win32 FFI 可行性；符合“验证可达性优先”且不动摇自绘定案。
- 备选/降级：P-WIN-1/P-WIN-3 本轮未启用；P-WIN-4 未触发（窗口+GL 提交成功）。

## 依赖 DLL（系统/运行时）

| DLL | 用途 |
|---|---|
| `kernel32.dll` | `GetModuleHandleW` / `GetLastError` / `GetTickCount64` |
| `user32.dll` | 窗口类注册、窗口创建、消息泵、DC、光标等 |
| `gdi32.dll` | 像素格式、`SwapBuffers` |
| `opengl32.dll` | WGL 上下文与 GL 1.1 调用 |

均为 Windows 系统 DLL，未引入第三方原生库；构建链接通过 Crystal/ucrt64 toolchain（`cc`/`ld`）。

## 交付物

- `examples/m0_window_probe.cr`：单文件探针
  - `RegisterClassExW`/`CreateWindowExW` 创建窗口（标题 `"Tessell M0 Probe"`，类名含 M0 标识），WndProc 处理 `WM_CLOSE`/`WM_DESTROY`/`WM_KEYDOWN(ESC)`
  - `GetDC` → `ChoosePixelFormat`(PFD_DRAW_TO_WINDOW|PFD_SUPPORT_OPENGL|PFD_DOUBLEBUFFER, RGBA32/Depth24/Stencil8) → `SetPixelFormat` → `wglCreateContext` → `wglMakeCurrent`
  - `glViewport`/`glClearColor`/`glClear` + GL 1.1 immediate mode 大三角形覆盖中心；`glFlush`；每帧 `glReadPixels` 读回中心像素；`SwapBuffers`
  - 非阻塞消息泵：`PeekMessageW`/`TranslateMessage`/`DispatchMessageW`
  - `--frames=N`（默认 180）自动退出，自然退出码 0；ESC/关闭可中断
  - 窗口/GL 上下文/消息循环/渲染全部在 `Fiber::ExecutionContext::Isolated.new("tessell-ui")` 内执行；输出 `iso_tid` 与 `main_tid`
  - 失败路径显式 `fail(...)` 打印 `error=... win32_error=...` 并 `exit 1`；`glGetString` 为空时 stderr 报错并退出
- `bin/m0_window_probe.exe`：构建产物（`bin/` gitignored）

## 构建过程与命令

### 初次构建调试（真实记录）

1. `crystal build examples/m0_window_probe.cr -o bin/m0_window_probe.exe` → **EXITCODE=1**  
   - 错误：`Error: HANDLE is already defined`（`LibC` 中自定义 `type HANDLE` 与 stdlib 冲突）。修复：去除 `lib LibC` 类型别名，改用 `Void*`/基础整型。
2. 同命令 → **EXITCODE=1**（链接失败）  
   - 错误：`undefined reference to ChoosePixelFormat/SetPixelFormat/wgl*/gl*/SwapBuffers`。修复：为各 `lib` 添加 `@[Link("kernel32")]`/`@[Link("user32")]`/`@[Link("gdi32")]`/`@[Link("opengl32")]`。

### 最终构建命令（成功）

```powershell
cd C:\Users\ShiningRay\projects\ShiningRay\tessell
New-Item -ItemType Directory -Force -Path bin | Out-Null
crystal build examples/m0_window_probe.cr -o bin/m0_window_probe.exe
echo "EXITCODE=$LASTEXITCODE"
```

**原始输出：**

```text
EXITCODE=0
```

## 运行命令与原始输出

```powershell
cd C:\Users\ShiningRay\projects\ShiningRay\tessell
.\bin\m0_window_probe.exe --frames=120
echo "EXITCODE=$LASTEXITCODE"
```

**原始输出：**

```text
hwnd=20712404 pixel_format=5 gl_version=4.6.0_-_Build_32.0.101.7092 gl_renderer=Intel(R)_Iris(R)_Xe_Graphics frames=120 swapbuffers=120 pixel_match=true iso_tid=2212314627120 main_tid=2212314627744 elapsed_ms=188 pixel_rgba=204,51,51,255 expected_rgb=204,51,51
EXITCODE=0
```

## 像素校验证据（glReadPixels）

- 清屏色：`(0.2, 0.4, 0.6, 1.0)`；覆盖中心的大三角形颜色：`(0.8, 0.2, 0.2)`。
- 中心像素读取：`pixel_rgba=204,51,51,255`，期望 `expected_rgb=204,51,51`（`round(0.8*255)=204, round(0.2*255)=51`），容差 ±2，结果 `pixel_match=true`。
- 提交证据：`frames=120`、`swapbuffers=120`、`gl_version`/`gl_renderer` 非空，`hwnd` 有效，程序在 ≤60s 内自然退出（`elapsed_ms=188`）。

## 线程/执行上下文证据

- `iso_tid=2212314627120`，`main_tid=2212314627744`，两者不同（`iso_tid != main_tid`），表明窗口/GL/消息循环在 Isolated 执行上下文线程内运行（符合要求“UI 全部在 Isolated 线程”）。

## 阻塞记录

- 无阻塞。当前会话具备可用窗口/GL 环境，P-WIN-4 离线降级未触发。

## 结论

- M0-WP3（P-WIN-2）：**通过（本机实测）**。构建成功、运行 120 帧退出码 0，`gl_version` 非空，`pixel_match=true`，`SwapBuffers` 每帧成功，Isolated 线程执行得到证据。
- 未验证项：多 DPI/多显示器行为、长时间稳定性、macOS/Linux 路径、与 tessell 现有渲染管线集成 `[未验证]`。
