require "spec"
require "../src/tessell"

# Issue #3：平台无关帧循环契约。平台宿主驱动 advance/should_stop?，
# 业务只写 on_frame；自动化帧数、虚拟时钟、帧预算、干净退出。
describe "Tessell::App::Runner" do
  it "on_frame runs per advance and counts frames" do
    r = Tessell::App::Runner.new
    ticks = 0
    r.on_frame { |runner| ticks += 1 }
    r.advance(16_i64).should be_false
    r.advance(32_i64).should be_false
    ticks.should eq(2)
    r.frame_count.should eq(2)
  end

  it "frames_limit stops automatically after N frames" do
    r = Tessell::App::Runner.new
    r.frames_limit = 3
    3.times { r.advance(0_i64) }
    r.should_stop?.should be_true
    r.frame_count.should eq(3)
    # 超额 advance 不再执行业务
    called = 0
    r.on_frame { called += 1 }
    r.advance(0_i64).should be_true
    called.should eq(0)
  end

  it "stop() exits cleanly on the next pump" do
    r = Tessell::App::Runner.new
    r.advance(0_i64)
    r.stop
    r.advance(16_i64).should be_true
    r.frame_count.should eq(1)
  end

  it "virtual clock advances with frame deltas (monotonic)" do
    r = Tessell::App::Runner.new
    r.advance(16_i64)
    r.advance(48_i64)
    r.clock_ms.should eq(32_i64)
  end

  it "frame_budget counts slow frames" do
    r = Tessell::App::Runner.new
    r.frame_budget_ms = 8.0_f32
    r.advance(0_i64)
    r.advance(20_i64)   # 帧耗时 20ms > 8ms
    r.advance(24_i64)   # 帧耗时 4ms
    r.slow_frames.should eq(1)
    r.frame_ms.round(0).should eq(4.0_f32)
  end

  it "drives a platform-style loop until automation limit" do
    r = Tessell::App::Runner.new
    r.frames_limit = 5
    painted = 0
    r.on_frame { painted += 1 }
    pump = -> { !r.advance(0_i64) }  # 平台泵：true 表示继续
    count = 0
    while pump.call && count < 100
      count += 1
    end
    painted.should eq(5)
  end
end
