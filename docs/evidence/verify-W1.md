# verify-W1 独立核验报告（大理寺卿）

## 1. 核验环境
- 核验时间（本地）：`2026-11-12 16:25:05 +08:00`（`Get-Date -Format "yyyy-MM-dd HH:mm:ss zzz"`）
- 仓库：`C:\Users\ShiningRay\projects\ShiningRay\tessell`
- `HEAD`：`981e7a9`（`git rev-parse --short HEAD`，与证据文档记录的 `981e7a9f0d401170472eb1e52d90b8338dc4d577` 一致）
- `git status --short`：`?? docs/evidence/`、`?? examples/`（仅未跟踪证据/示例目录；`src/`、`spec/`、`shard.yml` 无变更记录）
- Crystal：`Crystal 1.22.1 [23828b0a40] (2026-10-23), LLVM 23.1.3, Default target: x86_64-w64-windows-gnu`（`crystal --version`）
- OS/Arch：`Microsoft Windows NT 10.0.26300.0`，`AMD64`

## 2. 逐项结论表

| # | 核验项 | 结论 | 证据命令 | 关键证据 / 行号 |
|---|---|---|---|---|
| 1 | 代码真实性：M0-WP2 Isolated/Channel/Mutex 为真实调用（非打印常量伪装） | **通过** | `read examples/m0_isolated.cr`；`Select-String -Path examples\m0_isolated.cr,examples\m0_window_probe.cr -Pattern 'pixel_match\s*=\s*true|"pixel_match=true"'`；`crystal run examples/m0_isolated.cr` | `Isolated.new` `examples/m0_isolated.cr:14`；`Channel(Int32)` 收发 `:10-12,:23-25,:45-46`；`Fiber::ExecutionContext::Parallel.new("worker",4)`+`Mutex#synchronize` 累加 `:28-39`；结果由实测变量输出 `:54`。grep 未发现硬编码 `pixel_match=true` 赋值/字符串伪装。重跑输出：`main_fid=2648509075200 main_tid=2648509071008 iso_fid=2648509074400 iso_tid=2648509070384 same_fiber=true same_tid=true diff_from_main=true cross_iso=42 mutex_val=4`，`EXITCODE=0`（id/tid 为运行时值，语义与证据一致）。 |
| 1 | 代码真实性：M0-WP3 窗口探针真实调用 user32/gdi32/opengl32 FFI、WGL 上下文、SwapBuffers、glReadPixels 像素比对 | **通过** | `read examples/m0_window_probe.cr`；`Select-String ... -Pattern 'puts|print'`（检查输出来源） | FFI 绑定 `@[Link("user32")] :15`、`@[Link("gdi32")] :79`、`@[Link("opengl32")]` WGL/GL `:115,:122`；窗口/消息 `RegisterClassExW :241`、`CreateWindowExW :258`、`PeekMessageW/Translate/Dispatch :324-330`；像素格式+上下文 `ChoosePixelFormat/SetPixelFormat :288-292`、`wglCreateContext/wglMakeCurrent :294-298`；渲染提交 `SwapBuffers :348`；像素读取 `glReadPixels :346`；`pixel_match` 由中心像素与期望值计算 `:358-364` 并随 `line` 输出 `:374`（非硬编码）；UI/GL 在 `Fiber::ExecutionContext::Isolated.new("tessell-ui")` 内 `:218`，输出含 `iso_tid/main_tid`。 |
| 2 | 可复现性：`crystal run examples/m0_isolated.cr` | **通过** | `crystal run examples/m0_isolated.cr` | 原始输出：`main_fid=2648509075200 main_tid=2648509071008 iso_fid=2648509074400 iso_tid=2648509070384 same_fiber=true same_tid=true diff_from_main=true cross_iso=42 mutex_val=4`；`EXITCODE=0`。与 `docs/evidence/M0-WP2-isolated.md:28` 对比：关键 token/语义值（same_fiber/same_tid/diff_from_main/cross_iso/mutex_val）一致；fid/tid 数值因运行时不同而异，符合预期。 |
| 2 | 可复现性：`crystal build examples/m0_window_probe.cr -o bin/verify_window.exe` + `bin/verify_window.exe --frames=120` | **通过** | `New-Item -Force bin; crystal build examples/m0_window_probe.cr -o bin/verify_window.exe`；`bin\verify_window.exe --frames=120` | 构建输出：`EXITCODE=0`。运行原始输出：`hwnd=14355856 pixel_format=5 gl_version=4.6.0_-_Build_32.0.101.7092 gl_renderer=Intel(R)_Iris(R)_Xe_Graphics frames=120 swapbuffers=120 pixel_match=true iso_tid=2230644522032 main_tid=2230644522656 elapsed_ms=125 pixel_rgba=204,51,51,255 expected_rgb=204,51,51`；`EXITCODE=0`。与 `docs/evidence/M0-WP3-window.md:73-75` 对比：`frames=120`、`swapbuffers=120`、`pixel_match=true`、`gl_version/gl_renderer` 非空一致；`hwnd/tid/elapsed_ms/pixel_format` 等为运行时值差异，证据未声称固定，结果可复现。 |
| 3 | 证据完整性：证据文件含完整命令、原始输出、退出码、环境；未验证项标 `[未验证]`；未把规划当实测 | **通过** | `read docs/evidence/M0-WP1-baseline.md`；`read docs/evidence/M0-WP2-isolated.md`；`read docs/evidence/M0-WP3-window.md` | WP1 `M0-WP1-baseline.md`：含采集时间/HEAD/版本/spec 输出与 EXITCODE/环境/结论表，未执行项声明无 `:1-103`。WP2 `M0-WP2-isolated.md`：含命令、原始输出、退出码、环境、对照表，明确未复测项 `[未验证]` `:44-46,:51`。WP3 `M0-WP3-window.md`：含选型/依赖/构建调试记录/最终命令/原始输出/像素证据/阻塞记录“无阻塞”与未验证项 `[未验证]` `:39-94`。未见将规划描述写作已实测。 |
| 4 | 边界：未越界改 `src/`、`spec/`、`shard.yml`；`git status` 仅预期未跟踪（`examples/`、`docs/evidence/`，`bin/` 忽略） | **通过** | `Get-ChildItem src,spec,shard.yml`；`git status --short -- src spec shard.yml`；`git status --short` | `src/`、`spec/`、`shard.yml` 存在但 `git status --short -- src spec shard.yml` 无输出（`EXIT=0`）。全局状态仅 `?? docs/evidence/`、`?? examples/`；未见 `src`/`spec`/`shard.yml` 修改，未见 `bin/` 跟踪项。 |
| 5 | M0-WP1 基线：重跑 `crystal spec` 与文档记录一致 | **通过** | `crystal spec` | 原始输出：`......` / `Finished in 174 microseconds` / `6 examples, 0 failures, 0 errors, 0 pending`；`EXITCODE=0`。与 `docs/evidence/M0-WP1-baseline.md:37-42`（`222 microseconds`，6/0/0/0，`EXITCODE=0`）对比：退出码与用例统计一致，耗时微差异属正常波动。 |

## 3. 缺陷清单
| ID | 严重性 | 位置 | 复现命令 | 影响 |
|---|---|---|---|---|
| — | — | — | — | 本次核验未发现可判定缺陷（无硬编码伪证、无实测与证据不符、无越界修改证据）。 |

## 4. 最终裁定
- **裁定：PASS**
- 依据：task-3/task-4 代码经读码与 grep 检查为真实调用与实测输出；WP2/WP3 关键命令均由核验方重跑通过且语义结果与证据一致；WP1 `crystal spec` 重跑统计与基线一致；证据文件完整且对未验证项有标注；`src/`/`spec/`/`shard.yml` 未见改动痕迹。
- 备注：fid/tid/hwnd/elapsed_ms 等运行时标识在不同运行间变化，属正常现象；WP2/WP3 已对未复测项标注 `[未验证]`。
