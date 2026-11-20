# Changelog

## 未发布

- bug 修复（#50–#53），对应外部消费者 troupe-chat / tessell-todo 的真机报告。
- 字体集合能力（#55）：.ttc 集合内按 sfnt family 选 face，多字面 CJK
  字体不再依赖应用硬编码 ttc_index。
- 测量缓存两层化（#56）：L2 宽度无关 shaping 缓存 + 分段 LRU + 
  shapes/reflows 计数，resize 期间不再整段重 shape。
- 弹性布局（#49）：Row/Column 子项 grow 权重（紧约束分享剩余主轴空间，
  Flutter Expanded 语义）与 Spacer 占位组件，「输入框占满剩余宽度 +
  固定宽度按钮」不再溢出。
- 布局正确性 oracle（#64）：受控 Taffy fixtures 子集（commit 1abd8ee，
  MIT）+ 本地文本测量用例，共 25 个——纯函数路径 pass=12 / known-fail=13
  （交叉轴 stretch 与溢出钳制两类语义缺口，原因逐条登记），
  缓存路径 25/25 与纯函数几何一致；豁免条目开始通过即强制报
  EXPIRED-KNOWN-FAIL 要求清除。
- 组合动画（#63）：Tessell::Anim 闭式采样（opacity/translate/scale）+
  manual clock + CompositeOnly 失效协议——稳态不重建声明、不重测文本，
  取消/替换/owner dispose/detach 全链路收口，reduced-motion、暂停/恢复、
  无动画停帧有 spec；布局动画不属于本协议（另立提交协议）。
- 跨平台纵向切片（#61，X0–X3）：测试字体按平台解析（X0）；SDL2 提升
  为可选平台宿主 `require "tessell/platform/sdl2"`，示例宿主改为装配
  （X1）；三平台 CI + Linux Xvfb 真实窗口 L1（X2）；Windows 真机
  SDL2 计算器/编辑器截图证据（X3）。支持矩阵按 L0–L3 更新，
  macOS L1 待真机、L2/L3 未开始，不宣称 IME/屏幕阅读器/打包完成。
- 增量重放 oracle（#58，NSGo 机制）：固定 seed 更新序列下增量树与
  从零重建的全量树逐节点比较——落地首轮抓到 CachedNode#update 只比较
  text 的真实漏标（尺寸/padding/gap 变化不标脏复用旧缓存），update
  改按完整布局语义标脏（Layout.semantically_same? 单一真相）；
  oracle 仅 spec 工具不改热路径与门禁语义。
- 帧分段观测（#60，借 NSGo 测量维度不借阈值）：App::PerfCollector
  五段（input/build/layout/paint/present）op+调用计数、帧粒度失效→
  呈现延迟、跨上下文 hop 计数；默认关闭零基线改变，p50/p95/p99 只进
  F1 overlay 与人工 bench 管道（AGENTS #10 口径不变），文档写明与
  NSGo 双线程模型数字不可直接比较。
- 用户操作测试驱动（#59，NSGo nsgotest 理念）：Kit::TestDriver 按
  a11y 元数据 selector 定位（歧义/无匹配/禁用/不可见全部带诊断失败），
  press/focus/type/key/scroll 有界推进（无 sleep）；同一 journey 定义
  FakeHost 管道与 Raw 直投（真实宿主）双后端一致，SDL2 真实窗口
  journey 附截图证据（spec/test_driver_spec.cr 7 例 +
  test_driver_sdl_spec.cr，无桌面环境 pending_skip 按平台分级）。
- 内置组件可覆写切面（#66）：Button/Checkbox/Input 抽 protected
  切面（resolve_colors/draw_background/draw_border/draw_focus_ring/
  draw_content/inside?/activate/toggle 等），骨架保证焦点环与
  disabled 分支、命中激活状态机与 emit key 契约；像素输出不变
  （全量 spec 与既有 PaintList op 断言零回归），契约文档列出
  每组件可覆写点清单（docs/kit/component-contract.md）。
- 第三方组件文档与脚手架（#67/#68）：docs/kit/extending.md 三条路径
  （组合/受控继承/自绘 leaf）+ 六个坑（各带 spec 锁）；
  distribution.md 分发约定（tessell-<name> 命名、shards ~> 约束、
  发布清单，不建 registry）；templates/kit-component 可运行模板
  （shard.yml + Badge 组件 + 契约 spec 五例）与
  tools/kit_template_verify.sh 一键验证（KIT_TEMPLATE_VERIFY
  verify=pass，exit 0）。

### Bug 修复
- **#55 .ttc 集合内选 face 缺失**：`SystemFonts` 只按文件名匹配，`FontStack.open`
  需要应用手工指定 `ttc_index`——NotoSansCJK/MS Gothic 类多字面集合默认
  index 0 很可能拿错字面（中文界面拿到日文 face）。现在把字体集合当容器：
  `FtMeasurer` 暴露 `num_faces` 与 `face_family(index)`（读 sfnt name 表，
  nameID 16 优先退 1；平台 0/3 按 UTF-16BE、平台 1 按 Latin-1 解码）；
  `SystemFonts.find_face(patterns, family:)` 文件名筛候选后集合内按 family
  匹配返回 `{path, ttc_index}`，未命中退回 index 0 并一次性 warning；
  `FontStack.open` entry 增加可选 `family: String?` 字段在文件集合内解析
  index（显式 ttc_index 通道不变）。spec/font_ttc_face_spec.cr：Windows
  msgothic.ttc 三字面（MS Gothic/MS UI Gothic/MS PGothic）验证 family 读取、
  find_face 解析、未命中回退与「同集合两 index advance 不同」；其他平台发现
  任意多字面 .ttc 断言同机制。

- **#56 测量缓存两层化：resize 期间整段重 shape**：旧 `CachingMeasurer`
  的键含 max_width——窗口每变 1px 就是一条新键，且满 8192 整体 `clear`
  （全有全无），拖拽 resize 时万行列表整段 re-shape、measure 调用数在
  resize 场景不稳定。重构为两层：L1 结果缓存按 font_id 分段 LRU（段上限
  2048、总量 8192），一次 resize 风暴只挤占该字体自己的段；L2 宽度无关
  shaping 缓存 `(font_id, size, text_hash) → ShapeRun`（advance 序列 +
  行高），宽度变化只重排断点（`reflows` 计数），不重 shape（`shapes`
  计数）。断行口径收敛到唯一来源 `Text.reflow_run`（`FtMeasurer#measure`
  与 L2 reflow 共用，几何一致有 spec 锁）；`shape_run` 是 Measurer 可选
  接口，桩/计数桩自动走全量路径。回归判据：
  spec/text_measure_l2_spec.cr（32 cluster 文本 320→360 连续 41 个宽度
  shapes==1、回到原宽度 L1 命中 shapes 增量 0、分段隔离、总量有界、
  FtMeasurer 缓存 reflow 与全量 measure 逐宽度相等）；门禁
  counting_assertions/layout_cached/zero_alloc 不回退。

- **#50 / #52 `draw_text` 批次区间算错**：`draw_text(batch_count, from_batch)` 的
- **#50 / #52 `draw_text` 批次区间算错**：`draw_text(batch_count, from_batch)` 的
  `batch_count` 是「本次提交的批数量」，实现却当排他结束索引用
  （`while i < batch_count`）。交错提交（issue #15 口径，`delta` + `before`）时
  第 2 条起的文本整段不提交——只有第一个文本命令可见。区间语义收敛到
  `Backend.text_batch_end(size, count, from)`：`[from_batch, min(from_batch+count, size))`，
  GLBackend 三处循环 + `total_quads`、SoftwareBackend `draw_quads` 全部改用它。
  端点加法先加宽到 Int64 再钳制（`from_batch + batch_count` 在极值下触发
  Int32 OverflowError）；SoftwareBackend `draw_text` 返回值改为本次调用增量
  （与 GLBackend 及 `Backend#draw_text` 契约一致，此前返回帧累计）。
  回归判据：spec/render_text_batch_window_spec.cr（SoftwareBackend 像素级，
  修复前第二段文本区域像素数为 0；含溢出边界与每次调用增量断言）。


- **#53 `Kit::Text#truncate` 输出 Builder 对象**：`"#{builder}#{ellipsis}"` 插值的是
  `String::Builder` 本身，截断文本渲染为 `#<String::Builder:0x…>…`；改为
  `builder.to_s + ellipsis`。附带修正截断/换行的测量口径——此前用默认 face
  测宽，与 `measure` 的 `font_id_for(@content, @weight)` 不一致，字重回退时
  「measure 放得下、paint 却截断」，现在两者同 face。spec 用 face 感知桩
  （非 0 font_id 宽度不同）锁住截断/换行走同一 face 的口径。

- **#51 运行期增删子组件不重排**：retained-mode 下 `add/remove` 只改命中树不
  arrange，新组件停在零 bounds（不可见、不可命中）。`Component#mark_structure_dirty`
  沿父链打标记，`Root#build` 消费后补一次 `layout`；结构未变化时不付重排成本。
  宿主不再需要 `on_frame` 里手动 `root.layout`。`For#items=` 直接替换 `@children`
  （不经 add/remove），键序变化（增/删/重排）同样打标；键序不变的值更新不打
  ——动态列表稳态不重排。

## 0.4.1 (2026-11-15)

三个真机回归缺陷修复（#45–#47），GitHub issue 保持清零。

### Bug 修复
- **#47 无时间戳时双击静默失效**：宿主不透传 `timestamp_ms`（默认 0）时
  Router 双击判定恒不成立且无任何信号。`timestamp_ms == 0` 现在解释为
  「平台未提供」——双击退化为**同目标 + 位移上限 + 同修饰键**；透传时间戳
  的宿主仍享受完整时间窗判定。usage.md 新增宿主事件契约节
  （`timestamp_ms` / `repeat` 透传为必需项）。
- **#46 GLBackend 帧统计被逐次 draw_text 清零**：交错提交（#15/#21 推荐
  写法）下 `submitted_quads` 只反映最后一次调用（实测 200 字形 quads=10）。
  三处逐调用清零移除——stats 与 `begin_frame` 重置对齐，帧内只累加；
  `draw_text` 返回值改为**本次调用增量**，「本次提交了多少」与
  stats「本帧累计」同时成立。
- **#45 GLBackend 缺外部纹理通道**：`Kit::Image` 在 GL 宿主上静默画不出。
  GLBackend 实现 create/update/destroy/resolved_texture_external（handle
  独立命名空间）与 `CmdKind::Image` 分支（straight-alpha blend 临时切换 +
  GL_MODULATE tint + v 轴翻转 UV）；`Kit::Image` 支持
  `ctx.supports_external_texture = false` 跳过绘制（a11y 仍报 Role::Image）。
  附带修复示例宿主三处编译错误（GLPainter#image 缺失、`frames` 残留、
  `bounds.x` 访问器）——v0.3.0 起示例集不可编译的问题就此解决。
  GL/SDL 运行路径本机编译验证，真机渲染 [未验证]。

## 0.4.0 (2026-11-15)

跟进项 #43 / #44 处置完成，GitHub issue 全部清零。

### Bug 修复
- **#43 重复 UiKey 挂死节点遍历**：同帧两组件共用 UiKey 曾使节点父链成环
  （`component_for_node` / HitTest / a11y 沿 parent 上溯无限挂死，编译期
  无法发现）。`UI.apply` 现在在任何 pool 变更前预检单帧 decl 缓冲内的
  重复 key，fail-fast `ArgumentError` 并点名修复方式（`key.child` 派生）；
  异常路径不留下半套 pool 状态；跨帧同 key 稳定复用（identity 语义）不受
  影响。`Container` 新增 `remove`（动态树 detach）。

### 新能力
- **#44 Signal 接入 Kit**：
  - 组件响应式作用域：`Component#signal_owner` 懒创建 + `watch`（创建即
    首跑，Solid 语义）；组件移出树时 Root 差分自动 `dispose`——signal 写
    不再触发已卸载组件（泄漏契约有 spec）。
  - 三级失效对接：signal 写 → effect 更新组件状态 → 下一帧 Root#build 的
    decl diff 自动产出 Layout/Paint 失效（复用既有失效体系，effect 不直连
    后端）；稳态帧计数与直连状态组件一致（#36 口径）；与 #42 重入守卫
    安全组合。
  - `Kit::For(T)` keyed 行复用：keyed 只 Set item/index 两个可写 signal，
    组件实例跨帧保留（行内状态不丢）；移除行 dispose；重复行 key 与 #43
    同性质 fail-fast。LIS 省略（retained 树每帧重 emit，重排 = 数组重排，
    无逐行移动成本），commit 有记录。

## 0.3.0 (2026-11-15)

asuka 对照调研立项的 #19–#42 共 24 个 GitHub issue 处置完成（逐一提交关闭）。
新增 Signal 响应式内核、外部纹理通道、布局增量层与平台宿主契约四大地基。

### Bug 修复
- **#27 键枚举漂移**：`Kit::Key` 收敛为 `Input::KeyCode` 的 alias（核心补
  `Unknown` 占位），删除 21 分支手工映射表；spec 遍历全量键断言透传。
  `F1` 保留给帧调试 overlay。
- **#26 Focus 事件永不投递**：`Event::Kind::Focus` 真正投递给组件（与窗口级
  Blur 对称）；投递顺序入契约并有 spec 锁住（转移 A→B：A 回调 false →
  B 收 Focus → B 回调 true）。
- **#25 Painter clip 语义不一致**：`PaintCmd` 增加 `clip` 字段，
  `PaintListPainter` 维护 clip 栈——两 Painter 的 headless 裁切断言等价。
- **#23 Theme 往返丢信息**：`to_render`/`from_render` 改全量映射
  （panel←surface、panel_alt←surface_raised、focus_ring←focus），
  surface 不再被 bg 覆盖；已知无损边界显式登记。
- **#22 sync_atlas_dirty 不在抽象上**：提升到 `Backend` 基类（默认退化为
  全量），宿主按抽象编程即可每帧增量同步，无需 GLBackend 强转。
- **#20 Kit::Event 丢输入语义**：增加 `click_count` / `timestamp_ms` /
  `repeat` / `drag_distance`，Root 透传 Router 判定结果；修饰键变化打断
  双击链。组件区分单击/双击不再自存时间戳。
- **#21 DrawList Text 命令丢文本**：`DrawCmd` 携带 `text` / `font_size`
  载荷 + `DrawList#text_commands` 只读视图；示例宿主删除平行 batch 边界
  数组，单遍按命令序提交。
- **#24 测量缓存无界**：两代淘汰（上限 4096），键含文本内容——正确性不
  依赖清空；增加 `text_cache_stats` 观测面；清空契约入 cookbook。
- **#19 三套行高口径**：`CoreTextMetrics#line_height` 与 FT metrics 同源；
  Kit 组件基线全部改 `text_metrics` 推导（删 `fs*0.1` / `top+fs` 经验式）。
  14px 文本在 32px 容器几何居中有 spec。
- **#30 DPI 变更只能重建 Root**：`Root#scale=` / `Context#scale=` 联动清
  测量缓存并重排——组件树、焦点、编辑态跨 DPI 保留。
- **（过程中发现）重复 UiKey 挂死节点遍历**：同 key 声明使节点父链成环，
  `Root#build` 无限挂起。已复现并登记 issue #43（修复跟进）。

### 新能力
- **#33 Signal(T) 响应式内核**（`Tessell::Signal`）：拉取式依赖收集——
  侵入式链表依赖图 + version 戳复用（稳态零分配）、两级脏标 push/pull、
  memo 惰性重算 + 相等截断、有界 flush（100 pass raise 点名肇事 effect）、
  render/user 双优先级、Owner 树 + effect 重跑前 clean()。六不变量 spec：
  菱形 glitch-free、动态依赖、dispose、重跑清理等 12 例。
- **#28 外部纹理通道**：`Backend` 新增 create/update/destroy_texture 与
  `resolved_texture_external`（handle 独立命名空间）；`CmdKind::Image`
  （tint + 源矩形）；SoftwareBackend 光栅化（premultiplied 语义，参与脏矩形
  与 pixel() oracle）；`Kit::Image` 控件（Stretch/Contain/Cover，a11y
  `Role::Image`）。
- **#34 布局增量层**：`CachedNode` 每节点双层缓存（final 单槽 + 8 槽测量
  环形缓冲）+ MarkDirty 父链早停 + 帧间 rect 变更上报；纯函数 `Layout.solve`
  保留为 oracle，几何一致性有 spec。`CachingMeasurer` 补 8192 容量上限。
- **#35 Platform 契约 + FakeHost**：`Tessell::Platform::Host` 最小契约与
  记录式测试替身（虚拟时钟、事件注入、op 流记录、未实现能力显式 panic）。
  内置组件 emit 补 visible 守卫——不可见组件不进命中树。Kit spec 全部
  无窗口可跑。
- **#39 重启式热重载第一期**：命名 signal JSON 快照/回填
  （`Signal.snapshot_state`/`restore_state`，Runner#save_state/load_state）；
  restore 走写路径失效下游（memo 跟随）。保留 signal 值不保留 views
  （asuka RFC 0003 口径）；control socket/fd 继承属平台层后续。
- **#29 字体 face 链路**：`Kit::FontWeight` → `FontStack#pick(text, weight)`
  → `font_id` 一路传到 Painter（`DrawCmd#atlas_id`）；`Context#font_stack` +
  `MultiFaceTextMetrics`；`Kit::Text/Button` 增加 `weight` 属性——
  `Text.new(key, "Total", weight: :bold)` 渲出粗体，宿主只建 renderer 表。
- **#31 A11y 二维网格**：`Role` 补 Grid/GridCell/RowHeader/ColumnHeader；
  Meta/Node 补 row/col/row_count/col_count/index_text/selected/active/
  first_visible_index（全默认 nil，既有节点零改动）；坐标不再拼进 value。
- **#32 编辑态 Tab 语义**：`TextEditing#tabs`（Reject/Insert，	 展开为
  tab_width 空格）+ `Input#submit_on_tab`（Tab 触发 on_submit 并消费，
  wants_tab? 随动）；三种组合入契约文档。
- **#41 建树期 signal 读告警（第一期）**：debug 检查下建树函数直读未追踪
  signal 会被点名（消息自带修法与 peek 出口）；F1 overlay 可视化；
  peek/untrack 永不报。
- **#42 apply 重入隔离**：`UI.apply` 宿主回调缝 + Root 重入守卫——apply
  期间失效进 pending 通道，外层返回后二段提交；8 次不收敛 raise
  （宁报勿挂）。
- **#36 计数断言**：性能正确性全部用计数表达（measure 调用数/批数/事件
  路由/帧命令数 4 例）+ #34 布局计数 spec；「门禁看计数、优化看分布」
  分工入 AGENTS.md 与 cookbook。
- **#37 golden 探针模式**：注册标记定位 + Edge 0.5 交叉（亚像素）/Mix 混合
  比例/σ 软边量测——同一组探针在 scale=1.0/1.5/2.0 全过，无需按 DPI 重录
  golden；像素 golden 降级为失败诊断附件。
- **#40 跨后端 conformance**：`KNOWN_DIFFERENCES` 差异清单（skip 必须带
  理由，premultiplied/圆角登记为可断言）+ `compare_buffers` 双后端等价
  harness；GL 腿 headless 显式 gated 不静默。
- **#38 AGENTS.md**：仓库根新增协作约束——11 条可机械验证硬不变量 +
  意图→命令速查表 + Conventions（断言优先级、平台门控 SKIP 写法、
  新增组件固定步骤）。

### 已知事项
- #43（重复 UiKey 挂死）与 #44（Signal 接入 Kit：组件 Owner 绑定、三级
  失效对接、For keyed 行复用）为后续跟进项。
- Image 稳态重绘在 Windows 上 GC 统计残留 ≤256B/100 帧（平台统计口径，
  blit 路径纯标量运算）；精确归零挂 TODO(M1-WP5)。

## 0.2.0 (2026-11-14)

ShiningRay/tessell 全部 18 个 GitHub issue 处置完成（#1–#18，逐一提交关闭）。

### Bug 修复
- **#1 GlyphAtlas GPU 同步契约**：新增 `revision` / `page_revision` /
  `rgba_page_revision`（任何像素变化含既有页插入都递增）；
  `GLBackend#sync_atlas_dirty` 按页 revision 只重传变化页（新页
  `glTexImage2D`、已有页 `glTexSubImage2D`）。动态文本不再运行期缺字；
  `page_count` 不是变化信号，示例与宿主已改用增量同步。
- **#14 Kit::Context 文本度量单位**：`measure_text` / `line_height`
  统一返回**逻辑**单位（设备字号测量后除回 scale，max_width 同步乘 scale
  保证换行一致）。DPR≠1 不再宽度翻倍，宿主无须自写除法适配器。
- **#15 Painter z-order 与 clip 契约**：契约成文（调用顺序即绘制顺序，
  clip 同时约束形状与文本）；`Backend#draw_text` 增加 `from_batch/clip`、
  `draw_draw_list` 增加区间参数；SDL 宿主按命令序交错提交，滚动边缘文本
  由后端 scissor 裁切。
- **#16 Tab 键语义**：`Component#wants_tab?` 声明后 Root 先把 Tab 投递给
  焦点组件；`Ctrl/Meta+Tab` 恒定保留给焦点环（退出路径）。
- 附带修复：`draw_polygon` dirty 模式覆盖写出脏区；SDL 截图 PNG 写入器
  BFINAL 与块遍历双缺陷；脏区清屏移至 `begin_frame`（交错提交不被清屏
  擦掉形状）。

### 新能力（增强建议研判后执行）
- **#2 Render::Canvas**：统一绘制门面（fill/stroke/round_rect/line/
  polyline/push_clip），命令进 DrawList 由 `Backend#draw_draw_list` 执行；
  `draw_polygon` 保留为路径填充入口。
- **#4 输入模型**：KeyCode 补 KeyT/Digit0-9/F1-F4；Event 增加
  `timestamp_ms` / `repeat`；Router 点击语义（`last_click_count` 单/双击、
  `last_drag_distance`、可配双击参数）。
- **#5 DSL 自动布局**：`Layout` 内核 gap 支持；`vstack/hstack/auto_text/
  auto_node` + `UI.apply_auto_layout`——布局与命中树同源。
- **#6 文本 API**：`Text::FontMetrics`（FtMeasurer 读 FT size metrics）；
  `ctx.text_metrics`（逻辑单位）；`TextDrawing.draw_in_rect` 九宫格对齐；
  `measure_text` 内建缓存。
- **#7 字体栈**：`Text::FontStack`（cmap 真实覆盖选脸）+
  `Text::SystemFonts` 标准目录发现；选脸粒度=整段文本的边界如实文档化。
- **#8 主题 token**：核心 Theme 扩展 panel/panel_alt/card/grid/divider、
  up/down/up_soft/down_soft（预设 A 股口径）、hover/focus_ring、
  warning/danger/success/faint；Kit `ctx.render_theme` 镜像。
- **#9 PNG/golden 工具**：零依赖 PNG 写读（stored zlib）；`--screenshot=x.png`
  直出 PNG；`tools/golden` 比较/diff 图/TSRAW/PPM 互转，退出码可直接用于 CI。
- **#10 SoftwareBackend**：纯 CPU 离屏后端（无窗口/GPU/FFI），与 GLBackend
  同契约；「脏区重绘 == 全量重绘」可在纯 spec 内断言。
- **#11 帧调试 overlay**：F1 开关（Root 拦截，业务零改动）；
  `DebugInfo.collect` 一行接入——帧耗时/FPS/quads/scissor/culled、
  atlas used/evicted、dirty rects、hover/focus 名。
- **#17 ScrollModel**：可复用单轴滚动数学（clamp/thumb/可见区间/坐标↔索引），
  ScrollView 委托；二维控件 x/y 各持一实例。
- **#3 App::Runner**：平台无关帧循环契约（自动化帧数/虚拟时钟/帧预算/
  干净退出），SDL 宿主已接入。

### 文档
- **#12**：docs/cookbook.md 九节 + API reference 生成脚本
  （`tools/gen_api_docs.sh` → site/api）+ README 链接真实 demo 仓；
  「已知 API 缺口」刷新为 2026-11 现状。
- **#13**：K6 复盘七项问题处置映射回填 docs/kit/K6-review.md §7。
- **#18**：usage.md 新增「写示例常撞的 Crystal 编译错误」（逐条实测）与
  Rasterizer/FtMeasurer 分工契约。
- **#17 附带**：docs/kit/cookbook-custom-widget.md 自定义大控件清单。

### 平台口径
- macOS（SDL2/OpenGL）可验证面全部闭环：真实窗口截图、gallery verify
  （light/dark/dpi=1.5/2.0）、m3_sdl_dirty_probe 像素探针。
- Windows 真机 gate 与平台 provider 维持 No-Go：Win32 平台层立项
  docs/cross-platform-plan.md §11（issue #3 关闭评论与文档同步口径）。

**Full Changelog**: https://github.com/ShiningRay/tessell/compare/00af890...v0.2.0
