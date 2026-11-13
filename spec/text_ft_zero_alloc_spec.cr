require "./spec_helper"
require "spec"
require "../src/tessell/geometry"
require "../src/tessell/text/measurer"
require "../src/tessell/text/ft_measurer"

include Tessell
include Tessell::Text

FT_ZERO_ALLOC_FONT_PATH = "C:\\Windows\\Fonts\\msyh.ttc"

describe "Tessell::Text::FtMeasurer zero-alloc via CachingMeasurer" do
  it "CachingMeasurer(FtMeasurer) cache-hit measures satisfy zero-alloc criterion (GC probe)" do
    unless FtMeasurer.available?
      fail "FtMeasurer not available: #{FtMeasurer.unavailable_reason.inspect}"
    end
    ft = FtMeasurer.open(FT_ZERO_ALLOC_FONT_PATH, 0)
    begin
      c = CachingMeasurer.new(ft)
      n = 1000
      # warmup
      c.measure("Hello", 1, 16.0_f32, 0.0_f32)
      10.times { c.measure("Hello", 1, 16.0_f32, 0.0_f32) }

      # Prime window (diagnostic)
      delta_prime = 0_i64
      GC.collect
      GC.disable
      begin
        before = GC.stats.bytes_since_gc
        n.times { c.measure("Hello", 1, 16.0_f32, 0.0_f32) }
        after = GC.stats.bytes_since_gc
        delta_prime = after.to_i64 - before.to_i64
      ensure
        GC.enable
      end

      # Calib window (diagnostic)
      delta_calib = 0_i64
      calib_sink = 0_i64
      GC.collect
      GC.disable
      begin
        before = GC.stats.bytes_since_gc
        i = 0
        while i < n
          calib_sink &+= i.to_i64
          i += 1
        end
        after = GC.stats.bytes_since_gc
        delta_calib = after.to_i64 - before.to_i64
      ensure
        GC.enable
      end
      calib_sink.should be >= 0_i64

      # 3 work windows. First failure: retry whole 3-window set once (GC noise denoising).
      retried = false
      attempt = 1
      loop do
        work = [] of Int64
        3.times do
          GC.collect
          GC.disable
          begin
            before = GC.stats.bytes_since_gc
            n.times { c.measure("Hello", 1, 16.0_f32, 0.0_f32) }
            after = GC.stats.bytes_since_gc
            work << (after.to_i64 - before.to_i64)
          ensure
            GC.enable
          end
        end
        delta_work = work.max
        seq = "[#{work[0]},#{work[1]},#{work[2]}]"
        puts "zero-alloc probe(text_ft): delta_prime=#{delta_prime} delta_calib=#{delta_calib} delta_work=#{delta_work} N=#{n} windows=#{seq} retried=#{retried} attempt=#{attempt}"
        break if delta_work < n && delta_work <= 256
        if attempt >= 2
          fail "zero-alloc probe: delta_work=#{delta_work} delta_calib=#{delta_calib} delta_prime=#{delta_prime} N=#{n} windows=#{seq} retried=#{retried} attempt=#{attempt}"
        end
        retried = true
        attempt = 2
      end
    ensure
      ft.close
    end
  end
end
