require "./spec_helper"

# issue #24：文本测量缓存有界化 + 观测面 + 责任契约。
# 键含文本内容 → 正确性不依赖清空；容量两代淘汰（cur 满 4096 换代）。

private def new_ctx : Tessell::Kit::Context
  Tessell::Kit::Context.new(Tessell::Kit::Theme.light,
    Tessell::Kit::StubTextMetrics.new, 1.0_f32)
end

describe "Context measure cache (issue #24)" do
  it "counts hits and misses" do
    ctx = new_ctx
    ctx.measure_text("abc", 14.0_f32)
    ctx.measure_text("abc", 14.0_f32)

    ctx.text_cache_misses.should eq(1)
    ctx.text_cache_hits.should eq(1)
    ctx.text_cache_size.should eq(1)
    ctx.text_cache_stats[:misses].should eq(1)
  end

  it "stays bounded under a churning text set" do
    ctx = new_ctx
    i = 0
    while i < 5000
      ctx.measure_text("row-#{i}", 14.0_f32)
      i += 1
    end

    ctx.text_cache_size.should be <= Tessell::Kit::Context::MEASURE_CACHE_CAP
    ctx.text_cache_size.should be > 0
  end

  it "keeps the working set across a generation rotation" do
    ctx = new_ctx
    # 填满一代并触发换代
    i = 0
    while i < Tessell::Kit::Context::MEASURE_CACHE_CAP + 10
      ctx.measure_text("gen-#{i}", 14.0_f32)
      i += 1
    end
    misses_before = ctx.text_cache_misses

    # old 代里第一条仍在：命中提升回 cur，不再产生新 miss
    ctx.measure_text("gen-0", 14.0_f32)
    ctx.text_cache_misses.should eq(misses_before)
    ctx.text_cache_hits.should be > 0
  end

  it "never returns stale values: content change is a new key" do
    ctx = new_ctx
    a = ctx.measure_text("total", 14.0_f32)
    b = ctx.measure_text("total ", 14.0_f32)
    a.should_not eq(b)

    # 不调用 clear 也正确——组件改内容不需要记得清缓存
    again = ctx.measure_text("total", 14.0_f32)
    again.should eq(a)
  end

  it "clear_text_cache empties both generations" do
    ctx = new_ctx
    ctx.measure_text("x", 14.0_f32)
    ctx.measure_text("y", 14.0_f32, 100.0_f32)
    ctx.clear_text_cache

    ctx.text_cache_size.should eq(0)
    misses_before = ctx.text_cache_misses
    ctx.measure_text("x", 14.0_f32)
    ctx.text_cache_misses.should eq(misses_before + 1)
  end
end
