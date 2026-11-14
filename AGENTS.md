# AGENTS.md — Tessell 仓库协作约束

给 AI 代理与新人的单文件约束集。先读 `docs/architecture.md` 与 `docs/plan.md`，
按里程碑顺序做；本文件只放"每天都用得上"的硬不变量与命令速查。
组件层契约详见 `docs/kit/component-contract.md`，示例宿主见 `examples/lib/kit_sdl_host.cr`。

## 硬不变量（全部可机械验证）

1. **核心不反向依赖 Kit**：`src/tessell.cr` 与 `src/tessell/**`（除 `kit/`）不得
   `require "kit"`。验证：`grep -rn "kit" src/tessell.cr`（kit.cr 自身除外）。
   Kit 是可选入口（`require "tessell/kit"`）。
2. **UI 循环必须在 Isolated ExecutionContext**：见 `src/tessell.cr:38-40`。
   新增任何线程/GL 交互前先读这条注释。
3. **组件不得读窗口/GPU/平台 API**：组件只经 `Context`（主题/度量/DPI/时间）与
   `Painter`（绘制原语）看外部世界；GL 只在 `src/tessell/render/gl/` 与宿主。
4. **键盘键唯一真相是 `Input::KeyCode`**：`Kit::Key` 是它的 alias（issue #27）；
   `F1` 被 Root 预留给帧调试 overlay。不许再造平行枚举或映射表。
5. **resize/DPI 变更不重建 Root**：窗口尺寸用 `root.layout(w, h)`，DPI 用
   `root.scale = v`。重建 Root 会丢焦点与编辑态，是最后手段（issue #30）。
6. **稳态热路径零分配**：布局/绘制循环内不 new Array、不用 each+block 闭包、
   不做字符串插值；做不到处挂 `TODO(M1-WP5)` 等编号并写明豁免理由。
   判据工具：`tools/zero_alloc_frame.cr`。
7. **证据标注 `path:line`**；未实测的结论标 `[未验证]`，不许写成已验证。
8. **golden/探针判据不许静默放宽**：提高 `--max-diff`、放宽计数断言阈值必须
   在提交信息与文档写明原因。
9. **每加一个持有资源的构造都要测释放**：GlyphAtlas/FtMeasurer/Backend/FontStack
   的 `close`/`dispose` 必须有对应 spec（对齐 asuka "每加一个产生 owner 的构造
   都要测 dispose"）。
10. **断言 op 流与计数，不用 wall-clock**：性能正确性用"measure 调用数/帧命令数/
    分配字节"表达（issue #36 口径）；帧时间分布只出现在人工 bench。
    **门禁看计数、优化看分布**：CI 门禁只跑计数 spec（spec/kit/
    counting_assertions_spec.cr、spec/layout_cached_spec.cr）与 zero_alloc 探针
    （判据 alloc_bytes ≤ 预热余量，见 tools/zero_alloc_frame.cr 文件头——
    余量存在的原因是 GC 探针粒度，不是给退化留后门）；bench_frame_time/
    bench_scroll 只做人工定位，其输出禁止写进门禁判据。
11. **平台行为拿不准先查 `docs/research/`** 既有结论（crystal-capabilities、
    m3-platform-matrix 等），再自己发明。

## 命令速查

Crystal 在 Windows 上位于 `C:\msys64\ucrt64\bin`（先 `PATH` 加入或用 `tools/gate.ps1`）。

| 意图 | 命令 | 通过判据 |
| --- | --- | --- |
| 全量 spec | `crystal spec` | 0 failures；Windows 无 Unix 字体时允许 6 个预存门控错误（font_stack/software_backend 文本/text_unix_smoke），macOS/Linux 全绿 |
| Kit 子集 | `crystal spec spec/kit` | 0 failures |
| 门禁聚合（Windows） | `pwsh tools/gate.ps1` | 全部 [PASS] |
| Kit gallery 自校验 | `crystal run examples/kit_gallery.cr -- --verify` | 输出含 `KIT_GALLERY_VERIFY verify=pass` |
| golden 像素对比 | `crystal run tools/golden.cr -- baseline.png current.png --max-diff 0` | 退出码 0 |
| TSRAW→PNG 转换 | `crystal run tools/golden.cr -- --convert shot.tsraw shot.png` | 生成 PNG |
| 示例截图 | `crystal run examples/app_calculator.cr -- --frames=2 --screenshot=shot.png` | 生成 PNG |
| 稳态零分配探针 | `crystal run tools/zero_alloc_frame.cr` | delta 字节符合文件头口径，不许凑 0 |
| 帧时间 bench（人工，不进门禁） | `crystal run tools/bench_frame_time.cr -- --frames=300 --warmup=30 [--steady] [--json]` | 分布输出；禁止用平均 FPS 下结论 |
| 滚动 bench | `crystal run tools/bench_scroll.cr` | 分布输出 |
| atlas 光栅契约验证 | `crystal run tools/atlas_raster_verify.cr` | 退出码 0，key=value 输出 |
| Kit 文档站 | `crystal run tools/build_kit_site.cr` | 生成 `site/kit/*.html` |
| API reference | `sh tools/gen_api_docs.sh` | 生成 `site/api/`（已 gitignore） |
| 组件库消费者验证 | `sh tools/kit_consumer_verify.sh` | 退出码 0 |

## Conventions

- 文档与代码注释中文为主；提交信息中文、Conventional Commits 前缀（feat/fix/docs/chore）。
- 一个 issue 一个提交：实现 + spec + 文档同步更新，push 后 issue 自动关闭
  （提交信息含 `Closes #NN`）。
- 断言优先级：op 流/计数 > 像素 golden（失败诊断附件）> wall-clock（仅人工 bench）。
- spec 平台门控：真实字体路径只在有字体的平台跑（Windows 用 `C:/Windows/Fonts`，
  macOS/Linux 用候选列表），条件不满足时打印 SKIP 说明后跳过，不用 `pending` 嵌套
  （Crystal 1.22 不允许 nested pending，会直接 error）。
- 新增组件步骤：Component 子类（measure/arrange/emit/paint）→ 组件契约 spec
  （键盘路径、指针路径、a11y 元数据）→ cookbook 若有新用法。
