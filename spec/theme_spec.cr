require "./spec_helper"
require "../src/tessell/render/theme"

describe Tessell::Render::Theme do
  it "unpacks light theme channels byte-wise (RGBA 0xRRGGBBAA)" do
    t = Tessell::Render::Theme.light
    Tessell::Render::Theme.rb(t.bg).should eq 255_u8
    Tessell::Render::Theme.gb(t.bg).should eq 255_u8
    Tessell::Render::Theme.bb(t.bg).should eq 255_u8
    Tessell::Render::Theme.ab(t.bg).should eq 255_u8

    Tessell::Render::Theme.rb(t.fg).should eq 0_u8
    Tessell::Render::Theme.gb(t.fg).should eq 0_u8
    Tessell::Render::Theme.bb(t.fg).should eq 0_u8
    Tessell::Render::Theme.ab(t.fg).should eq 255_u8

    Tessell::Render::Theme.rb(t.accent).should eq 0x2f_u8
    Tessell::Render::Theme.gb(t.accent).should eq 0x6f_u8
    Tessell::Render::Theme.bb(t.accent).should eq 0xed_u8
    Tessell::Render::Theme.ab(t.accent).should eq 0xff_u8
  end

  it "unpacks dark theme channels byte-wise" do
    t = Tessell::Render::Theme.dark
    Tessell::Render::Theme.rb(t.bg).should eq 0x1e_u8
    Tessell::Render::Theme.gb(t.bg).should eq 0x1e_u8
    Tessell::Render::Theme.bb(t.bg).should eq 0x1e_u8
    Tessell::Render::Theme.ab(t.bg).should eq 0xff_u8

    Tessell::Render::Theme.rb(t.fg).should eq 0xe0_u8
    Tessell::Render::Theme.gb(t.fg).should eq 0xe0_u8
    Tessell::Render::Theme.bb(t.fg).should eq 0xe0_u8
    Tessell::Render::Theme.ab(t.fg).should eq 0xff_u8

    Tessell::Render::Theme.rb(t.selection).should eq 0x2b_u8
    Tessell::Render::Theme.gb(t.selection).should eq 0x4a_u8
    Tessell::Render::Theme.bb(t.selection).should eq 0x7d_u8
    Tessell::Render::Theme.ab(t.selection).should eq 0xff_u8
  end

  it "has opaque backgrounds for light and dark themes" do
    Tessell::Render::Theme.ab(Tessell::Render::Theme.light.bg).should eq 255_u8
    Tessell::Render::Theme.ab(Tessell::Render::Theme.dark.bg).should eq 255_u8
  end

  it "has six mutually different fields within each theme" do
    light = Tessell::Render::Theme.light
    lvals = [light.bg, light.fg, light.accent, light.muted, light.border, light.selection]
    lvals.uniq.size.should eq 6

    dark = Tessell::Render::Theme.dark
    dvals = [dark.bg, dark.fg, dark.accent, dark.muted, dark.border, dark.selection]
    dvals.uniq.size.should eq 6
  end

  it "light and dark themes differ in all six fields" do
    l = Tessell::Render::Theme.light
    d = Tessell::Render::Theme.dark
    l.bg.should_not eq d.bg
    l.fg.should_not eq d.fg
    l.accent.should_not eq d.accent
    l.muted.should_not eq d.muted
    l.border.should_not eq d.border
    l.selection.should_not eq d.selection
  end

  it "is a value type with copy semantics (independent values)" do
    a = Tessell::Render::Theme.light
    b = a
    b.bg.should eq a.bg
    b.fg.should eq a.fg

    c = Tessell::Render::Theme.new(0x00000000_u32, a.fg, a.accent, a.muted, a.border, a.selection)
    c.bg.should_not eq a.bg
    a.bg.should eq 0xffffffff_u32
  end

  it "exposes normalized float channel helpers" do
    Tessell::Render::Theme.r(Tessell::Render::Theme.light.bg).should be_close(1.0_f32, 0.001_f32)
    Tessell::Render::Theme.g(Tessell::Render::Theme.light.bg).should be_close(1.0_f32, 0.001_f32)
    Tessell::Render::Theme.b(Tessell::Render::Theme.light.bg).should be_close(1.0_f32, 0.001_f32)
    Tessell::Render::Theme.a(Tessell::Render::Theme.light.bg).should be_close(1.0_f32, 0.001_f32)

    Tessell::Render::Theme.r(Tessell::Render::Theme.dark.bg).should be_close(30.0_f32 / 255.0_f32, 0.001_f32)
    Tessell::Render::Theme.a(Tessell::Render::Theme.dark.fg).should be_close(1.0_f32, 0.001_f32)
  end
end

# issue #8：扩展语义 token。
describe "Render::Theme extended tokens" do
  it "light/dark presets define panel/grid/up/down family" do
    light = Tessell::Render::Theme.light
    dark = Tessell::Render::Theme.dark
    light.panel.should_not eq(0_u32)
    dark.panel_alt.should_not eq(0_u32)
    light.grid.should_not eq(0_u32)
    dark.divider.should_not eq(0_u32)
    light.up.should_not eq(0_u32)
    dark.down.should_not eq(0_u32)
    light.hover.should_not eq(0_u32)
    dark.focus_ring.should_not eq(0_u32)
    light.warning.should_not eq(0_u32)
    dark.danger.should_not eq(0_u32)
    light.success.should_not eq(0_u32)
    dark.faint.should_not eq(0_u32)
    light.panel.should_not eq(light.bg)
    dark.panel.should_not eq(dark.bg)
  end

  it "up/down differ and soft variants carry lower alpha" do
    t = Tessell::Render::Theme.light
    t.up.should_not eq(t.down)
    Tessell::Render::Theme.ab(t.up_soft).should be < Tessell::Render::Theme.ab(t.up)
    Tessell::Render::Theme.ab(t.down_soft).should be < Tessell::Render::Theme.ab(t.down)
  end

  it "fg > muted > faint ordering (same hue family, decreasing prominence)" do
    t = Tessell::Render::Theme.dark
    t.fg.should_not eq(t.muted)
    t.muted.should_not eq(t.faint)
  end

  it "six-arg constructor derives extended tokens deterministically" do
    a = Tessell::Render::Theme.new(0xffffffff_u32, 0x000000ff_u32, 0x2f6fedff_u32,
      0x8a8a8aff_u32, 0xd0d0d0ff_u32, 0xbcd4ffff_u32)
    b = Tessell::Render::Theme.new(0xffffffff_u32, 0x000000ff_u32, 0x2f6fedff_u32,
      0x8a8a8aff_u32, 0xd0d0d0ff_u32, 0xbcd4ffff_u32)
    a.panel.should eq(b.panel)
    a.grid.should eq(b.grid)
    a.up.should_not eq(a.down)
    a.focus_ring.should eq(a.accent)
  end

  it "mix/with_alpha helpers behave" do
    c = Tessell::Render::Theme.mix(0x000000ff_u32, 0xffffffff_u32, 0.5_f32)
    Tessell::Render::Theme.rb(c).should eq(128_u8)
    Tessell::Render::Theme.ab(c).should eq(255_u8)
    half = Tessell::Render::Theme.with_alpha(0x112233ff_u32, 0x80_u8)
    Tessell::Render::Theme.ab(half).should eq(0x80_u8)
    Tessell::Render::Theme.rb(half).should eq(0x11_u8)
  end
end
