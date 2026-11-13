# M4-WP2 字体许可决策记录（D-C9）

- 状态：C9 决策记录（task-128）；只写本文件；未改 src/spec/examples/tools。
- 决策日期：2026-11-13；HEAD `5547fac`。

## 1. 决策 D-C9

- **不随包分发任何 Windows 系统字体**（`C:\Windows\Fonts\*` 不可再分发）；
  运行时依赖用户本机已装字体（`msyh.ttc`/`seguiemj.ttf` 等）[来源:
  docs/research/font-fallback.md:47,49]。
- 示例内字体路径硬编码 `C:/Windows/Fonts/msyh.ttc`
  （`examples/app_demo.cr`；缺字体时 `FtMeasurer.open` 失败）。

## 2. 替代方案（发布版推荐）

- 随包 `Noto Sans SC` / `Noto Serif SC`（SIL OFL 1.1，可分发）：须附 OFL
  文本与版权声明，保留 Font License/Notice；改名遵循 OFL 改名条款
  （不得使用 Reserved Font Name），不得单独售卖字体文件
  [来源: docs/research/font-fallback.md:48]。
- 本机已存在 `C:\Windows\Fonts\NotoSansSC-VF.ttf`（17773244 B）与
  `NotoSerifSC-VF.ttf`（25129160 B）[来源:
  docs/research/font-fallback.md:37-38]；OFL 全文 `https://scripts.sil.org/OFL`
  本机未下载核对 [未验证]（font-fallback.md:48,91）。

## 3. 依赖许可清单

| 依赖 | 许可 | 来源 |
|---|---|---|
| FreeType（`libfreetype-6.dll`） | FTL 或 GPLv2+ 双许可 | [M4-WP2-packaging.md:108,139](docs/evidence/M4-WP2-packaging.md) |
| HarfBuzz（`libharfbuzz-0.dll`） | MIT | [M4-WP2-packaging.md:113,141](docs/evidence/M4-WP2-packaging.md) |
| Crystal 标准库 + Boehm GC（`libgc-1.dll`） | MIT / MIT-like | [M4-WP2-packaging.md:109](docs/evidence/M4-WP2-packaging.md) |
| msys2 运行时 DLL（16 个最小集） | 各自许可，随 `MANIFEST.txt` 记录 | [M4-WP2-packaging.md:98-123](docs/evidence/M4-WP2-packaging.md) |

- 许可为上游常见声明，未逐包核对 msys2 PKGBUILD/COPYING `[未验证]`
  （M4-WP2-packaging.md:122-123）。

## 4. 项目本体

- `LICENSE` = MIT（首行 `MIT License`，Copyright (c) 2026 ShiningRay，
  共 21 行）。

## 5. 未验证（需后续人工/实测）

- OFL 全文是否需随二进制分发包内附 —— 法务判断，非技术可决。
- Noto VF 在 `GL_INTENSITY` 渲染路径下的一致性 —— 需实测对拍。
- 第三方 DLL 再分发条款逐项核对 —— 需按 msys2 包内 COPYING 复核。

## 6. 边界声明

- 本记录为技术侧决策留档，**不是法务审查结论**；分发前须完成上表
  `[未验证]` 项复核。
