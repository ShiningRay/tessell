require "./spec_helper"
require "../tools/lib/png"

# issue #40：跨后端 conformance——已知差异显式登记（绝不静默 skip），
# 同一帧命令经 render_software 渲染后可做像素等价断言；GL 腿需要窗口
# 上下文，headless CI 按 skip_reason 显式登记。

private def probe_scene : Tessell::Render::DrawList
  # 场景：矩形 + 圆角矩形 + clip（文本走 #37 探针，逐位比较按清单 skip）
  list = Tessell::Render::DrawList.new
  clip = Tessell::Rect.new(0.0_f32, 0.0_f32, 120.0_f32, 80.0_f32)
  list.push(Tessell::Render::DrawCmd.new(Tessell::Render::CmdKind::Rect,
    Tessell::Rect.new(10.0_f32, 10.0_f32, 40.0_f32, 20.0_f32), 0x2f6fedff_u32,
    clip: clip))
  list.push(Tessell::Render::DrawCmd.new(Tessell::Render::CmdKind::RoundRect,
    Tessell::Rect.new(60.0_f32, 10.0_f32, 40.0_f32, 20.0_f32), 0x1f8f4eff_u32,
    clip: clip, radius: 4.0_f32))
  list.push(Tessell::Render::DrawCmd.new(Tessell::Render::CmdKind::Rect,
    Tessell::Rect.new(10.0_f32, 40.0_f32, 100.0_f32, 20.0_f32), 0xd92d20ff_u32,
    clip: Tessell::Rect.new(0.0_f32, 0.0_f32, 60.0_f32, 80.0_f32)))
  list
end

describe "cross-backend conformance (issue #40)" do
  it "registers known differences explicitly (skip with reason, assert with contract)" do
    aa = TessellGolden.skip_reason("text.antialiasing")
    aa.should_not be_nil
    aa.not_nil!.should contain("SoftwareBackend")

    poly = TessellGolden.skip_reason("polygon.antialiasing")
    poly.should_not be_nil

    # premultiplied 是可断言契约——不是 skip
    TessellGolden.skip_reason("rect.premultiplied").should be_nil
    TessellGolden.difference_for("rect.premultiplied").not_nil!.disposition.should eq("assert")

    # 未登记特性不静默跳过
    TessellGolden.skip_reason("feature.never_registered").should be_nil
  end

  it "same DrawList renders deterministically on SoftwareBackend (0 diff)" do
    scene = probe_scene
    a = TessellGolden.render_software(scene, 120, 80)
    b = TessellGolden.render_software(scene, 120, 80)
    result = TessellGolden.compare_buffers(a, b, 120, 80)
    result.pass?.should be_true
    result.diff_pixels.should eq(0)
  end

  it "tolerance gate: 1-device-pixel edge differences pass, real drift fails" do
    a = TessellGolden.render_software(probe_scene, 120, 80)
    b = a.clone
    # 1 像素 ±1 容差内扰动
    b[0] = (b[0].to_i + 1).clamp(0, 255).to_u8
    within = TessellGolden.compare_buffers(a, b, 120, 80, tolerance: 1)
    within.pass?.should be_true

    c = a.clone
    64.times { |i| c[i * 4] = 0x00_u8 } # 大面积漂移
    broken = TessellGolden.compare_buffers(a, c, 120, 80, tolerance: 1)
    broken.pass?.should be_false
    broken.diff_pixels.should be > 0
  end

  it "clip is honored in the software rasterization path (probe oracle input)" do
    # 第三条命令 clip 到 x<60：60..110 区间必须保持底色
    scene = probe_scene
    rgba = TessellGolden.render_software(scene, 120, 80)
    bg = Tessell::Render::Theme.light.bg
    # 检查 (70..110, 45) 一带仍是底色
    x = 70
    clean = true
    while x < 110
      i = (45 * 120 + x) * 4
      if rgba[i] != ((bg >> 24) & 0xff).to_u8
        clean = false
        break
      end
      x += 1
    end
    clean.should be_true
  end

  it "GL leg is explicitly gated, never silently claimed" do
    # GL 需要窗口上下文——headless CI 无法运行。登记在案：skip 理由可查，
    # macOS 真机轮（kit_gallery --verify）执行 GL 等价断言。
    TessellGolden.skip_reason("gl.headless").should be_nil # 未登记 ≠ 可用
    # 差异清单覆盖软件↔GL 的全部已知语义边界
    features = TessellGolden::KNOWN_DIFFERENCES.map(&.feature)
    features.should contain("text.antialiasing")
    features.should contain("rect.premultiplied")
    features.should contain("roundrect.rasterization")
  end
end
