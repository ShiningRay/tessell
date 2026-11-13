require "../src/tessell/widgets/virtual_list"
require "../src/tessell/render/draw_list"
require "../src/tessell/render/text_renderer"
require "../src/tessell/text/ft_measurer"
require "../src/tessell/text/glyph_atlas"
require "../src/tessell/text/rasterizer"

module BenchScroll
  extend self

  FONT_PATH = "C:/Windows/Fonts/msyh.ttc"
  TEXT_SIZE = 16
  LABEL     = "row 12345"

  ROW_COUNT   = 10_000
  ROW_H       = 20
  VIEWPORT_H  = 600
  VIEWPORT_W  = 800
  FRAMES      = 2000
  N_ALLOC     = 1000

  def percentile(sorted : Array(Int64), p : Float64) : Int64
    return 0_i64 if sorted.empty?
    idx = ((p / 100.0) * (sorted.size - 1)).round.to_i
    idx = 0 if idx < 0
    idx = sorted.size - 1 if idx >= sorted.size
    sorted[idx]
  end

  # Fills page texture ids to cover atlas pages (called outside timed/alloc hot loops)
  def ensure_page_tex_ids(page_tex_ids : Array(Int32), atlas : Tessell::Text::GlyphAtlas) : Nil
    while page_tex_ids.size < atlas.page_count
      page_tex_ids << page_tex_ids.size
    end
  end

  def run
    fetch = ->(i : Int32) { nil }

    puts "bench_scroll config row_count=#{ROW_COUNT} row_h=#{ROW_H} viewport_h=#{VIEWPORT_H} viewport_w=#{VIEWPORT_W} frames=#{FRAMES} n_alloc=#{N_ALLOC} font=#{FONT_PATH} label=\"#{LABEL}\""

    # Setup text pipeline (pre-open msyh, pre-warm atlas/glyphs/buffers)
    atlas = Tessell::Text::GlyphAtlas.new
    measurer = Tessell::Text::FtMeasurer.open(FONT_PATH, 0)
    rasterizer = Tessell::Text::Rasterizer.new(measurer, atlas, 0)
    placement_sink = [] of Tessell::Text::GlyphPlacement
    renderer = Tessell::Render::TextRenderer.new(atlas, rasterizer)
    renderer.reserve_quads(512)
    renderer.reserve_batches(64)
    draw_list = Tessell::Render::DrawList.new
    draw_list.reserve(256)
    batch_sink = [] of Tessell::Render::Batch
    page_tex_ids = [0, 0, 0, 0]

    # Warm glyphs for label and ensure buffers/pages
    renderer.build_text(placement_sink, LABEL, 0.0_f32, 0.0_f32, TEXT_SIZE, VIEWPORT_W, 10_000_000, page_tex_ids)
    ensure_page_tex_ids(page_tex_ids, atlas)

    # ============================================================
    # Scenario 1: scroll +1px per frame (real CPU frame)
    # ============================================================
    vl1 = Tessell::Widgets::VirtualList.new(ROW_COUNT, ROW_H, VIEWPORT_H, fetch, VIEWPORT_W)
    max_scroll1 = vl1.total_height - VIEWPORT_H
    max_scroll1 = 0 if max_scroll1 < 0

    # warmup steady path (200 frames)
    warm = 0
    while warm < 200
      vl1.scroll_by(1)
      if max_scroll1 > 0 && vl1.scroll_y >= max_scroll1
        vl1.scroll_to(0)
      end
      vl1.dirty_rects
      vl1.prepare_visible
      draw_list.clear
      i = vl1.visible_first
      last = vl1.visible_last
      while i <= last
        oy = vl1.node_offset(i).to_f32
        draw_list.push(Tessell::Render::DrawCmd.new(Tessell::Render::CmdKind::Rect,
          Tessell::Rect.new(0.0_f32, oy, VIEWPORT_W.to_f32, ROW_H.to_f32),
          0xFFF0F0F0_u32, -1, nil))
        sep_y = oy + ROW_H.to_f32 - 1.0_f32
        draw_list.push(Tessell::Render::DrawCmd.new(Tessell::Render::CmdKind::Rect,
          Tessell::Rect.new(0.0_f32, sep_y, VIEWPORT_W.to_f32, 1.0_f32),
          0xFFD0D0D0_u32, -1, nil))
        text_y = oy + 14.0_f32
        renderer.build_text(placement_sink, LABEL, 8.0_f32, text_y, TEXT_SIZE, VIEWPORT_W, 10_000_000, page_tex_ids)
        i += 1
      end
      draw_list.build_batches_into(batch_sink)
      warm += 1
    end
    ensure_page_tex_ids(page_tex_ids, atlas)
    vl1.scroll_to(0); vl1.dirty_rects; vl1.prepare_visible

    # timed measurement
    times1 = Array(Int64).new(FRAMES, 0_i64)
    visible_sum1 = 0_i64
    fetched_sum1 = 0_i64
    cmds_sum1 = 0_i64
    batches_sum1 = 0_i64
    quads_sum1 = 0_i64
    f = 0
    while f < FRAMES
      t0 = Time.instant
      vl1.scroll_by(1)
      if max_scroll1 > 0 && vl1.scroll_y >= max_scroll1
        vl1.scroll_to(0)
      end
      vl1.dirty_rects
      vl1.prepare_visible
      draw_list.clear
      total_quads = 0
      i = vl1.visible_first
      last = vl1.visible_last
      while i <= last
        oy = vl1.node_offset(i).to_f32
        draw_list.push(Tessell::Render::DrawCmd.new(Tessell::Render::CmdKind::Rect,
          Tessell::Rect.new(0.0_f32, oy, VIEWPORT_W.to_f32, ROW_H.to_f32),
          0xFFF0F0F0_u32, -1, nil))
        sep_y = oy + ROW_H.to_f32 - 1.0_f32
        draw_list.push(Tessell::Render::DrawCmd.new(Tessell::Render::CmdKind::Rect,
          Tessell::Rect.new(0.0_f32, sep_y, VIEWPORT_W.to_f32, 1.0_f32),
          0xFFD0D0D0_u32, -1, nil))
        text_y = oy + 14.0_f32
        renderer.build_text(placement_sink, LABEL, 8.0_f32, text_y, TEXT_SIZE, VIEWPORT_W, 10_000_000, page_tex_ids)
        total_quads += renderer.stats[:quads]
        i += 1
      end
      bcount = draw_list.build_batches_into(batch_sink)
      t1 = Time.instant
      times1[f] = (t1 - t0).total_microseconds.to_i64
      vrf = vl1.visible_first
      vrl = vl1.visible_last
      vis = vrl >= vrf ? (vrl - vrf + 1) : 0
      visible_sum1 += vis
      fetched_sum1 += vl1.fetched_count
      cmds_sum1 += draw_list.size
      batches_sum1 += bcount
      quads_sum1 += total_quads
      f += 1
    end
    times1.sort!
    p50_1 = percentile(times1, 50.0)
    p95_1 = percentile(times1, 95.0)
    p99_1 = percentile(times1, 99.0)

    # steady warmup for alloc probe
    vl1.scroll_to(0); vl1.dirty_rects; vl1.prepare_visible
    warm = 0
    while warm < 100
      vl1.scroll_by(1)
      if max_scroll1 > 0 && vl1.scroll_y >= max_scroll1
        vl1.scroll_to(0)
      end
      vl1.dirty_rects
      vl1.prepare_visible
      draw_list.clear
      i = vl1.visible_first
      last = vl1.visible_last
      while i <= last
        oy = vl1.node_offset(i).to_f32
        draw_list.push(Tessell::Render::DrawCmd.new(Tessell::Render::CmdKind::Rect,
          Tessell::Rect.new(0.0_f32, oy, VIEWPORT_W.to_f32, ROW_H.to_f32), 0xFFF0F0F0_u32, -1, nil))
        sep_y = oy + ROW_H.to_f32 - 1.0_f32
        draw_list.push(Tessell::Render::DrawCmd.new(Tessell::Render::CmdKind::Rect,
          Tessell::Rect.new(0.0_f32, sep_y, VIEWPORT_W.to_f32, 1.0_f32), 0xFFD0D0D0_u32, -1, nil))
        text_y = oy + 14.0_f32
        renderer.build_text(placement_sink, LABEL, 8.0_f32, text_y, TEXT_SIZE, VIEWPORT_W, 10_000_000, page_tex_ids)
        i += 1
      end
      draw_list.build_batches_into(batch_sink)
      warm += 1
    end
    vl1.scroll_to(0); vl1.dirty_rects; vl1.prepare_visible

    # alloc probe scenario 1
    delta_prime1 = 0_i64
    GC.collect
    GC.disable
    begin
      before = GC.stats.bytes_since_gc
      k = 0
      while k < N_ALLOC
        vl1.scroll_by(1)
        if max_scroll1 > 0 && vl1.scroll_y >= max_scroll1
          vl1.scroll_to(0)
        end
        vl1.dirty_rects
        vl1.prepare_visible
        draw_list.clear
        i = vl1.visible_first
        last = vl1.visible_last
        while i <= last
          oy = vl1.node_offset(i).to_f32
          draw_list.push(Tessell::Render::DrawCmd.new(Tessell::Render::CmdKind::Rect,
            Tessell::Rect.new(0.0_f32, oy, VIEWPORT_W.to_f32, ROW_H.to_f32), 0xFFF0F0F0_u32, -1, nil))
          sep_y = oy + ROW_H.to_f32 - 1.0_f32
          draw_list.push(Tessell::Render::DrawCmd.new(Tessell::Render::CmdKind::Rect,
            Tessell::Rect.new(0.0_f32, sep_y, VIEWPORT_W.to_f32, 1.0_f32), 0xFFD0D0D0_u32, -1, nil))
          text_y = oy + 14.0_f32
          renderer.build_text(placement_sink, LABEL, 8.0_f32, text_y, TEXT_SIZE, VIEWPORT_W, 10_000_000, page_tex_ids)
          i += 1
        end
        draw_list.build_batches_into(batch_sink)
        k += 1
      end
      delta_prime1 = GC.stats.bytes_since_gc.to_i64 - before.to_i64
    ensure
      GC.enable
    end

    delta_calib1 = 0_i64
    calib_sink1 = 0_i64
    GC.collect
    GC.disable
    begin
      before = GC.stats.bytes_since_gc
      k = 0
      while k < N_ALLOC
        calib_sink1 &+= k.to_i64
        k += 1
      end
      delta_calib1 = GC.stats.bytes_since_gc.to_i64 - before.to_i64
    ensure
      GC.enable
    end
    _ = calib_sink1

    retried1 = false
    attempt1 = 1
    delta_work1 = 0_i64
    seq1 = [0_i64, 0_i64, 0_i64]
    loop do
      w = 0
      while w < 3
        GC.collect
        GC.disable
        begin
          before = GC.stats.bytes_since_gc
          k = 0
          while k < N_ALLOC
            vl1.scroll_by(1)
            if max_scroll1 > 0 && vl1.scroll_y >= max_scroll1
              vl1.scroll_to(0)
            end
            vl1.dirty_rects
            vl1.prepare_visible
            draw_list.clear
            i = vl1.visible_first
            last = vl1.visible_last
            while i <= last
              oy = vl1.node_offset(i).to_f32
              draw_list.push(Tessell::Render::DrawCmd.new(Tessell::Render::CmdKind::Rect,
                Tessell::Rect.new(0.0_f32, oy, VIEWPORT_W.to_f32, ROW_H.to_f32), 0xFFF0F0F0_u32, -1, nil))
              sep_y = oy + ROW_H.to_f32 - 1.0_f32
              draw_list.push(Tessell::Render::DrawCmd.new(Tessell::Render::CmdKind::Rect,
                Tessell::Rect.new(0.0_f32, sep_y, VIEWPORT_W.to_f32, 1.0_f32), 0xFFD0D0D0_u32, -1, nil))
              text_y = oy + 14.0_f32
              renderer.build_text(placement_sink, LABEL, 8.0_f32, text_y, TEXT_SIZE, VIEWPORT_W, 10_000_000, page_tex_ids)
              i += 1
            end
            draw_list.build_batches_into(batch_sink)
            k += 1
          end
          seq1[w] = GC.stats.bytes_since_gc.to_i64 - before.to_i64
        ensure
          GC.enable
        end
        w += 1
      end
      delta_work1 = seq1[0]
      delta_work1 = seq1[1] if seq1[1] > delta_work1
      delta_work1 = seq1[2] if seq1[2] > delta_work1
      break if delta_work1 < N_ALLOC && delta_work1 <= 256
      if attempt1 >= 2
        break
      end
      retried1 = true
      attempt1 = 2
    end

    puts "scenario=scroll_plus1px visible_avg=#{visible_sum1.to_f64 / FRAMES.to_f64} fetched_per_frame_avg=#{fetched_sum1.to_f64 / FRAMES.to_f64} cmds_avg=#{cmds_sum1.to_f64 / FRAMES.to_f64} batches_avg=#{batches_sum1.to_f64 / FRAMES.to_f64} quads_avg=#{quads_sum1.to_f64 / FRAMES.to_f64} alloc_bytes=#{delta_work1} frame_cpu_p50_us=#{p50_1} frame_cpu_p95_us=#{p95_1} frame_cpu_p99_us=#{p99_1} frames=#{FRAMES} alloc_windows=[#{seq1[0]},#{seq1[1]},#{seq1[2]}] delta_prime=#{delta_prime1} delta_calib=#{delta_calib1} retried=#{retried1} attempt=#{attempt1} pool_size=#{vl1.pool_size} created=#{vl1.recycle_stats[:created]}"

    # ============================================================
    # Scenario 2: jump with fixed seed (real CPU frame)
    # ============================================================
    vl2 = Tessell::Widgets::VirtualList.new(ROW_COUNT, ROW_H, VIEWPORT_H, fetch, VIEWPORT_W)
    max_scroll2 = vl2.total_height - VIEWPORT_H
    max_scroll2 = 0 if max_scroll2 < 0
    rng = Random.new(12345_u64)

    warm = 0
    while warm < 200
      vl2.scroll_to(rng.rand(0..max_scroll2))
      vl2.dirty_rects
      vl2.prepare_visible
      draw_list.clear
      i = vl2.visible_first
      last = vl2.visible_last
      while i <= last
        oy = vl2.node_offset(i).to_f32
        draw_list.push(Tessell::Render::DrawCmd.new(Tessell::Render::CmdKind::Rect,
          Tessell::Rect.new(0.0_f32, oy, VIEWPORT_W.to_f32, ROW_H.to_f32), 0xFFF0F0F0_u32, -1, nil))
        sep_y = oy + ROW_H.to_f32 - 1.0_f32
        draw_list.push(Tessell::Render::DrawCmd.new(Tessell::Render::CmdKind::Rect,
          Tessell::Rect.new(0.0_f32, sep_y, VIEWPORT_W.to_f32, 1.0_f32), 0xFFD0D0D0_u32, -1, nil))
        text_y = oy + 14.0_f32
        renderer.build_text(placement_sink, LABEL, 8.0_f32, text_y, TEXT_SIZE, VIEWPORT_W, 10_000_000, page_tex_ids)
        i += 1
      end
      draw_list.build_batches_into(batch_sink)
      warm += 1
    end
    vl2.scroll_to(0); vl2.dirty_rects; vl2.prepare_visible

    rng2 = Random.new(12345_u64)
    times2 = Array(Int64).new(FRAMES, 0_i64)
    visible_sum2 = 0_i64
    fetched_sum2 = 0_i64
    cmds_sum2 = 0_i64
    batches_sum2 = 0_i64
    quads_sum2 = 0_i64
    f = 0
    while f < FRAMES
      t0 = Time.instant
      vl2.scroll_to(rng2.rand(0..max_scroll2))
      vl2.dirty_rects
      vl2.prepare_visible
      draw_list.clear
      total_quads = 0
      i = vl2.visible_first
      last = vl2.visible_last
      while i <= last
        oy = vl2.node_offset(i).to_f32
        draw_list.push(Tessell::Render::DrawCmd.new(Tessell::Render::CmdKind::Rect,
          Tessell::Rect.new(0.0_f32, oy, VIEWPORT_W.to_f32, ROW_H.to_f32), 0xFFF0F0F0_u32, -1, nil))
        sep_y = oy + ROW_H.to_f32 - 1.0_f32
        draw_list.push(Tessell::Render::DrawCmd.new(Tessell::Render::CmdKind::Rect,
          Tessell::Rect.new(0.0_f32, sep_y, VIEWPORT_W.to_f32, 1.0_f32), 0xFFD0D0D0_u32, -1, nil))
        text_y = oy + 14.0_f32
        renderer.build_text(placement_sink, LABEL, 8.0_f32, text_y, TEXT_SIZE, VIEWPORT_W, 10_000_000, page_tex_ids)
        total_quads += renderer.stats[:quads]
        i += 1
      end
      bcount = draw_list.build_batches_into(batch_sink)
      t1 = Time.instant
      times2[f] = (t1 - t0).total_microseconds.to_i64
      vrf = vl2.visible_first
      vrl = vl2.visible_last
      vis = vrl >= vrf ? (vrl - vrf + 1) : 0
      visible_sum2 += vis
      fetched_sum2 += vl2.fetched_count
      cmds_sum2 += draw_list.size
      batches_sum2 += bcount
      quads_sum2 += total_quads
      f += 1
    end
    times2.sort!
    p50_2 = percentile(times2, 50.0)
    p95_2 = percentile(times2, 95.0)
    p99_2 = percentile(times2, 99.0)

    rng3 = Random.new(12345_u64)
    vl2.scroll_to(0); vl2.dirty_rects; vl2.prepare_visible
    warm = 0
    while warm < 100
      vl2.scroll_to(rng3.rand(0..max_scroll2))
      vl2.dirty_rects
      vl2.prepare_visible
      draw_list.clear
      i = vl2.visible_first
      last = vl2.visible_last
      while i <= last
        oy = vl2.node_offset(i).to_f32
        draw_list.push(Tessell::Render::DrawCmd.new(Tessell::Render::CmdKind::Rect,
          Tessell::Rect.new(0.0_f32, oy, VIEWPORT_W.to_f32, ROW_H.to_f32), 0xFFF0F0F0_u32, -1, nil))
        sep_y = oy + ROW_H.to_f32 - 1.0_f32
        draw_list.push(Tessell::Render::DrawCmd.new(Tessell::Render::CmdKind::Rect,
          Tessell::Rect.new(0.0_f32, sep_y, VIEWPORT_W.to_f32, 1.0_f32), 0xFFD0D0D0_u32, -1, nil))
        text_y = oy + 14.0_f32
        renderer.build_text(placement_sink, LABEL, 8.0_f32, text_y, TEXT_SIZE, VIEWPORT_W, 10_000_000, page_tex_ids)
        i += 1
      end
      draw_list.build_batches_into(batch_sink)
      warm += 1
    end
    vl2.scroll_to(0); vl2.dirty_rects; vl2.prepare_visible

    rng4 = Random.new(12345_u64)
    delta_prime2 = 0_i64
    GC.collect
    GC.disable
    begin
      before = GC.stats.bytes_since_gc
      k = 0
      while k < N_ALLOC
        vl2.scroll_to(rng4.rand(0..max_scroll2))
        vl2.dirty_rects
        vl2.prepare_visible
        draw_list.clear
        i = vl2.visible_first
        last = vl2.visible_last
        while i <= last
          oy = vl2.node_offset(i).to_f32
          draw_list.push(Tessell::Render::DrawCmd.new(Tessell::Render::CmdKind::Rect,
            Tessell::Rect.new(0.0_f32, oy, VIEWPORT_W.to_f32, ROW_H.to_f32), 0xFFF0F0F0_u32, -1, nil))
          sep_y = oy + ROW_H.to_f32 - 1.0_f32
          draw_list.push(Tessell::Render::DrawCmd.new(Tessell::Render::CmdKind::Rect,
            Tessell::Rect.new(0.0_f32, sep_y, VIEWPORT_W.to_f32, 1.0_f32), 0xFFD0D0D0_u32, -1, nil))
          text_y = oy + 14.0_f32
          renderer.build_text(placement_sink, LABEL, 8.0_f32, text_y, TEXT_SIZE, VIEWPORT_W, 10_000_000, page_tex_ids)
          i += 1
        end
        draw_list.build_batches_into(batch_sink)
        k += 1
      end
      delta_prime2 = GC.stats.bytes_since_gc.to_i64 - before.to_i64
    ensure
      GC.enable
    end

    delta_calib2 = 0_i64
    calib_sink2 = 0_i64
    GC.collect
    GC.disable
    begin
      before = GC.stats.bytes_since_gc
      k = 0
      while k < N_ALLOC
        calib_sink2 &+= k.to_i64
        k += 1
      end
      delta_calib2 = GC.stats.bytes_since_gc.to_i64 - before.to_i64
    ensure
      GC.enable
    end
    _ = calib_sink2

    retried2 = false
    attempt2 = 1
    delta_work2 = 0_i64
    seq2 = [0_i64, 0_i64, 0_i64]
    rng5 = Random.new(12345_u64)
    loop do
      w = 0
      rng5 = Random.new(12345_u64) if w == 0 # reset per full attempt set? we need same sequence per window? better use same seed per window sequence
      # reset seed for each attempt so 3 windows comparable across attempts
      rng5 = Random.new(12345_u64)
      while w < 3
        rngw = Random.new(12345_u64) # same fixed jump sequence per window
        GC.collect
        GC.disable
        begin
          before = GC.stats.bytes_since_gc
          k = 0
          while k < N_ALLOC
            vl2.scroll_to(rngw.rand(0..max_scroll2))
            vl2.dirty_rects
            vl2.prepare_visible
            draw_list.clear
            i = vl2.visible_first
            last = vl2.visible_last
            while i <= last
              oy = vl2.node_offset(i).to_f32
              draw_list.push(Tessell::Render::DrawCmd.new(Tessell::Render::CmdKind::Rect,
                Tessell::Rect.new(0.0_f32, oy, VIEWPORT_W.to_f32, ROW_H.to_f32), 0xFFF0F0F0_u32, -1, nil))
              sep_y = oy + ROW_H.to_f32 - 1.0_f32
              draw_list.push(Tessell::Render::DrawCmd.new(Tessell::Render::CmdKind::Rect,
                Tessell::Rect.new(0.0_f32, sep_y, VIEWPORT_W.to_f32, 1.0_f32), 0xFFD0D0D0_u32, -1, nil))
              text_y = oy + 14.0_f32
              renderer.build_text(placement_sink, LABEL, 8.0_f32, text_y, TEXT_SIZE, VIEWPORT_W, 10_000_000, page_tex_ids)
              i += 1
            end
            draw_list.build_batches_into(batch_sink)
            k += 1
          end
          seq2[w] = GC.stats.bytes_since_gc.to_i64 - before.to_i64
        ensure
          GC.enable
        end
        w += 1
      end
      delta_work2 = seq2[0]
      delta_work2 = seq2[1] if seq2[1] > delta_work2
      delta_work2 = seq2[2] if seq2[2] > delta_work2
      break if delta_work2 < N_ALLOC && delta_work2 <= 256
      if attempt2 >= 2
        break
      end
      retried2 = true
      attempt2 = 2
    end

    puts "scenario=jump_fixed_seed seed=12345 visible_avg=#{visible_sum2.to_f64 / FRAMES.to_f64} fetched_per_frame_avg=#{fetched_sum2.to_f64 / FRAMES.to_f64} cmds_avg=#{cmds_sum2.to_f64 / FRAMES.to_f64} batches_avg=#{batches_sum2.to_f64 / FRAMES.to_f64} quads_avg=#{quads_sum2.to_f64 / FRAMES.to_f64} alloc_bytes=#{delta_work2} frame_cpu_p50_us=#{p50_2} frame_cpu_p95_us=#{p95_2} frame_cpu_p99_us=#{p99_2} frames=#{FRAMES} alloc_windows=[#{seq2[0]},#{seq2[1]},#{seq2[2]}] delta_prime=#{delta_prime2} delta_calib=#{delta_calib2} retried=#{retried2} attempt=#{attempt2} pool_size=#{vl2.pool_size} created=#{vl2.recycle_stats[:created]}"

    puts "GL_SCROLL_WINDOW=not_done reason=optional_not_implemented_in_task70"
    puts "BENCH_SCROLL_EXIT=0"

    measurer.close
  end
end

BenchScroll.run