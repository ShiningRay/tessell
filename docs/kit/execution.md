# Tessell Kit 执行记录

> 本文件只记录实际做了什么、验证了什么、还没验证什么。计划与范围见 [plan.md](plan.md)；未验证项不得因为本文件写了“完成”而消失。

## 环境口径

- 当前开发机：macOS arm64，Crystal 1.21.1（Homebrew），FreeType/HarfBuzz 库可加载但既有 Windows FFI 结构在本机不可安全用于真实字体渲染。
- 既有 M0–M4 的真实窗口证据来自 Windows + msys2 ucrt64；本机不能替代运行 `tools/gate.ps1`。
- Kit 的纯逻辑、声明、绘制命令、布局、输入与 a11y 测试可在 macOS 运行；真实 GL 上屏仍以 Windows 证据为准。

## K0 契约与纵向原型

状态：进行中。

计划交付：

- `docs/kit/plan.md`、`component-contract.md`、`design-tokens.md`、`repository-strategy.md`。
- 可选入口 `require "tessell/kit"` 与 `Tessell::Kit`；核心入口 `require "tessell"` 不加载 Kit。
- `Kit::Theme`、`Kit::Component`、`Kit::Painter`、`Kit::Context`、`Kit::Root` 最小契约。
- `Kit::Button` 纵向原型：measure → arrange → emit declarations → paint → input activation → a11y。
- `spec/kit/` 纯逻辑测试与可选入口测试。

退出条件：

- 核心入口不加载 Kit；`require "tessell/kit"` 可单独编译。
- Button 的指针、键盘、disabled、单次激活、声明与 a11y 有 spec。
- 记录未验证项，尤其是真实窗口与平台 a11y。

验证记录将在每轮结束时追加。

### 迭代记录

#### K0（本轮）

- 完成：`docs/kit/` 计划与契约文档；`src/tessell/kit.cr` 可选入口；Theme/token、Painter、Component、Context、Root、Button 最小闭环。
- 验证：`crystal spec spec/kit` → 19 examples / 0 failures；`crystal build src/tessell.cr --no-codegen` 通过；`crystal tool format --check` 通过。
- 未验证：真实窗口交互、GL 上屏、平台 a11y provider、Windows gate、完整 `crystal spec`（本机缺 Windows 字体）。
- 提交：`918e7f7`。
