# 扩展 Tessell Kit：第三方组件的三条路径

> 目标读者：想在 Tessell Kit 之上写自己的组件/包装内置组件的应用开发者。
> 本文是操作指引；机制调研与取舍见
> [component-extension-survey.md](../research/component-extension-survey.md)
> （#57，七家对照），可覆写点清单见
> [component-contract.md](component-contract.md)（#66）。

## 三条路径（按优先级选择）

### 路径一：组合（首选）

用 `Column` / `Row` / `Container` 把内置组件拼成复合结构。不写新组件类，
状态归属应用，交互回调走内置组件的 `on_click`/`on_change`。

```crystal
# 表单行：输入框吃掉剩余宽度 + 固定宽度按钮（issue #49 grow 语义）
row = Tessell::Kit::Row.new(key, Tessell::Insets.all(4.0_f32), 4.0_f32)
input = Tessell::Kit::Input.new(key.child(1_u64), label: "New item")
row.add(input, grow: 1.0_f32)
add_btn = Tessell::Kit::Button.new(key.child(2_u64), "Add")
add_btn.on_click = -> { app.add_item(input.text) }
row.add(add_btn)
```

适用：布局与事件全部能用内置组件表达时（大多数表单/工具栏/列表）。

### 路径二：包装（改外观或行为的一小步）

继承内置组件，覆写**单个 `protected` 切面**（#66 契约）——骨架保证焦点环、
disabled 分支、命中/激活状态机与 emit key 契约不变。每组件可覆写点清单见
[component-contract.md](component-contract.md#内置组件可覆写切面issue-66)。

```crystal
# 按钮"按下时多画一圈"：只覆写背景切面，其余走内置
class AccentButton < Tessell::Kit::Button
  def draw_background(p : Painter, ctx : Context,
                      colors : ButtonColors, radius : Float32) : Nil
    super
    p.fill_rect(@bounds, 0x2200ff00_u32)
  end
end
```

适用：改外观的一小步、换色/换形状、收窄命中区域、扩展激活语义。
完整可运行示例：`spec/kit/override_hooks_spec.cr`。

### 路径三：自绘 leaf（内置没有的控件）

继承 `Component`，实现 `measure`/`arrange`/`emit`/`paint` 四件套，
配合 `ScrollModel` 做滚动（见
[cookbook-custom-widget.md](cookbook-custom-widget.md)）。

```crystal
class Badge < Tessell::Kit::Component
  def measure(ctx : Context, constraints : Constraints) : Size
    s = ctx.measure_text(@text, 12.0_f32)
    constraints.constrain(Size.new(s.width + 8.0_f32, 18.0_f32))
  end

  def paint(p : Painter, ctx : Context) : Nil
    return unless @visible
    p.fill_round_rect(@bounds, 4.0_f32, ctx.theme.palette.accent)
    # 文本基线用 text_metrics 口径（issue #19），不用 fs*0.1 经验系数
    baseline = Tessell::Kit::TextDrawing.middle_baseline(@bounds, ctx.text_metrics(12.0_f32))
    p.text(@bounds.origin.x + 4.0_f32, baseline, @text,
      ctx.theme.palette.accent_foreground, 12.0_f32)
  end

  def a11y_role : A11y::Role
    A11y::Role::Text
  end

  def a11y_name : String
    @text
  end
end
```

适用：表格/时间线/徽章等内置没有的控件；复杂交互参考
[cookbook-custom-widget.md](cookbook-custom-widget.md) 的清单
（滚动/命中/裁切/键盘/a11y）。

## 最小可运行验证

三种路径的真实可运行模板都在本仓 spec 里（非伪代码）：

| 路径 | 参考文件 |
|---|---|
| 组合 + grow | `spec/kit/flex_grow_spec.cr` |
| 受控继承切面 | `spec/kit/override_hooks_spec.cr` |
| 自绘 leaf | `spec/kit/cookbook` 用例与 `docs/kit/cookbook-custom-widget.md` |
| 用户路径测试 | `spec/test_driver_spec.cr`（TestDriver 双后端） |

外部消费者验证：`bash tools/kit_consumer_verify.sh`
（临时目录 + Shards path 依赖，退出码 0）；分发约定见 #68。

## 六个坑（每个都有真实 spec 锁）

1. **UiKey 必须显式且唯一**：同一逻辑组件跨帧同一 key；重复 key fail-fast
   （#43）。**保留 key**：`UiKey.root` 本身不能当组件 key（会 build 死循环，
   #69）——永远从 `root.child(...)` 派生。
2. **visible 双守卫**：`paint` 与 `emit` 都要 `return unless @visible`
   ——emit 即存在（不可见组件不进命中树），只守卫一边会出现"看得见点不到"
   或"点得到看不见"。
3. **dispose/watch 生命周期**：持有 Signal watch 的组件实现 `dispose`
   停 Owner（Root#build 对移出树的组件自动调用，#44）；重挂树后重建
   watch，不自动恢复。
4. **a11y 元数据**：`a11y_role/name/value/focusable/enabled` 随 emit 同步；
   无可见文本的控件必须给 name；本库只产出进程内树，不可被屏幕阅读器
   读取（不要宣称平台 provider）。
5. **Painter 边界**：组件不得读窗口/GPU/平台 API（AGENTS #3）——
   只经 `Context`（主题/度量/DPI/时间）与 `Painter`（绘制原语）看世界；
   GL 只在 `render/gl/` 与宿主。
6. **主题 token**：第三方组件从 `ctx.theme` 取语义 token（accent/danger/
   surface…），不要硬编码颜色；light/dark 与 scale 用纯逻辑 spec 验证。

## 语义边界（诚实口径）

- 不做组件 registry / 插件系统（#57 结论：七家参考框架均无）。
- 不做 Tailwind 式任意样式覆盖；主题只能整套注入（per-subtree 作用域
  等 plan.md 后续立项）。
- 叶组件通用 slot/children 协议暂不排期（等真实第三方需求）。
