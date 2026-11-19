require "./kit/spec_helper"

# issue #63：CompositeOnly 组合动画——闭式时间函数、manual clock、
# 取消/替换/owner dispose/detach 收口、reduced-motion、无动画停帧。
# 布局动画不属于本协议（合成路径绝不触发 Layout 传播）。

describe "Anim closed-form sampling (issue #63)" do
  it "轨迹由时刻唯一决定：整段推进与逐帧推进同一时刻取值相同" do
    track = Tessell::Anim::Track(String).new(KitSpecHelpers.key, 0_i64,
      opacity_from: 0.0_f32, opacity_to: 1.0_f32, duration_ms: 300_i64)
    a = track.state_at(150_i64)
    # 模拟掉帧：10ms×15 次推进后同一时刻
    clock = Tessell::Anim::Clock.new
    15.times { clock.advance(10_i64) }
    b = track.state_at(clock.now_ms)
    a.opacity.should eq(b.opacity)
    a.opacity.should be > 0.0_f32
    a.opacity.should be < 1.0_f32
  end

  it "delay 阶段保持起点值，结束后取精确终值" do
    track = Tessell::Anim::Track(String).new(KitSpecHelpers.key, 0_i64,
      opacity_from: 0.2_f32, opacity_to: 0.8_f32,
      duration_ms: 100_i64, delay_ms: 50_i64)
    track.state_at(25_i64).opacity.should eq(0.2_f32)
    track.state_at(75_i64).opacity.should be > 0.2_f32
    track.state_at(75_i64).opacity.should be < 0.8_f32
    track.state_at(150_i64).opacity.should eq(0.8_f32)
    track.finished?(150_i64).should be_true
  end

  it "闭式时间函数确定性：spring 解析解在 t=1 收敛到 1" do
    Tessell::Anim::Easing.spring(0.0_f32).should eq(0.0_f32)
    (Tessell::Anim::Easing.spring(1.0_f32) - 1.0_f32).abs.should be < 0.005_f32
    # 同一 t 重复采样结果一致（无内部状态）
    a = Tessell::Anim::Easing.spring(0.37_f32)
    b = Tessell::Anim::Easing.spring(0.37_f32)
    a.should eq(b)
  end

  it "progress 钳制：now 早于 start 为起点值，不产生负进度" do
    track = Tessell::Anim::Track(String).new(KitSpecHelpers.key, 100_i64,
      opacity_from: 0.0_f32, opacity_to: 1.0_f32, duration_ms: 100_i64)
    track.state_at(50_i64).opacity.should eq(0.0_f32)
    track.finished?(50_i64).should be_false
  end
end

describe "Anim::Runner lifecycle (issue #63)" do
  it "animate 替换同 key：旧轨触发 on_cancel，新轨生效" do
    runner = Tessell::Anim::Runner(String).new
    cancelled = 0
    old = Tessell::Anim::Track(String).new(KitSpecHelpers.key, 0_i64, duration_ms: 100_i64)
    old.on_cancel = ->{ cancelled += 1 }
    runner.animate(old)
    new = Tessell::Anim::Track(String).new(KitSpecHelpers.key, 0_i64, duration_ms: 200_i64)
    new.on_cancel = ->{ cancelled += 1 }
    runner.animate(new)
    cancelled.should eq(1)
    runner.track_count.should eq(1)
    runner.cancel(KitSpecHelpers.key).should be_true
    cancelled.should eq(2)
    runner.active?.should be_false
  end

  it "cancel 后 tick 不再推进，on_finish 不触发" do
    runner = Tessell::Anim::Runner(String).new
    finished = 0
    track = Tessell::Anim::Track(String).new(KitSpecHelpers.key, 0_i64,
      duration_ms: 10_i64)
    track.on_finish = ->{ finished += 1 }
    runner.animate(track)
    applier = RecordingApplier.new
    runner.cancel(KitSpecHelpers.key)
    runner.tick(1000_i64, false, applier)
    finished.should eq(0)
    applier.calls.should eq(0)
  end

  it "cancel_owner 收口 owner 名下全部轨" do
    runner = Tessell::Anim::Runner(String).new
    t1 = Tessell::Anim::Track(String).new(KitSpecHelpers.key, 0_i64, duration_ms: 100_i64, owner: "comp-a")
    t2 = Tessell::Anim::Track(String).new(KitSpecHelpers.key.child(1_u64), 0_i64, duration_ms: 100_i64, owner: "comp-a")
    t3 = Tessell::Anim::Track(String).new(KitSpecHelpers.key.child(2_u64), 0_i64, duration_ms: 100_i64, owner: "comp-b")
    runner.animate(t1)
    runner.animate(t2)
    runner.animate(t3)
    runner.cancel_owner("comp-a").should eq(2)
    runner.track_count.should eq(1)
    runner.cancel_owner("missing").should eq(0)
  end

  it "tick 完成：应用终值、移除轨、触发 on_finish；无动画停帧" do
    runner = Tessell::Anim::Runner(String).new
    finished = 0
    track = Tessell::Anim::Track(String).new(KitSpecHelpers.key, 0_i64,
      opacity_from: 0.0_f32, opacity_to: 0.5_f32, duration_ms: 100_i64)
    track.on_finish = ->{ finished += 1 }
    runner.animate(track)
    applier = RecordingApplier.new
    runner.active?.should be_true
    runner.tick(50_i64, false, applier).should eq(1)
    runner.tick(100_i64, false, applier).should eq(0)
    finished.should eq(1)
    applier.last_state.not_nil!.opacity.should eq(0.5_f32)
    # 无动画：active? false——宿主据此停帧
    runner.active?.should be_false
    runner.tick(200_i64, false, applier).should eq(0)
  end

  it "detach 收口：applier 返回 false 时静默移除，无回调" do
    runner = Tessell::Anim::Runner(String).new
    callbacks = 0
    track = Tessell::Anim::Track(String).new(KitSpecHelpers.key, 0_i64, duration_ms: 100_i64)
    track.on_finish = ->{ callbacks += 1 }
    track.on_cancel = ->{ callbacks += 1 }
    runner.animate(track)
    applier = MissingApplier.new # 目标不在树（组件已 detach）
    runner.tick(50_i64, false, applier).should eq(0)
    runner.active?.should be_false
    callbacks.should eq(0) # 静默收口，不触发任何回调
  end

  it "reduced-motion：首 tick 直接落到终值并完成" do
    runner = Tessell::Anim::Runner(String).new
    track = Tessell::Anim::Track(String).new(KitSpecHelpers.key, 0_i64,
      opacity_from: 0.0_f32, opacity_to: 1.0_f32, duration_ms: 500_i64)
    runner.animate(track)
    applier = RecordingApplier.new
    runner.tick(10_i64, true, applier).should eq(0)
    applier.last_state.not_nil!.opacity.should eq(1.0_f32)
    runner.active?.should be_false
  end
end

describe "Kit::Root composite animation protocol (issue #63)" do
  it "稳态只产生 CompositeOnly：不触发 Layout/Paint，命令数与文本测量数不变" do
    col = Tessell::Kit::Column.new(KitSpecHelpers.key, Tessell::Insets.all(4.0_f32), 4.0_f32)
    text = Tessell::Kit::Text.new(KitSpecHelpers.key.child(1_u64), "animated label")
    button = Tessell::Kit::Button.new(KitSpecHelpers.key.child(2_u64), "OK")
    col.add(text)
    col.add(button)
    root = Tessell::Kit::Root.new(col)
    root.layout(300.0_f32, 200.0_f32)
    root.build
    base_buf_size = root.decl_count
    base_misses = root.context.text_cache_stats[:misses]

    key = text.key
    root.animate_composite(key, 0_i64, opacity_from: 0.0_f32, opacity_to: 1.0_f32,
      duration_ms: 300_i64)
    node = root.pool.map[key].not_nil!

    clock = Tessell::Anim::Clock.new
    i = 0
    while i < 6
      clock.advance(40_i64)
      root.tick_animations(clock)
      # 合成轨推进中：最高脏级别必须是 CompositeOnly（绝不 Layout/Paint）
      if dirty = node.dirty?
        dirty.should eq(Tessell::Invalidation::CompositeOnly)
      end
      root.build # 宿主正常提交流程（不做 layout）
      root.decl_count.should eq(base_buf_size) # 声明数不变（不重建）
      i += 1
    end
    root.context.text_cache_stats[:misses].should eq(base_misses) # 文本零重测

    # 动画完成 → 无活动动画（宿主停帧依据）
    12.times { clock.advance(40_i64); root.tick_animations(clock) }
    root.animations_active?.should be_false
  end

  it "取消动画后 Node 不再被 tick 改写" do
    col = Tessell::Kit::Column.new(KitSpecHelpers.key)
    text = Tessell::Kit::Text.new(KitSpecHelpers.key.child(1_u64), "x")
    col.add(text)
    root = Tessell::Kit::Root.new(col)
    root.layout(200.0_f32, 100.0_f32)
    root.build
    root.animate_composite(text.key, 0_i64, opacity_from: 1.0_f32, opacity_to: 0.0_f32,
      duration_ms: 200_i64)
    clock = Tessell::Anim::Clock.new
    clock.advance(50_i64)
    root.tick_animations(clock)
    node = root.pool.map[text.key].not_nil!
    mid_opacity = node.opacity
    mid_opacity.should be < 1.0_f32
    root.cancel_composite(text.key).should be_true
    clock.advance(150_i64)
    root.tick_animations(clock)
    node.opacity.should eq(mid_opacity) # 不再被推进
  end

  it "owner dispose 收口：组件移出树后其名下轨被取消（无泄漏）" do
    col = Tessell::Kit::Column.new(KitSpecHelpers.key)
    text = Tessell::Kit::Text.new(KitSpecHelpers.key.child(1_u64), "x")
    col.add(text)
    root = Tessell::Kit::Root.new(col)
    root.layout(200.0_f32, 100.0_f32)
    root.build
    root.animate_composite(text.key, 0_i64, opacity_from: 1.0_f32, opacity_to: 0.0_f32,
      duration_ms: 500_i64, owner: text)
    root.animations_active?.should be_true
    # 无窗口验证走 --frames 截图路径不可用，这里用工具口径直接验证：
    root.cancel_anim_owner(text).should eq(1)
    root.animations_active?.should be_false
  end

  it "pause/resume：暂停时采样冻结，恢复后从冻结点继续" do
    runner = Tessell::Anim::Runner(String).new
    track = Tessell::Anim::Track(String).new(KitSpecHelpers.key, 0_i64,
      opacity_from: 0.0_f32, opacity_to: 1.0_f32, duration_ms: 400_i64)
    runner.animate(track)
    applier = RecordingApplier.new
    clock = Tessell::Anim::Clock.new
    clock.advance(100_i64)
    runner.tick(clock.now_ms, false, applier)
    frozen = applier.last_state.not_nil!.opacity
    clock.pause
    clock.advance(1000_i64) # 暂停期间推进无效（离屏/最小化冻结语义）
    clock.now_ms.should eq(100_i64)
    runner.tick(clock.now_ms, false, applier)
    applier.last_state.not_nil!.opacity.should eq(frozen)
    clock.resume
    clock.advance(100_i64)
    runner.tick(clock.now_ms, false, applier)
    resumed = applier.last_state.not_nil!.opacity
    resumed.should be > frozen
    resumed.should be < 1.0_f32
  end
end

# 测试桩：记录最后一次写入（BufferedApplier 不需要零分配口径）
private class RecordingApplier < Tessell::Anim::Applier
  getter calls : Int32
  property last_state : Tessell::Anim::CompositeState?

  def initialize
    @calls = 0
    @last_state = nil
  end

  def apply(key : Tessell::UI::UiKey, state : Tessell::Anim::CompositeState) : Bool
    @calls += 1
    @last_state = state
    true
  end
end

private class MissingApplier < Tessell::Anim::Applier
  def apply(key : Tessell::UI::UiKey, state : Tessell::Anim::CompositeState) : Bool
    false
  end
end

describe "Anim steady-state allocation (issue #63)" do
  it "稳态 tick 分配字节有界（GC 探针，口径同零分配探针）" do
    col = Tessell::Kit::Column.new(KitSpecHelpers.key)
    text = Tessell::Kit::Text.new(KitSpecHelpers.key.child(1_u64), "steady tick")
    col.add(text)
    root = Tessell::Kit::Root.new(col)
    root.layout(200.0_f32, 100.0_f32)
    root.build
    # 长时长轨 + 时钟不推进：稳态 tick = 采样 + 比较后不写（最便宜路径）
    root.animate_composite(text.key, 0_i64, opacity_from: 1.0_f32,
      opacity_to: 0.0_f32, duration_ms: 1_000_000_i64)
    clock = Tessell::Anim::Clock.new
    clock.advance(10_i64)
    root.tick_animations(clock)

    n = 1000
    GC.collect
    GC.disable
    begin
      before = GC.stats.bytes_since_gc
      i = 0
      while i < n
        root.tick_animations(clock)
        i += 1
      end
      delta = GC.stats.bytes_since_gc - before
    ensure
      GC.enable
    end
    # 判据：每 tick 分配 < 1 字节量级（余量 256B 对齐 text_ft 探针口径）
    (delta < n && delta <= 256).should be_true, "稳态 tick 分配 #{delta}B / #{n} ticks"
  end
end
