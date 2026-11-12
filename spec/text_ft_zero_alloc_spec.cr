require "spec"
require "../src/tessell/geometry"
require "../src/tessell/text/measurer"
require "../src/tessell/text/ft_measurer"

include Tessell
include Tessell::Text

FT_ZERO_ALLOC_FONT_PATH = "C:\\Windows\\Fonts\\msyh.ttc"

describe "Tessell::Text::FtMeasurer zero-alloc via CachingMeasurer" do
  it "CachingMeasurer(FtMeasurer) 1000 cache-hit measures have delta bytes_since_gc == 0" do
    unless FtMeasurer.available?
      fail "FtMeasurer not available: #{FtMeasurer.unavailable_reason.inspect}"
    end
    ft = FtMeasurer.open(FT_ZERO_ALLOC_FONT_PATH, 0)
    begin
      c = CachingMeasurer.new(ft)
      # warmup
      c.measure("Hello", 1, 16.0_f32, 0.0_f32)
      GC.collect
      GC.disable
      before = GC.stats.bytes_since_gc
      1000.times do
        c.measure("Hello", 1, 16.0_f32, 0.0_f32)
      end
      after = GC.stats.bytes_since_gc
      GC.enable
      delta = after.to_i64 - before.to_i64
      if delta != 0
        fail "zero-alloc cache-hit measure failed: delta bytes_since_gc=#{delta} (expected 0). " \
             "First allocation point unknown without GC profiling; report as-is."
      end
      delta.should eq 0
    ensure
      ft.close
    end
  end
end
