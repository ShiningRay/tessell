# M3 平台可行性矩阵

- 任务：task-90
- 仓库：`C:\Users\ShiningRay\projects\ShiningRay\tessell`
- HEAD：`4cc928a`（2026-11-13）
- 本机：Windows 10/11（26300），Crystal 1.22.1 ucrt64，Intel Iris Xe，WGL/GL 4.6 兼容
- 证据：本文件 §1 + `docs/evidence/M3-env-baseline.md`（若需），`docs/research/m3-backends.md`（167 行）
- 规则：三态 = 本机可验证 / 不可验证（给证据）/ 需外部环境；`[未验证]` 附「需要什么才能验证」

## 1. 实测环境探针（只取关键行）

### 1.1 WSL

- 命令：`wsl --status` → `Default Distribution: Ubuntu`，`Default Version: 2`
- 命令：`wsl -l -v` → `Ubuntu  Stopped  2`，`docker-desktop  Running  2`
- 结论：WSL2 可用，Ubuntu 已装但 stopped；docker-desktop 也在 WSL2 中运行。[未验证] Ubuntu 启动与 apt install crystal 是否能跑通——需要 `wsl -d Ubuntu` 启动并实测 `crystal --version`。

### 1.2 Docker / Podman

- 命令：`docker version` → Client 29.8.2 windows/amd64，Server Docker Desktop 4.95.0 Engine 29.8.2
- 命令：`podman version` → `无法将 podman 项识别为 cmdlet`（不存在）
- 结论：Docker Desktop 可用（Linux 容器可跑）；Podman 不装。[未验证] Linux 容器内 Crystal 编译——需 `docker run crystallang/crystal:latest crystal --version`。

### 1.3 交叉编译链

- 命令：`Get-Command clang,gcc,ld.lld` → 仅 `gcc.exe C:\msys64\ucrt64\bin\gcc.exe`，clang/ld.lld 未找到
- 命令：`crystal env` → CRYSTAL_VERSION=1.22.1，CRYSTAL_EXEC_PATH=C:\msys64\ucrt64\bin
- 结论：本机有 ucrt64 gcc（Windows 原生），无 clang/ld.lld，无交叉编译链。[未验证] 是否能用 gcc 交叉编译 Linux 目标——需 `gcc -dumpmachine` 确认目标三元组与 sysroot。

### 1.4 虚拟化

- 命令：`systeminfo` → `Hyper-V Requirements: A hypervisor has been detected`；`Virtualization-based security: Running`
- 命令：`Get-ComputerInfo -Property HyperV*` → `HyperVisorPresent=True`
- 结论：Hypervisor 存在（Docker Desktop/WSL2 依赖），Hyper-V 要求字段未显示（已由 hypervisor 占用）。[未验证] 能否起独立 Linux VM——需 `Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V` 或 VirtualBox/VMware 可用性。

### 1.5 SSH 外部主机

- `~/.ssh/config`：存在，820B，含条目（未读内容，仅计大小）
- `~/.ssh/known_hosts`：存在，44 行
- `~/.ssh/` 目录：含 `id_ed25519_*`（5 把）、`id_rsa`（1 把）、`config`、`known_hosts`、`known_hosts.old`
- 结论：SSH 客户端可用，有已知主机记录与密钥对，**外部 mac/Linux 主机理论上可连**，但本 probe 未尝试连接（按任务书：不连接、不读私钥）。[未验证] mac/Linux 主机是否实际可达且 Crystal 已装——需 `ssh -o BatchMode=yes <host> "crystal --version"`（不读私钥，仅 BatchMode 探测）。

## 2. 逐 WP 判定表

| WP | 三态 | 验证方式 / 缺什么 | plan 应如何改写 |
|---|---|---|---|
| M3-WP1 后端抽象+脏矩形 | **本机可验证** | GL 4.6 兼容上下文已实证（m0_window_probe.cr）；脏区提交 via glScissor + readback 像素 diff；帧时间 via bench_scroll | 保留，设为 M3 首要 WP；验收口径见 §3 |
| M3-WP2 macOS 对齐 | **需外部环境** | 无 mac 本机；WSL/Docker 无法模拟 macOS；需 mac 主机或 CI runner | 改写为「No-Go（本机不可验证），解除条件：mac 主机或 macOS CI runner 可用 + Crystal 1.22.1 + GL/Metal 上下文」 |
| M3-WP3 Linux 后端 | **不可验证（本机缺 Linux GUI）** | WSL2 有 Ubuntu（stopped）但无 X11/Wayland 显示服务器；Docker 可跑 headless 但无 GL 上下文 | 改写为「本机不可验证，WSL2 Ubuntu 可做编译/单元测试，GUI 需 X11/Wayland 环境（WSLg 或真机）」；解除条件：WSLg 可用或真 Linux 机 |
| M3-WP4 stencil/cover | **本机可验证** | GL 4.6 支持 GL_STENCIL；Intel Iris Xe 已实证 GL 4.6 | 保留为可选 WP，标「可选，不阻塞核心 UI」 |
| M3-WP5 DPI/主题 | **本机可验证** | Windows DPI awareness API 可调；主题 token 为纯数据 | 保留；DPI 需 `SetProcessDpiAwareness` 实测（当前 m0_window_probe 未调用） |

## 3. M3-WP1 验收口径草案

### 3.1 后端抽象能力清单（从 gl_renderer.cr 反推）

- `init(hdc)` → 创建 GL 上下文、加载函数指针
- `resize(w, h)` → `glViewport` + 更新正交投影
- `begin_frame()` → `glClear` + `glOrtho(0,w,h,0,-1,1)` + blend/texture 状态
- `sync_atlas_textures(atlas)` → `glPixelStorei(GL_UNPACK_ALIGNMENT,1)` + `glTexImage2D` per page
- `draw_text(batch)` → `glBindTexture` + `glBegin(GL_QUADS)`/`glDrawArrays` per batch
- `end_frame()` → `glFlush`/`SwapBuffers`
- `delete_textures()` → `glDeleteTextures` + clear id 数组
- scissor 序列：`glEnable(GL_SCISSOR_TEST)` + `glScissor(x,y,w,h)` per dirty rect + `glDisable` after
- 纹理归属：`page_texture_ids` 由调用方管理（当前设计），RHI 可选下沉

### 3.2 脏区提交「可观测生效」判据

| 判据 | 表达式 | 建议阈值 | 来源 |
|---|---|---|---|
| 像素等价 | `readback_full == readback_scissor` 逐像素 diff==0 | diff==0（硬门） | m2_text_window.cr:357-364（±2 容差） |
| scissor 面积占比 | `scissor_area / viewport_area < T` | T=0.3（[未验证]） | m3-backends.md §2 |
| 帧时间不劣 | `p95_scissor <= p95_full * 1.05` | 5% 容差（[未验证]） | bench_scroll 实测 p95 193µs |
| 脏区合并正确 | `merge_into(max_regions=8)` 输出区域数 ≤8 且覆盖所有 dirty rect | ≤8 | dirty.cr:18 |

### 3.3 阈值标 [未验证] 说明

- T=0.3（scissor 面积占比）：需要什么才能验证——真实 UI 场景的脏区分布统计（滚动/输入/动画各 100 帧采样）
- p95 5% 容差：需要什么才能验证——bench_scroll 3 次复跑的 p95 方差（当前仅 1 次）
- diff==0 硬门：已部分验证（m2_text_window --verify pixel_match=true），但 scissor 路径未实测

## 4. 风险与替代方案

| # | 风险 | 若发生怎么办 |
|---|---|---|
| R1 | WSL2 Ubuntu 无 X11/Wayland 显示服务器，Linux GUI 不可验证 | 用 WSLg（Windows 11 22H2+）或真机；编译/单元测试仍可在 WSL2 headless 跑 |
| R2 | Docker Desktop 依赖 WSL2/Hyper-V，CI 环境可能无虚拟化 | 替代：GitHub Actions windows-latest runner + WSL2；或纯 ucrt64 gcc 交叉编译 |
| R3 | 无 clang/ld.lld，无法交叉编译 Linux 目标 | 用 WSL2 内部 gcc（`apt install build-essential`）；或 zig cc 作为替代交叉编译器 |
| R4 | macOS 无任何环境（无 mac、无 SSH 主机） | M3-WP2 标 No-Go；解除条件：mac 主机或 macOS CI runner；plan 改写为「外部环境不可得」 |
| R5 | Intel Iris Xe GL 4.6 兼容上下文非 core profile，shader 路径受限 | 当前 GL 1.1 固定管线已够用；core profile 需要 Intel 驱动更新或 NVIDIA/AMD 显卡 |
| R6 | DPI awareness 未在 m0_window_probe 调用，高 DPI 下坐标错位 | M3-WP5 增加 `SetProcessDpiAwareness` 调用；验收用 96/144/192 DPI 三档截图对比 |

## 5. 建议 plan.md M3 修订（具体行号）

| plan.md 行 | 当前 | 建议改为 |
|---|---|---|
| L254 M3-WP2 | `macOS 对齐 | ... | 4–7 | 环境不可得 [来源: ...; 待证据]` | `macOS 对齐 | No-Go（本机不可验证） | 解除条件：mac 主机或 macOS CI runner 可用 + Crystal 1.22.1 + GL/Metal 上下文 | 0（阻断）` |
| L255 M3-WP3 | `Linux 后端 | ... | 3–6 | 显示服务器差异 [待证据]` | `Linux 后端 | 本机不可验证（WSL2 无 X11/Wayland） | 编译/UT 可在 WSL2 Ubuntu 跑；GUI 需 WSLg 或真机 | 2–4（仅编译/UT）` |
| L253 M3-WP1 | `2–4 | 驱动差异 [来源: ...]` | `2–4 | GL 4.6 兼容上下文已实证（m0_window_probe.cr）；脏区提交 via glScissor+readback` |
| L256 M3-WP4 | `4–8 | 工期膨胀 [来源: ...]` | 保留可选，加「不阻塞核心 UI，Intel Iris Xe 已实证 GL 4.6」 |
| L257 M3-WP5 | `2–4 | 字体/渲染差异 [来源: ...]` | `2–4 | DPI：SetProcessDpiAwareness 未调用（[未验证]）；主题 token 为纯数据` |

## 6. [未验证] 清单

| 项 | 需要什么才能验证 |
|---|---|
| WSL2 Ubuntu 启动 + crystal --version | `wsl -d Ubuntu` 启动，`apt install crystal` 或下载 tarball |
| Docker 内 Crystal 编译 | `docker run crystallang/crystal:latest crystal --version` |
| gcc 交叉编译 Linux | `gcc -dumpmachine` + sysroot 配置 |
| 独立 Linux VM | Hyper-V/VMware/VirtualBox 可用性 + ISO |
| mac/Linux SSH 可达性 | `ssh -o BatchMode=yes <host> "crystal --version"`（不读私钥） |
| WSLg X11/Wayland 可用性 | `wsl -d Ubuntu` 后 `echo $DISPLAY` / `ls /mnt/wslg` |
| scissor 面积占比阈值 T=0.3 | 真实 UI 场景 100 帧脏区分布采样 |
| p95 5% 容差 | bench_scroll 3 次复跑 p95 方差 |
| GL core profile 可用性 | Intel 驱动更新或 NVIDIA/AMD 显卡 |

## 7. 结论

- M3-WP1（后端抽象+脏矩形）：本机可验证，建议优先做
- M3-WP2（macOS）：需外部环境，建议 No-Go 并记录解除条件
- M3-WP3（Linux）：不可验证（本机缺 X11/Wayland），WSL2 可做编译/UT
- M3-WP4（stencil/cover）：本机可验证，可选
- M3-WP5（DPI/主题）：本机可验证，DPI 需实测

(End of file)