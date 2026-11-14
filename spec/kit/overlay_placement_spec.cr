require "./spec_helper"

describe "Tessell::Kit::OverlayPlacement" do
  viewport = Tessell::Rect.new(0.0_f32, 0.0_f32, 300.0_f32, 200.0_f32)

  it "places below when there is room" do
    anchor = Tessell::Rect.new(20.0_f32, 20.0_f32, 80.0_f32, 24.0_f32)
    rect = Tessell::Kit::OverlayPlacement.place(anchor, Tessell::Size.new(100.0_f32, 60.0_f32),
      viewport, Tessell::Kit::OverlaySide::Below, 4.0_f32, 8.0_f32)
    rect.origin.y.should eq(48.0_f32)
    rect.origin.x.should eq(20.0_f32)
  end

  it "flips above when below would overflow" do
    anchor = Tessell::Rect.new(20.0_f32, 150.0_f32, 80.0_f32, 24.0_f32)
    rect = Tessell::Kit::OverlayPlacement.place(anchor, Tessell::Size.new(100.0_f32, 60.0_f32),
      viewport, Tessell::Kit::OverlaySide::Below, 4.0_f32, 8.0_f32)
    (rect.max_y <= anchor.origin.y).should be_true
  end

  it "clamps horizontally into the viewport" do
    anchor = Tessell::Rect.new(280.0_f32, 20.0_f32, 10.0_f32, 24.0_f32)
    rect = Tessell::Kit::OverlayPlacement.place(anchor, Tessell::Size.new(100.0_f32, 60.0_f32),
      viewport, Tessell::Kit::OverlaySide::Below, 4.0_f32, 8.0_f32)
    (rect.max_x <= viewport.max_x - 8.0_f32).should be_true
    rect.origin.x.should be >= 8.0_f32
  end

  it "centers and clamps oversized content" do
    rect = Tessell::Kit::OverlayPlacement.center(Tessell::Size.new(500.0_f32, 300.0_f32), viewport)
    rect.origin.x.should be >= 8.0_f32
    rect.origin.y.should be >= 8.0_f32
    rect.size.width.should eq(284.0_f32)
    rect.size.height.should eq(184.0_f32)
  end
end
