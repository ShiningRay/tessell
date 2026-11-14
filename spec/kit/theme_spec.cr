require "./spec_helper"

describe "Tessell::Kit theme" do
  it "light and dark palettes are distinct" do
    light = Tessell::Kit::Theme.light
    dark = Tessell::Kit::Theme.dark
    light.palette.canvas.should_not eq(dark.palette.canvas)
    light.palette.foreground.should_not eq(dark.palette.foreground)
    light.dark.should be_false
    dark.dark.should be_true
  end

  it "size tokens resolve consistently" do
    theme = Tessell::Kit::Theme.light
    theme.control_height(Tessell::Kit::ControlSize::Small).should eq(theme.metrics.control_height_sm)
    theme.font_size(Tessell::Kit::ControlSize::Medium).should eq(theme.metrics.font_size_md)
    theme.padding_x(Tessell::Kit::ControlSize::Large).should eq(theme.metrics.padding_x_lg)
  end

  it "button colors distinguish variant and state" do
    theme = Tessell::Kit::Theme.light
    normal = Tessell::Kit::InteractionState.normal
    hovered = Tessell::Kit::InteractionState.new(hovered: true)
    primary = theme.button_colors(Tessell::Kit::Variant::Primary, Tessell::Kit::ControlSize::Medium, normal)
    primary_hover = theme.button_colors(Tessell::Kit::Variant::Primary, Tessell::Kit::ControlSize::Medium, hovered)
    ghost = theme.button_colors(Tessell::Kit::Variant::Ghost, Tessell::Kit::ControlSize::Medium, normal)
    danger = theme.button_colors(Tessell::Kit::Variant::Danger, Tessell::Kit::ControlSize::Medium, normal)
    primary.background.should_not eq(primary_hover.background)
    ghost.background.should eq(0x00000000_u32)
    danger.background.should eq(theme.palette.danger)
  end

  it "adapts a core Render::Theme without leaving half a theme" do
    core = Tessell::Render::Theme.dark
    theme = Tessell::Kit::Theme.from_render(core, dark: true)
    theme.dark.should be_true
    theme.palette.canvas.should eq(core.bg)
    theme.palette.foreground.should eq(core.fg)
    theme.palette.accent.should eq(core.accent)
    theme.palette.border.should eq(core.border)
  end

  it "disabled button colors are muted and do not follow variant accent" do
    theme = Tessell::Kit::Theme.light
    disabled = Tessell::Kit::InteractionState.new(disabled: true)
    colors = theme.button_colors(Tessell::Kit::Variant::Primary, Tessell::Kit::ControlSize::Medium, disabled)
    colors.background.should eq(theme.palette.surface_raised)
    colors.foreground.should eq(theme.palette.muted)
  end
end

# issue #8：Context#render_theme 镜像核心扩展 token，切换主题时同步。
describe "Kit::Context render_theme mirror" do
  it "mirrors the initial theme and follows theme=" do
    ctx = Tessell::Kit::Context.new(Tessell::Kit::Theme.light,
      Tessell::Kit::StubTextMetrics.new, 1.0_f32)
    ctx.render_theme.bg.should eq(ctx.theme.to_render.bg)
    ctx.render_theme.up.should_not eq(ctx.render_theme.down)

    ctx.theme = Tessell::Kit::Theme.dark
    ctx.render_theme.bg.should eq(ctx.theme.to_render.bg)
    ctx.render_theme.panel.should_not eq(ctx.render_theme.bg)
  end
end

# issue #23：to_render/from_render 往返丢信息（v0.2.0 surface 被 bg 覆盖）。
describe "Kit::Theme ↔ Render::Theme round trip (issue #23)" do
  it "carries Kit surface tokens into the render panel tokens" do
    kit = Tessell::Kit::Theme.light
    r = kit.to_render
    r.panel.should eq(kit.palette.surface)
    r.panel_alt.should eq(kit.palette.surface_raised)
    r.card.should eq(kit.palette.surface)
    r.focus_ring.should eq(kit.palette.focus)
    r.danger.should eq(kit.palette.danger)
    r.success.should eq(kit.palette.success)
  end

  it "preserves surface across to_render → from_render in light" do
    kit = Tessell::Kit::Theme.light
    rt = Tessell::Kit::Theme.from_render(kit.to_render, dark: false)
    rt.palette.canvas.should eq(kit.palette.canvas)
    rt.palette.surface.should eq(kit.palette.surface)
    rt.palette.surface_raised.should eq(kit.palette.surface_raised)
    rt.palette.foreground.should eq(kit.palette.foreground)
    rt.palette.muted.should eq(kit.palette.muted)
    rt.palette.border.should eq(kit.palette.border)
    rt.palette.accent.should eq(kit.palette.accent)
    rt.palette.focus.should eq(kit.palette.focus)
    rt.palette.selection.should eq(kit.palette.selection)
    rt.palette.danger.should eq(kit.palette.danger)
    rt.palette.success.should eq(kit.palette.success)
  end

  it "preserves surface across to_render → from_render in dark" do
    kit = Tessell::Kit::Theme.dark
    rt = Tessell::Kit::Theme.from_render(kit.to_render, dark: true)
    rt.palette.surface.should eq(kit.palette.surface)
    rt.palette.surface_raised.should eq(kit.palette.surface_raised)
    rt.palette.canvas.should eq(kit.palette.canvas)
    rt.palette.focus.should eq(kit.palette.focus)
    rt.dark.should be_true
  end

  it "documents the known loss boundary: hover/scrim/accent variants are preset-only" do
    # Render::Theme 没有 accent_hover/pressed/foreground、danger_hover/pressed/
    # foreground、scrim 概念——往返后这些取同明暗预设值，属登记过的已知边界。
    kit = Tessell::Kit::Theme.light
    rt = Tessell::Kit::Theme.from_render(kit.to_render, dark: false)
    rt.palette.accent_hover.should eq(Tessell::Kit::Theme.light.palette.accent_hover)
    rt.palette.scrim.should eq(Tessell::Kit::Theme.light.palette.scrim)
  end
end
