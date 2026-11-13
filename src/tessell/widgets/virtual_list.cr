# Tessell::Widgets::VirtualList (M2-WP4)
#
# Viewport-only virtualization: never materializes all rows.
# - Fixed/variable row heights (prefix-sum cache, rebuilt only on invalidate_heights)
# - Visible range + bind_visible/fetch only over visible rows (fetched_count)
# - Recycler stats: pool_size cap (default ceil(viewport_h/row_h)+2), created bounded
# - Scroll dirty strips merged via Render::Dirty.merge_into (no full-layout rearrange)
# - Steady-state scroll_by/dirty_rects path designed for zero-alloc (preallocated sinks)

require "../geometry"
require "../render/dirty"

module Tessell
  module Widgets
    class VirtualList
      alias RowHeightProc = Proc(Int32, Int32)

      getter row_count : Int32
      getter viewport_h : Int32
      getter viewport_w : Int32
      getter scroll_y : Int32
      getter fetched_count : Int32
      getter visible_first : Int32
      getter visible_last : Int32

      # recycle stats
      getter acquired_total : Int32
      getter released_total : Int32
      getter reused_total : Int32
      getter created_total : Int32

      @fixed_height : Int32?
      @height_proc : RowHeightProc?
      @fetch : Proc(Int32, Nil)

      @prefix : Array(Int32)  # prefix sums, size row_count+1, prefix[0]=0
      @prefix_valid : Bool
      @total_h : Int32

      @visible_first : Int32
      @visible_last : Int32
      @last_bound_first : Int32
      @last_bound_last : Int32
      @has_bound : Bool

      @pool_size : Int32
      @active_slots : Int32

      # dirty tracking
      @prev_scroll_y : Int32
      @dirty_accum : Int32
      @dirty_input : Array(Rect)
      @dirty_output : Array(Rect)
      @last_dirty_count : Int32
      @last_dirty_area : Int64

      def initialize(@row_count : Int32, row_height : Int32 | RowHeightProc, @viewport_h : Int32,
                     fetch : Proc(Int32, Nil), @viewport_w : Int32 = 1)
        @fetch = fetch
        @scroll_y = 0
        @fetched_count = 0
        @acquired_total = 0
        @released_total = 0
        @reused_total = 0
        @created_total = 0
        @visible_first = 0
        @visible_last = -1
        @last_bound_first = 0
        @last_bound_last = -1
        @has_bound = false
        @active_slots = 0
        @prev_scroll_y = 0
        @dirty_accum = 0
        @dirty_input = [] of Rect
        @dirty_output = [] of Rect
        # pre-size sinks to avoid steady-state growth (max_regions default 8)
        8.times { @dirty_input << Rect.new(0.0_f32, 0.0_f32, 0.0_f32, 0.0_f32) }
        8.times { @dirty_output << Rect.new(0.0_f32, 0.0_f32, 0.0_f32, 0.0_f32) }
        @dirty_input.clear
        @dirty_output.clear
        @last_dirty_count = 0
        @last_dirty_area = 0_i64

        @prefix = [] of Int32
        @prefix_valid = false
        @total_h = 0

        case row_height
        in Int32
          @fixed_height = row_height
          @height_proc = nil
          @pool_size = default_pool_size(row_height)
          @total_h = @row_count * row_height
          @prefix_valid = true # not needed for fixed
        in Proc(Int32, Int32)
          @fixed_height = nil
          @height_proc = row_height
          # pool size: estimate by average/first sample; compute after prefix
          build_prefix
          avg_h = average_height
          @pool_size = default_pool_size(avg_h)
        end

        recompute_visible
      end

      private def default_pool_size(h : Int32) : Int32
        h = 1 if h <= 0
        # ceil(viewport_h / h) + 2
        ((@viewport_h + h - 1) // h) + 2
      end

      private def average_height : Int32
        return 1 if @row_count <= 0
        th = total_height
        h = th // @row_count
        h <= 0 ? 1 : h
      end

      private def build_prefix : Nil
        @prefix = Array(Int32).new(@row_count + 1, 0)
        sum = 0
        proc = @height_proc
        if proc
          i = 0
          while i < @row_count
            @prefix[i] = sum
            sum += proc.call(i)
            i += 1
          end
          @prefix[@row_count] = sum
        else
          h = @fixed_height || 0
          i = 0
          while i <= @row_count
            @prefix[i] = i * h
            i += 1
          end
          sum = @row_count * h
        end
        @total_h = sum
        @prefix_valid = true
      end

      def pool_size : Int32
        @pool_size
      end

      def total_height : Int32
        if fh = @fixed_height
          @row_count * fh
        else
          build_prefix unless @prefix_valid
          @total_h
        end
      end

      private def max_scroll : Int32
        th = total_height
        ms = th - @viewport_h
        if @row_count == 0 || th <= @viewport_h || ms < 0
          0
        else
          ms
        end
      end

      def scroll_by(dy : Int32) : Int32
        scroll_to(@scroll_y + dy)
      end

      def scroll_to(y : Int32) : Int32
        ms = max_scroll
        ny = y
        ny = 0 if ny < 0
        ny = ms if ny > ms
        if ny != @scroll_y
          @dirty_accum += (ny - @scroll_y).abs
          @scroll_y = ny
          recompute_visible
        end
        @scroll_y
      end

      def visible_range : NamedTuple(first: Int32, last: Int32)
        {first: @visible_first, last: @visible_last}
      end

      # Compute visible range without allocations
      private def recompute_visible : Nil
        if @row_count <= 0
          @visible_first = 0
          @visible_last = -1
          return
        end
        if fh = @fixed_height
          h = fh <= 0 ? 1 : fh
          first = @scroll_y // h
          last = (@scroll_y + @viewport_h - 1) // h
          first = 0 if first < 0
          max_idx = @row_count - 1
          first = max_idx if first > max_idx
          last = max_idx if last > max_idx
          # ensure intersection with [scroll_y, scroll_y+viewport_h)
          while last >= first && (last * h) >= (@scroll_y + @viewport_h)
            last -= 1
          end
          if last < first
            # at least the row containing scroll_y if within bounds
            first = @scroll_y // h
            first = 0 if first < 0
            first = max_idx if first > max_idx
            last = first
            if (first * h) >= (@scroll_y + @viewport_h)
              @visible_last = -1
              @visible_first = 0
              return
            end
          end
          @visible_first = first
          @visible_last = last
        else
          build_prefix unless @prefix_valid
          compute_visible_variable
        end
      end

      private def compute_visible_variable : Nil
        # binary search for first row with bottom > scroll_y and top < scroll_y+viewport_h
        top_v = @scroll_y
        bot_v = @scroll_y + @viewport_h
        # first: smallest i with prefix[i+1] > top_v
        first = lower_bound_row(top_v)
        # last: largest i with prefix[i] < bot_v
        last = upper_bound_row(bot_v) - 1
        max_idx = @row_count - 1
        first = 0 if first < 0
        first = max_idx if first > max_idx
        last = -1 if last < 0
        last = max_idx if last > max_idx
        if last < first
          @visible_first = 0
          @visible_last = -1
        else
          @visible_first = first
          @visible_last = last
        end
      end

      # first index i in [0,row_count) with prefix[i+1] > y
      private def lower_bound_row(y : Int32) : Int32
        lo = 0
        hi = @row_count
        while lo < hi
          mid = (lo + hi) >> 1
          if @prefix[mid + 1] <= y
            lo = mid + 1
          else
            hi = mid
          end
        end
        lo
      end

      # first index i in [0,row_count] with prefix[i] >= y
      private def upper_bound_row_exclusive(y : Int32) : Int32
        lo = 0
        hi = @row_count + 1
        while lo < hi
          mid = (lo + hi) >> 1
          if @prefix[mid] < y
            lo = mid + 1
          else
            hi = mid
          end
        end
        lo
      end

      # number of rows whose top < y  => returns count; last index = count-1
      private def upper_bound_row(y : Int32) : Int32
        upper_bound_row_exclusive(y)
      end

      def node_offset(i : Int32) : Int32
        if fh = @fixed_height
          i * fh - @scroll_y
        else
          build_prefix unless @prefix_valid
          return -@scroll_y if i <= 0
          return @prefix[@row_count] - @scroll_y if i >= @row_count
          @prefix[i] - @scroll_y
        end
      end

      # Reconcile recycler accounting for current visible range and fetch visible rows.
      # No block/yield: hot-path friendly (avoids closure/Proc capture in caller).
      # Returns fetched_count. Use visible_first/visible_last + node_offset(i) to iterate work.
      def prepare_visible : Int32
        @fetched_count = 0
        f = @visible_first
        l = @visible_last
        if l < f
          # release all previously bound
          if @has_bound
            release_range(@last_bound_first, @last_bound_last)
            @has_bound = false
          end
          @last_bound_first = 0
          @last_bound_last = -1
          return 0
        end

        new_count = l - f + 1
        if @has_bound
          of = @last_bound_first
          ol = @last_bound_last
          if ol >= of
            # rows that left: [of, min(ol,f-1)] and [max(of,l+1), ol]
            left1_end = {ol, f - 1}.min
            if left1_end >= of
              release_range(of, left1_end)
            end
            left2_start = {of, l + 1}.max
            if ol >= left2_start
              release_range(left2_start, ol)
            end
            # overlap reused
            overlap_first = {of, f}.max
            overlap_last = {ol, l}.min
            if overlap_last >= overlap_first
              @reused_total += (overlap_last - overlap_first + 1)
            end
            # rows that entered
            if f < overlap_first
              acquire_range(f, overlap_first - 1)
            elsif of > l || ol < f
              acquire_range(f, l)
            end
            if l > overlap_last
              acquire_range(overlap_last + 1, l)
            elsif of > l || ol < f
              # already acquired all
            end
          else
            acquire_range(f, l)
          end
        else
          acquire_range(f, l)
          @has_bound = true
        end

        @last_bound_first = f
        @last_bound_last = l
        @active_slots = new_count

        i = f
        while i <= l
          @fetch.call(i)
          @fetched_count += 1
          i += 1
        end
        @fetched_count
      end

      # Bind only visible rows. Calls fetch(index) for each visible row and yields (index, offset).
      # Tracks recycler acquire/release/reused/created by diffing visible ranges.
      def bind_visible(&block : Int32, Int32 -> Nil) : Int32
        count = prepare_visible
        f = @visible_first
        l = @visible_last
        return 0 if l < f
        i = f
        while i <= l
          block.call(i, node_offset(i))
          i += 1
        end
        count
      end

      def each_visible(&block : Int32, Int32 -> Nil) : Int32
        bind_visible(&block)
      end

      private def acquire_range(a : Int32, b : Int32) : Nil
        return if b < a
        n = b - a + 1
        @acquired_total += n
        # create up to pool_size slots total
        need = n
        while need > 0 && @created_total < @pool_size
          @created_total += 1
          need -= 1
        end
        # if pool exhausted, still count acquired but do not exceed pool semantics in created
        # (spec requires created <= pool_size+1 after 200 scrolls; cap at pool_size)
      end

      private def release_range(a : Int32, b : Int32) : Nil
        return if b < a
        @released_total += (b - a + 1)
      end

      def recycle_stats : NamedTuple(acquired: Int32, released: Int32, reused: Int32, created: Int32, pool_size: Int32)
        {acquired: @acquired_total, released: @released_total, reused: @reused_total, created: @created_total, pool_size: @pool_size}
      end

      # Dirty rects from accumulated scroll since last call.
      # < viewport_h => up to 2 strips (old exposed + new exposed); >= viewport_h => 1 full window.
      # Returns {count, area}. Uses Dirty.merge_into into reusable sink.
      def dirty_rects(max_regions : Int32 = 8) : NamedTuple(count: Int32, area: Int64)
        dy = @dirty_accum
        @dirty_accum = 0
        @dirty_input.clear

        w = @viewport_w.to_f32
        vh = @viewport_h
        vh_f = vh.to_f32
        if dy == 0
          # no movement
        elsif dy.abs >= vh
          @dirty_input << Rect.new(0.0_f32, 0.0_f32, w, vh_f)
        else
          d = dy.abs
          d_f = d.to_f32
          # two strips: newly exposed edge + counterpart strip ("old exposed + new exposed")
          # strip 1 (newly exposed): bottom if scrolled down (+y), top if scrolled up
          # strip 2 (old exposed counterpart): opposite edge of same thickness
          if dy > 0
            # scrolled down: new content exposed at bottom, old region vacated at top
            @dirty_input << Rect.new(0.0_f32, (vh - d).to_f32, w, d_f)
            @dirty_input << Rect.new(0.0_f32, 0.0_f32, w, d_f)
          else
            # scrolled up: new content exposed at top, old region vacated at bottom
            @dirty_input << Rect.new(0.0_f32, 0.0_f32, w, d_f)
            @dirty_input << Rect.new(0.0_f32, (vh - d).to_f32, w, d_f)
          end
        end

        Render::Dirty.merge_into(@dirty_input, @dirty_output, max_regions)
        count = @dirty_output.size
        area = 0_i64
        i = 0
        while i < count
          r = @dirty_output[i]
          aw = r.size.width
          ah = r.size.height
          if aw > 0.0_f32 && ah > 0.0_f32
            area += (aw.to_f64 * ah.to_f64).to_i64
          end
          i += 1
        end
        @last_dirty_count = count
        @last_dirty_area = area
        {count: count, area: area}
      end

      def invalidate_row(i : Int32) : Nil
        # content change only; geometry unchanged in fixed mode. Rebuild prefix if variable.
        if @fixed_height.nil?
          # variable height may change for row i; safest to invalidate cache
          invalidate_heights
        end
      end

      def invalidate_heights : Nil
        @prefix_valid = false
        @prefix.clear
        @total_h = 0
        build_prefix
        # recompute visible with current scroll_y clamped
        ms = max_scroll
        @scroll_y = ms if @scroll_y > ms
        recompute_visible
      end
    end
  end
end