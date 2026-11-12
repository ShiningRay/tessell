# M2 迭代 1 收口日志（M2-iter1）

## 迭代概览
- 迭代：M2-iter1
- 仓库：C:\Users\ShiningRay\projects\ShiningRay\tessell（HEAD=a74823b，origin/main 同步）
- 执行：gongbu-shangshu-2（工部尚书副手）
- 收口任务：task-44「M2 迭代 1 收口：提交并推送」

## 任务表
| 任务 | 状态 | 说明 |
|---|---|---|
| T39（输入/命中/焦点/路由） | 完成 | 输入事件、命中测试、焦点与路由；spec 数量 107→110 examples，全绿 |
| T40（font-fallback） | 完成 | `docs/research/font-fallback.md`（117 行） |
| T41（核验 PASS） | 完成（核验） | P3 六条核验通过，flake 0/20 不复现（`docs/evidence/verify-M2-WP1.md`） |
| T42（glyph-atlas） | 完成 | `docs/research/glyph-atlas.md`（108 行） |
| T43（PointerUp 清 pressed 修复 + 4 用例） | 完成（已由首辅复核并由本次执行者完成确认） | `src/tessell/input/router.cr:46-49` 修复；`spec/input_router_spec.cr` 覆盖相关用例；`crystal spec` 全绿 |

## 本机环境
- Crystal：1.22.1 [23828b0a40]
- 平台：Windows（ucrt64）
- PATH：需 `C:\msys64\ucrt64\bin`（执行前设置 `$env:PATH="C:\msys64\ucrt64\bin;$env:PATH"`）

## 验收数字（提交前自检）
- `crystal spec`：110 examples / 0 failures / 0 errors / 0 pending（SPEC_EXIT=0）
- `crystal build src/tessell.cr`：EXITCODE 0（构建产物 `tessell.exe` 已按流程删除）
- `crystal run tools/zero_alloc_frame.cr`（两场景 token）：static/paint1 alloc_bytes=0

## 未验证清单
- 真实 IME 组合
- 绝对坐标换算
- 冒泡/enabled 未实现
- glyph atlas 未实现
- GPU 上传未纳入 GC 窗口

## 已知缺口与后续
- M2-WP2 文本栈
- M2-WP3 IME
- M2-WP4 虚拟列表
- M2-WP5 a11y

## 提交信息
- 提交 1（feat）hash：17814ca9465eb1f3353bc689797392449fc7215d
- 提交 1（feat）短 hash：17814ca
- 提交 2（docs 回填）hash：见本次收口回报（HEAD / origin/main）
- 提交 2（docs 回填）短 hash：见本次收口回报
