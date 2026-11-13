require "./spec_helper"
require "../src/tessell/render/dpi"

describe Tessell::Render::Dpi do
  it "computes scale_for standard dpi values" do
    Tessell::Render::Dpi.scale_for(96_u32).should be_close(1.0_f32, 0.001_f32)
    Tessell::Render::Dpi.scale_for(120_u32).should be_close(1.25_f32, 0.001_f32)
    Tessell::Render::Dpi.scale_for(144_u32).should be_close(1.5_f32, 0.001_f32)
    Tessell::Render::Dpi.scale_for(192_u32).should be_close(2.0_f32, 0.001_f32)
  end

  it "clamps scale_for to [0.5, 4.0]" do
    Tessell::Render::Dpi.scale_for(0_u32).should be_close(0.5_f32, 0.001_f32)
    Tessell::Render::Dpi.scale_for(10_u32).should be_close(0.5_f32, 0.001_f32)
    Tessell::Render::Dpi.scale_for(1000_u32).should be_close(4.0_f32, 0.001_f32)
    Tessell::Render::Dpi.scale_for(384_u32).should be_close(4.0_f32, 0.001_f32)
  end

  it "rounds size_px for point_size*scale and matches expected values" do
    Tessell::Render::Dpi.size_px(16.0_f32, 1.5_f32).should be_close(24.0_f32, 0.001_f32)
    Tessell::Render::Dpi.size_px(13.0_f32, 1.25_f32).should be_close(16.0_f32, 0.001_f32)
    Tessell::Render::Dpi.size_px(16.0_f32, 1.25_f32).should be_close(20.0_f32, 0.001_f32)
  end

  it "enforces a lower bound of 1.0 for size_px" do
    Tessell::Render::Dpi.size_px(0.0_f32, 1.0_f32).should be_close(1.0_f32, 0.001_f32)
    Tessell::Render::Dpi.size_px(0.1_f32, 0.5_f32).should be_close(1.0_f32, 0.001_f32)
  end

  it "maps logical to device coordinates by scale" do
    Tessell::Render::Dpi.logical_to_device(10.0_f32, 1.0_f32).should be_close(10.0_f32, 0.001_f32)
    Tessell::Render::Dpi.logical_to_device(10.0_f32, 1.5_f32).should be_close(15.0_f32, 0.001_f32)
    Tessell::Render::Dpi.logical_to_device(7.0_f32, 2.0_f32).should be_close(14.0_f32, 0.001_f32)
  end

  it "combines scale_for and size_px consistently" do
    s = Tessell::Render::Dpi.scale_for(120_u32)
    s.should be_close(1.25_f32, 0.001_f32)
    Tessell::Render::Dpi.size_px(16.0_f32, s).should be_close(20.0_f32, 0.001_f32)
  end
end
