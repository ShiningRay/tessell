# M0-WP4 依赖与字体路径调研（EX-W1-05，W2 前置）

## 元信息

- 任务：task-6「W2 前置调研：FreeType/HarfBuzz 依赖与 CJK/Emoji 字体路径（EX-W1-05）」
- 对应：`docs/plan-execution.md` EX-W1-05（W2-D1）、`docs/plan.md` M0-WP4 / M2-WP2F 前置
- 性质：仅调研与记录；**未安装、未下载、未改代码、未改 PATH、未改系统**
- 调研人：翰林院编修（hanlin-bianxiu）
- 采集时间（本地）：`2026-11-12 16:20:44 +08:00`
- 命令：`Get-Date -Format "yyyy-MM-dd HH:mm:ss zzz"; git rev-parse HEAD`
- repo HEAD：`981e7a9f0d401170472eb1e52d90b8338dc4d577`
- 工作目录：`C:\Users\ShiningRay\projects\ShiningRay\tessell`
- 边界：未动 `examples/`、`bin/`、`src/`、`spec/`、`shard.yml`、`docs/plan*.md`

## 1) FreeType / HarfBuzz 本机可用性

### 1.1 搜索 `*freetype*` / `*harfbuzz*`（含 lib*.dll）

- 命令（搜索）：
  - `Get-ChildItem -Path 'C:\msys64\ucrt64\bin','C:\msys64\mingw64\bin','C:\Windows\System32' -Filter '*freetype*' -ErrorAction SilentlyContinue | Select-Object FullName,Length,LastWriteTime | Format-Table -AutoSize`
  - `Get-ChildItem -Path 'C:\msys64\ucrt64\bin','C:\msys64\mingw64\bin','C:\Windows\System32' -Filter '*harfbuzz*' -ErrorAction SilentlyContinue | Select-Object FullName,Length,LastWriteTime | Format-Table -AutoSize`
  - `Get-ChildItem -Path 'C:\msys64\ucrt64\bin' -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'freetype|harfbuzz' } | Select-Object FullName,Length,LastWriteTime,VersionInfo | Format-List`
  - `Get-ChildItem -Path 'C:\Windows\System32' -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'freetype|harfbuzz' } | Select-Object FullName,Length,LastWriteTime | Format-Table -AutoSize`
- 路径存在性确认：
  - `Test-Path 'C:\msys64\ucrt64\bin'` → `True`
  - `Test-Path 'C:\msys64\mingw64\bin'` → `True`
- 结果（原始输出均为空，仅输出分隔/存在性）：

```text
---SEPARATOR---
(无 freetype/harfbuzz 匹配项)

---UCRT64-EXISTS---
True
---MINGW64-EXISTS---
True

(System32 freetype/harfbuzz 复查：无输出)
```

- 结论：在 `C:\msys64\ucrt64\bin`、`C:\msys64\mingw64\bin`、`C:\Windows\System32` 下**未发现** `*freetype*`、`*harfbuzz*`（含 lib*.dll 等）文件。
- 版本：不可得（无可执行/库文件可查询）。`[未验证]` 其他路径（如 `C:\msys64\usr\bin`、自定义安装目录、vcpkg/conan 前缀）是否存在 FreeType/HarfBuzz。

### 1.2 可安装途径（MSYS2 pacman，**未安装/未执行**）

若需在本机（ucrt64 工具链环境）提供 FreeType/HarfBuzz 供 FFI 链接/运行，常见 MSYS2 包名（**仅记录，未执行**）：

- FreeType：`mingw-w64-ucrt-x86_64-freetype`（ucrt64）；或 `mingw-w64-x86_64-freetype`（mingw64）
- HarfBuzz：`mingw-w64-ucrt-x86_64-harfbuzz`（ucrt64）；或 `mingw-w64-x86_64-harfbuzz`（mingw64）

最小安装命令示例（**未安装/未执行**，需在 MSYS2 环境且具备相应权限时方可运行；可能引入依赖包如 graphite2/icu/glib 等，具体依赖以 pacman 解析为准）：

```bash
# [未安装/未执行] 在 MSYS2 UCRT64 shell 中：
pacman -S mingw-w64-ucrt-x86_64-freetype mingw-w64-ucrt-x86_64-harfbuzz
```

影响（记录）：会向 MSYS2 前缀安装库与 DLL（通常位于对应 `bin/`、`lib/`、`include/`），并可能拉取传递依赖；运行时需确保 DLL 可被定位（PATH 或随应用分发）。本次未改 PATH、未改系统。

### 1.3 Crystal 侧绑定/链接方式（仓库现状）

- 命令：`Get-Content 'C:\Users\ShiningRay\projects\ShiningRay\tessell\shard.yml'`
- `shard.yml` 关键内容（原文摘录）：

```text
name: tessell
version: 0.1.0
...
crystal: ">= 1.21.0"
license: MIT
targets:
  tessell:
    main: src/tessell.cr
development_dependencies:
  # ameba:
  #   github: crystal-ameba/ameba
```

- 仓库根目录列表（`Get-ChildItem ...\tessell -Force`）含 `.git, bin, docs, examples, spec, src, .gitignore, LICENSE, README.md, shard.yml`；未见 `lib/` 条目。对 `lib/` 的探查命令 `Get-ChildItem ...\tessell\lib -Force -ErrorAction SilentlyContinue` 返回退出码 1（无可列内容/目录可能不存在）。`[未验证]` 其他位置是否存在本地 shard 或绑定代码。
- 结论：仓库内**未见**已声明的 FreeType/HarfBuzz Crystal shard 依赖（`shard.yml` 无 runtime dependencies），亦未见已落地的文本 FFI 绑定实现证据；**不得臆测**生态有可直接使用的绑定。若 W2 需探针，需自行编写 `lib`/`fun` FFI 或引入经审计的 shard（引入/安装行为超出本次调研范围）。

## 2) 字体清单（目标 CJK/Emoji）

### 2.1 `C:\Windows\Fonts` 目标文件存在性、路径与大小

- 命令：按模式 `msyh*`、`simsun*`、`simhei*`、`seguiemj.ttf`、`arial.ttf` 在 `C:\Windows\Fonts` 下 `Get-ChildItem ... | Select-Object FullName,Length,LastWriteTime`
- 输出（原文）：

```text
FullName                      Length LastWriteTime     
--------                      ------ -------------     
C:\Windows\Fonts\msyh.ttc   19704352 2025/3/29 18:53:39
C:\Windows\Fonts\msyhbd.ttc 16883552 2025/3/29 18:53:50
C:\Windows\Fonts\msyhl.ttc  12189612 2025/3/29 18:53:50

FullName                          Length LastWriteTime     
--------                          ------ -------------     
C:\Windows\Fonts\simsun.ttc     18316748 2026/3/30 7:32:55 
C:\Windows\Fonts\simsunb.ttf    21894056 2025/10/16 1:26:16
C:\Windows\Fonts\SimsunExtG.ttf  3549508 2025/10/16 1:26:16

FullName                     Length LastWriteTime    
--------                     ------ -------------    
C:\Windows\Fonts\simhei.ttf 9745792 2026/3/30 7:32:54

FullName                        Length LastWriteTime     
--------                        ------ -------------     
C:\Windows\Fonts\seguiemj.ttf 12934920 2026/9/11 16:28:42

FullName                    Length LastWriteTime     
--------                    ------ -------------     
C:\Windows\Fonts\arial.ttf 1045720 2026/6/14 13:47:36
```

| 目标 | 存在 | 路径 | 大小（bytes） | LastWriteTime |
|---|---|---|---:|---|
| 微软雅黑 `msyh*` | 是 | `C:\Windows\Fonts\msyh.ttc` | 19704352 | 2025/3/29 18:53:39 |
| 微软雅黑 `msyh*` | 是 | `C:\Windows\Fonts\msyhbd.ttc` | 16883552 | 2025/3/29 18:53:50 |
| 微软雅黑 `msyh*` | 是 | `C:\Windows\Fonts\msyhl.ttc` | 12189612 | 2025/3/29 18:53:50 |
| 宋体 `simsun*` | 是 | `C:\Windows\Fonts\simsun.ttc` | 18316748 | 2026/3/30 7:32:55 |
| 宋体 `simsun*` | 是 | `C:\Windows\Fonts\simsunb.ttf` | 21894056 | 2025/10/16 1:26:16 |
| 宋体扩展 `simsun*` | 是 | `C:\Windows\Fonts\SimsunExtG.ttf` | 3549508 | 2025/10/16 1:26:16 |
| 黑体 `simhei*` | 是 | `C:\Windows\Fonts\simhei.ttf` | 9745792 | 2026/3/30 7:32:54 |
| Segoe UI Emoji | 是 | `C:\Windows\Fonts\seguiemj.ttf` | 12934920 | 2026/9/11 16:28:42 |
| Arial | 是 | `C:\Windows\Fonts\arial.ttf` | 1045720 | 2026/6/14 13:47:36 |

### 2.2 开源替代字体（Noto 等）本机情况

- 命令：`Get-ChildItem -Path 'C:\Windows\Fonts' -Filter '*noto*' -ErrorAction SilentlyContinue | Select-Object FullName,Length,LastWriteTime`
- 输出：

```text
FullName                              Length LastWriteTime    
--------                              ------ -------------    
C:\Windows\Fonts\NotoSansSC-VF.ttf  17773244 2025/4/10 0:54:44
C:\Windows\Fonts\NotoSerifSC-VF.ttf 25129160 2025/4/10 0:54:45
```

- 发现：`NotoSansSC-VF.ttf`、`NotoSerifSC-VF.ttf` 已存在于 `C:\Windows\Fonts`。
- 未发现（本次 `*noto*` 搜索未命中）：`Noto Color Emoji` 等 Emoji 专用 Noto 字体。`[未验证]` 其他目录（如用户字体目录 `%LOCALAPPDATA%\Microsoft\Windows\Fonts`、自定义路径）是否已安装 Noto Color Emoji / Noto Sans CJK 完整家族。
- 许可与可再分发：Noto 字体通常采用 SIL Open Font License（OFL）等开源许可，但**具体文件的许可文本与再分发条件需核对随附 LICENSE/元数据**，本次未逐文件核实。`[未验证]` 本机已安装 Noto 字体文件的确切许可版本与再分发适用性。

## 3) 字体许可/可再分发风险与替代方案

- Windows 系统字体（如微软雅黑 msyh*、宋体 simsun*、黑体 simhei、Segoe UI Emoji seguiemj、Arial 等）通常受 Microsoft/相应权利方许可约束，**不可随应用一并再分发**（除非获得明确授权）。本次仅确认本机存在与路径，不构成再分发许可判断。
- 风险：若 W2/M2 文本渲染依赖上述系统字体路径，在目标用户机器上可能缺失特定字体或版本差异；分发应用时不可捆绑上述字体文件。
- 开源替代（候选，供后续 M2-WP2F 确认）：
  - CJK：Noto Sans CJK / Noto Serif CJK（本机已发现 `NotoSansSC-VF.ttf`、`NotoSerifSC-VF.ttf`；完整家族/其他字重/地区变体与许可 `[未验证]`）。
  - Emoji：Noto Color Emoji（本机 `C:\Windows\Fonts` 下 `*noto*` 未发现该文件；是否需获取及获取来源/版本 `[未验证]`）。
- 建议（记录）：M2-WP2F 需产出明确字体清单、回退链顺序与每个字体的许可证/再分发结论；本次仅提供本机事实与风险提示。

## 4) 阻塞与风险结论（W2 文本探针能否直接开始）

- **FreeType/HarfBuzz 原生库（DLL/可链接库）**：在 `C:\msys64\ucrt64\bin`、`C:\msys64\mingw64\bin`、`C:\Windows\System32` **未发现**。若 W2 探针 `examples/m0_text_probe.cr` 采用 `@[Link("freetype")]` / `@[Link("harfbuzz")]` 等 FFI 直连原生库，则在当前可见路径条件下**无法直接开始**（缺少运行/链接所需库文件或其路径配置）。`[未验证]` 其他目录是否可用。
- **Crystal 绑定**：仓库无 FreeType/HarfBuzz shard 依赖与已落地绑定；需自行实现或引入绑定代码（实现/引入工作不在本调研范围）。
- **字体资源**：目标 CJK/Emoji/Arial 系统字体在本机 `C:\Windows\Fonts` 均存在，可作为本机探针输入候选；但不可作为可再分发资产。Noto Sans/Serif SC VF 已存在；Noto Color Emoji 未在 `C:\Windows\Fonts` 发现（`[未验证]` 其他位置）。
- **结论**：W2 文本 FFI 探针（EX-W1-06）在**依赖就绪前**存在阻塞；建议先完成依赖安装/定位与最小 FFI 绑定路径决策后再实施探针。字体许可与回退链需在 M2-WP2F 前置/并行明确。

最小安装命令与影响（**不改系统，仅记录；未安装/未执行**）：

```bash
# MSYS2 UCRT64（示例，未执行）
pacman -S mingw-w64-ucrt64-x86_64-freetype mingw-w64-ucrt64-x86_64-harfbuzz
```

- 影响：安装 native 库/DLL 与头文件/导入库至 MSYS2 前缀；可能引入传递依赖；后续需确认 `crystal run/build` 的链接与运行时 DLL 查找路径。Harfbuzz 包变体（含/不含 ICU、subset 等）与所需 API 覆盖度 `[未验证]`。

## 5) 与 `docs/research/ecosystem.md` L43-L58、L111 对照

### L43-L58（文本栈 HarfBuzz/FreeType 现状与 FFI 评估）

| ecosystem.md 原文/要点 | 本次实测/结论 | 状态 |
|---|---|---|
| L47 harfbuzz.cr：Windows 上安装/链接 HarfBuzz DLL **未能核实** | 本机 `C:\msys64\ucrt64\bin`、`C:\msys64\mingw64\bin`、`C:\Windows\System32` **未发现** harfbuzz DLL/文件；其他路径/是否可安装后链接 `[未验证]`。harfbuzz.cr 绑定本身未安装/未审计。 | **部分实测补充**（指定路径未发现）/其余仍未核实 |
| L48 freetype.cr (watzon)：Windows **未能核实** | 指定路径未发现 freetype DLL/文件；绑定未安装/未审计。 | **部分实测补充**/仍未核实 |
| L49 freetype.cr (OrelSokolov)：许可证未声明、Windows **未能核实** | 指定路径未发现 freetype DLL/文件；绑定与许可证未本机核实。 | **未实测变更**（照抄限定：许可证/Windows 可用性仍未能核实） |
| L52 FreeType 直绑工作量估算（1–2 周最小可用层等），Windows 需处理 `freetype.dll` 分发与 `@[Link]` | 本机当前未具备可见 freetype.dll；分发/链接前提未满足。工作量估算属经验估算，本次未实测。 | **前提条件实测为否（当前环境）**；估算 `[未验证]` |
| L53 HarfBuzz 直绑工作量估算（1–2 周基础 shaping 等），依赖 HarfBuzz + 可能 ICU/graphite 需评估 | 本机当前未具备可见 harfbuzz DLL；依赖变体未评估。估算未实测。 | **前提条件实测为否**；估算 `[未验证]` |
| L57 建议核实命令 `shards search harfbuzz` / `shards search freetype`、编译示例需先安装 native libs | 本次未执行 `shards search`/安装/编译示例（遵守不安装、不下载）。 | `[未验证]`（照抄原限定） |
| L54/L58 结论性判断（现成绑定 Windows 验证不足；直接复用 C 库+自写薄 FFI 较现实） | 与本机“无原生库、无绑定依赖”现状相容，但未通过构建/运行验证。 | **未否定/未实证**（判断仍待探针验证） |

### L111（调研结论摘要 - 文本）

| ecosystem.md 原文（L111） | 本次实测/结论 | 状态 |
|---|---|---|
| “**文本**：现成 Crystal 绑定零散且多为薄封装/维护不一（`harfbuzz.cr`、`freetype.cr` 多个变体）；高质量文本链路大概率需要 **直接 FFI 绑定 FreeType + HarfBuzz**（中等工作量）并自建整形/缓存层。” | 本机未发现 FreeType/HarfBuzz 原生 DLL（ucrt64/mingw64/System32）；仓库 `shard.yml` 无相关依赖、无已落地绑定证据。该结论方向与本机前置条件缺失一致，但“绑定可用性/工作量/高质量链路”仍**未实测**。 | **部分条件确认**（本机缺原生库与绑定）；总体结论 `[未验证]` 待 W2 探针实测 |

### 照抄/保留的不确定项（原限定仍有效）

- 绑定 API 覆盖度、稳定性、与 Crystal 1.22.1/ucrt64 工具链兼容性：`[未验证]`
- Windows 上安装/链接 HarfBuzz/FreeType DLL 的完整可行路径（除本次已查路径外）：`[未验证]`
- 字体许可文本核验与可再分发结论：`[未验证]`
- CJK/Emoji 复杂文本（shaping/fallback/RTL/合字）实际渲染与测量效果：`[未验证]`

## 6) 关键结论摘要（供回报）

1. `C:\msys64\ucrt64\bin`、`C:\msys64\mingw64\bin`、`C:\Windows\System32` 均**未发现** `*freetype*` / `*harfbuzz*`（含 lib*.dll）；版本不可得。
2. MSYS2 可选安装包（记录，**未安装/未执行**）：`mingw-w64-ucrt64-x86_64-freetype`、`mingw-w64-ucrt64-x86_64-harfbuzz`（或 mingw64 对应包）；安装会引入库/DLL/可能传递依赖并影响链接与运行时查找。
3. Crystal 侧：`shard.yml` 无 FreeType/HarfBuzz runtime 依赖，仓库未见已落地绑定；不得臆测生态绑定可直接使用。
4. 目标字体均存在于 `C:\Windows\Fonts`：`msyh.ttc/msyhbd.ttc/msyhl.ttc`、`simsun.ttc/simsunb.ttf/SimsunExtG.ttf`、`simhei.ttf`、`seguiemj.ttf`、`arial.ttf`（路径/大小见 §2.1）。
5. 许可风险：Windows 系统字体不可随应用分发；开源替代本机已见 `NotoSansSC-VF.ttf`、`NotoSerifSC-VF.ttf`，但 `Noto Color Emoji` 未在 `C:\Windows\Fonts` 发现；具体许可/再分发与缺失字体获取 `[未验证]`。
6. W2 文本 FFI 探针在当前状态下**存在依赖阻塞**（缺原生库/绑定）；需先完成依赖就绪与 FFI 路径决策。ecosystem.md L47-L49/L52-L53 关于指定路径的“未核实”已获本机反证（未发现），但绑定可用性与工作量/效果仍 `[未验证]`。
