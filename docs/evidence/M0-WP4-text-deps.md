# M0-WP4 文本依赖实证：FreeType/HarfBuzz 安装与 FFI 动态加载（W2-1 / task-8）

- 采集时间（本地）：2026-11-12 16:40:57 +08:00
- HEAD：`1b0d832220f3017e9efd6f42d59b5d7fab6b09f3`
- OS：`Microsoft Windows NT 10.0.26300.0`
- ARCH：`AMD64`
- Crystal：`C:\msys64\ucrt64\bin\crystal.exe`，`Crystal 1.22.1 [23828b0a40] (2026-10-23) LLVM 23.1.3 Default target x86_64-w64-windows-gnu`
- 任务：`task-8`「W2-1：安装 FreeType/HarfBuzz 并验证 FFI 动态加载」

## 1) pacman 定位与版本

命令：
```powershell
Get-Command pacman -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source; pacman --version 2>&1 | Select-Object -First 5; "EXITCODE=$LASTEXITCODE"
$paths = @('C:\msys64\usr\bin\pacman.exe','C:\msys64\mingw64\bin\pacman.exe','C:\msys64\ucrt64\bin\pacman.exe')
foreach($p in $paths){ "EXISTS $p = $(Test-Path $p)" }
```
原始结果（关键）：
- `Get-Command pacman`：未找到（PowerShell 报 `CommandNotFoundException`）。
- 路径探测：
  - `EXISTS C:\msys64\usr\bin\pacman.exe = True`
  - `EXISTS C:\msys64\mingw64\bin\pacman.exe = False`
  - `EXISTS C:\msys64\ucrt64\bin\pacman.exe = False`
- 结论：使用绝对路径 `C:\msys64\usr\bin\pacman.exe`。

## 2) 安装尝试（真实执行）

### 2.1 任务书包名尝试（失败，按指示记录完整错误链）

命令：
```powershell
& "C:\msys64\usr\bin\pacman.exe" -S --noconfirm mingw-w64-ucrt64-x86_64-freetype mingw-w64-ucrt64-x86_64-harfbuzz
```
退出码：`EXITCODE=1`

stderr/输出（关键错误）：
```
error: target not found: mingw-w64-ucrt64-x86_64-freetype
error: target not found: mingw-w64-ucrt64-x86_64-harfbuzz
```
（PowerShell NativeCommandError 包装上述 stderr）

### 2.2 同步数据库后重试同名（失败，EXITCODE=1）

命令：
```powershell
& "C:\msys64\usr\bin\pacman.exe" -Sy --noconfirm mingw-w64-ucrt64-x86_64-freetype mingw-w64-ucrt64-x86_64-harfbuzz
```
退出码：`EXITCODE=1`
关键结果：数据库同步成功（clangarm64/mingw32/mingw64/ucrt64/clang64 下载完成），但安装目标仍报：
```
error: target not found: mingw-w64-ucrt64-x86_64-freetype
error: target not found: mingw-w64-ucrt64-x86_64-harfbuzz
```

### 2.3 仓库搜索确认正确包名

命令：
```powershell
& "C:\msys64\usr\bin\pacman.exe" -Ss freetype | Select-Object -First 40
& "C:\msys64\usr\bin\pacman.exe" -Ss harfbuzz | Select-Object -First 40
& "C:\msys64\usr\bin\pacman.exe" -Sl ucrt64 | Select-String -Pattern "freetype|harfbuzz"
```
关键输出：
```
ucrt64/mingw-w64-ucrt-x86_64-freetype 2.15.0-1
    TrueType font rendering library (mingw-w64)
ucrt64/mingw-w64-ucrt-x86_64-harfbuzz 15.1.0-1
    OpenType text shaping engine (mingw-w64) (mingw-w64)
...
ucrt64 mingw-w64-ucrt-x86_64-freetype 2.15.0-1
ucrt64 mingw-w64-ucrt-x86_64-harfbuzz 15.1.0-1
ucrt64 mingw-w64-ucrt-x86_64-harfbuzz-cairo 15.1.0-1
ucrt64 mingw-w64-ucrt-x86_64-harfbuzz-docs 15.1.0-1
ucrt64 mingw-w64-ucrt-x86_64-harfbuzz-icu 15.1.0-1
ucrt64 mingw-w64-ucrt-x86_64-harfbuzz-utils 15.1.0-1
EXITCODE=0
```
结论：任务书示例包名后缀为 `ucrt64-x86_64`，本机仓库实际为 `ucrt-x86_64`（少一个 `64` 段），属包名不匹配；改用实际存在包名安装。

### 2.4 正确包名安装（成功）

命令：
```powershell
& "C:\msys64\usr\bin\pacman.exe" -S --noconfirm mingw-w64-ucrt-x86_64-freetype mingw-w64-ucrt-x86_64-harfbuzz
```
退出码：`EXITCODE=0`

关键输出（摘要）：
- 解析依赖并安装 18 个包（含依赖）：
  - `mingw-w64-ucrt-x86_64-brotli-1.2.1-1`, `mingw-w64-ucrt-x86_64-expat-2.10.0-1`, `mingw-w64-ucrt-x86_64-glib2-2.90.1-1`, `mingw-w64-ucrt-x86_64-graphite2-1.3.15-1`, `mingw-w64-ucrt-x86_64-libb2-0.98.1-3`, `mingw-w64-ucrt-x86_64-libpng-1.6.59-2`, `mingw-w64-ucrt-x86_64-libsystre-1.0.2-3`, `mingw-w64-ucrt-x86_64-libtre-0.9.0-2`, `mingw-w64-ucrt-x86_64-mpdecimal-4.0.1-3`, `mingw-w64-ucrt-x86_64-ncurses-6.6-4`, `mingw-w64-ucrt-x86_64-python-3.14.10-1`, `mingw-w64-ucrt-x86_64-python-packaging-26.3-1`, `mingw-w64-ucrt-x86_64-sqlite-3.54.1-2`, `mingw-w64-ucrt-x86_64-tcl-8.6.18-1`, `mingw-w64-ucrt-x86_64-tk-8.6.18-1`, `mingw-w64-ucrt-x86_64-xz-5.8.4-1`, `mingw-w64-ucrt-x86_64-freetype-2.15.0-1`, `mingw-w64-ucrt-x86_64-harfbuzz-15.1.0-1`
- 统计：`Total Download Size: 46.24 MiB`，`Total Installed Size: 347.29 MiB`
- stderr 警告（非致命）：
```
warning: dependency cycle detected:
warning: mingw-w64-ucrt-x86_64-harfbuzz will be installed before its mingw-w64-ucrt-x86_64-freetype dependency
```
- 过程含各包下载进度与 `installing ...` 成功输出，最终 `EXITCODE=0`。

## 3) 版本、DLL 路径与依赖闭包

命令：
```powershell
& "C:\msys64\usr\bin\pacman.exe" -Q mingw-w64-ucrt-x86_64-freetype mingw-w64-ucrt-x86_64-harfbuzz
Get-ChildItem "C:\msys64\ucrt64\bin\libfreetype*.dll","C:\msys64\ucrt64\bin\libharfbuzz*.dll" | Select-Object FullName,Length,LastWriteTime
& "C:\msys64\ucrt64\bin\objdump.exe" -p "C:\msys64\ucrt64\bin\libfreetype-6.dll" | Select-String "DLL Name"
& "C:\msys64\ucrt64\bin\objdump.exe" -p "C:\msys64\ucrt64\bin\libharfbuzz-0.dll" | Select-String "DLL Name"
```
原始输出：
```
mingw-w64-ucrt-x86_64-freetype 2.15.0-1
mingw-w64-ucrt-x86_64-harfbuzz 15.1.0-1
Q_EXIT=0

FullName                                        Length LastWriteTime      
--------                                        ------ -------------      
C:\msys64\ucrt64\bin\libfreetype-6.dll          808305 2026/10/14 15:08:38
C:\msys64\ucrt64\bin\libharfbuzz-0.dll         1892473 2026/11/5 7:34:59  
C:\msys64\ucrt64\bin\libharfbuzz-gobject-0.dll   94276 2026/11/5 7:34:59  
C:\msys64\ucrt64\bin\libharfbuzz-raster-0.dll   131445 2026/11/5 7:34:59  
C:\msys64\ucrt64\bin\libharfbuzz-subset-0.dll  2763827 2026/11/5 7:34:59  
C:\msys64\ucrt64\bin\libharfbuzz-vector-0.dll   239477 2026/11/5 7:34:59  

OBJDUMP_EXISTS=True
---libfreetype deps---
	DLL Name: KERNEL32.dll
	DLL Name: api-ms-win-crt-convert-l1-1-0.dll
	DLL Name: api-ms-win-crt-environment-l1-1-0.dll
	DLL Name: api-ms-win-crt-heap-l1-1-0.dll
	DLL Name: api-ms-win-crt-private-l1-1-0.dll
	DLL Name: api-ms-win-crt-runtime-l1-1-0.dll
	DLL Name: api-ms-win-crt-stdio-l1-1-0.dll
	DLL Name: api-ms-win-crt-string-l1-1-0.dll
	DLL Name: api-ms-win-crt-utility-l1-1-0.dll
	DLL Name: libbrotlidec.dll
	DLL Name: libbz2-1.dll
	DLL Name: libharfbuzz-0.dll
	DLL Name: libpng16-16.dll
	DLL Name: zlib1.dll
---libharfbuzz deps---
	DLL Name: DWrite.dll
	DLL Name: libgcc_s_seh-1.dll
	DLL Name: GDI32.dll
	DLL Name: KERNEL32.dll
	DLL Name: api-ms-win-crt-convert-l1-1-0.dll
	DLL Name: api-ms-win-crt-environment-l1-1-0.dll
	DLL Name: api-ms-win-crt-filesystem-l1-1-0.dll
	DLL Name: api-ms-win-crt-heap-l1-1-0.dll
	DLL Name: api-ms-win-crt-locale-l1-1-0.dll
	DLL Name: api-ms-win-crt-math-l1-1-0.dll
	DLL Name: api-ms-win-crt-private-l1-1-0.dll
	DLL Name: api-ms-win-crt-runtime-l1-1-0.dll
	DLL Name: api-ms-win-crt-stdio-l1-1-0.dll
	DLL Name: api-ms-win-crt-string-l1-1-0.dll
	DLL Name: api-ms-win-crt-utility-l1-1-0.dll
	DLL Name: RPCRT4.dll
	DLL Name: USER32.dll
	DLL Name: USP10.dll
	DLL Name: libfreetype-6.dll
	DLL Name: libglib-2.0-0.dll
	DLL Name: libgraphite2.dll
```

依赖闭包说明（基于 `objdump -p` 直接依赖）：`libfreetype-6.dll` 依赖 `libharfbuzz-0.dll`、`libbrotlidec.dll`、`libbz2-1.dll`、`libpng16-16.dll`、`zlib1.dll` 及 UCRT/Kernel32；`libharfbuzz-0.dll` 依赖 `libfreetype-6.dll`、`libglib-2.0-0.dll`、`libgraphite2.dll`、`libgcc_s_seh-1.dll`、`DWrite.dll`、`GDI32.dll`、`USP10.dll`、`USER32.dll`、`RPCRT4.dll` 及 UCRT/Kernel32。两者存在循环依赖（与 pacman 警告一致）。传递依赖的完整闭包（如 glib/brotli/libintl/iconv 等间接 DLL）未逐一枚举。[未验证]

## 4) FFI 动态加载探针

文件：`examples/m0_ffi_load.cr`（写入路径：`C:\Users\ShiningRay\projects\ShiningRay\tessell\examples\m0_ffi_load.cr`）

内容要点：`@[Link("freetype")]` 声明 `FT_Init_FreeType/FT_Done_FreeType/FT_Library_Version`；`@[Link("harfbuzz")]` 声明 `hb_version_string/hb_version`；真实调用并打印版本，任一失败 `exit 1`。

调试记录（真实）：
1. 首次运行 `crystal run examples/m0_ffi_load.cr`：`EXITCODE=1`，编译错误 `Error: argument 'alibrary' of 'LibFT#FT_Init_FreeType' must be Pointer(LibFT::FT_Library), not Pointer(Pointer(Void))`（修复：改为 `ft_library = uninitialized LibFT::FT_Library` 并 `pointerof(ft_library)`）。
2. 修复后重跑成功。

实测命令（验证）：
```powershell
$env:PATH = "C:\msys64\ucrt64\bin;" + $env:PATH
Push-Location "C:\Users\ShiningRay\projects\ShiningRay\tessell"
& "C:\msys64\ucrt64\bin\crystal.exe" run examples/m0_ffi_load.cr
"EXITCODE=$LASTEXITCODE"
Pop-Location
```
原始输出：
```
ft_init_ok=true
ft_library_version=2.15.0
hb_version_string=15.1.0
hb_version=15.1.0
EXITCODE=0
```
复验命令（再次运行）：
```powershell
$env:PATH = "C:\msys64\ucrt64\bin;" + $env:PATH
& "C:\msys64\ucrt64\bin\crystal.exe" run "C:\Users\ShiningRay\projects\ShiningRay\tessell\examples\m0_ffi_load.cr"
"VERIFY_EXIT=$LASTEXITCODE"
```
原始输出同上，`VERIFY_EXIT=0`。

## 5) 构建/分发含义

- 运行/链接依赖：`C:\msys64\ucrt64\bin\libfreetype-6.dll`、`C:\msys64\ucrt64\bin\libharfbuzz-0.dll` 及其 objdump 列出的直接依赖 DLL（含 `libglib-2.0-0.dll`、`libgraphite2.dll`、`libpng16-16.dll`、`libbrotlidec.dll`、`zlib1.dll`、`libbz2-1.dll`、`libgcc_s_seh-1.dll` 等）需在 PATH 或与可执行文件同目录。
- 本次实测通过 `PATH` 前置 `C:\msys64\ucrt64\bin` 保证动态加载解析；未将 DLL 复制到仓库。
- 分发影响：发布 `crystal build` 产物时需携带/安装上述 ucrt64 运行时 DLL 集合，否则在无 MSYS2 ucrt64 环境机器上可能因缺 DLL 失败。[未验证：未在干净环境实测最小分发 DLL 集合]

## 6) [未验证] 项

- `dumpbin /dependents` 未运行（未确认 Visual Studio 工具链可用）；仅用 `objdump -p`。
- 传递依赖闭包未完整展开（如 `libglib-2.0-0.dll`、`libbrotlidec.dll` 的再依赖）。
- 未在未设置 `C:\msys64\ucrt64\bin` 到 PATH 的环境下测试 `crystal run/build` 与最终 exe 的 DLL 解析行为。
- 未测试 mingw64 变体包与 ucrt64 包共存/冲突。
- 未验证静态链接（`-static`/静态库）可行性与许可证/分发影响。
- pacman 安装日志已包含完整关键退出码与错误；因输出极长，curl 下载进度细节未逐行全文抄录于本文，但安装最终 `EXITCODE=0` 与安装包清单已记录。

## 7) 结论

- **安装：成功**。通过 `C:\msys64\usr\bin\pacman.exe -S --noconfirm mingw-w64-ucrt-x86_64-freetype mingw-w64-ucrt-x86_64-harfbuzz` 安装 `freetype 2.15.0-1` 与 `harfbuzz 15.1.0-1`（ucrt64）。
- **FFI 动态加载：成功**。`examples/m0_ffi_load.cr` 实测 `EXITCODE=0`，输出 `ft_init_ok=true ft_library_version=2.15.0 hb_version_string=15.1.0 hb_version=15.1.0`。
- **阻塞解除（对 task-9 前置）**：DLL 与版本可用；后续文本探针运行需保证 `C:\msys64\ucrt64\bin` 在 PATH 或复制依赖 DLL。
- **异常记录**：任务书包名 `mingw-w64-ucrt64-x86_64-*` 在本机仓库不存在（EXITCODE=1），正确包名为 `mingw-w64-ucrt-x86_64-*`；已如实记录并以正确包名完成安装。
