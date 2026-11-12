# M1 迭代记录 W1（WP1/WP2）— 提交推送收口

## 范围

本轮迭代涵盖 M1 第一轮：M1-WP1 两遍布局内核 + M1-WP2 文本测量接口与缓存。
M0 门禁已裁定 PASS-WITH-CONDITIONS，M1-WP1 GO（docs/evidence/M0-gate.md）。

## T25 — M1-WP1：两遍布局内核

- 交付：`src/tessell/layout.cr`（206 行）、`spec/layout_spec.cr`（14 examples）
- 能力：Pass A measure（约束下行、尺寸上行）、Pass B arrange（主轴排列、Fixed/Auto/Fraction）；纯函数、无全局状态；注入 `Measurer` 可选参数
- 核验：docs/evidence/verify-M1-WP1.md（PASS）
- P3 观察：热路径 Array 缓冲待 M1-WP5 消除（TODO 标注）；margin 未参与计算；用例 2/3/7/8 留待后续
- 未验证：Margin 语义、零分配

## T27 — M1-WP2：文本测量接口与缓存

- 交付：`src/tessell/text/measurer.cr`（115 行）、`spec/text_measurer_spec.cr`（12 examples）
- 能力：Measurer 抽象、MeasureKey（FNV-1a 64 位，hash 返回 UInt64）、CachingMeasurer（hits/misses/evictions/invalidate_font/clear）、StubMeasurer（确定性桩）
- 契约：measure(font_id, size, text_hash, max_width) : Size；缓存 key (font_id, size, text_hash, max_width)
- 核验：docs/evidence/verify-M1-WP2.md（PASS）
- 修复记录：hash 返回类型 UInt64（lead 诊断：Crystal 1.22 Object#hash 返回 UInt64）
- 注入：layout.cr 新增 `measurer : Text::Measurer? = nil` 可选参数，默认 nil 等价原行为
- 未验证：真实 FreeType/HarfBuzz shaping（属 M2）

## T26 / T28 — 核验裁定

- T26 (verify-M1-WP1.md)：PASS — 纯函数性/两遍语义/手算 2 例均过
- T28 (verify-M1-WP2.md)：PASS — FNV-1a 正确性/缓存语义/布局注入兼容性

## 未验证清单

- 真实 FreeType/HarfBuzz shaping（M2-WP2F）
- Margin 语义（M1-WP3 或 M2）
- 零分配热路径（M1-WP5）
- GSUB 跨字体深度（M2）

## 自检结果

- `crystal spec`：30 examples, 0 failures, 0 errors, 0 pending（EXITCODE 0）
- `crystal build src/tessell.cr`：EXITCODE 0
- 根目录无 tessell.exe（已清理）
- `.gitignore` 含 `/*.exe`

## 提交 hash

- 主提交：bedc80b（feat(m1): 两遍布局内核与文本测量缓存（M1-WP1/WP2））
- 回填提交：（回填）