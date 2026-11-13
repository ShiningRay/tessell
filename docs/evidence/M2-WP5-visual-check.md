# M2-WP5 真实窗口截图证据

- 日期：2026-11-14；HEAD `f7312f5`；范围：Windows 11 / WGL / GL1.1，真实窗口 `--verify`。
- 复核＝像素统计复核（lead，独立解码 PNG 统计饱和度/暗像素/角点像素）+ 用户可直接查看 PNG 复核；**无人眼 QA 签字，也不存在人眼观察记录**。结论仅限下列 PNG 的可见内容。

## 1. 证据链

- `tools/lib/shot.cr`（44 行）：`glFinish` → `glReadBuffer(GL_FRONT)` → `GL_PACK_ALIGNMENT=1` →
  `glReadPixels(RGBA)` → 垂直翻转 top-down → `TSRAW <w> <h> RGBA\n` + 像素。
- `examples/lib/shot.cr`（2 行）为 shim：`require "../../tools/lib/shot"`；保留。
- 5 个 example 均已 `require "./lib/shot"` 并解析 `--screenshot=`；保存点：
  `app_demo.cr:733,948`、`m2_text_window.cr:479,570,643`、`m3_path_window.cr:550`、
  `m3_dpi_theme.cr:495,646`、`m3_scroll_window.cr:630`；均在 `SwapBuffers` 之后。
- `tools/shot2png.ps1`（55 行）：读 TSRAW 头 → RGBA→BGRA → `Bitmap.LockBits` → PNG。

## 2. 六张图

| 文件 | 尺寸 | 字节 | 来源命令（均 EXIT 0） |
|---|---:|---:|---|
| `m2_text_hello.png` | 800×600 | 8,177 | `m2_text_window --frames=20 --verify` |
| `m2_emoji_color.png` | 800×600 | 9,217 | `m2_text_window --emoji-color --frames=20 --verify` |
| `m3_path_star.png` | 800×600 | 4,837 | `m3_path_window --frames=20 --verify` |
| `m3_dpi_dark.png` | 640×360 | 9,527 | `m3_dpi_theme --theme=dark --frames=20 --verify` |
| `app_demo.png` | 800×688 | 39,665 | `app_demo --frames=30 --verify` |
| `m3_scroll.png` | 800×600 | 35,772 | `m3_scroll_window --frames=20 --dy=20 --verify` |

- 合计 **107,195 B（104.7 KiB）**；单张最大 39,665 B；均 ≤220 KB/张、≤1.1 MB 合计。

## 3. 可见内容事实（逐张）

- `m2_text_hello.png`：`Hello 你好 Tessell` 完整、正立、白底黑字；无方块字/裁切/上下颠倒。
- `m2_emoji_color.png`：`😀👍` 为彩色（黄脸、竖大拇指），后接 `Hello 你好`；非灰阶、无黑块、正立。
- `m3_path_star.png`：红色五角星，中心白色五边形（even-odd 空洞）；不是矩形包围盒实心填充。
- `m3_dpi_dark.png`：深色背景（约 `#1e1e1e`），白字 `Hello DPI / Theme Token / MOVE / Scale Test`；正立、可读。
- `app_demo.png`：`Hello Tessell` + `Row 0`–`Row 29` 列表，底部 `theme=light dpi=1.0`；文字正立、未重叠。
- `m3_scroll.png`：`Row 1`–`Row 30` 可见，行距均匀；顶部标题已随 `dy=20` 滚出，无重叠/黑块。

## lead 复核（像素统计）

```
app_demo.png       800x688  sampled=137600 sat=0  dark=1452  bright=135540 corner=255,255,255 center=255,255,255
m2_emoji_color.png 800x600  sampled=120000 sat=309 avgSatRGB=245,171,75 dark=322  corner=255,255,255
m2_text_hello.png  800x600  sampled=120000 sat=0  dark=456   corner=255,255,255
m3_dpi_dark.png    640x360  sampled=57600  sat=0  dark=56977 bright=355 corner=30,30,30 center=30,30,30
m3_path_star.png   800x600  sampled=120000 sat=1936 avgSatRGB=255,0,0 dark=0  corner=255,255,255 center=255,255,255
m3_scroll.png      800x600  sampled=120000 sat=0  dark=1367  corner=255,255,255
```

`sat=0` 表示无彩色像素；`dark>0` 表示存在暗色文字像素。

## 4. 取帧与转换结论

- `GL_FRONT` + `SwapBuffers` 之后在 6/6 均取到非空画面；未出现黑屏，故未启用 `GL_BACK` 回退。
- 初版 `shot2png.ps1` 用 `StreamReader.ReadLine()` 读头，预读导致
  `short read at 1918995/1920000`；改为读 64 B 定位 LF 并 `$fs.Position=$lf+1` 后 6/6 成功。
- 截图段在 `--verify` 读回之后执行；未改变 verify 数字（见 §5）。

## 5. 自检

- `crystal spec`：`263 examples, 0 failures, 0 errors, 0 pending`，EXIT 0。
- `crystal build src/tessell.cr`：EXIT 0，产物 2,280,978 B，已删。
- `m3_path_window --frames=20 --verify`（无截图）：`fill_pixels_gl=7794 fill_pixels_cpu=7794 diff_pixels=0 verify=pass`，EXIT 0。
- `app_demo --frames=30 --verify`（无截图）：`diff_A_vs_C=3113 verify=pass`，EXIT 0。

## 6. [未验证]

- 2.0 DPI / 其它缩放下的文字清晰度（仅 1.5 dark 与 1.0 app 截图）。
- 真实显示器色彩管理 / HDR / 宽色域（PNG 无 ICC，像素统计/用户查看非校准）。
- 高对比主题与色盲可读性（仅一张 dark）。
- 窗口遮挡、交互缩放、多显示器下的截图位置。
- 真实 IME 键盘组合（截图不含交互）。

## 7. 交付状态

- 6 PNG + 本文 + shot 工具/example 开关已提交；提交 hash 见 `PROJECT-final-gate.md` r4；`src/**` 未改。
