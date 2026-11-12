# Crystal GUI/文本/GPU 生态与依赖可用性调研（Windows 视角）

- 调研日期：2026-11-12（本地时区 Asia/Shanghai）
- 本机环境（已核实）：Crystal `1.22.1 [23828b0a40] (2026-10-23)`，`Default target: x86_64-w64-windows-gnu`，LLVM 23.1.3（证据：本地执行 `crystal --version`）
- 工作目录：`C:\Users\ShiningRay\projects\ShiningRay\tessell`
- 证据来源：优先 GitHub REST API / 仓库页面（`web_fetch`）；未能取证处明确标注「未能核实」

## 1. 候选总表（窗口/事件、GPU 相关绑定、文本、2D、同类框架）

| 类别 | 候选 | 仓库/URL | 最近活跃度（API 证据） | 支持平台 | 许可证 | 可直接依赖? | 风险/备注 |
|---|---|---|---|---|---|---|---|
| 窗口/事件 | CrystGLFW (GLFW Crystal API) | https://github.com/calebuharrison/CrystGLFW | `pushed_at`: 2023-09-15T02:14:45Z, `updated_at`: 2026-03-28T15:59:04Z, stars 35, open issues 3（GitHub API） | GLFW 本身跨平台（Win/macOS/Linux），但绑定 README/CI 对 Windows 支持**未能核实**；需本机实测 | MIT（API `license`） | 谨慎可用（作为 GLFW FFI/封装基础） | 近年无代码推送，维护活跃度偏低；Windows 构建/链接细节需验证 |
| 窗口/事件 | sdl.cr (SDL2 bindings) | https://github.com/ysbaddaden/sdl.cr | `pushed_at`: 2025-06-29T13:30:31Z, `updated_at`: 2026-09-23T00:37:55Z, stars 105, open issues 21 | SDL2 跨平台（含 Windows）；`shard.yml` 依赖 `libSDL2 ~> 2.0.2` 等（raw 内容已取证） | API 未返回 license 字段（`license: null`）→ **未能核实**；需查仓库 LICENSE 文件 | 可作为底层绑定候选 | issue 较多；Windows 下 DLL/静态库分发与链接需验证；API 覆盖度需评估 |
| 窗口/事件/多媒体 | crsfml (SFML bindings) | https://github.com/oprypin/crsfml | `pushed_at`: 2025-11-23T11:02:56Z, `updated_at`: 2026-10-10T08:11:21Z, stars 356, open issues 5 | SFML 跨平台（Win/macOS/Linux）；Windows 支持通常较成熟，但该仓库当前 Windows CI/说明**未能核实** | zlib（API `license`） | 较可行（成熟度/人气较高） | 依赖 SFML/CSFML 原生库；Windows 运行需配套 DLL/构建链配置，需实测 |
| 窗口/事件/游戏框架 | raylib-cr (raylib bindings) | https://github.com/sol-vin/raylib-cr | `pushed_at`: 2026-10-21T12:46:15Z, `updated_at`: 2026-11-05T20:55:28Z, stars 122, open issues 0 | README 明确列出 `64-bit Windows`、`64-bit Linux`、`MacOS` 开箱即用并静态链接（README 已取证） | Apache-2.0（API `license`） | **Windows 上可直接尝试的高优先候选**（窗口/输入/2D/基础图形一体） | 依赖 C:\raylib 路径与 LIB/PATH 配置（README）；raylib 抽象层可能限制底层 GPU/文本栈可控性；需与 Tessell 架构目标匹配评估 |
| 窗口/事件 | winit (Rust 窗口库) Crystal 绑定 | （GitHub 搜索）`https://api.github.com/search/repositories?q=winit+language:crystal` | 搜索结果 `total_count: 0`（2026-11-12 取证） | N/A | N/A | 否（无现成绑定） | 如需 winit 语义需自建 FFI 绑定（工作量中高：需封装 Rust/C ABI 或改用 winit 的 C 友好替代方案） |
| 文本/整形 | harfbuzz.cr | https://github.com/hugopl/harfbuzz.cr | `pushed_at`: 2025-08-05T20:47:10Z, `updated_at`: 2025-08-05T20:47:09Z, stars 2, open issues 0 | 依赖系统 HarfBuzz；跨平台潜力有但 Windows 预编译/安装路径**未能核实** | MIT（API `license`） | 可作为轻量 FFI 绑定起点（需评估 API 覆盖） | 星标/生态规模小，近期无更新；“bindings” 覆盖度与稳定性需代码级审查 |
| 文本/字体栅格 | freetype.cr (watzon) | https://github.com/watzon/freetype.cr | `pushed_at`: 2022-04-23T22:08:30Z, `updated_at`: 2022-04-04T21:12:19Z, stars 7, open issues 1 | 依赖 FreeType2；Windows 可达性**未能核实** | MIT（API `license`） | 谨慎（年代较久，维护停滞风险） | 长期未更新，可能与新 Crystal/工具链存在兼容性问题；需实测 |
| 文本/字体栅格 | freetype.cr (OrelSokolov) | https://github.com/OrelSokolov/freetype.cr | `pushed_at`: 2026-10-13T09:13:26Z, `updated_at`: 2026-10-13T09:01:35Z, stars 0, open issues 0 | 依赖 FreeType；Windows 支持**未能核实** | API `license: null` → **未能核实** | 实验性候选（较新但成熟度未知） | 无许可证声明、无星标、文档未知；引入前需审计与补充验证 |
| 2D 渲染/矢量 | cairo-cr | https://github.com/TamasSzekeres/cairo-cr | `pushed_at`: 2022-06-12T16:26:57Z, `updated_at`: 2025-08-27T12:10:37Z, stars 33, open issues 0 | Cairo 跨平台；Windows 依赖 DLL/头文件配置**未能核实** | MIT（API `license`） | 可作为 2D 光栅/矢量备选（成熟 C 库绑定） | 代码较久未推送；在 Windows + Crystal toolchain 下链接成本需评估 |
| 2D 渲染/光栅 | Skia Crystal 绑定（如 skia.cr） | （GitHub 搜索）`https://api.github.com/search/repositories?q=skia+crystal+binding` | 搜索结果 `total_count: 0`（2026-11-12 取证） | N/A | N/A | 否（未发现现成绑定） | Skia C API/构建复杂，FFI 直绑与构建集成工作量高；Windows 预编译分发链路成本大 |
| 2D 渲染/光栅 | NanoVG Crystal 绑定 | （GitHub 搜索）`https://api.github.com/search/repositories?q=nanovg+language:crystal` | 搜索结果 `total_count: 0`（2026-11-12 取证） | N/A | N/A | 否（未发现现成绑定） | NanoVG 体量小但需与 GL 后端/字体栈集成；FFI 直绑中等工作量，Windows 需验证编译与链接 |
| 同类框架/GUI | GTK4.cr | https://github.com/hugopl/gtk4.cr | `pushed_at`: 2025-09-05T18:20:28Z, `updated_at`: 2026-10-09T13:13:50Z, stars 129, open issues 10 | README 提及 Linux/macOS/MSYS2 依赖安装；**Windows 原生（非 MSYS2）可用性未能核实** | MIT（API `license`） | Linux/GTK 生态下可行；Windows 作为 Tessell 主路径风险高 | 依赖 GTK4 + gobject-introspection 运行/编译环境；Windows 分发与打包复杂 |
| 同类框架/GUI | CrystKit（WebView 桌面框架） | https://github.com/naqvis/crystkit | `pushed_at`: 2026-11-10T10:59:02Z, `updated_at`: 2026-11-11T09:52:56Z, stars 6, open issues 0 | 描述含 WebKitGTK/WebView2/跨平台桌面；Windows WebView2 细节**未能核实**（README 未完整抓取到平台矩阵） | MIT（API `license`） | 作为“Web 技术栈 UI”参考/备选，不等同原生自绘 GPU UI | 非自绘渲染路线，与 Tessell 若走自研渲染栈目标差异大；项目很新、生态验证不足 |
| 同类框架/工具 | crystal-imgui (Dear ImGui bindings) | https://github.com/oprypin/crystal-imgui | `pushed_at`: 2025-11-23T11:23:17Z, `updated_at`: 2026-08-27T15:43:36Z, stars 75, open issues 0 | 需后端（OpenGL/SDL/GLFW 等）配合；Windows 可行性取决于后端绑定，**未能核实** | MIT（API `license`） | 可作为调试/工具 UI 候选（需选定渲染后端） | Immediate-mode UI，非通用应用框架；后端与字体/输入集成工作需自担 |
| 同类框架/GUI | CrymbleUI（Crystal 原生 GUI 框架） | https://github.com/wolfgang371/crymbleui | `pushed_at`: 2026-10-19T18:12:56Z, `updated_at`: 2026-10-24T13:51:43Z, stars 52, open issues 1 | README 声明 “Desktop apps with an SFML 3.0 backend, for Linux and Windows…”（README 已取证）；另有 Web/WASM 路线 | API `license: null` → **未能核实**（需查仓库 LICENSE） | 可作为同类实现与架构参考；若直接复用需验证 Windows+SFML3 依赖链 | 体量大、依赖 SFML3 后端；许可证字段缺失需确认；与 Tessell 目标的耦合/可裁剪性待评估 |

> 说明：star/fork/issue/push 日期均来自 2026-11-12 的 GitHub API 响应；未抓取到 README/许可证文件的细节标为“未能核实”。

## 2. GPU 与图形后端（Windows 重点）

| 主题 | 结论 | 证据/链接 | Windows 可达性与 M0 建议 |
|---|---|---|---|
| OpenGL / WGL | Windows 通过系统 `opengl32.dll` 提供 OpenGL 入口与 WGL 上下文机制；多数窗口库（GLFW/SDL/SFML/raylib）可在 Windows 创建 OpenGL 上下文。 | 事实性平台能力（**未在本次 web_fetch 中抓取权威文档 URL，未能核实细节版本**）；可用窗口绑定证据：raylib-cr README 声明 64-bit Windows 支持 https://github.com/sol-vin/raylib-cr ，sdl.cr https://github.com/ysbaddaden/sdl.cr ，crsfml https://github.com/oprypin/crsfml | **M0 在 Windows 推荐验证路径：OpenGL + WGL**。建议：选 `raylib-cr` 或 `sdl.cr/crsfml + OpenGL` 快速跑通“创建窗口→GL 上下文→清屏/绘制三角形→事件循环”最小样例；同时记录 GPU 驱动与实际 OpenGL 版本（`glGetString`）。 |
| Vulkan | Vulkan API 在 Windows 上可用但依赖 Vulkan Loader/ICD 与 GPU 驱动；并非系统默认必备能力。 | **未能核实本机 Vulkan runtime/驱动状态**（未执行系统探测）；通用性说明属平台常识，未附权威 URL | **按任务要求写明：在本机 Windows 环境下 Vulkan 路径视为不可达/未验证，不作为 M0 默认路径。** 若后续要验证，建议命令：`vulkaninfo --summary`（需安装 Vulkan SDK/工具）或检查 `vulkan-1.dll` 是否存在。 |
| Metal | Metal 为 Apple 平台图形 API，Windows 上不可用。 | 平台事实（**未附取证 URL**） | **按任务要求写明：Metal 在 Windows 不可达。** M0 不考虑 Metal；跨平台渲染抽象需将 Metal 限定为 macOS/iOS 后端。 |

**M0（Windows）替代验证路径建议（可执行优先级）：**
1. **OpenGL/WGL 路径（首选）**：用 `raylib-cr`（README 已给 Windows 安装步骤与 `C:\raylib`/`LIB`/`PATH`）或 `sdl.cr` 创建窗口并绘制，验证事件与渲染循环。
2. **软件渲染/CPU 2D 路径（兜底）**：若 GPU/驱动受限，先用 Cairo（`cairo-cr`）或框架内置软件光栅验证布局/文本/2D 管线，不阻塞上层架构。
3. **Vulkan（后续可选，非 M0 前置）**：仅在确认驱动与 SDK 后再做；建议核实命令 `where vulkan-1.dll`、`vulkaninfo --summary`。本次 **未能核实**。

## 3. 文本栈（HarfBuzz / FreeType）现状与 FFI 评估

| 候选 | 仓库/URL | 最近活跃度 | 许可证 | 可直接依赖? | 评估/风险 |
|---|---|---|---|---|---|
| harfbuzz.cr | https://github.com/hugopl/harfbuzz.cr | pushed 2025-08-05, stars 2（API） | MIT | 可能（轻量绑定） | 维护者与 `gtk4.cr` 同源，质量预期尚可但 **API 覆盖度未审计**；Windows 上安装/链接 HarfBuzz DLL **未能核实** |
| freetype.cr (watzon) | https://github.com/watzon/freetype.cr | pushed 2022-04-23, stars 7（API） | MIT | 低（停滞） | 久未维护，兼容性风险；Windows **未能核实** |
| freetype.cr (OrelSokolov) | https://github.com/OrelSokolov/freetype.cr | pushed 2026-10-13, stars 0（API） | 未声明（**未能核实**） | 低（实验性） | 活跃但新且无许可证/口碑证据；不建议直接用于核心链路 |

**无现成/覆盖不足时的 FFI 直绑工作量评估（经验估算，未实测）：**
- **FreeType 直绑（中等）**：核心字形加载/光栅（`FT_Init_FreeType`, `FT_New_Face`, `FT_Load_Glyph`, `FT_Render_Glyph`, bitmap 读取）约 1–2 周可出最小可用层；完善 hinting、subpixel、缓存与错误处理再 +1–2 周。Windows 需处理 `freetype.dll` 分发与 `@[Link]`。
- **HarfBuzz 直绑（中等偏高）**：基础 shaping（buffer/shape/获取 glyph infos & positions）1–2 周；与 FreeType 集成、复杂脚本/特性、fallback 与双向文本支持 2–4 周。依赖 HarfBuzz + 可能的 ICU/graphite 变体需评估。
- **结论**：文本栈若要求高质量排版（复杂脚本、ligature、fallback），直接复用成熟 C 库 + 自写薄 FFI/封装较现实；现成 Crystal 绑定可作参考但多为薄封装且 Windows 验证不足。

建议核实命令（未在本次执行）：
- `shards search harfbuzz` / `shards search freetype`（生态发现）
- 在候选仓库执行 `crystal spec` 或编译示例（需先安装对应 native libs）

## 4. 2D 渲染/光栅绑定现状

| 候选 | 仓库/URL | 最近活跃度 | 许可证 | 结论 |
|---|---|---|---|---|
| Skia | 搜索无现成 Crystal 绑定（`q=skia+crystal+binding`, total_count 0） https://api.github.com/search/repositories?q=skia+crystal+binding | N/A | N/A | **无现成可直接依赖绑定（基于搜索证据）**；自建绑定+构建 Skia（尤其 Windows）成本高 |
| cairo-cr | https://github.com/TamasSzekeres/cairo-cr | pushed 2022-06-12, stars 33 | MIT | 有现成绑定，适合 2D 矢量/CPU 渲染验证；但维护较久远，Windows 链接 **未能核实** |
| NanoVG | 搜索无 Crystal 结果（`q=nanovg+language:crystal`, total_count 0） https://api.github.com/search/repositories?q=nanovg+language:crystal | N/A | N/A | **未发现现成绑定**；若走 OpenGL 2D UI，NanoVG C 库可考虑 FFI 直绑（中等工作量） |

## 5. 同类框架现状与差异（用于“不重复造轮子”论据）

| 项目 | 仓库/URL | 最近活跃度 | 支持平台（证据） | 许可证 | 结论/与 Tessell 关系 |
|---|---|---|---|---|---|
| GTK4.cr | https://github.com/hugopl/gtk4.cr | pushed 2025-09-05, updated 2026-10-09, stars 129（API）；README 含 macOS/Ubuntu/Fedora/MSYS2 依赖 | Linux/macOS 较顺畅；Windows 通过 MSYS2 路径，原生 MSVC/gnu toolchain 体验 **未能核实** | MIT | 成熟系统控件路线，适合快速桌面 UI；但依赖 GTK 运行时与分发较重，不同于自绘渲染引擎路线 |
| CrystKit | https://github.com/naqvis/crystkit | pushed 2026-11-10, updated 2026-11-11, stars 6（API） | 描述提及 WebView/多平台；具体 Windows(WebView2) 细节 **未能核实** | MIT | Web 技术栈壳（类 Electron/Tauri 思路），可参考桌面打包/IPC/能力模型；与自研渲染管线目标不同 |
| crystal-imgui | https://github.com/oprypin/crystal-imgui | pushed 2025-11-23, updated 2026-08-27, stars 75（API） | 依赖宿主渲染后端；平台跟随后端 | MIT | 适合工具面板/调试 UI，不作为最终用户 GUI 框架；可与 OpenGL/SDL 后端组合 |
| CrymbleUI | https://github.com/wolfgang371/crymbleui | pushed 2026-10-19, updated 2026-10-24, stars 52（API） | README 声明 “SFML 3.0 backend, for Linux and Windows” 且含 WebAssembly 路线 https://raw.githubusercontent.com/wolfgang371/crymbleui/main/README.md | **未能核实**（API license null） | 最接近“Crystal 原生 UI 框架”的参考对象之一；可借鉴布局/虚拟化/主题等实现，但依赖 SFML3 且许可需确认 |

> 架构文档 `architecture.md` 提及 CrymbleUI（任务书说明）：本仓库未找到 `architecture.md` 文件（本地检查 `docs/` 仅含 `naming.md`），因此 **无法核实第 79 行原文**；建议在仓库根或上级确认后补链。

## 6. Windows 上 Crystal 静态链接与 DLL 分发约束

**一句话结论：** Crystal 在 Windows（本机 `x86_64-w64-windows-gnu`）可生成原生可执行文件，但实际分发通常仍需随附所依赖的 C 运行库/第三方原生 DLL（如 SDL2、GLFW、SFML、Cairo、FreeType 等），并受链接器与各库提供的静态库形态限制，“完全静态单文件”往往不可直接达成。

**证据与现状：**
- 本机工具链：Crystal 1.22.1，target `x86_64-w64-windows-gnu`（本地 `crystal --version`，已核实）。
- 生态侧例证：`raylib-cr` README 明确 Windows 需设置 `LIB/PATH` 指向 `C:\raylib` 并提供安装脚本（https://raw.githubusercontent.com/sol-vin/raylib-cr/master/README.md），体现对外部原生库路径/二进制的依赖；并非零依赖分发。
- `sdl.cr` 通过 `shard.yml` 声明 `libSDL2` 等库依赖（https://github.com/ysbaddaden/sdl.cr ，`shard.yml` 已取证），运行期需可定位对应 DLL/导入库。
- 官方/通用静态链接策略细节（`--static` 在 Windows-gnu/MSVC 的支持边界、推荐分发方式）**本次未能核实**（未抓取到 Crystal 官方 Windows 打包文档页面）。

**建议核实命令：**
```powershell
crystal build src/your_app.cr --release
dumpbin /dependents .\your_app.exe   # 需 VS Developer Tools，查看 DLL 依赖
ldd .\your_app.exe                    # 若使用 MSYS2 环境
crystal build --help                  # 查看静态/链接相关选项在本平台可用性
```

## 7. 未能核实清单（需后续补证）

1. `architecture.md` 第 79 行关于 CrymbleUI 的原文与上下文：仓库中未找到该文件（本地检索）。
2. 各绑定在 **Windows + Crystal 1.22.1 (x86_64-w64-windows-gnu)** 下的实际编译/运行可行性：**未实测**。
3. sdl.cr、CrymbleUI、OrelSokolov/freetype.cr 的明确许可证文本：GitHub API `license` 字段为空或 README 未含，需打开仓库 LICENSE 文件确认。
4. 本机 OpenGL 版本/驱动能力、是否安装 Vulkan runtime（`vulkan-1.dll`/`vulkaninfo`）：**未实测**。
5. GTK4.cr 在非 MSYS2 的 Windows 原生工具链下可用性：**未能核实**。
6. Skia/NanoVG 是否存在非 GitHub 主流索引可见的 Crystal 绑定：仅基于 GitHub API 搜索，**未穷尽**。
7. Crystal Windows 下官方推荐的静态链接与 DLL 打包最佳实践文档：**未抓取**。

## 8. 调研结论摘要（面向路线图）

- **窗口/事件（Windows 优先）**：`raylib-cr`（Apache-2.0，近期活跃，README 明确 Windows 支持）是 M0 快速验证窗口+输入+基础渲染的稳妥候选；`sdl.cr`/`crsfml` 可作底层跨平台备选但需补许可证与 Windows 集成验证。
- **GPU（M0@Windows）**：按任务约束，**Vulkan/Metal 在 Windows 视为不可达/不作为 M0 路径**；采用 **OpenGL/WGL**（或框架封装的 GL 后端）做技术验证最现实，软件渲染作为兜底。
- **文本**：现成 Crystal 绑定零散且多为薄封装/维护不一（`harfbuzz.cr`、`freetype.cr` 多个变体）；高质量文本链路大概率需要 **直接 FFI 绑定 FreeType + HarfBuzz**（中等工作量）并自建整形/缓存层。
- **2D 光栅**：`cairo-cr` 有绑定可用作 CPU 2D；**Skia/NanoVG 无明显现成 Crystal 绑定**（搜索证据），若选用需自建 FFI 与构建/分发方案。
- **同类框架**：`GTK4.cr`（系统原生控件）、`CrystKit`（WebView）、`crystal-imgui`（即时模式工具 UI）、`CrymbleUI`（SFML 自绘框架）各代表不同路线，可作“不重复造轮子/借鉴实现”参考，但与自研渲染栈的契合度需按 Tessell 目标单独裁决。
- **构建/打包**：Windows 分发应预期 **原生 DLL 依赖管理**（随包携带或安装依赖），静态链接能力有限且需逐库验证。
