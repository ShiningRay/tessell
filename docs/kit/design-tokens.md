# 设计 token

> 代码权威：`src/tessell/kit/theme.cr`。本文件解释层级与命名，不复制全部数值。

## 三层结构

1. **语义色**：`canvas/surface/surface_raised/foreground/muted/border/accent/danger/success/focus/selection/scrim`。组件只引用语义色。
2. **组件 token**：`Theme#button_colors`、`Theme#input_colors` 等把语义色 + 状态解析为组件实际颜色。组件不得在绘制代码里写死色值。
3. **尺寸与排版**：`Theme::Metrics` 统一提供间距、圆角、边框、焦点环、字号、行高与控件高度。

## 颜色格式

- 全部使用 `0xRRGGBBAA` 的 `UInt32`，与核心 `Render::Theme` 的打包口径一致。
- `Theme::Palette` 不直接暴露给组件绘制；组件通过解析函数取色，便于以后换主题。
- 首版只提供编译进 shard 的 `Theme.light` / `Theme.dark`，不监听系统主题目录。

## 尺寸档位

| 档位 | 控件高度来源 | 字号来源 | 水平内边距来源 |
|---|---|---|---|
| Small | `control_height_sm` | `font_size_sm` | `padding_x_sm` |
| Medium | `control_height_md` | `font_size_md` | `padding_x_md` |
| Large | `control_height_lg` | `font_size_lg` | `padding_x_lg` |

DPI 不在组件层重复乘 scale：布局使用逻辑单位，绘制文本时由 `Context#device_font_size` 或后端统一换算。首版 `Context#scale` 只影响文本设备字号与 1px 边框的下限，不改变逻辑布局。

## 状态视觉

- normal / hover / pressed / focus / disabled / invalid 必须有可区分的颜色或边框。
- 焦点环使用 `focus` 色，不改变控件主体尺寸；优先画在控件内侧，避免裁切。
- Primary 使用 accent 背景 + accent_foreground 文本；Danger 使用 danger 背景；Secondary 使用 surface + border；Ghost 无常态背景，仅 hover/pressed 有底色。
- 禁用态降低对比度，但不使用透明到不可读；disabled 文本仍要可辨识。

## 变更规则

- 新增语义色必须先证明现有语义色不能表达；新增组件 token 只在该组件确有跨组件差异时增加。
- 不在组件绘制里写 `0x...` 常量作为最终颜色；测试可以断言解析后的值。
- 主题数值调整需要同步更新 `spec/kit/theme_spec.cr` 的对比度/差异性断言。
