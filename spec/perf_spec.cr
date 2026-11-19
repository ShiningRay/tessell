require "./spec_helper"
require "../src/tessell/kit"

# issue #60：帧/提交分段观测。
# - 分段区分 input/build/layout/paint/present 的 op 数与调用数；同一帧可读出
#   各段命令数；静止画面（无失效）五段全零 op——「静止无多余提交」验收。
# - 失效→呈现延迟：帧粒度近似（失效年龄帧数）；跨 Isolated context 只记
#   hop 计数不做跨钟差（两钟不同源）。
# - 默认关闭：disabled 时 record/frame_start/frame_end 全 no-op，不产生
#   样本、不改变计数基线（AGENTS #10：测量关闭不改基线）。
# - p50/p95/p99 仅读取面（overlay/离线 JSON），固定样本集上验证分位数
#   数学；绝不把分布写进门禁判据。

describe "App::PerfCollector 分段观测（issue #60）" do
  it "默认关闭：记录调用零副作用，样本为空" do
    perf = Tessell::App::PerfCollector.new # enabled 默认 false
    perf.frame_start
    perf.record_ops(:build, 42)
    perf.record(:paint, 100, 0_i64, 5_i64)
    perf.mark_invalidated(3)
    perf.record_hop
    perf.frame_end(16.0_f32)
    perf.sample_size.should eq(0)
    perf.frame_count.should eq(0)
    perf.latest.should be_nil
    perf.hop_count.should eq(0)
    perf.idle_last_frame?.should be_true
    perf.enabled?.should be_false
  end

  it "启用后：同一帧可区分五段 op 数与调用数" do
    perf = Tessell::App::PerfCollector.new(enabled: true)
    perf.frame_start
    perf.record_ops(:input, 6)    # 泵入 6 事件
    perf.record_ops(:build, 24)   # 24 条 decl
    perf.record_ops(:layout, 30)  # 30 节点 arrange
    perf.record_ops(:paint, 48)   # 48 绘制命令
    perf.record_ops(:present, 1)  # 1 次 swap
    perf.frame_end(16.6_f32)
    s = perf.latest.not_nil!
    s.seg_ops[0].should eq(6)
    s.seg_ops[1].should eq(24)
    s.seg_ops[2].should eq(30)
    s.seg_ops[3].should eq(48)
    s.seg_ops[4].should eq(1)
    s.seg_calls[1].should eq(1)
    perf.frame_count.should eq(1)
    perf.idle_last_frame?.should be_false
  end

  it "静止画面：无失效帧五段全零 op（idle 判定）" do
    perf = Tessell::App::PerfCollector.new(enabled: true)
    perf.frame_start
    perf.frame_end(16.0_f32) # 什么都没做的一帧
    perf.idle_last_frame?.should be_true
    # 有失效后非 idle
    perf.frame_start
    perf.mark_invalidated(1)
    perf.record_ops(:paint, 3)
    perf.frame_end(5.0_f32)
    perf.idle_last_frame?.should be_false
  end

  it "失效→呈现延迟：帧粒度年龄计数，present 后归零" do
    perf = Tessell::App::PerfCollector.new(enabled: true)
    perf.frame_start
    perf.mark_invalidated(2) # 第 0 帧失效
    perf.frame_end(16.0_f32)
    perf.latest.not_nil!.invalidation_lag_frames.should eq(0)
    # 失效后两帧才 present：年龄在后续帧累计（宿主时钟推进但不 present 期间）
    perf.frame_start
    perf.frame_end(16.0_f32) # 失效状态跨帧，年龄+1
    perf.frame_start
    perf.frame_end(16.0_f32)
    perf.latest.not_nil!.invalidation_lag_frames.should eq(2)
    # present 帧（paint/present 段有 op）→ 年龄归零
    perf.frame_start
    perf.record_ops(:present, 1)
    perf.frame_end(16.0_f32)
    perf.latest.not_nil!.invalidation_lag_frames.should eq(0)
  end

  it "hop 计数：跨上下文提交只计数，不做跨钟差" do
    perf = Tessell::App::PerfCollector.new(enabled: true)
    3.times { perf.record_hop }
    perf.hop_count.should eq(3)
  end

  it "环形缓冲有界：超过 SAMPLE_CAP 后覆盖最旧样本" do
    perf = Tessell::App::PerfCollector.new(enabled: true)
    total = Tessell::App::PerfCollector::SAMPLE_CAP + 10
    i = 0
    while i < total
      perf.frame_start
      perf.record_ops(:build, i + 1)
      perf.frame_end(1.0_f32)
      i += 1
    end
    perf.sample_size.should eq(Tessell::App::PerfCollector::SAMPLE_CAP)
    perf.frame_count.should eq(total)
    # 最旧样本是第 10 帧（0..9 被覆盖），ops=11
    perf.sample(0).not_nil!.seg_ops[1].should eq(11)
    perf.latest.not_nil!.seg_ops[1].should eq(total)
  end

  it "分位数：固定样本集上 p50/p95 数学正确（仅读取面，不进门禁）" do
    perf = Tessell::App::PerfCollector.new(enabled: true)
    # 100 帧样本：paint op = 帧号+1（1..100）
    i = 0
    while i < 100
      perf.frame_start
      perf.record_ops(:paint, i + 1)
      perf.frame_end(1.0_f32 + i.to_f32 / 100.0_f32)
      i += 1
    end
    perf.percentile(:paint, 50.0_f32).should be_close(50.5_f32, 1.0_f32)
    perf.percentile(:paint, 95.0_f32).should be_close(95.05_f32, 1.5_f32)
    perf.percentile_frame_ms(50.0_f32).should be_close(1.5_f32, 0.05_f32)
    # JSON 离线读取面可解析且含分段键
    json = perf.to_json_string
    json.should contain("\"p95_frame_ms\"")
    json.should contain("\"build\"")
    json.should contain("\"present\"")
  end

  it "启用开关中途切换：关闭后的帧不进样本" do
    perf = Tessell::App::PerfCollector.new(enabled: true)
    perf.frame_start
    perf.frame_end(10.0_f32)
    perf.enabled = false
    perf.frame_start
    perf.frame_end(20.0_f32)
    perf.frame_count.should eq(1)
    perf.latest.not_nil!.frame_ms.should eq(10.0_f32)
  end
end

describe "DebugInfo perf 行（issue #60 F1 overlay 接线）" do
  it "perf_summary 空串时不占 overlay 行；有值时占一行" do
    info = Tessell::Kit::DebugInfo.new
    info.perf_summary.should eq("")
    info2 = Tessell::Kit::DebugInfo.new(perf_summary: "perf p50=16.0 p95=18.0ms")
    info2.perf_summary.should contain("p95")
  end

  it "PerfCollector 摘要文本可生成（宿主接线用）" do
    perf = Tessell::App::PerfCollector.new(enabled: true)
    perf.frame_start
    perf.record_ops(:paint, 10)
    perf.frame_end(16.0_f32)
    s = perf.latest.not_nil!
    line = "perf f=#{perf.frame_count} p50=#{perf.percentile_frame_ms(50.0_f32).round(1)}ms " \
           "ops[input/build/layout/paint/present]=#{s.seg_ops[0]}/#{s.seg_ops[1]}/" \
           "#{s.seg_ops[2]}/#{s.seg_ops[3]}/#{s.seg_ops[4]}"
    line.should contain("ops[")
    line.should contain("10")
  end
end
