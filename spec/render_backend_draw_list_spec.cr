require "spec"
require "../src/tessell/render/backend"
require "../src/tessell/render/draw_list"
require "../src/tessell/render/theme"
require "../src/tessell/text/glyph_atlas"

private class StubBackend < Tessell::Render::Backend
  def init(width : Int32, height : Int32) : Nil
  end

  def resize(width : Int32, height : Int32) : Nil
  end

  def begin_frame(dirty : Array(Tessell::Rect)? = nil,
                  theme : Tessell::Render::Theme = Tessell::Render::Theme.light) : Nil
  end

  def sync_atlas(atlas : Tessell::Text::GlyphAtlas) : Nil
  end

  def draw_text(vertices : Array(Tessell::Render::Vertex),
                batches : Array(Tessell::Render::TextBatch),
                batch_count : Int32 = batches.size) : Int32
    0
  end

  def end_frame : Nil
  end

  def close : Nil
  end

  def stats : Tessell::Render::FrameStats
    Tessell::Render::FrameStats.new
  end

  def resolved_texture(page : Int32) : Int32
    0
  end
end

describe "Backend draw_draw_list default" do
  it "returns 0 for unsupported backends instead of claiming success" do
    list = Tessell::Render::DrawList.new
    list.push(Tessell::Render::DrawCmd.new(Tessell::Render::CmdKind::Rect,
      Tessell::Rect.new(0.0_f32, 0.0_f32, 10.0_f32, 10.0_f32), 0xff0000ff_u32))
    StubBackend.new.draw_draw_list(list).should eq(0)
  end
end
