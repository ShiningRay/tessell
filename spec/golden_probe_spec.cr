require "./spec_helper"
require "../tools/lib/png"

# issue #37：golden 探针模式——注册标记定位 + Edge/Mix 量测断言。
# 同一组探针断言在 scale=1.0/1.5/2.0 全过，无需按 DPI 重录 golden：
# 期望值全部由标记推出的 px/pt 比例换算，断言与 DPI 解耦。

# 颜色格式 0xRRGGBBAA（alpha 在低位，Theme.ab 口径）
MARK = 0xff00ffff_u32      # 品红注册标记（R=ff G=00 B=ff A=ff）
FG   = 0x2f6fedff_u32      # 前景（accent 蓝，不透明）
BG   = Tessell::Render::Theme.light.bg
MIX  = 0x2f6fed80_u32      # 同色 50% alpha（premultiplied 语义的量测探针）

# 画一帧探针场景（逻辑 pt 坐标，scale 由 SoftwareBackend 处理）：
#   - 两个品红标记：(20,4) 与 (120,4)，相距 100pt；
#   - 一个实心 FG 矩形：左边缘在 x=40pt；
#   - 一个 50% MIX 矩形：x=150..190pt。
private def render(scale : Float32) : {Int32, Int32, Bytes}
  w = (220 * scale).round.to_i
  h = (40 * scale).round.to_i
  backend = Tessell::Render::SoftwareBackend.new
  backend.init(w, h)
  backend.begin_frame(nil, Tessell::Render::Theme.light)

  list = Tessell::Render::DrawList.new
  [
    # 1px 精确锚点（scale 整除 20/120×1.5/2.0）
    {Tessell::Rect.new(20.0_f32 * scale, 4.0_f32 * scale, 1.0_f32, 1.0_f32), MARK},
    {Tessell::Rect.new(120.0_f32 * scale, 4.0_f32 * scale, 1.0_f32, 1.0_f32), MARK},
    {Tessell::Rect.new(40.0_f32 * scale, 10.0_f32 * scale, 60.0_f32 * scale, 20.0_f32 * scale), FG},
    {Tessell::Rect.new(150.0_f32 * scale, 10.0_f32 * scale, 40.0_f32 * scale, 20.0_f32 * scale), MIX},
  ].each do |rect, color|
    list.push(Tessell::Render::DrawCmd.new(Tessell::Render::CmdKind::Rect, rect, color))
  end
  backend.draw_draw_list(list)
  backend.end_frame

  rgba = Bytes.new(w * h * 4)
  y = 0
  while y < h
    x = 0
    while x < w
      px = backend.pixel(x, y)
      i = (y * w + x) * 4
      rgba[i] = ((px >> 24) & 0xff).to_u8
      rgba[i + 1] = ((px >> 16) & 0xff).to_u8
      rgba[i + 2] = ((px >> 8) & 0xff).to_u8
      rgba[i + 3] = (px & 0xff).to_u8
      x += 1
    end
    y += 1
  end
  {w, h, rgba}
end

describe "golden probe mode (issue #37)" do
  it "locates registration marks and derives px/pt scale at every DPI" do
    [1.0_f32, 1.5_f32, 2.0_f32].each do |scale|
      w, h, rgba = render(scale)
      marks = TessellGolden.locate_marks(rgba, w, h, MARK)
      marks.size.should eq(2) # 两个 1px 锚点

      px_per_pt = TessellGolden.scale_from_marks(marks, 100.0_f32)
      px_per_pt.should be_close(scale, 0.01_f32) # 标记相距 100pt
    end
  end

  it "Edge probe: the 0.5 crossing lands at the mark-derived position (±1 device px)" do
    [1.0_f32, 1.5_f32, 2.0_f32].each do |scale|
      w, h, rgba = render(scale)
      marks = TessellGolden.locate_marks(rgba, w, h, MARK)
      px_per_pt = TessellGolden.scale_from_marks(marks, 100.0_f32)

      # 扫描线 y=20pt（穿 FG 矩形），剖面取 R 通道（蓝底 R 低、FG R=0x2f 低——
      # 用 B 通道更分明：bg B=0xff，fg B=0xed——仍相近；改用 G：bg=0xf7，fg=0x6f）
      scan_y = (20.0_f32 * scale).round.to_i
      profile = TessellGolden.profile(rgba, w, h, 0, scan_y, w - 1, scan_y, 1)
      crossings = TessellGolden.crossings(profile)

      # 矩形左缘 x=40pt（R 通道：bg 亮 → fg 暗的下穿）与右缘 100pt（上穿）
      expected_left = 40.0_f32 * px_per_pt
      expected_right = 100.0_f32 * px_per_pt
      crossings.size.should eq(2)
      (crossings[0] - expected_left).abs.should be <= 1.0_f32
      (crossings[1] - expected_right).abs.should be <= 1.0_f32
    end
  end

  it "Mix probe: 50% alpha rect reads back ~0.5 blend ratio at every DPI" do
    [1.0_f32, 2.0_f32].each do |scale|
      w, h, rgba = render(scale)
      # MIX 矩形中心 20x10pt 区域（避开边缘抗锯齿）
      cx = (150.0_f32 * scale).round.to_i + (2.0_f32 * scale).round.to_i
      cy = (10.0_f32 * scale).round.to_i + (2.0_f32 * scale).round.to_i
      rw = (36.0_f32 * scale).round.to_i
      rh = (16.0_f32 * scale).round.to_i
      ratio = TessellGolden.mix_ratio(rgba, w, h, cx, cy, rw, rh, FG, BG)
      ratio.should be_close(0.5_f32, 0.05_f32)
    end
  end

  it "sigma probe: soft band edge-to-edge distance halves into sigma" do
    w = 50
    h = 4
    rgba = Bytes.new(w * h * 4)
    # 软边带：x∈[10,20) 线性上升、[20,30) 平台、[30,40) 线性下降
    y = 0
    while y < h
      x = 0
      while x < w
        i = (y * w + x) * 4
        v = if x < 10
              0.0_f32
            elsif x < 20
              (x - 10).to_f32 / 10.0_f32 * 255.0_f32
            elsif x < 30
              255.0_f32
            elsif x < 40
              (1.0_f32 - (x - 30).to_f32 / 10.0_f32) * 255.0_f32
            else
              0.0_f32
            end
        g = v.round.to_u8
        rgba[i] = g
        rgba[i + 1] = g
        rgba[i + 2] = g
        rgba[i + 3] = 255_u8
        x += 1
      end
      y += 1
    end
    profile = TessellGolden.profile(rgba, w, h, 0, 2, w - 1, 2, 0)
    sigma = TessellGolden.sigma_between_edges(profile)
    sigma.should_not be_nil
    # 两个 0.5 交叉在 ~15 与 ~35 → 间距 20 → σ=10
    sigma.not_nil!.should be_close(10.0_f32, 1.0_f32)
  end
end
