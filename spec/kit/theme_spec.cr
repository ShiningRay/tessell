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

  it "disabled button colors are muted and do not follow variant accent" do
    theme = Tessell::Kit::Theme.light
    disabled = Tessell::Kit::InteractionState.new(disabled: true)
    colors = theme.button_colors(Tessell::Kit::Variant::Primary, Tessell::Kit::ControlSize::Medium, disabled)
    colors.background.should eq(theme.palette.surface_raised)
    colors.foreground.should eq(theme.palette.muted)
  end
end
