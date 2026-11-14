require "./spec_helper"

# issue #36：性能正确性全部用计数表达——measure 调用数、批数、事件路由
# 次数、帧命令数。wall-clock 只属于人工 bench（tools/bench_frame_time.cr），
# 不进门禁。布局增量的计数断言见 spec/layout_cached_spec.cr（#34）。

describe "counting assertions (issue #36)" do
  it "Kit text measurement: second frame has zero cache misses (hit counting)" do
    texts = Tessell::Kit::Column.new(KitSpecHelpers.key, Tessell::Insets.all(0.0_f32), 0.0_f32)
      .tap do |col|
        col.add(Tessell::Kit::Text.new(KitSpecHelpers.key.child(1_u64), "alpha"))
        col.add(Tessell::Kit::Text.new(KitSpecHelpers.key.child(2_u64), "beta"))
      end
    root = Tessell::Kit::Root.new(texts, metrics: Tessell::Kit::StubTextMetrics.new)
    root.layout(200.0_f32, 100.0_f32)
    first_misses = root.context.text_cache_stats[:misses]
    first_misses.should be >= 2 # 每种文本至少一次实测

    root.layout(200.0_f32, 100.0_f32)
    root.context.text_cache_stats[:misses].should eq(first_misses) # 第二帧零新增 miss
  end

  it "batching: N same-atlas same-clip commands collapse into exactly 1 batch" do
    list = Tessell::Render::DrawList.new
    clip = Tessell::Rect.new(0.0_f32, 0.0_f32, 100.0_f32, 100.0_f32)
    i = 0
    while i < 8
      list.push(Tessell::Render::DrawCmd.new(Tessell::Render::CmdKind::Rect,
        Tessell::Rect.new(0.0_f32, i * 10.0_f32, 10.0_f32, 10.0_f32), 0xff000000_u32,
        atlas_id: 0, clip: clip))
      i += 1
    end
    list.build_batches.size.should eq(1) # 8 命令 → 1 批

    # atlas 变化切批
    list.push(Tessell::Render::DrawCmd.new(Tessell::Render::CmdKind::Rect,
      Tessell::Rect.new(0.0_f32, 80.0_f32, 10.0_f32, 10.0_f32), 0xff000000_u32,
      atlas_id: 1, clip: clip))
    list.build_batches.size.should eq(2)
  end

  it "event routing: one click → exactly one activation; keydown reaches exactly one focused component" do
    clicks = 0
    button = Tessell::Kit::Button.new(KitSpecHelpers.key, "Save")
    button.on_click = -> { clicks += 1; nil }
    root = Tessell::Kit::Root.new(button)
    root.layout(200.0_f32, 100.0_f32)
    root.build

    root.handle(Tessell::Input::Event.pointer_down(20.0_f32, 10.0_f32, timestamp_ms: 100_i64))
    root.handle(Tessell::Input::Event.pointer_up(20.0_f32, 10.0_f32, timestamp_ms: 120_i64))
    clicks.should eq(1) # 按压+抬起 = 一次语义回调（不双发）

    # 重复抬起不重复触发（无按压目标）
    root.handle(Tessell::Input::Event.pointer_up(20.0_f32, 10.0_f32, timestamp_ms: 130_i64))
    clicks.should eq(1)

    # 键盘激活同口径
    key_activations = 0
    button2 = Tessell::Kit::Button.new(KitSpecHelpers.key.child(9_u64), "Key")
    button2.on_click = -> { key_activations += 1; nil }
    root2 = Tessell::Kit::Root.new(button2)
    root2.layout(200.0_f32, 100.0_f32)
    root2.build
    root2.handle(Tessell::Input::Event.key_down(Tessell::Input::KeyCode::Tab))
    root2.handle(Tessell::Input::Event.key_down(Tessell::Input::KeyCode::Space, timestamp_ms: 100_i64))
    root2.handle(Tessell::Input::Event.key_up(Tessell::Input::KeyCode::Space, timestamp_ms: 120_i64))
    key_activations.should eq(1)
  end

  it "frame command count: idle button paint emits a fixed number of commands" do
    button = Tessell::Kit::Button.new(KitSpecHelpers.key, "Save")
    root = Tessell::Kit::Root.new(button)
    root.layout(200.0_f32, 40.0_f32)
    root.build

    d = Tessell::Kit::DrawListPainter.new
    button.paint(d, root.context)
    # 背景 fill_round_rect + 边框 stroke_round_rect + 文本 = 3（未聚焦无焦点环）
    d.list.size.should eq(3)

    # 聚焦后恰多一个焦点环
    root.focus(button)
    d.reset
    button.paint(d, root.context)
    d.list.size.should eq(4)
  end
end
