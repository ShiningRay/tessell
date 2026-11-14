require "spec"
require "../../src/tessell/kit"

# Issue #17：可复用滚动数学。ScrollView 委托；二维控件按 x/y 各持一个实例。
describe "Kit::ScrollModel" do
  it "offset clamps to [0, max]" do
    m = Tessell::Kit::ScrollModel.new(1000.0_f32, 400.0_f32)
    m.max_offset.should eq(600.0_f32)
    m.offset = -50.0_f32
    m.offset.should eq(0.0_f32)
    m.offset = 900.0_f32
    m.offset.should eq(600.0_f32)
    m.scrollable?.should be_true
  end

  it "non-scrollable content pins offset at 0" do
    m = Tessell::Kit::ScrollModel.new(100.0_f32, 400.0_f32)
    m.scrollable?.should be_false
    m.offset = 50.0_f32
    m.offset.should eq(0.0_f32)
  end

  it "scroll_by accumulates and clamps" do
    m = Tessell::Kit::ScrollModel.new(1000.0_f32, 400.0_f32)
    m.scroll_by(100.0_f32)
    m.offset.should eq(100.0_f32)
    m.scroll_by(-200.0_f32)
    m.offset.should eq(0.0_f32)
    m.scroll_by(10_000.0_f32)
    m.offset.should eq(600.0_f32)
  end

  it "thumb geometry: size by ratio, position by offset progress" do
    m = Tessell::Kit::ScrollModel.new(1000.0_f32, 400.0_f32)
    track = 300.0_f32
    t = m.thumb(track)
    t.size.should eq(120.0_f32)               # 300 * 400/1000
    t.pos.should eq(0.0_f32)
    m.offset = 600.0_f32
    t2 = m.thumb(track)
    t2.pos.should eq(180.0_f32)               # (300-120) * 600/600
    # thumb 不小于 min_thumb_size
    m2 = Tessell::Kit::ScrollModel.new(1_000_000.0_f32, 400.0_f32)
    m2.thumb(track).size.should eq(20.0_f32)
  end

  it "offset_for_thumb maps track position back to offset" do
    m = Tessell::Kit::ScrollModel.new(1000.0_f32, 400.0_f32)
    m.offset_for_thumb(0.0_f32, 300.0_f32).should eq(0.0_f32)
    m.offset_for_thumb(300.0_f32, 300.0_f32).should eq(600.0_f32)
    m.offset_for_thumb(150.0_f32, 300.0_f32).should eq(300.0_f32)
  end

  it "visible_range returns inclusive first/last for uniform rows" do
    m = Tessell::Kit::ScrollModel.new(24.0_f32 * 1000, 240.0_f32)
    first, last = m.visible_range(24.0_f32, 1000)
    first.should eq(0)
    last.should eq(10)                        # 240/24 → 11 行（含部分行）
    m.offset = 24.0_f32 * 500
    first2, last2 = m.visible_range(24.0_f32, 1000)
    first2.should eq(500)
    last2.should eq(510)
    m.offset = 24.0_f32 * 990
    _f3, last3 = m.visible_range(24.0_f32, 1000)
    last3.should eq(999)                      # 尾部收敛到 total-1
  end

  it "offset_at / index_at round-trip coordinate and index" do
    m = Tessell::Kit::ScrollModel.new(24.0_f32 * 1000, 240.0_f32)
    m.offset_at(3, 24.0_f32).should eq(72.0_f32)
    m.index_at(72.0_f32, 24.0_f32).should eq(3)
    m.offset = 240.0_f32
    m.index_at(0.0_f32, 24.0_f32).should eq(10)
    m.index_at(-1.0_f32, 24.0_f32).should eq(-1)
    # 超出内容的坐标 → -1
    m2 = Tessell::Kit::ScrollModel.new(240.0_f32, 240.0_f32)
    m2.index_at(300.0_f32, 24.0_f32).should eq(-1)
  end

  it "ScrollView delegates scroll math to models (API unchanged)" do
    text = Tessell::Kit::Text.new(Tessell::UI::UiKey.root.child(1_u64),
      "line", Tessell::Kit::TextTone::Normal, Tessell::Kit::ControlSize::Medium)
    sv = Tessell::Kit::ScrollView.new(Tessell::UI::UiKey.root, text)
    ctx = Tessell::Kit::Context.new
    sv.arrange(ctx, Tessell::Rect.new(0, 0, 200.0_f32, 100.0_f32))
    sv.scroll_to(1000.0_f32)
    sv.scroll_y.should eq(0.0_f32)            # 内容不足一屏 → 0
    sv.scroll_by(50.0_f32)
    sv.scroll_y.should eq(0.0_f32)
    sv.paint_token.should be_a(UInt32)
  end
end
