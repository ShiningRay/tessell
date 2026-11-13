# tools/atlas_raster_verify.cr
# Current-HEAD verification probe for M2-WP2b atlas/rasterizer contracts (task-85, C2 closeout).
# Pure Crystal, key=value output, exit 0 on all checks pass, 1 on failure.
#
# Usage:
#   $env:PATH="C:\msys64\ucrt64\bin;$env:PATH"; crystal run tools/atlas_raster_verify.cr

require "../src/tessell"

include Tessell::Text

FAILED = [] of String

def check(name : String, cond : Bool, detail : String = "")
  unless cond
    FAILED << (detail.empty? ? name : "#{name} #{detail}")
  end
end

def placements_equal?(a : GlyphPlacement, b : GlyphPlacement) : Bool
  a.key == b.key &&
    a.glyph_id == b.glyph_id &&
    a.advance_px == b.advance_px &&
    a.offset_x == b.offset_x &&
    a.offset_y == b.offset_y &&
    a.w == b.w &&
    a.h == b.h &&
    a.u0 == b.u0 &&
    a.v0 == b.v0 &&
    a.u1 == b.u1 &&
    a.v1 == b.v1 &&
    a.page == b.page
end

# 1. Frame-eviction contract (atlas): begin_frame -> evict raises FrameEvictionError; end_frame -> evictable.
def verify_frame_eviction
  atlas = GlyphAtlas.new(256, 2)
  k1 = GlyphKey.new(1, 1_u32, 16, 0_u8, 0_u8)
  k2 = GlyphKey.new(1, 2_u32, 16, 0_u8, 0_u8)
  atlas.insert(k1, 10, 10)
  atlas.insert(k2, 10, 10)
  atlas.begin_frame
  raised = false
  klass = "none"
  begin
    atlas.evict_lru(1)
  rescue ex : GlyphAtlas::FrameEvictionError
    raised = true
    klass = ex.class.name
  rescue ex
    klass = ex.class.name
  end
  puts "frame_eviction_raised=#{raised} class=#{klass}"
  check("frame_eviction", raised && klass.includes?("FrameEvictionError"))
  atlas.end_frame
  evicted = atlas.evict_lru(1)
  puts "frame_eviction_after_end_evicted=#{evicted}"
  check("frame_eviction_after_end", evicted == 1)
end

# 2. invalidate_font targeted eviction count, no collateral damage.
def verify_invalidate_font
  atlas = GlyphAtlas.new(256)
  atlas.insert(GlyphKey.new(1, 1_u32, 16, 0_u8, 0_u8), 10, 10)
  atlas.insert(GlyphKey.new(1, 2_u32, 16, 0_u8, 0_u8), 10, 10)
  atlas.insert(GlyphKey.new(2, 1_u32, 16, 0_u8, 0_u8), 10, 10)
  evicted = atlas.invalidate_font(1)
  font1a = atlas.lookup(GlyphKey.new(1, 1_u32, 16, 0_u8, 0_u8))
  font1b = atlas.lookup(GlyphKey.new(1, 2_u32, 16, 0_u8, 0_u8))
  font2 = atlas.lookup(GlyphKey.new(2, 1_u32, 16, 0_u8, 0_u8))
  puts "invalidate_font_evicted=#{evicted} font1a_nil=#{font1a.nil?} font1b_nil=#{font1b.nil?} font2_present=#{!font2.nil?}"
  check("invalidate_font", evicted == 2 && font1a.nil? && font1b.nil? && !font2.nil?)
end

# 3. LRU tick refresh via lookup: evict_lru removes oldest.
def verify_lru_tick
  atlas = GlyphAtlas.new(256, 2)
  k1 = GlyphKey.new(1, 1_u32, 16, 0_u8, 0_u8)
  k2 = GlyphKey.new(1, 2_u32, 16, 0_u8, 0_u8)
  k3 = GlyphKey.new(1, 3_u32, 16, 0_u8, 0_u8)
  atlas.insert(k1, 10, 10)
  atlas.insert(k2, 10, 10)
  atlas.lookup(k1) # refresh k1, so k2 becomes oldest
  atlas.insert(k3, 10, 10) # capacity 2 -> evict k2
  k1p = atlas.lookup(k1)
  k2p = atlas.lookup(k2)
  k3p = atlas.lookup(k3)
  puts "lru_tick_k1_present=#{!k1p.nil?} lru_tick_k2_nil=#{k2p.nil?} lru_tick_k3_present=#{!k3p.nil?}"
  check("lru_tick", !k1p.nil? && k2p.nil? && !k3p.nil?)
end

# 4. Random packing 200 different sizes: no overlap, no out-of-bounds.
def verify_random200
  atlas = GlyphAtlas.new(1024)
  rng = Random.new(424242_u64)
  slots = [] of GlyphSlot
  200.times do |i|
    w = rng.rand(6..80)
    h = rng.rand(6..80)
    key = GlyphKey.new(3, i.to_u32, 16, 0_u8, 0_u8)
    slots << atlas.insert(key, w, h, 0, 0, w.to_f32)
  end
  ok = true
  i = 0
  while i < slots.size
    a = slots[i]
    if a.x < 0 || a.y < 0 || a.x + a.w > 1024 || a.y + a.h > 1024
      ok = false
      break
    end
    j = i + 1
    while j < slots.size
      b = slots[j]
      if a.page == b.page
        overlap = !(a.x + a.w <= b.x || b.x + b.w <= a.x || a.y + a.h <= b.y || b.y + b.h <= a.y)
        if overlap
          ok = false
          break
        end
      end
      j += 1
    end
    break unless ok
    i += 1
  end
  puts "RANDOM200 ok=#{ok} count=#{slots.size} pages=#{atlas.page_count}"
  check("random200", ok && slots.size == 200)
end

# 5. UV stability across page expansion.
def uv_tuple(atlas : GlyphAtlas, slot : GlyphSlot) : Tuple(Int32, Int32, Int32, Int32)
  {slot.x, slot.y, slot.w, slot.h}
end

def verify_uv_stable
  atlas = GlyphAtlas.new(256)
  keys = [] of GlyphKey
  before = [] of GlyphSlot
  # Fill first pages and record slots
  gid = 0_u32
  20.times do
    k = GlyphKey.new(5, gid, 16, 0_u8, 0_u8)
    s = atlas.insert(k, 120, 120, 0, 0, 1.0_f32)
    keys << k
    before << s
    gid += 1_u32
  end
  pages_before = atlas.page_count
  # Force expansion with more inserts
  20.times do
    k = GlyphKey.new(5, gid, 16, 0_u8, 0_u8)
    atlas.insert(k, 120, 120, 0, 0, 1.0_f32)
    gid += 1_u32
  end
  pages_after = atlas.page_count
  mismatch = 0
  i = 0
  while i < keys.size
    got = atlas.lookup(keys[i])
    if got
      if got.page != before[i].page || got.x != before[i].x || got.y != before[i].y || got.w != before[i].w || got.h != before[i].h
        mismatch += 1
      end
    else
      mismatch += 1
    end
    i += 1
  end
  uv_stable = mismatch == 0 && pages_after >= pages_before
  puts "UV_STABLE=#{uv_stable} mismatch=#{mismatch} pages_before=#{pages_before} pages_after=#{pages_after}"
  check("uv_stable", uv_stable)
end

# 6. Page reuse: whole page freed -> reuse, page_count not increased.
def verify_page_reuse
  atlas = GlyphAtlas.new(128, 128)
  # fill keys on page 0
  keys = [] of GlyphKey
  10.times do |i|
    k = GlyphKey.new(6, i.to_u32, 16, 0_u8, 0_u8)
    atlas.insert(k, 40, 40)
    keys << k
  end
  pc_before = atlas.page_count
  # remove all so page becomes fully free (live_count==0 path in remove_key)
  keys.each { |k| atlas.evict_lru(0) } # no-op; need actual removal
  atlas.invalidate_font(6)
  # also clear any others
  pc_after_free = atlas.page_count
  # insert new keys - should reuse freed page
  atlas.insert(GlyphKey.new(7, 1_u32, 16, 0_u8, 0_u8), 40, 40)
  atlas.insert(GlyphKey.new(7, 2_u32, 16, 0_u8, 0_u8), 40, 40)
  pc_after = atlas.page_count
  # page_count (total pages allocated) should not grow compared to after-free state; reuse means same count
  ok = pc_after <= pc_before
  puts "page_reuse_page_count_before=#{pc_before} page_count_after_free=#{pc_after_free} page_count_after=#{pc_after} reused=#{ok}"
  check("page_reuse", ok)
end

# 7. Lookup probe: 3x1000 full-hit, GC criterion A/B, 3 windows max, GC.enable in ensure.
def verify_lookup_alloc
  atlas = GlyphAtlas.new(256)
  key = GlyphKey.new(7, 99_u32, 16, 0_u8, 0_u8)
  atlas.insert(key, 16, 16, 0, 0, 8.0_f32)
  n = 1000
  10.times { atlas.lookup(key) }

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
  pass = delta_work < n && delta_work <= 256
  puts "lookup_probe deltas=[#{work[0]},#{work[1]},#{work[2]}] delta_work=#{delta_work} N=#{n} pass=#{pass}"
  check("lookup_probe", pass)
end

# 8. shape_run_into hit path placements == rasterize_into per-glyph path (field-by-field).
def verify_shaped_run_equiv
  font_path = "C:\\Windows\\Fonts\\msyh.ttc"
  measurer = FtMeasurer.open(font_path, 0)
  begin
    atlas1 = GlyphAtlas.new(1024, 4096)
    atlas2 = GlyphAtlas.new(1024, 4096)
    r1 = Rasterizer.new(measurer, atlas1, 1)
    r2 = Rasterizer.new(measurer, atlas2, 1)
    text = "row 12345"
    size_px = 16

    # per-glyph baseline path
    base = [] of GlyphPlacement
    r1.rasterize_into(text, size_px, base)

    # miss then hit via shape_run_into
    miss = [] of GlyphPlacement
    r2.shape_run_into(text, size_px, miss) # miss, caches
    hit = [] of GlyphPlacement
    r2.shape_run_into(text, size_px, hit) # hit

    ok = base.size == hit.size
    bad = 0
    if ok
      i = 0
      while i < base.size
        unless placements_equal?(base[i], hit[i])
          bad += 1
        end
        i += 1
      end
      ok = bad == 0
    end
    cache_hit = r2.run_cache_size == 1
    puts "shaped_run_hit_equiv=#{ok && cache_hit} count_base=#{base.size} count_hit=#{hit.size} bad=#{bad} run_cache_size=#{r2.run_cache_size}"
    check("shaped_run_equiv", ok && cache_hit)
  ensure
    measurer.close
  end
end

begin
  verify_frame_eviction
  verify_invalidate_font
  verify_lru_tick
  verify_random200
  verify_uv_stable
  verify_page_reuse
  verify_lookup_alloc
  verify_shaped_run_equiv
rescue ex
  puts "PROBE_EXCEPTION class=#{ex.class} message=#{ex.message}"
  FAILED << "exception:#{ex.class}"
end

if FAILED.empty?
  puts "ATLAS_RASTER_VERIFY_EXIT=0"
  exit 0
else
  puts "ATLAS_RASTER_VERIFY_FAILED=#{FAILED.join("|")}"
  puts "ATLAS_RASTER_VERIFY_EXIT=1"
  exit 1
end
