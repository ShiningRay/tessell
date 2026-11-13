# M4-WP2 打包与 DLL 依赖清单（实测证据）

> 状态：task-119 实测记录（未 commit）。新增 `tools/package.ps1`、
> `docs/evidence/M4-WP2-packaging.md` 与本地 `dist/tessell/` 产物；
> 未改 `src/`/`spec/`/`examples/`，未安装任何包。

## 1) 结论摘要
- 目标 example：`examples/m3_dpi_theme.cr`（M3-WP5 DPI/theme verify）。
- 构建：`crystal build examples/m3_dpi_theme.cr -o bin/pkg_probe.exe`
  （省略 `--release`，已记录）`EXIT=0`，3607653 B。
- objdump 导入表去重排序 20 个 DLL；msys2/ucrt64 可复制直接导入：
  `libfreetype-6.dll`、`libgc-1.dll`、`libharfbuzz-0.dll`、`libiconv-2.dll`。
- 裸 PATH（`C:\Windows\System32;C:\Windows`）跑原 exe：`EXIT=-1073741515`
  （`STATUS_DLL_NOT_FOUND`，loader 失败，无业务 token）。
- 打包 exe + 16 个 msys2 运行时 DLL（4 个 + 传递闭包）同目录后，裸 PATH
  跑 `--dpi=1.0 --frames=10 --verify`：`EXIT=0`，含 `j1_pass=true`、
  `j5_pass=true j5_j3_pass=true`、`verify=pass`。
- 删测 3 次（每次删 1 个再裸 PATH 跑）：删 `libintl-8.dll`、删
  `libgraphite2.dll`、删 `libiconv-2.dll` 均 `EXIT=-1073741515`；恢复后正常。
- `tools/package.ps1` 一键生成 `dist/tessell/`（exe+DLL+`MANIFEST.txt`）。
- `.gitignore` 仅含 `/bin/` 不含 dist；`git status` 显示 `?? dist/`，
  `dist/` 不得提交（需后续决定是否加入 `.gitignore`）。

## 2) 方法与环境
- 时间：2026-11-13 19:07:11 +08:00（构建/探测）；19:11:11 +08:00（gcc）
- Crystal：`Crystal 1.22.1 [23828b0a40] (2026-10-23)` x86_64-windows-msvc
  `C:\msys64\ucrt64\bin\crystal.exe`
- objdump：`C:\msys64\ucrt64\bin\objdump.exe`
- gcc：`gcc.exe (Rev6, Built by MSYS2 project) 16.2.0`
  `C:\msys64\ucrt64\bin\gcc.exe`
- OS：Windows，ucrt64；工作区含并行 M3/M4 WIP。

## 3) 逐步原始命令与关键输出

### 3.1 构建
```powershell
$env:PATH="C:\msys64\ucrt64\bin;$env:PATH"
crystal build examples/m3_dpi_theme.cr -o bin/pkg_probe.exe
"BUILD_EXIT=$LASTEXITCODE"; "SIZE=$((Get-Item bin/pkg_probe.exe).Length)"
```
输出：`BUILD_EXIT=0`，`SIZE=3607653`。未加 `--release`（控时，已记录）。

### 3.2 导入表（objdump -p）
```powershell
$env:PATH="C:\msys64\ucrt64\bin;$env:PATH"
& C:\msys64\ucrt64\bin\objdump.exe -p bin/pkg_probe.exe |
  Select-String 'DLL Name' |
  ForEach-Object { ($_ -replace '^\s*DLL Name:\s*','').Trim() } |
  Sort-Object -Unique
```
完整清单（去重排序，20 项）：
`ADVAPI32.dll`, `api-ms-win-crt-environment-l1-1-0.dll`,
`api-ms-win-crt-heap-l1-1-0.dll`, `api-ms-win-crt-locale-l1-1-0.dll`,
`api-ms-win-crt-math-l1-1-0.dll`, `api-ms-win-crt-private-l1-1-0.dll`,
`api-ms-win-crt-runtime-l1-1-0.dll`, `api-ms-win-crt-stdio-l1-1-0.dll`,
`api-ms-win-crt-string-l1-1-0.dll`, `GDI32.dll`, `KERNEL32.dll`,
`libfreetype-6.dll`, `libgc-1.dll`, `libharfbuzz-0.dll`,
`libiconv-2.dll`, `ntdll.dll`, `ole32.dll`, `OPENGL32.dll`,
`SHELL32.dll`, `USER32.dll`。

msys2/ucrt64 bin 存在：`libfreetype-6.dll`、`libharfbuzz-0.dll`、
`libgc-1.dll`、`libiconv-2.dll`；其余为系统/Windows CRT（ucrt64 bin 无同名）。

### 3.3 裸 PATH 运行（打包前，核心证据）
```powershell
$env:PATH="C:\Windows\System32;C:\Windows"
& (Resolve-Path bin/pkg_probe.exe).Path --dpi=1.0 --frames=10 --verify
"BARE_EXIT=$LASTEXITCODE"
```
输出：无 token 行，`BARE_EXIT=-1073741515`（`STATUS_DLL_NOT_FOUND`）。

### 3.4 传递依赖与打包后裸 PATH
- 对 4 个 msys2 DLL 做 objdump 传递闭包（排除系统与 `api-ms-win-*`）：
  新增 `libbrotlicommon.dll`、`libbrotlidec.dll`、`libbz2-1.dll`、
  `libgcc_s_seh-1.dll`、`libglib-2.0-0.dll`、`libgraphite2.dll`、
  `libintl-8.dll`、`libpcre2-8-0.dll`、`libpng16-16.dll`、
  `libstdc++-6.dll`、`libwinpthread-1.dll`、`zlib1.dll`。
  `DWrite.dll`/`USP10.dll` 出现于闭包但 ucrt64 bin 不存在，未复制 `[未验证]`。
- 放入 `dist\tessell/`（exe + 16 DLL）后裸 PATH 运行：
```powershell
$env:PATH="C:\Windows\System32;C:\Windows"
Set-Location dist\tessell
.\pkg_probe.exe --dpi=1.0 --frames=10 --verify
"BARE_CWD_EXIT=$LASTEXITCODE"
```
关键输出：
- `dpi_scale=1.00 ... corner_pixel_rgba=0xffffffff ... verify=pass`
- `dpi_scale=1.50 ... verify=pass`
- `dpi_scale=2.00 ... verify=pass`
- `J1 mono=true px10=1605 px15=3079 px20=5094 r15=1.918380 r20=3.173832 ...`
- `J1 ... r15_ok=true r20_ok=true j1_pass=true`
- `J5 dpi_scale=1.50 theme=dark diff_pixels=0 diff_A_vs_C=1180 ...`
- `J5 ... submitted_quads_dirty=4 submitted_quads_full=31 culled_quads=27 ...`
- `J5 ... corner_pixel_rgba=0x1e1e1eff ... j5_pass=true j5_j3_pass=true`
- `verify=pass`，`BARE_CWD_EXIT=0`
- 仓库根裸 PATH 跑 `dist\tessell\pkg_probe.exe ...` 同样 `BARE_DIST2_EXIT=0`。

## 4) 最小 DLL 集表（裸 PATH 成功）
来源均为 `C:\msys64\ucrt64\bin`（实测 `Get-FileHash SHA256`）。最终 dist：
`m3_dpi_theme.exe`（脚本产物）+ 16 DLL + `MANIFEST.txt`。

| 文件 | 字节数 | SHA256 前16 | 许可（上游） |
|---|---:|---|---|
| m3_dpi_theme.exe | 3607653 | 4b98a26a408f5eaf | 本仓构建产物 |
| libbrotlicommon.dll | 140697 | 7b0047dc16dd92a7 | MIT |
| libbrotlidec.dll | 60224 | c4c987a01597ddf9 | MIT |
| libbz2-1.dll | 107741 | 1790bf6473c9d48d | bzip2-1.0.6 |
| libfreetype-6.dll | 808305 | 19604dde573cbb8a | FTL/GPLv2+ 双许可 |
| libgc-1.dll | 182726 | 79d588f45c0fc2f5 | Boehm GC (MIT-like) |
| libgcc_s_seh-1.dll | 150537 | 791ebf66e99c7c1b | GPLv3+ runtime exc |
| libglib-2.0-0.dll | 1568604 | 3a1abec0184b238d | LGPL-2.1+ |
| libgraphite2.dll | 167857 | 93953e4744bcfce9 | LGPL-2.1+/MPL-1.1 |
| libharfbuzz-0.dll | 1892473 | f3bfe34ffac38f82 | MIT ("Old MIT") |
| libiconv-2.dll | 1141951 | 94ec68fb8d342b6c | LGPL-2.1+ (lib) |
| libintl-8.dll | 298164 | 0e5a178731e6be6d | LGPL-2.1+ |
| libpcre2-8-0.dll | 706022 | 1f609cde2ce432ef | BSD-3-Clause |
| libpng16-16.dll | 254777 | 28db7a8c6fcc579c | libpng/zlib |
| libstdc++-6.dll | 2659194 | 4e4822dc4aaa9938 | GPLv3+ runtime exc |
| libwinpthread-1.dll | 71836 | 6a5b2d360cd46dc3 | MIT/BSD (mingw-w64) |
| zlib1.dll | 121530 | 8ae7aeb0467763a1 | zlib |

许可为上游常见声明，**未逐包核对 msys2 PKGBUILD/COPYING** `[未验证]`；
分发前应以 `pacman -Qi`/包内 license 文件复核并随包附带。

## 5) 裸 PATH 前后对照
| 场景 | 命令环境 | 关键输出/退出码 |
|---|---|---|
| 打包前（bin/pkg_probe.exe） | 裸 PATH | 无 token，`EXIT=-1073741515` |
| 打包后（dist\tessell） | 裸 PATH，同目录 | `j1_pass=true`、`j5_pass=true`、`verify=pass`、`EXIT=0` |

删测（3 次，dist\tessell，裸 PATH，每次恢复）：
| 删除 DLL | 结果 | 结论 |
|---|---|---|
| libintl-8.dll | `EXIT=-1073741515` | 必需（传递依赖链） |
| libgraphite2.dll | `EXIT=-1073741515` | 必需（harfbuzz 链） |
| libiconv-2.dll | `EXIT=-1073741515` | 必需（exe 直接导入） |

## 6) 许可与字体（建议，不实现）
- freetype（`libfreetype-6.dll`）：FTL/GPLv2+ 双许可，可随包分发（选一许可、
  附版权与许可文本）`[未验证]` 具体随包文本。
- harfbuzz（`libharfbuzz-0.dll`）：MIT，可随包分发（保留版权与许可声明）。
- Windows 系统字体（如 msyh/seguiemj）**不可**随包分发；据
  `docs/research/font-fallback.md:47,49`（系统字体不可再分发/嵌入；Segoe UI
  Emoji 不可分发，发布用 OFL 彩色字体替代）。
- Noto 系列 SIL OFL 1.1 可分发（附 OFL 文本与版权声明，遵守 Reserved Font
  Name 约束；`docs/research/font-fallback.md:48,86-92`）。
- 用户缺字体建议：开发用系统字体映射；发布可选附带 OFL 字体（Noto Sans SC/
  Noto Color Emoji 等）并在 manifest/README 声明许可；若未打包字体则在运行
  说明中提示安装/指向系统字体或官方 OFL 下载来源（不内置下载逻辑）。

## 7) 打包脚本
- `tools/package.ps1`：参数 `-OutDir dist\tessell`、
  `-Example examples/m3_dpi_theme.cr`。
- 步骤：build→复制 exe→按 objdump 导入+传递闭包复制 msys2 DLL→写
  `MANIFEST.txt`（名/字节/SHA256）→打印汇总。用绝对路径调用
  `C:\msys64\ucrt64\bin\crystal.exe` 与 `objdump.exe`；构建时脚本内部临时
  加入 msys2 bin 以满足工具链；失败 `exit 1`。
- 验收运行：`powershell -File tools/package.ps1` → `PACKAGE_OK`、
  `dll_count=16`、`PKG_EXIT=0`；生成 `m3_dpi_theme.exe`+16 DLL+`MANIFEST.txt`。
  裸 PATH 运行 `dist\tessell\m3_dpi_theme.exe --dpi=1.0 --frames=10 --verify`
  → `verify=pass`，`BARE_EXE_EXIT=0`。
- `dist/`、`bin/` 产物不应提交；`.gitignore` 已忽略 `/bin/`，`dist/` 未忽略。

## 8) 已知限制与 [未验证]
- `[未验证]` 干净虚拟机/无 msys2 环境端到端验证未做（仅本机裸 PATH 验证）。
- `[未验证]` MSVC 目标/非 ucrt64 Crystal 产物 DLL 集未验证（本次 ucrt64）。
- `[未验证]` 未制作安装器（MSI/MSIX/Inno）与卸载/注册逻辑。
- `[未验证]` 未做代码签名（exe/DLL Authenticode）；SmartScreen/WDAC 未验证。
- `[未验证]` DWrite.dll/USP10.dll 在部分依赖导入中出现但 ucrt64 bin 无同名；
  本次运行成功，其运行时解析路径/可选性未逐项确认。
- `[未验证]` 各 DLL 许可文本未从 msys2 包 COPYING 提取随附（表为上游常见）。
- `[未验证]` `--release` 构建及其他 example 打包与 DLL 集差异。
- `[未验证]` 字体缺失时应用实际降级/提示行为（示例用 `msyh.ttc` 绝对路径）。