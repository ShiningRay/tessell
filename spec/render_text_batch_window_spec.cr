require "./spec_helper"
require "./support/fonts"
require "../src/tessell/render/software_backend"
require "../src/tessell/render/text_renderer"
require "../src/tessell/text/ft_measurer"
require "../src/tessell/text/glyph_atlas"
require "../src/tessell/text/rasterizer"

# issue #50 / #52：draw_text 的 (batch_count, from_batch) 语义必须解释为
# 「从 from_batch 起画 batch_count 条批」，即半开区间
# [from_batch, from_batch + batch_count)。宿主按 issue #15 的口径逐条交错提交
# （每次传本次增量 delta 与本次起点 before）时，第 2 条起的文本曾整段不落屏。
# 这里用纯 CPU 的 SoftwareBackend 做像素级判据（GL 路径同一处区间计算）。

private def render_font_path : String?
  TestFonts.latin
end

# 统计区域内与底色不同的像素数（有字形落屏的判据）
private def painted_pixels(backend : Tessell::Render::SoftwareBackend,
                           x0 : Int32, y0 : Int32, x1 : Int32, y1 : Int32) : Int32
  bg = Tessell::Render::Theme.light.bg
  count = 0
  (y0...y1).each do |y|
    (x0...x1).each do |x|
      count += 1 if backend.pixel(x, y) != bg
    end
  end
  count
end

describe "Render::Backend.text_batch_end（issue #50/#52）" do
  it "解释 batch_count 为数量而非排他结束索引" do
    Tessell::Render::Backend.text_batch_end(5, 1, 0).should eq(1)
    Tessell::Render::Backend.text_batch_end(5, 1, 1).should eq(2)
    Tessell::Render::Backend.text_batch_end(5, 2, 3).should eq(5)
  end

  it "默认全量调用（count=size, from=0）行为不变" do
    Tessell::Render::Backend.text_batch_end(4, 4, 0).should eq(4)
  end

  it "夹到 batches.size，越界起点得到空区间" do
    Tessell::Render::Backend.text_batch_end(3, 10, 1).should eq(3)
    Tessell::Render::Backend.text_batch_end(3, 1, 7).should eq(7)
    Tessell::Render::Backend.text_batch_end(0, 1, 0).should eq(0)
    Tessell::Render::Backend.text_batch_end(3, -1, 1).should eq(1)
  end

  it "端点加法不溢出 Int32（PR #54 review：先加宽再钳制）" do
    # 修复前 1 + Int32::MAX 在钳制前就触发 OverflowError
    Tessell::Render::Backend.text_batch_end(3, Int32::MAX, 1).should eq(3)
    Tessell::Render::Backend.text_batch_end(3, Int32::MAX, 0).should eq(3)
    # 负极值边界：钳到空区间 [from_batch, from_batch)
    Tessell::Render::Backend.text_batch_end(3, Int32::MIN, 2).should eq(2)
  end
end

describe "SoftwareBackend#draw_text 交错提交（issue #50/#52）" do
  it "同帧第二次及以后的增量提交仍然落屏" do
    path = render_font_path
    unless path
      puts "SKIP text batch window: no platform font found"
      next
    end

    w = 260
    h = 80
    ft = Tessell::Text::FtMeasurer.open(path)
    atlas = Tessell::Text::GlyphAtlas.new(256, 256)
    rasterizer = Tessell::Text::Rasterizer.new(ft, atlas, 0)
    renderer = Tessell::Render::TextRenderer.new(atlas, rasterizer)
    backend = Tessell::Render::SoftwareBackend.new
    backend.init(w, h)
    backend.attach_atlas(atlas)

    backend.begin_frame(nil, Tessell::Render::Theme.light)

    # 第 1 段：from_batch=0, delta=1
    sink = [] of Tessell::Text::GlyphPlacement
    renderer.append_text_cached(sink, "FIRST", 20.0_f32, 30.0_f32, 20, w, h, 0x000000ff_u32)
    before = renderer.batch_count - 1
    delta1 = renderer.batch_count - before
    submitted1 = backend.draw_text(renderer.vertices, renderer.batch_runs, delta1, before)

    # 第 2 段：from_batch=1, delta=1 —— 修复前这里循环条件恒假，一个 quad 都不画
    renderer.append_text_cached(sink, "SECOND", 140.0_f32, 30.0_f32, 20, w, h, 0x000000ff_u32)
    before2 = renderer.batch_count - 1
    delta2 = renderer.batch_count - before2
    submitted2 = backend.draw_text(renderer.vertices, renderer.batch_runs, delta2, before2)
    # 空提交：返回 0 而不是上一帧累计（Backend#draw_text 契约，issue #46）
    submitted3 = backend.draw_text(renderer.vertices, renderer.batch_runs, 0, renderer.batch_count)
    backend.end_frame

    submitted1.should be > 0
    submitted2.should be > 0
    submitted3.should eq(0)
    # 每次返回值 = 本次增量，帧累计 = 两次之和（stats 口径不变）
    backend.stats.submitted_quads.should eq(submitted1 + submitted2)
    painted_pixels(backend, 18, 10, 118, 40).should be > 10
    # 第二段文本区域必须有像素（旧实现恒为 0）
    painted_pixels(backend, 138, 10, 250, 40).should be > 10

    ft.close
  end
end
