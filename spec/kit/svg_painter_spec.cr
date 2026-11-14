require "./spec_helper"

describe "Tessell::Kit::SvgPainter" do
  it "emits shapes, text, clips and theme background" do
    painter = Tessell::Kit::SvgPainter.new(200, 100)
    painter.background = Tessell::Kit::Theme.dark.palette.canvas
    painter.fill_round_rect(Tessell::Rect.new(10.0_f32, 10.0_f32, 80.0_f32, 24.0_f32), 4.0_f32, 0xff0000ff_u32)
    painter.line(10.0_f32, 40.0_f32, 90.0_f32, 40.0_f32, 0x00ff00ff_u32, 2.0_f32)
    painter.push_clip(Tessell::Rect.new(0.0_f32, 0.0_f32, 50.0_f32, 50.0_f32))
    painter.text(12.0_f32, 26.0_f32, "Hello <Kit>", 0xffffffff_u32, 14.0_f32)
    painter.pop_clip

    painter.clip_depth.should eq(0)
    painter.elements.should eq(3)
    svg = painter.svg
    svg.should contain("<svg")
    svg.should contain("clipPath")
    svg.should contain("Hello &lt;Kit&gt;")
    svg.should contain("rgba(23,26,31,1.0)")
    svg.should contain("</g>")
  end
end
