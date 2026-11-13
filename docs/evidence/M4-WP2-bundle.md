# M4-WP2 分发包证据（Bundle）

- 日期：2026-11-14；HEAD `75cb40d`；task-139。
- 0.1.0 时本包只含示例 exe（m3_dpi_theme），库本身以源码形式发布；0.2.0 见 §9。

## 1. 命令
```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/package.ps1 -Bundle
# 洁净解压验证（裸 PATH）
$zip='dist\tessell-0.1.0-win64.zip'; $tmp=Join-Path $env:TEMP 'tessell_bundle_check_<rnd>'
Expand-Archive $zip $tmp -Force
$env:PATH='C:\Windows\System32;C:\Windows'; Push-Location $tmp
cmd /c run.cmd --frames=20 --verify; $ec=$LASTEXITCODE; Pop-Location
Remove-Item -Recurse -Force $tmp
```

## 2. BUNDLE_OK（PKG_EXIT=0）
```
BUNDLE_OK zip=C:\Users\ShiningRay\projects\ShiningRay\tessell\dist\tessell-0.1.0-win64.zip zip_bytes=5729761 entries=20 dll_count=16 exe_bytes=3672821 sha256_zip=e0a32e39fd7d2c10df1da156f6d1f64483d35679ba522e11517daa0c0737589a
```

## 3. Zip 条目（前 10 / 总 20，5729761 B）
1. libbrotlicommon.dll
2. libbrotlidec.dll
3. libbz2-1.dll
4. libfreetype-6.dll
5. libgc-1.dll
6. libgcc_s_seh-1.dll
7. libglib-2.0-0.dll
8. libgraphite2.dll
9. libharfbuzz-0.dll
10. libiconv-2.dll
- 总数：20（含 16 DLL + exe + MANIFEST.txt + NOTICE.txt + run.cmd）。

## 4. MANIFEST 校验
- MANIFEST.txt 行数 19；逐行文件名均存在于 zip 内：MISSING=0。

## 5. 洁净解压裸 PATH 运行
- 解压到 `%TEMP%\tessell_bundle_check_4c5baf26`；`PATH=C:\Windows\System32;C:\Windows`
- 执行 `run.cmd --frames=20 --verify`，EXIT=0，临时目录已删除（TMP_REMOVED=True）。
```text
dpi_scale=1.00 theme_bg=0xffffffff theme_fg=0x000000ff text_pixels_nonbg=1605 corner_pixel_rgba=0xffffffff expected_bg=0xffffffff text_advance=71.554688 pen_end_x=91.554688 quads=27 batches=3 alloc_bytes=80 alloc_windows=[32,64,80] retried=false attempt=1 verify=pass
dpi_scale=1.50 theme_bg=0xffffffff theme_fg=0x000000ff text_pixels_nonbg=3079 corner_pixel_rgba=0xffffffff expected_bg=0xffffffff text_advance=107.332031 pen_end_x=137.332031 quads=27 batches=3 alloc_bytes=80 alloc_windows=[32,64,80] retried=false attempt=1 verify=pass
dpi_scale=2.00 theme_bg=0xffffffff theme_fg=0x000000ff text_pixels_nonbg=5094 corner_pixel_rgba=0xffffffff expected_bg=0xffffffff text_advance=143.109375 pen_end_x=183.109375 quads=27 batches=3 alloc_bytes=80 alloc_windows=[32,48,80] retried=false attempt=1 verify=pass
J1 mono=true px10=1605 px15=3079 px20=5094 r15=1.918380 r20=3.173832 r15_ok=true r20_ok=true j1_pass=true
J5 dpi_scale=1.50 theme=dark diff_pixels=0 diff_A_vs_C=1180 a_nonbg=3779 b_nonbg=3779 c_nonbg=3779 ac_loc=x=32 y=180 a=158,158,158,255 c=30,30,30,255 submitted_quads_dirty=4 submitted_quads_full=31 culled_quads=27 dirty_rects=1 corner_pixel_rgba=0x1e1e1eff expected_bg=0x1e1e1eff j5_pass=true j5_j3_pass=true
verify=pass
```

## 6. run.cmd 全文
```bat
@echo off
"%~dp0m3_dpi_theme.exe" %*
exit /b %ERRORLEVEL%
```

## 7. NOTICE.txt 全文
```text
Tessell distribution bundle

This package contains a sample executable and runtime DLLs only.
Tessell itself is distributed as source code in the repository.

Third-party runtime components (upstream license notices):
- FreeType (libfreetype): FTL / GPLv2+ (dual license)
- HarfBuzz (libharfbuzz): MIT
- Boehm GC (libgc): MIT-like
- msys2/ucrt64 runtime DLLs: licenses as provided by their upstream projects

Fonts: this bundle does NOT distribute any Windows system fonts.
At runtime the sample loads fonts installed on the user's machine.
See repository evidence: docs/evidence/M4-WP2-licensing.md
```

## 8. 未验证
- [未验证] 代码签名/Authenticode 未做（SmartScreen 可能拦截未签名 exe）。验证：SignTool 签名后复测。
- [未验证] 未制作 MSI/安装器与注册表/卸载项。验证：WiX/MSIX 打包并静默安装回归。
- [未验证] 未在干净 VM（无 msys2/ucrt64/dev 工具）实测。验证：新建 Win11 VM 裸 PATH 复跑。
- [未验证] SmartScreen/Defender 对 zip+exe 的信誉与误报。验证：上传样本与干净 VM 观察。

## 9. 0.2.0 重打包（3 个示例 + 洁净解压验证）

> §1–§8 是 0.1.0 的历史记录；当前分发包以本节为准。

- 基线 HEAD `cb4e4ec`；`tools/package.ps1 -Bundle` 循环构建 3 个 example，每个生成 `run_<name>.cmd`；`run.cmd` 保留并指向 `m3_dpi_theme.exe`（0.1.0 兼容）。
- 构建清单：`app_demo.exe` 4,018,412 B；`m3_dpi_theme.exe` 3,776,423 B；`m3_path_window.exe` 2,615,520 B；16 个 DLL；`MANIFEST.txt` 24 行；`NOTICE.txt`；`run.cmd` + 3 个 `run_*.cmd`。
- zip：`dist/tessell-0.2.0-win64.zip`，**7,757,194 B**，**25 entries**（3 exe + 16 DLL + 4 cmd + NOTICE + MANIFEST），SHA256 `625c2fc838a5698f4b639d016cfc07a3bfada8f4adcbad76ae21052a4d6bbc06`。
- 洁净解压：全新 `%TEMP%\tessell_pkg_verify_8338765e`；`PATH=C:\Windows\System32;C:\Windows`；三条均 EXIT 0，临时目录已删。

```text
# run_app_demo.cmd --frames=30 --verify
frames=30 rows=10000 row_h=20 viewport=800x688 list_viewport=800x600 theme=light dpi=1.0 text_size=16 visible_avg=30.0000 quads_dirty=159 quads_full=171 culled=12 diff_pixels=0 diff_A_vs_C=3113 diff_theme=0 diff_theme_roundtrip=0 alloc_windows=[0,0,0] retried=false attempt=1 scroll=0 a11y_nodes=34 verify=pass

# run_m3_dpi_theme.cmd --frames=20 --verify
J1 mono=true px10=1605 px15=3079 px20=5094 r15=1.918380 r20=3.173832 r15_ok=true r20_ok=true j1_pass=true
J5 dpi_scale=1.50 theme=dark diff_pixels=0 diff_A_vs_C=1180 a_nonbg=3779 b_nonbg=3779 c_nonbg=3779 ac_loc=x=32 y=180 a=158,158,158,255 c=30,30,30,255 submitted_quads_dirty=4 submitted_quads_full=31 culled_quads=27 dirty_rects=1 corner_pixel_rgba=0x1e1e1eff expected_bg=0x1e1e1eff j5_pass=true j5_j3_pass=true
verify=pass

# run_m3_path_window.cmd --frames=20 --verify
mode=stencil_cover stencil_bits=8 fill_pixels_gl=7794 fill_pixels_cpu=7794 star_pixels=7794 diff_pixels=0 star_offset_x=0.13 star_offset_y=0.29 star_vertices=5 frames=20 alloc_windows=[64,80,80] retried=false attempt=1 negative_holds=true verify=pass
```

- 与 0.1.0 差异：新增 `app_demo.exe`、`m3_path_window.exe`；zip 条目 20→25，字节 5,729,761→7,757,193；版本 0.1.0→0.2.0；新增 3 个 per-example `run_*.cmd`，`run.cmd` 保留兼容。
- [未验证] 未测 Windows 10、其它 GPU/驱动、远程桌面/虚拟显示器下的 3 个示例。
- [未验证] exe 未做代码签名/Authenticode；SmartScreen/Defender 信誉未测。
- [未验证] 未做 MSI/安装器、注册表/卸载项；未在无 msys2 的干净 VM 实测。
- [未验证] 未测其它 DPI/缩放、显示器色彩管理与多显示器截图位置。