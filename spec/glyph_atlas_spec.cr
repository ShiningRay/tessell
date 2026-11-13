require "./spec_helper"
require "spec"
require "../src/tessell/text/glyph_atlas"

include Tessell::Text

describe GlyphAtlas do
  it "shelf packing: 50 random-sized glyphs do not overlap and stay within page bounds" do
    atlas = GlyphAtlas.new(1024)
    rng = Random.new(12345_u64)
    slots = [] of GlyphSlot
    50.times do |i|
      w = rng.rand(8..96)
      h = rng.rand(8..96)
      key = GlyphKey.new(1, i.to_u32, 16, 0_u8, 0_u8)
      slots << atlas.insert(key, w, h, 0, 0, w.to_f32)
    end
    # no overlap pairwise
    i = 0
    while i < slots.size
      a = slots[i]
      a.x.should be >= 0
      a.y.should be >= 0
      (a.x + a.w).should be <= 1024
      (a.y + a.h).should be <= 1024
      j = i + 1
      while j < slots.size
        b = slots[j]
        if a.page == b.page
          overlap = !(a.x + a.w <= b.x || b.x + b.w <= a.x || a.y + a.h <= b.y || b.y + b.h <= a.y)
          overlap.should be_false
        end
        j += 1
      end
      i += 1
    end
  end

  it "same key lookup returns same slot and used_pixels does not increase" do
    atlas = GlyphAtlas.new(1024)
    key = GlyphKey.new(1, 42_u32, 16, 0_u8, 0_u8)
    s1 = atlas.insert(key, 20, 20, 1, 2, 10.0_f32)
    used1 = atlas.used_pixels
    s2 = atlas.lookup(key)
    s2.should_not be_nil
    if s2
      s2.page.should eq s1.page
      s2.x.should eq s1.x
      s2.y.should eq s1.y
      s2.w.should eq s1.w
      s2.h.should eq s1.h
    end
    s3 = atlas.insert(key, 20, 20, 1, 2, 10.0_f32)
    s3.page.should eq s1.page
    s3.x.should eq s1.x
    atlas.used_pixels.should eq used1
  end

  it "page expansion keeps existing slot coordinates stable" do
    atlas = GlyphAtlas.new(256)
    key1 = GlyphKey.new(1, 1_u32, 16, 0_u8, 0_u8)
    s1 = atlas.insert(key1, 200, 200, 0, 0, 1.0_f32)
    atlas.page_count.should eq 1
    # force new page
    key2 = GlyphKey.new(1, 2_u32, 16, 0_u8, 0_u8)
    s2 = atlas.insert(key2, 200, 200, 0, 0, 1.0_f32)
    atlas.page_count.should be >= 2
    s1_after = atlas.lookup(key1)
    s1_after.should_not be_nil
    if s1_after
      s1_after.page.should eq s1.page
      s1_after.x.should eq s1.x
      s1_after.y.should eq s1.y
      s1_after.w.should eq s1.w
      s1_after.h.should eq s1.h
    end
    s2.page.should_not eq s1.page
  end

  it "GlyphKey equality and hash: same key equal/hash-equal; different subpixel/flags differ" do
    a = GlyphKey.new(1, 100_u32, 16, 0_u8, 0_u8)
    b = GlyphKey.new(1, 100_u32, 16, 0_u8, 0_u8)
    c = GlyphKey.new(1, 100_u32, 16, 1_u8, 0_u8)
    d = GlyphKey.new(1, 100_u32, 16, 0_u8, 1_u8)
    e = GlyphKey.new(2, 100_u32, 16, 0_u8, 0_u8)
    (a == b).should be_true
    a.hash.should eq b.hash
    (a == c).should be_false
    (a == d).should be_false
    (a == e).should be_false
    atlas = GlyphAtlas.new(256)
    atlas.insert(a, 10, 10)
    atlas.insert(c, 10, 10)
    atlas.insert(d, 10, 10)
    atlas.insert(e, 10, 10)
    # all distinct entries stored
    atlas.lookup(a).should_not be_nil
    atlas.lookup(c).should_not be_nil
    atlas.lookup(d).should_not be_nil
    atlas.lookup(e).should_not be_nil
  end

  it "invalidate_font removes only target font slots and reports evicted count" do
    atlas = GlyphAtlas.new(256)
    atlas.insert(GlyphKey.new(1, 1_u32, 16, 0_u8, 0_u8), 10, 10)
    atlas.insert(GlyphKey.new(1, 2_u32, 16, 0_u8, 0_u8), 10, 10)
    atlas.insert(GlyphKey.new(2, 1_u32, 16, 0_u8, 0_u8), 10, 10)
    evicted = atlas.invalidate_font(1)
    evicted.should eq 2
    atlas.lookup(GlyphKey.new(1, 1_u32, 16, 0_u8, 0_u8)).should be_nil
    atlas.lookup(GlyphKey.new(1, 2_u32, 16, 0_u8, 0_u8)).should be_nil
    atlas.lookup(GlyphKey.new(2, 1_u32, 16, 0_u8, 0_u8)).should_not be_nil
  end

  it "frame contract: evict_lru inside begin_frame raises FrameEvictionError" do
    atlas = GlyphAtlas.new(256, 2)
    atlas.insert(GlyphKey.new(1, 1_u32, 16, 0_u8, 0_u8), 10, 10)
    atlas.insert(GlyphKey.new(1, 2_u32, 16, 0_u8, 0_u8), 10, 10)
    atlas.begin_frame
    expect_raises(GlyphAtlas::FrameEvictionError) do
      atlas.evict_lru(1)
    end
    # also capacity-triggered eviction during frame should raise
    expect_raises(GlyphAtlas::FrameEvictionError) do
      atlas.insert(GlyphKey.new(1, 3_u32, 16, 0_u8, 0_u8), 10, 10)
    end
    atlas.end_frame
  end

  it "zero-alloc reuse: 1000 lookup hits after pre-insert satisfy zero-alloc criterion (GC probe)" do
    atlas = GlyphAtlas.new(256)
    key = GlyphKey.new(7, 99_u32, 16, 0_u8, 0_u8)
    atlas.insert(key, 16, 16, 0, 0, 8.0_f32)
    n = 1000
    # warmup
    10.times { atlas.lookup(key) }

    # Prime window (diagnostic)
    delta_prime = 0_i64
    GC.collect
    GC.disable
    begin
      before = GC.stats.bytes_since_gc
      i = 0
      while i < n
        atlas.lookup(key)
        i += 1
      end
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

    # 3 work windows
    work = [] of Int64
    3.times do
      GC.collect
      GC.disable
      begin
        before = GC.stats.bytes_since_gc
        i = 0
        while i < n
          atlas.lookup(key)
          i += 1
        end
        after = GC.stats.bytes_since_gc
        work << (after.to_i64 - before.to_i64)
      ensure
        GC.enable
      end
    end
    delta_work = work.max
    seq = "[#{work[0]},#{work[1]},#{work[2]}]"
    puts "zero-alloc probe(glyph_atlas): delta_prime=#{delta_prime} delta_calib=#{delta_calib} delta_work=#{delta_work} N=#{n} windows=#{seq}"
    unless delta_work < n && delta_work <= 64
      fail "zero-alloc probe: delta_work=#{delta_work} delta_calib=#{delta_calib} delta_prime=#{delta_prime} N=#{n} windows=#{seq}"
    end
  end

  it "dense small glyphs keep waste_ratio < 0.5" do
    atlas = GlyphAtlas.new(1024, 4096)
    # fill densely with uniform small glyphs to minimize shelf waste
    gid = 0_u32
    3000.times do
      key = GlyphKey.new(1, gid, 16, 0_u8, 0_u8)
      atlas.insert(key, 16, 16, 0, 0, 8.0_f32)
      gid += 1_u32
    end
    atlas.waste_ratio.should be < 0.5
  end

  it "page_data and slot_rect expose rasterizer API" do
    atlas = GlyphAtlas.new(128)
    key = GlyphKey.new(1, 5_u32, 16, 0_u8, 0_u8)
    slot = atlas.insert(key, 12, 14, 3, 4, 9.5_f32)
    data = atlas.page_data(slot.page)
    data.size.should eq 128 * 128
    rect = atlas.slot_rect(slot)
    rect[:x].should eq slot.x
    rect[:y].should eq slot.y
    rect[:w].should eq slot.w
    rect[:h].should eq slot.h
  end

  it "LRU eviction happens outside frame and reused page bytes do not grow page_count" do
    atlas = GlyphAtlas.new(128, 2)
    k1 = GlyphKey.new(1, 1_u32, 16, 0_u8, 0_u8)
    k2 = GlyphKey.new(1, 2_u32, 16, 0_u8, 0_u8)
    k3 = GlyphKey.new(1, 3_u32, 16, 0_u8, 0_u8)
    atlas.insert(k1, 10, 10)
    atlas.insert(k2, 10, 10)
    # touch k1 so k2 becomes LRU
    atlas.lookup(k1)
    atlas.insert(k3, 10, 10) # should evict k2 (outside frame)
    atlas.lookup(k2).should be_nil
    atlas.lookup(k1).should_not be_nil
    atlas.lookup(k3).should_not be_nil
    # evict remaining, then insert to reuse freed page bytes
    atlas.evict_lru(2)
    pc = atlas.page_count
    atlas.insert(GlyphKey.new(1, 4_u32, 16, 0_u8, 0_u8), 10, 10)
    atlas.page_count.should eq pc
  end

  it "oversized glyph raises without leaving a stray page; old slots intact; message fixed" do
    atlas = GlyphAtlas.new(64)
    k1 = GlyphKey.new(1, 1_u32, 16, 0_u8, 0_u8)
    s1 = atlas.insert(k1, 10, 10, 0, 0, 10.0_f32)
    before_pages = atlas.page_count
    before_used = atlas.used_pixels
    ex = expect_raises(Exception) do
      atlas.insert(GlyphKey.new(1, 2_u32, 16, 0_u8, 0_u8), 100, 100)
    end
    ex.message.should eq "Glyph (100x100) does not fit in empty page of size 64"
    atlas.page_count.should eq before_pages
    atlas.used_pixels.should eq before_used
    got = atlas.lookup(k1).not_nil!
    got.page.should eq s1.page
    got.x.should eq s1.x
    got.y.should eq s1.y
    got.w.should eq s1.w
    got.h.should eq s1.h
  end

  it "zero-size insert raises ArgumentError and creates nothing" do
    atlas = GlyphAtlas.new(64)
    expect_raises(ArgumentError) do
      atlas.insert(GlyphKey.new(1, 1_u32, 16, 0_u8, 0_u8), 0, 8)
    end
    expect_raises(ArgumentError) do
      atlas.insert(GlyphKey.new(1, 2_u32, 16, 0_u8, 0_u8), 8, 0)
    end
    atlas.page_count.should eq 0
    atlas.used_pixels.should eq 0
  end

  it "duplicate-key insert is idempotent: first slot wins, new params ignored" do
    atlas = GlyphAtlas.new(64)
    k = GlyphKey.new(1, 7_u32, 16, 0_u8, 0_u8)
    s1 = atlas.insert(k, 6, 6, 1, 2, 12.0_f32)
    used1 = atlas.used_pixels
    s2 = atlas.insert(k, 99, 99, 9, 9, 99.0_f32)
    s2.page.should eq s1.page
    s2.x.should eq s1.x
    s2.y.should eq s1.y
    s2.w.should eq s1.w
    s2.h.should eq s1.h
    s2.bearing_x.should eq s1.bearing_x
    s2.bearing_y.should eq s1.bearing_y
    s2.advance.should eq s1.advance
    atlas.used_pixels.should eq used1
    atlas.page_count.should eq 1
  end
end