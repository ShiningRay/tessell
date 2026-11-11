# Quartz

A retained-mode, declarative GUI framework for **Crystal**.

Quartz 的设计目标：用 Crystal 的表达力做可控渲染的原生桌面 UI，而不是再做一层 C toolkit 绑定。

## 为什么是这条路

- **Execution Contexts**（2026-07）让单个 fiber 独占系统线程，官方明确支持 GUI/game loop。UI 主循环跑在 `Isolated` context，业务留在默认 context，语言层面解决了主线程归属问题。
- **GC 决定 retained 优于 immediate**。Boehm GC 停等会把每帧全量重建变成掉帧，retained 树 + 脏重绘把稳态分配压到近零。
- **绑定路线没有空位**。GTK4.cr / CrystKit / crystal-imgui 已各占一位，且绑定时 Crystal 的编译期优势被 C 侧吸收。

架构与论证见 [docs/architecture.md](docs/architecture.md)。

## 状态

**早期设计阶段，不可用于生产。** M0 技术验证未完成。

## License

MIT
