# M2-WP2F 字体清单、回退链与分发许可风险（M-2）

> 状态：纯调研草案（未实现/未下载/未安装/未改码）。所有结论锚定本机路径、命令输出或 URL；未实测项显式标 `[未验证]`。
> 采集时间：2026-11-12 22:42:24 +08:00；HEAD=`a74823b7fefa551765232f3157bf3882f3ce6dfc`；本机 `C:\Windows\Fonts` 文件总数 391（`Get-ChildItem -File | Measure-Object`）。
> 任务锚点：`docs/plan.md:212`（M2-WP2F 字体获取/回退/许可确认，M-2）；`docs/plan.md:243`（字体获取/回退/许可确认）；`docs/architecture.md:155`（`MeasureKey` `(font_id,size,text_hash,max_width)`）；`docs/architecture.md:180,219`（CJK/Emoji/RTL/组合字为 M2 示例正确性目标）。
> 写入范围：仅 `docs/research/font-fallback.md`；未安装字体、未下载文件、未改代码/其他 docs、未 commit。

## 1) 目标字体族与用途（系统可用 vs 可分发作替代）

| 类别 | 系统可用（仅开发环境） | 可分发作替代（发布产物） | 说明 |
|---|---|---|---|
| UI 默认（拉丁） | `C:\Windows\Fonts\segoeui.ttf`（Segoe UI） | Noto Sans SC / Noto Sans（OFL）[未验证 下载] | 系统字体不可再分发；Noto 为 OFL 可分发替代。 |
| CJK 简体 | `C:\Windows\Fonts\msyh.ttc`（Microsoft YaHei） | `C:\Windows\Fonts\NotoSansSC-VF.ttf`（Noto Sans SC VF，OFL）[未验证 下载/版本] | 本机已有 Noto Sans SC-VF，但许可/版本未实测确认。 |
| CJK 繁体 | `C:\Windows\Fonts\msyh.ttc`（部分覆盖）/ `C:\Windows\Fonts\mingliub.ttc` | Noto Sans TC / Noto Serif TC（OFL）[未验证] | 本机未列 Noto Sans TC；繁体覆盖需逐字验证。 |
| Emoji（彩色） | `C:\Windows\Fonts\seguiemj.ttf`（Segoe UI Emoji，COLR/CPAL） | Noto Color Emoji（COLRv0/CBDT-CBLC）[未验证 可获取] | 本机 `C:\Windows\Fonts` 无 NotoColorEmoji；Segoe UI Emoji 不可分发。 |
| 等宽 | `C:\Windows\Fonts\consola.ttf`（Consolas） | Noto Sans Mono / Source Code Pro（OFL）[未验证] | 本机有 `SourceCodePro-Regular.ttf`（OFL，可作等宽替代候选；非 Noto）。 |

## 2) 本机实测清单（C:\Windows\Fonts，15/15 命中）

命令：`Get-ChildItem C:\Windows\Fonts -File`；`python` 解析 TTF/TTC 表目录（`ttcf` 头→offset→numTables→tag）。`fc-query`/`fc-list`/`otfinfo`/`ttx` 均 NOT FOUND；`fontTools` 未安装（`ModuleNotFoundError: No module named 'fontTools'`）→ GSUB/GPOS 以外更细粒度语言覆盖/字符覆盖 `[未验证]`。

| 文件 | 字节 | 格式 | 集合内字体数 | GSUB | GPOS | 彩色表 | VF 表 | nameID1/2/4/6（name 表，platformID=3） |
|---|---:|---|---:|---|---|---|---|---|
| msyh.ttc | 19704352 | ttc | 2 | true | true | none | none | Microsoft YaHei / Normal / Microsoft YaHei / MicrosoftYaHei |
| msyhbd.ttc | 16883552 | ttc | 2 | true | true | none | none | Microsoft YaHei / Negreta / Microsoft YaHei Negreta / MicrosoftYaHei-Bold |
| msyhl.ttc | 12189612 | ttc | 2 | true | true | none | none | Microsoft YaHei Light / Regular / Microsoft YaHei Light / MicrosoftYaHeiLight（nameID16=Microsoft YaHei, 17=Light） |
| simsun.ttc | 18316748 | ttc | 2 | true | false | none | none | SimSun / Regular / SimSun / SimSun |
| simhei.ttf | 9745792 | ttf | 1 | true | true | none | none | SimHei / Normal / SimHei / SimHei |
| simkai.ttf | 11779732 | ttf | 1 | true | false | none | none | KaiTi / Normal / KaiTi / KaiTi |
| simfang.ttf | 10570564 | ttf | 1 | true | false | none | none | FangSong / Normal / FangSong / FangSong |
| seguiemj.ttf | 12934920 | ttf | 1 | true | true | COLR,CPAL | none | Segoe UI Emoji / Normal / Segoe UI Emoji / SegoeUIEmoji |
| segoeui.ttf | 960076 | ttf | 1 | true | true | none | none | Segoe UI / Normal / Segoe UI / SegoeUI |
| tahoma.ttf | 919260 | ttf | 1 | true | true | none | none | Tahoma / Normal / Tahoma / Tahoma |
| arial.ttf | 1045720 | ttf | 1 | true | true | none | none | Arial / Normal / Arial / ArialMT |
| times.ttf | 1190736 | ttf | 1 | true | true | none | none | Times New Roman / Normal / Times New Roman / TimesNewRomanPSMT |
| consola.ttf | 453088 | ttf | 1 | true | true | none | none | Consolas / Regular / Consolas / Consolas |
| NotoSansSC-VF.ttf | 17773244 | ttf | 1 | true | true | none | fvar,STAT,gvar | Noto Sans SC / Regular / Noto Sans SC / NotoSansSC-Thin（nameID17=Thin） |
| NotoSerifSC-VF.ttf | 25129160 | ttf | 1 | true | true | none | fvar,STAT,gvar | Noto Serif SC / Regular / Noto Serif SC / NotoSerifSC-ExtraLight（nameID17=ExtraLight） |

- NotoColorEmoji 是否存在：**不存在**（`Get-ChildItem -Filter '*NotoColorEmoji*'` 计数 0；`*Noto*` 计数 2，仅上述 NotoSansSC-VF/NotoSerifSC-VF；`*emoji*` 计数 0）。
- `OS/2.fsSelection`：13 个静态字体为 `0x0040`（REGULAR 位）；msyhbd `0x0020`（BOLD 位）；msyhl `0x0100`（非 REGULAR/BOLD/ITALIC 位；语义按表原始值记录，不进一步断言 `[未验证]`）；两个 Noto VF 为 `0x0000`（VF 默认实例的 fsSelection 语义 `[未验证]`）。
- TTC 具体内嵌字体序号与各自 cmap 覆盖 `[未验证]`（仅解析到第 1 个 font 的表目录；ttc_index 提案见 §4）。
- 彩色 glyph：仅 seguiemj.ttf 实测含 COLR+CPAL；CBDT/CBLC/sbix 在 15 个目标文件中均未出现。Noto Color Emoji 是否提供 CBDT/COLR 版本 `[未验证]`（未下载）。

## 3) 许可与分发风险

- Windows 系统字体（msyh/simsun/simhei/simkai/simfang/segoeui/tahoma/arial/times/consola/seguiemj 等）随 Windows 许可，**不可再分发/不得嵌入发布产物**（任务书约束；具体 EULA 文本未逐字核对 `[未验证]`，以微软许可条款为准）。
- Noto 系列为 SIL Open Font License 1.1：**可分发**（含修改版），义务要点：随附 OFL 文本与版权声明；保留 Font License/Notice；修改后须改名（不得使用 Reserved Font Name）；不得单独售卖字体文件。OFL 全文 URL：`https://scripts.sil.org/OFL`（本机未下载核对 `[未验证]`）。
- Segoe UI Emoji（seguiemj.ttf）属 Windows 系统字体，**不可分发**；发布产物必须用 Noto Color Emoji 或其他 OFL 彩色字体替代。
- 两套策略与切换点：
  - 开发环境：`font_id → C:\Windows\Fonts\...` 直接映射（系统字体，丰富覆盖，零打包）。
  - 发布产物：`font_id → <app>/fonts/...` 映射（仅 OFL 字体：Noto Sans SC/Noto Serif SC/Noto Color Emoji/Noto Sans Mono，附 OFL 与版权文件）。
  - 切换点：构建/发布开关解析 `font_id` 时选择路径来源；运行时只读 `font_id`，不直接绑定绝对路径。

| font_id（开发） | 路径 | 来源 | font_id（发布） | 路径 | 来源 |
|---|---|---|---|---|---|
| segoe-ui | `C:\Windows\Fonts\segoeui.ttf` | Windows | noto-sans | `<app>/fonts/NotoSans-Regular.ttf` | OFL 下载 `[未验证]` |
| yahei | `C:\Windows\Fonts\msyh.ttc`（ttc_index=0） | Windows | noto-sans-sc | `<app>/fonts/NotoSansSC-VF.ttf` | OFL 下载 `[未验证]` |
| segoe-ui-emoji | `C:\Windows\Fonts\seguiemj.ttf` | Windows | noto-color-emoji | `<app>/fonts/NotoColorEmoji.ttf` | OFL 下载 `[未验证]` |
| consolas | `C:\Windows\Fonts\consola.ttf` | Windows | noto-sans-mono | `<app>/fonts/NotoSansMono-Regular.ttf` | OFL 下载 `[未验证]` |

## 4) 回退链提案与 chain 数据结构

按字符类别（`→` 表示逐级 fallback；括号为本机实测/可分发候选）：
- latin：Segoe UI → Tahoma → Arial → Noto Sans SC（系统/发布两套来源）。
- CJK 简体：Microsoft YaHei → SimSun → Noto Sans SC；繁体：Microsoft YaHei → MingLiU（mingliub.ttc，本机存在 37112128 字节 ttc）→ Noto Sans TC `[未验证 获取]`。
- emoji：Segoe UI Emoji → Noto Color Emoji `[未验证 获取]`；若均无彩色表（CBDT/COLR），按单色 glyph 渲染或 tofu。
- 缺失字符：记录 `codepoint/font_id/chain_pos` 与 tofu 事件；告警策略：首次缺失 warn + 聚合计数，不阻断布局（M2-WP2 评估是否升级）。

chain 数据结构（提案，非实现）：
```text
FontRef { path: String; ttc_index: Int; family: String; postscript_name: String; weight_axis: Float? }
FontChain { category: Symbol; entries: Array(FontRef) }   # 有序，font_id 稳定
FontSet { chains: Hash(Symbol, FontChain); font_id_of(ref): String }
resolve(codepoint): FontRef?   # 逐级 FT_Get_Char_Index>0；命中即返回并缓存
```
算法要点：每字符按 chain 顺序查 cmap/`FT_Get_Char_Index`；命中即停；未命中继续；全未命中返回 tofu 记录。缓存键 `(codepoint, font_set_version)`；失效：字体文件变更/替换、chain 配置变更、`font_id` 重算时清空对应条目。

## 5) 与 M2-WP2 接口草案（对齐 MeasureKey.font_id）

- `FontSet#resolve(codepoint : Int32) : FontRef?`：返回含 `path/ttc_index/family` 的 `FontRef`；调用方据此构造 `font_id`。
- `FontRef` 记录 `path`、`ttc_index`、`family`、可选 `weight_axis`；`font_id` 由 `FontRef` 派生（建议 `family|path|ttc_index|weight_axis` 的稳定字符串或哈希）。
- 与 `docs/architecture.md:155` 的 `MeasureKey(font_id,size,text_hash,max_width)` 对齐：measure/栅格只接收 `font_id`，由 `FontSet` 解析到 `FontRef`；缓存键沿用 `(font_id,size,text_hash,max_width)`，不把绝对路径直接暴露给 measure 缓存。
- 以上为接口草案，非实现；M2-WP2 开工前需与工部尚书实现对齐 `[未验证]`。

## 6) Noto 获取途径与校验步骤（仅列步骤，未执行）

- Noto Sans SC：`https://github.com/googlefonts/noto-cjk`（Sans/SubsetOTF/SC 或 Variable）；Google Fonts 页 `https://fonts.google.com/noto/specimen/Noto+Sans+SC`。
- Noto Serif SC：同仓 `noto-cjk` Serif/SC；Google Fonts `https://fonts.google.com/noto/specimen/Noto+Serif+SC`。
- Noto Color Emoji：`https://github.com/googlefonts/noto-emoji`；Google Fonts `https://fonts.google.com/noto/specimen/Noto+Color+Emoji`。
- OFL 文本：`https://scripts.sil.org/OFL`（或 Google Fonts OFL 副本 `https://raw.githubusercontent.com/google/fonts/main/OFL.txt`）。
- 下载后校验（执行前提：网络/授权；本机未执行）：① `certutil -hashfile <file> SHA256` 与官方发布页/`git` commit 校验值比对 `[未验证]`；② 用 `fc-query`/fontTools 验语言覆盖 `zh-hans`（需安装工具 `[未验证]`）；③ 解析表目录确认 GSUB/GPOS 与彩色表（CBDT/CBLC 或 COLR/CPAL）；④ VF 字体确认 fvar/STAT/gvar；⑤ 保留 LICENSE/OFL 与 copyright notice 于发布包。

## 7) 风险表

| 风险 | 影响 | 处置 |
|---|---|---|
| Windows 系统字体许可 | 随包分发违约 | 发布产物仅用 OFL 字体；开发/发布双映射 |
| Noto CJK 体积 | 包体积增大（本机 NotoSansSC-VF 17.8MB、NotoSerifSC-VF 25.1MB） | 子集化/按需加载 `[未验证]` |
| 彩色 emoji 渲染路径 | CBDT/COLR 需 FreeType 支持 | M2-WP2 评估；seguiemj 实测 COLR+CPAL，Noto Color Emoji 表结构未验证 |
| VF 变量字体支持 | 实例选择/轴值错误风险 | M2-WP2 评估 fvar/STAT；本机 Noto VF 仅确认表存在 |
| 字体缓存失效 | 文件替换/版本变更致脏读 | `font_set_version` 参与缓存键；变更即清空 |
| 语言覆盖/字符覆盖 | zh-hans/繁体/emoji 覆盖差异 | 下载后逐字验证；当前 `[未验证]` |

## 8) 命令输出锚点（摘要）

```text
> Get-ChildItem C:\Windows\Fonts -File | Measure-Object
Count: 391
> *Noto* 计数 2；*NotoColorEmoji* 计数 0；*emoji* 计数 0；15 目标文件全部存在
> python 解析表目录：msyh.ttc ttc/2/GSUB=true/GPOS=true/color=none/VF=none
  seguiemj.ttf ttf/1/GSUB=true/GPOS=true/color=COLR,CPAL/VF=none
  NotoSansSC-VF.ttf ttf/1/GSUB=true/GPOS=true/color=none/VF=fvar,STAT,gvar
  NotoSerifSC-VF.ttf ttf/1/GSUB=true/GPOS=true/color=none/VF=fvar,STAT,gvar
  simsun.ttc ttc/2/GSUB=true/GPOS=false；simkai.ttf/simfang.ttf GSUB=true/GPOS=false
> fc-query/fc-list/otfinfo/ttx NOT FOUND；fontTools ModuleNotFoundError
```
