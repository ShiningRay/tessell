require "spec"
require "../../src/tessell/kit"

# Issue #11：F1 开关的帧调试 overlay，业务代码零改动。
def overlay_root : Tessell::Kit::Root
  btn = Tessell::Kit::Button.new(Tessell::UI::UiKey.root.child(1_u64), "Save")
  root = Tessell::Kit::Root.new(btn)
  root.layout(300.0_f32, 200.0_f32)
  root.build
  root
end

describe "Kit::DebugOverlay" do

  it "F1 toggles visibility and is consumed by Root" do
    root = overlay_root
    root.debug_overlay.visible.should be_false
    root.handle(Tessell::Input::Event.key_down(Tessell::Input::KeyCode::F1)).should be_true
    root.debug_overlay.visible.should be_true
    root.handle(Tessell::Input::Event.key_down(Tessell::Input::KeyCode::F1)).should be_true
    root.debug_overlay.visible.should be_false
  end

  it "paints nothing while hidden, emits text lines when visible with info" do
    root = overlay_root
    info = Tessell::Kit::DebugInfo.collect(
      Tessell::Render::FrameStats.new(42, 3, 5, 1),
      nil, root, 16.6_f32)
    root.debug_info = info

    p = Tessell::Kit::PaintListPainter.new
    root.paint(p)
    hidden_cmds = p.list.size
    p.list.clear

    root.handle(Tessell::Input::Event.key_down(Tessell::Input::KeyCode::F1))
    root.paint(p)
    visible_cmds = p.list.size
    visible_cmds.should be > hidden_cmds
    # 至少一条帧信息文本
    text_cmds = p.list.to_a.count { |c| c.kind == Tessell::Kit::PaintKind::Text }
    text_cmds.should be > 3
  end

  it "DebugInfo.collect reads atlas counters and root hover/focus" do
    btn = Tessell::Kit::Button.new(Tessell::UI::UiKey.root.child(1_u64), "Save")
    root = Tessell::Kit::Root.new(btn)
    root.layout(300.0_f32, 200.0_f32)
    root.build
    root.focus(btn)
    atlas = Tessell::Text::GlyphAtlas.new(128, 64)
    atlas.insert(Tessell::Text::GlyphKey.new(0, 1_u32, 16, 0_u8, 0_u8), 8, 8)
    info = Tessell::Kit::DebugInfo.collect(
      Tessell::Render::FrameStats.new(10, 1, 2, 0), atlas, root, 8.0_f32)
    info.atlas_pages.should eq(1)
    info.used_pixels.should be > 0
    info.focus_name.should eq("Save")
    info.fps.round(0).should eq(125.0_f32)
  end

  it "overlay paints inside viewport clip and leaves clip depth balanced" do
    root = overlay_root
    root.handle(Tessell::Input::Event.key_down(Tessell::Input::KeyCode::F1))
    root.debug_info = Tessell::Kit::DebugInfo.collect(
      Tessell::Render::FrameStats.new, nil, root, 16.0_f32)
    p = Tessell::Kit::PaintListPainter.new
    root.paint(p)
    p.list.clip_depth.should eq(0)
  end
end
