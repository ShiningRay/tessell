require "./spec_helper"
require "../src/tessell/render/software_backend"
require "../src/tessell/render/canvas"

# Issue #10：无窗口渲染与像素/命中断言。SoftwareBackend 纯 CPU，
# CI 可跑；脏区语义与 GLBackend 对齐，纯 spec 内断言「脏区 == 全量」。
def sw_backend(w : Int32, h : Int32) : Tessell::Render::SoftwareBackend
  b = Tessell::Render::SoftwareBackend.new
  b.init(w, h)
  b
end

describe "Render::SoftwareBackend" do
  it "begin_frame(nil) clears to theme bg" do
    b = sw_backend(8, 6)
    b.begin_frame(nil, Tessell::Render::Theme.light)
    b.end_frame
    b.pixel(0, 0).should eq(Tessell::Render::Theme.light.bg)
    b.pixel(7, 5).should eq(Tessell::Render::Theme.light.bg)
  end

  it "fill_rect writes exact premultiplied color inside bounds" do
    b = sw_backend(16, 16)
    b.begin_frame(nil, Tessell::Render::Theme.light)
    b.draw_draw_list(canvas_list([
      ->(c : Tessell::Render::Canvas) { c.fill_rect(Tessell::Rect.new(2, 2, 6, 6), 0x2f6fedff_u32) },
    ]))
    b.end_frame
    # 不透明覆盖：中心 = 0xED6F2F（BGRA 读序 => RGBA 值 0xff2f6fed）
    b.pixel(5, 5).should eq(0x2f6fedff_u32)
    # 边界外保持底色
    b.pixel(1, 1).should eq(Tessell::Render::Theme.light.bg)
    b.pixel(9, 9).should eq(Tessell::Render::Theme.light.bg)
  end

  it "per-command clip restricts painting (pixel outside clip untouched)" do
    b = sw_backend(20, 20)
    b.begin_frame(nil, Tessell::Render::Theme.light)
    b.draw_draw_list(canvas_list([
      ->(c : Tessell::Render::Canvas) do
        c.push_clip(Tessell::Rect.new(0, 0, 10, 20))
        c.fill_rect(Tessell::Rect.new(0, 0, 20, 20), 0x000000ff_u32)
        c.pop_clip
      end,
    ]))
    b.end_frame
    b.pixel(5, 10).should eq(0x000000ff_u32)
    b.pixel(15, 10).should eq(Tessell::Render::Theme.light.bg)
  end

  it "later commands cover earlier ones (z-order)" do
    b = sw_backend(10, 10)
    b.begin_frame(nil, Tessell::Render::Theme.light)
    b.draw_draw_list(canvas_list([
      ->(c : Tessell::Render::Canvas) do
        c.fill_rect(Tessell::Rect.new(0, 0, 10, 10), 0x000000ff_u32)
        c.fill_rect(Tessell::Rect.new(0, 0, 10, 10), 0x00ff00ff_u32)
      end,
    ]))
    b.end_frame
    b.pixel(4, 4).should eq(0x00ff00ff_u32)
  end

  it "draw_line paints along the segment with thickness" do
    b = sw_backend(20, 20)
    b.begin_frame(nil, Tessell::Render::Theme.light)
    b.draw_draw_list(canvas_list([
      ->(c : Tessell::Render::Canvas) { c.line(2.0_f32, 10.0_f32, 18.0_f32, 10.0_f32, 0xff0000ff_u32, 3.0_f32) },
    ]))
    b.end_frame
    b.pixel(10, 10).should eq(0xff0000ff_u32)
    b.pixel(10, 12).should eq(Tessell::Render::Theme.light.bg)
  end

  it "draw_polygon even-odd fill" do
    b = sw_backend(40, 40)
    b.begin_frame(nil, Tessell::Render::Theme.light)
    pts = [Tessell::Point.new(5.0_f32, 5.0_f32),
           Tessell::Point.new(35.0_f32, 5.0_f32),
           Tessell::Point.new(20.0_f32, 35.0_f32)]
    b.draw_polygon(pts, 0x112233ff_u32)
    b.end_frame
    b.pixel(20, 15).should eq(0x112233ff_u32)
    b.pixel(2, 2).should eq(Tessell::Render::Theme.light.bg)
  end

  it "renders text glyphs from the atlas (headless, no window)" do
    path = unix_font_path
    unless path
      pending "no Unix test font found"
      next
    end
    w = 120
    h = 40
    atlas = Tessell::Text::GlyphAtlas.new(256, 128)
    ft = Tessell::Text::FtMeasurer.open(path)
    rasterizer = Tessell::Text::Rasterizer.new(ft, atlas, 0)
    renderer = Tessell::Render::TextRenderer.new(atlas, rasterizer)
    sink = [] of Tessell::Text::GlyphPlacement
    renderer.append_text_cached(sink, "HI", 10.0_f32, 30.0_f32, 24, w, h, 0x000000ff_u32)

    b = sw_backend(w, h)
    b.attach_atlas(atlas)
    b.begin_frame(nil, Tessell::Render::Theme.light)
    submitted = b.draw_text(renderer.vertices, renderer.batch_runs, renderer.batch_count)
    b.end_frame
    submitted.should be > 0
    # 字形区域出现非底色像素（黑字白底）
    dark = 0
    (8..80).each do |x|
      (10..34).each do |y|
        dark += 1 if b.pixel(x, y) != Tessell::Render::Theme.light.bg
      end
    end
    dark.should be > 20
    ft.close
  end

  it "dirty redraw equals full redraw (pure spec oracle)" do
    path = unix_font_path
    unless path
      pending "no Unix test font found"
      next
    end
    w = 160
    h = 120
    dirty = Tessell::Rect.new(0.0_f32, 0.0_f32, 80.0_f32, 60.0_f32)
    polygon = [
      Tessell::Point.new(10.0_f32, 10.0_f32),
      Tessell::Point.new(150.0_f32, 40.0_f32),
      Tessell::Point.new(80.0_f32, 110.0_f32),
    ]

    b_full = sw_backend(w, h)
    ft = Tessell::Text::FtMeasurer.open(path)
    atlas = Tessell::Text::GlyphAtlas.new(256, 128)
    rasterizer = Tessell::Text::Rasterizer.new(ft, atlas, 0)
    renderer = Tessell::Render::TextRenderer.new(atlas, rasterizer)
    b_full.attach_atlas(atlas)
    b_full.begin_frame(nil, Tessell::Render::Theme.light)
    b_full.draw_polygon(polygon, 0x2222ddff_u32)
    b_full.draw_draw_list(canvas_list([
      ->(c : Tessell::Render::Canvas) { c.fill_rect(Tessell::Rect.new(20, 20, 40, 30), 0x00ff0066_u32) },
    ]))
    sink = [] of Tessell::Text::GlyphPlacement
    renderer.append_text_cached(sink, "XY", 120.0_f32, 30.0_f32, 16, w, h, 0x000000ff_u32)
    b_full.draw_text(renderer.vertices, renderer.batch_runs, renderer.batch_count)
    b_full.end_frame

    # 同一后端：先整帧清底（等价探针的 base 帧），再走脏帧
    b_dirty = sw_backend(w, h)
    b_dirty.attach_atlas(atlas)
    b_dirty.begin_frame(nil, Tessell::Render::Theme.light)
    b_dirty.end_frame
    b_dirty.begin_frame([dirty], Tessell::Render::Theme.light)
    b_dirty.draw_polygon(polygon, 0x2222ddff_u32)
    b_dirty.draw_draw_list(canvas_list([
      ->(c : Tessell::Render::Canvas) { c.fill_rect(Tessell::Rect.new(20, 20, 40, 30), 0x00ff0066_u32) },
    ]))
    sink2 = [] of Tessell::Text::GlyphPlacement
    renderer.append_text_cached(sink2, "XY", 120.0_f32, 30.0_f32, 16, w, h, 0x000000ff_u32)
    b_dirty.draw_text(renderer.vertices, renderer.batch_runs, renderer.batch_count)
    b_dirty.end_frame

    # 脏区内：与全量一致
    inside_diff = 0
    (0...60).each do |y|
      (0...80).each do |x|
        inside_diff += 1 if b_full.pixel(x, y) != b_dirty.pixel(x, y)
      end
    end
    inside_diff.should eq(0)
    # 脏区外（有内容的右侧带）：保持底色（文本在 120,30 处，必须有像素！）
    outside_bg = 0
    (0...60).each do |y|
      (90...160).each do |x|
        outside_bg += 1 if b_dirty.pixel(x, y) != Tessell::Render::Theme.light.bg
      end
    end
    outside_bg.should eq(0)
    # 全量帧同区域有字形像素（区分度）
    full_bg = 0
    (0...60).each do |y|
      (90...160).each do |x|
        full_bg += 1 if b_full.pixel(x, y) != Tessell::Render::Theme.light.bg
      end
    end
    full_bg.should be > 10
    ft.close
  end
end

def canvas_list(emitters : Array(Proc(Tessell::Render::Canvas, Nil))) : Tessell::Render::DrawList
  c = Tessell::Render::Canvas.new
  emitters.each { |e| e.call(c) }
  c.list
end

def unix_font_path : String?
  candidates = [
    "/System/Library/Fonts/Supplemental/Arial.ttf",
    "/System/Library/Fonts/Supplemental/Arial Unicode.ttf",
    "/System/Library/Fonts/Helvetica.ttc",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
  ]
  candidates.find { |path| File.exists?(path) }
end
