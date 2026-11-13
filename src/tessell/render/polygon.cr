# Tessell::Render::Polygon (M3-WP4, CPU reference)
# Pure Crystal, no FFI. Caller supplies/preallocates buffers; no copies on init.

require "../geometry"

module Tessell
  module Render
    struct Polygon
      getter points : Array(Tessell::Point)
      getter size : Int32
      getter bounds : Tessell::Rect
      getter signed_area : Float32

      # Holds the caller's array reference (no copy).
      def initialize(@points : Array(Tessell::Point))
        @size = @points.size
        @bounds = compute_bounds
        @signed_area = compute_signed_area
      end

      # Even-odd ray casting: a horizontal ray from p toward +x crosses an edge
      # when (y0 > p.y) != (y1 > p.y) (so edges with y0 == y1 do not cross) and
      # p.x is strictly less than the edge's x at p.y. Boundary/on-edge points:
      # classification follows these strict comparisons and is not guaranteed to
      # be treated as inside (edge cases may return false).
      def contains?(p : Tessell::Point) : Bool
        n = @size
        return false if n < 3
        pts = @points
        inside = false
        j = n - 1
        i = 0
        while i < n
          pi = pts.unsafe_fetch(i)
          pj = pts.unsafe_fetch(j)
          yi = pi.y
          yj = pj.y
          if (yi > p.y) != (yj > p.y)
            x_int = (pj.x - pi.x) * (p.y - yi) / (yj - yi) + pi.x
            inside = !inside if p.x < x_int
          end
          j = i
          i += 1
        end
        inside
      end

      # Writes w*h bytes (0/1 coverage) into caller-preallocated sink for bounds,
      # sampling pixel centers at (bounds.x + x + 0.5, bounds.y + y + 0.5).
      # Returns covered pixel count. Raises ArgumentError if sink is too small.
      def self.mask(points : Array(Tessell::Point), bounds : Tessell::Rect, sink : Bytes) : Int32
        w = bounds.size.width.to_i
        h = bounds.size.height.to_i
        needed = w * h
        raise ArgumentError.new("mask sink too small") if sink.size < needed
        return 0 if w <= 0 || h <= 0
        poly = Polygon.new(points)
        covered = 0
        bx = bounds.origin.x
        by = bounds.origin.y
        y = 0
        while y < h
          py = by + y.to_f32 + 0.5_f32
          x = 0
          row = y * w
          while x < w
            px = bx + x.to_f32 + 0.5_f32
            if poly.contains?(Point.new(px, py))
              sink.unsafe_put(row + x, 1_u8)
              covered += 1
            else
              sink.unsafe_put(row + x, 0_u8)
            end
            x += 1
          end
          y += 1
        end
        covered
      end

      # Emits a triangle fan from points[0] as explicit triangles in fan order:
      # (p0,p1,p2), (p0,p2,p3), ... writing x,y for each vertex into sink.
      # Total floats = 6*(n-2). Returns triangle count (n-2). Raises if sink small.
      def self.emit_fan(points : Array(Tessell::Point), sink : Slice(Float32)) : Int32
        n = points.size
        return 0 if n < 3
        tris = n - 2
        needed = tris * 6
        raise ArgumentError.new("emit_fan sink too small") if sink.size < needed
        p0 = points.unsafe_fetch(0)
        i = 0
        off = 0
        while i < tris
          p1 = points.unsafe_fetch(i + 1)
          p2 = points.unsafe_fetch(i + 2)
          sink.unsafe_put(off, p0.x)
          off += 1
          sink.unsafe_put(off, p0.y)
          off += 1
          sink.unsafe_put(off, p1.x)
          off += 1
          sink.unsafe_put(off, p1.y)
          off += 1
          sink.unsafe_put(off, p2.x)
          off += 1
          sink.unsafe_put(off, p2.y)
          off += 1
          i += 1
        end
        tris
      end

      private def compute_bounds : Tessell::Rect
        n = @size
        return Tessell::Rect.new(0.0_f32, 0.0_f32, 0.0_f32, 0.0_f32) if n == 0
        p0 = @points.unsafe_fetch(0)
        min_x = p0.x
        max_x = p0.x
        min_y = p0.y
        max_y = p0.y
        i = 1
        while i < n
          p = @points.unsafe_fetch(i)
          min_x = p.x if p.x < min_x
          max_x = p.x if p.x > max_x
          min_y = p.y if p.y < min_y
          max_y = p.y if p.y > max_y
          i += 1
        end
        Tessell::Rect.new(min_x, min_y, max_x - min_x, max_y - min_y)
      end

      private def compute_signed_area : Float32
        n = @size
        return 0.0_f32 if n < 3
        sum = 0.0_f32
        i = 0
        j = 1
        while i < n
          j = 0 if j == n
          pi = @points.unsafe_fetch(i)
          pj = @points.unsafe_fetch(j)
          sum += pi.x * pj.y - pj.x * pi.y
          i += 1
          j += 1
        end
        0.5_f32 * sum
      end
    end
  end
end
