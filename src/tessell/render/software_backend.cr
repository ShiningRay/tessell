# Tessell::Render::SoftwareBackend（issue #10）
#
# 纯 CPU 光栅后端：渲染到内存 RGBA 缓冲，无窗口/GPU/FFI 依赖，CI 可跑。
# 与 GLBackend 同一 Backend 契约（begin_frame/draw_draw_list/draw_text/
# draw_polygon），混合语义对齐 GL（premultiplied，GL_ONE /
# GL_ONE_MINUS_SRC_ALPHA）：
#   R8 覆盖页（coverage I）：src = (fg.rgb * I, I)
#   RGBA 预乘页：src = texel
#   out = src.rgb + dst.rgb * (1 - src.a)
#
# dirty 语义与 GLBackend 相同：begin_frame(dirty) 不清屏；draw_text 先按
# 脏矩形清底色再逐矩形重画。headless 断言「脏区重绘 == 全量重绘」用本后端
# 即可在纯 spec 内完成（无需真机窗口探针）。
#
# 已知边界：nearest 采样（字形与四边形按设备像素 1:1 提交，与 GL 线性采样
# 在该场景下等价）；文本页数据经 attach_atlas 注入。

require "./backend"
require "./draw_list"
require "../text/glyph_atlas"

module Tessell
  module Render
    class SoftwareBackend < Backend
      getter width : Int32
      getter height : Int32
      getter pixels : Bytes

      @dirty : Array(Tessell::Rect)?
      @bg_color : UInt32
      @atlas : Text::GlyphAtlas?
      @submitted_quads : Int32
      @scissor_calls : Int32
      @culled_quads : Int32
      @stencil_fills : Int32

      def initialize
        @width = 0
        @height = 0
        @pixels = Bytes.new(0)
        @dirty = nil
        @bg_color = 0xffffffff_u32
        @atlas = nil
        @submitted_quads = 0
        @scissor_calls = 0
        @culled_quads = 0
        @stencil_fills = 0
      end

      def init(width : Int32, height : Int32) : Nil
        @width = width
        @height = height
        @pixels = Bytes.new(width * height * 4)
      end

      def resize(width : Int32, height : Int32) : Nil
        init(width, height)
      end

      # 文本采样需要 atlas 页数据；与 GL 的 resolved_texture 对应。
      def attach_atlas(atlas : Text::GlyphAtlas) : Nil
        @atlas = atlas
      end

      def begin_frame(dirty : Array(Tessell::Rect)? = nil,
                      theme : Tessell::Render::Theme = Tessell::Render::Theme.light) : Nil
        @dirty = dirty
        @bg_color = theme.bg
        if dirty.nil?
          fill_bg(@bg_color)
        else
          # 脏矩形清屏在 begin_frame 完成（与 GLBackend 同语义，issue #15）
          dirty.each { |r| fill_rect_pixels(r, @bg_color) }
        end
        @submitted_quads = 0
        @scissor_calls = 0
        @culled_quads = 0
        @stencil_fills = 0
      end

      def end_frame : Nil
        @dirty = nil
      end

      def close : Nil
      end

      def stats : FrameStats
        FrameStats.new(@submitted_quads, @scissor_calls, @culled_quads, @stencil_fills)
      end

      def resolved_texture(page : Int32) : Int32
        page
      end

      def sync_atlas(atlas : Text::GlyphAtlas) : Nil
        @atlas = atlas
      end

      # 软件后端无上传概念，增量与全量同为引用更新（issue #22）。
      def sync_atlas_dirty(atlas : Text::GlyphAtlas) : Nil
        @atlas = atlas
      end

      def pixel(x : Int32, y : Int32) : UInt32
        return 0_u32 if x < 0 || y < 0 || x >= @width || y >= @height
        i = (y * @width + x) * 4
        (@pixels[i].to_u32 << 24) | (@pixels[i + 1].to_u32 << 16) |
          (@pixels[i + 2].to_u32 << 8) | @pixels[i + 3].to_u32
      end

      # ---- Backend 契约 ----

      def draw_text(vertices : Array(Vertex), batches : Array(TextBatch),
                    batch_count : Int32 = batches.size, from_batch : Int32 = 0,
                    clip : Tessell::Rect? = nil) : Int32
        if rects = @dirty
          rects.each do |r|
            effective = clip ? intersect(clip, r) : r
            next if effective.size.width <= 0 || effective.size.height <= 0
            draw_quads(vertices, batches, batch_count, from_batch, effective)
          end
        else
          draw_quads(vertices, batches, batch_count, from_batch, clip)
        end
        @submitted_quads
      end

      def draw_draw_list(list : Tessell::Render::DrawList, from : Int32 = 0,
                         count : Int32 = -1) : Int32
        submitted = 0
        last = count < 0 ? list.size : Math.min(from + count, list.size)
        i = from
        while i < last
          cmd = list[i]
          clip = cmd.clip
          case cmd.kind
          when Tessell::Render::CmdKind::Rect
            fill_rect_pixels(cmd.bounds, cmd.color, clip)
            submitted += 1
          when Tessell::Render::CmdKind::RoundRect
            fill_round_rect_pixels(cmd.bounds, cmd.radius, cmd.color, clip)
            submitted += 1
          when Tessell::Render::CmdKind::StrokeRect
            stroke_rect_pixels(cmd.bounds,
              cmd.stroke_width <= 0 ? 1.0_f32 : cmd.stroke_width, cmd.color, clip)
            submitted += 1
          when Tessell::Render::CmdKind::StrokeRoundRect
            w = cmd.stroke_width <= 0 ? 1.0_f32 : cmd.stroke_width
            inner = Tessell::Rect.new(cmd.bounds.origin.x + w, cmd.bounds.origin.y + w,
              (cmd.bounds.size.width - 2 * w).clamp(0.0_f32, cmd.bounds.size.width),
              (cmd.bounds.size.height - 2 * w).clamp(0.0_f32, cmd.bounds.size.height))
            fill_round_rect_pixels(cmd.bounds, cmd.radius, cmd.color, clip)
            fill_round_rect_pixels(inner, Math.max(0.0_f32, cmd.radius - w), @bg_color, clip)
            submitted += 1
          when Tessell::Render::CmdKind::Line
            draw_line_pixels(cmd.p1, cmd.p2,
              cmd.stroke_width <= 0 ? 1.0_f32 : cmd.stroke_width, cmd.color, clip)
            submitted += 1
          when Tessell::Render::CmdKind::Text
            # 文本由 draw_text 按命令序交错提交（issue #15）
          else
          end
          i += 1
        end
        submitted
      end

      # even-odd 扫描填充（draw_polygon 的软件对应）。dirty 模式下逐脏矩形
      # 裁剪（与 GLBackend 的 #2 修复同语义：覆盖不得写出脏区）。
      def draw_polygon(points : Array(Tessell::Point), color : UInt32,
                       even_odd : Bool = true) : Bool
        return false unless even_odd
        return false if points.size < 3
        if rects = @dirty
          rects.each { |r| draw_polygon_clipped(points, color, r) }
        else
          draw_polygon_clipped(points, color, nil)
        end
        @stencil_fills += 1
        true
      end

      private def draw_polygon_clipped(points : Array(Tessell::Point),
                                       color : UInt32, clip : Tessell::Rect?) : Nil
        min_x = points[0].x; max_x = points[0].x
        min_y = points[0].y; max_y = points[0].y
        points.each do |p|
          min_x = p.x if p.x < min_x
          max_x = p.x if p.x > max_x
          min_y = p.y if p.y < min_y
          max_y = p.y if p.y > max_y
        end
        bbox = Tessell::Rect.new(min_x, min_y, max_x - min_x, max_y - min_y)
        if clip
          bbox = intersect(bbox, clip)
          return if bbox.size.width <= 0 || bbox.size.height <= 0
        end
        x0 = Math.max(0, bbox.origin.x.floor.to_i)
        y0 = Math.max(0, bbox.origin.y.floor.to_i)
        x1 = Math.min(@width - 1, (bbox.max_x - 0.001_f32).ceil.to_i)
        y1 = Math.min(@height - 1, (bbox.max_y - 0.001_f32).ceil.to_i)
        pr, pg, pb, pa = premultiply(color)
        y = y0
        while y <= y1
          cy = y.to_f32 + 0.5_f32
          x = x0
          while x <= x1
            if point_in_polygon?(x.to_f32 + 0.5_f32, cy, points)
              blend_pixel(x, y, pr, pg, pb, pa)
            end
            x += 1
          end
          y += 1
        end
      end

      # ---- 光栅内核 ----

      private def fill_bg(color : UInt32) : Nil
        r = Tessell::Render::Theme.rb(color)
        g = Tessell::Render::Theme.gb(color)
        b = Tessell::Render::Theme.bb(color)
        a = Tessell::Render::Theme.ab(color)
        i = 0
        n = @pixels.size
        while i < n
          @pixels[i] = r; @pixels[i + 1] = g; @pixels[i + 2] = b; @pixels[i + 3] = a
          i += 4
        end
      end

      private def premultiply(color : UInt32) : {Float32, Float32, Float32, Float32}
        a = Tessell::Render::Theme.ab(color).to_f32 / 255.0_f32
        r = Tessell::Render::Theme.rb(color).to_f32 / 255.0_f32 * a
        g = Tessell::Render::Theme.gb(color).to_f32 / 255.0_f32 * a
        b = Tessell::Render::Theme.bb(color).to_f32 / 255.0_f32 * a
        {r, g, b, a}
      end

      private def intersect(a : Tessell::Rect, b : Tessell::Rect) : Tessell::Rect
        x0 = Math.max(a.origin.x, b.origin.x)
        y0 = Math.max(a.origin.y, b.origin.y)
        x1 = Math.min(a.max_x, b.max_x)
        y1 = Math.min(a.max_y, b.max_y)
        Tessell::Rect.new(x0, y0, x1 - x0, y1 - y0)
      end

      # clip（Rect?）与 viewport/脏矩形求交后的像素循环边界。
      private def clip_bounds(clip : Tessell::Rect?) : {Int32, Int32, Int32, Int32}
        x0 = 0
        y0 = 0
        x1 = @width - 1
        y1 = @height - 1
        if clip
          x0 = Math.max(x0, clip.origin.x.floor.to_i)
          y0 = Math.max(y0, clip.origin.y.floor.to_i)
          x1 = Math.min(x1, (clip.max_x - 0.001_f32).floor.to_i)
          y1 = Math.min(y1, (clip.max_y - 0.001_f32).floor.to_i)
        end
        {x0, y0, x1, y1}
      end

      private def fill_rect_pixels(rect : Tessell::Rect, color : UInt32,
                                   clip : Tessell::Rect? = nil) : Nil
        return if rect.size.width <= 0 || rect.size.height <= 0
        effective = clip ? intersect(rect, clip) : rect
        bx0, by0, bx1, by1 = clip_bounds(effective)
        pr, pg, pb, pa = premultiply(color)
        y = by0
        while y <= by1
          x = bx0
          while x <= bx1
            blend_pixel(x, y, pr, pg, pb, pa)
            x += 1
          end
          y += 1
        end
      end

      private def fill_round_rect_pixels(rect : Tessell::Rect, radius : Float32,
                                         color : UInt32, clip : Tessell::Rect? = nil) : Nil
        return if rect.size.width <= 0 || rect.size.height <= 0
        r = radius.clamp(0.0_f32, Math.min(rect.size.width, rect.size.height) / 2.0_f32)
        effective = clip ? intersect(rect, clip) : rect
        bx0, by0, bx1, by1 = clip_bounds(effective)
        pr, pg, pb, pa = premultiply(color)
        y = by0
        while y <= by1
          cy = y.to_f32 + 0.5_f32
          x = bx0
          while x <= bx1
            if in_round_rect?(x.to_f32 + 0.5_f32, cy, rect, r)
              blend_pixel(x, y, pr, pg, pb, pa)
            end
            x += 1
          end
          y += 1
        end
      end

      private def in_round_rect?(px : Float32, py : Float32,
                                 rect : Tessell::Rect, r : Float32) : Bool
        return false if px < rect.origin.x || px >= rect.max_x
        return false if py < rect.origin.y || py >= rect.max_y
        return true if r <= 0.0_f32
        cx = rect.origin.x + r
        cy = rect.origin.y + r
        dx = px - cx
        dy = py - cy
        if dx < 0 && dy < 0 && dx * dx + dy * dy > r * r
          return false
        end
        cx = rect.max_x - r
        dx = px - cx
        if dx > 0 && dy < 0 && dx * dx + dy * dy > r * r
          return false
        end
        cy = rect.max_y - r
        dy = py - cy
        if dx > 0 && dy > 0 && dx * dx + dy * dy > r * r
          return false
        end
        cx = rect.origin.x + r
        dx = px - cx
        if dx < 0 && dy > 0 && dx * dx + dy * dy > r * r
          return false
        end
        true
      end

      private def stroke_rect_pixels(rect : Tessell::Rect, width : Float32,
                                     color : UInt32, clip : Tessell::Rect?) : Nil
        w = width.clamp(0.5_f32, Math.min(rect.size.width, rect.size.height) / 2.0_f32)
        top = Tessell::Rect.new(rect.origin.x, rect.origin.y, rect.size.width, w)
        bottom = Tessell::Rect.new(rect.origin.x, rect.max_y - w, rect.size.width, w)
        left = Tessell::Rect.new(rect.origin.x, rect.origin.y + w, w,
          (rect.size.height - 2 * w).clamp(0.0_f32, rect.size.height))
        right = Tessell::Rect.new(rect.max_x - w, rect.origin.y + w, w,
          (rect.size.height - 2 * w).clamp(0.0_f32, rect.size.height))
        fill_rect_pixels(top, color, clip)
        fill_rect_pixels(bottom, color, clip)
        fill_rect_pixels(left, color, clip)
        fill_rect_pixels(right, color, clip)
      end

      private def draw_line_pixels(p1 : Tessell::Point, p2 : Tessell::Point,
                                   width : Float32, color : UInt32,
                                   clip : Tessell::Rect?) : Nil
        half = width / 2.0_f32
        bbox = Tessell::Rect.new(
          Math.min(p1.x, p2.x) - half, Math.min(p1.y, p2.y) - half,
          (p2.x - p1.x).abs + width, (p2.y - p1.y).abs + width)
        bx0, by0, bx1, by1 = clip_bounds(clip ? intersect(bbox, clip) : bbox)
        pr, pg, pb, pa = premultiply(color)
        dx = p2.x - p1.x
        dy = p2.y - p1.y
        len2 = dx * dx + dy * dy
        y = by0
        while y <= by1
          cy = y.to_f32 + 0.5_f32
          x = bx0
          while x <= bx1
            cx = x.to_f32 + 0.5_f32
            t = len2 > 0.0_f32 ? ((cx - p1.x) * dx + (cy - p1.y) * dy) / len2 : 0.0_f32
            t = t.clamp(0.0_f32, 1.0_f32)
            px = p1.x + t * dx
            py = p1.y + t * dy
            ddx = cx - px
            ddy = cy - py
            if ddx * ddx + ddy * ddy <= half * half
              blend_pixel(x, y, pr, pg, pb, pa)
            end
            x += 1
          end
          y += 1
        end
      end

      # 四边形批量提交：atlas 采样 + 预乘混合。clip 为 scissor 等价物。
      private def draw_quads(vertices : Array(Vertex), batches : Array(TextBatch),
                             batch_count : Int32, from_batch : Int32,
                             clip : Tessell::Rect?) : Nil
        atlas = @atlas
        bx0, by0, bx1, by1 = clip_bounds(clip)
        i = from_batch
        while i < batch_count
          b = batches[i]
          page_size = atlas ? atlas.page_size : 0
          vi = b.start
          vend = b.start + b.count
          while vi < vend
            v0 = vertices[vi]
            v1 = vertices[vi + 1]
            v2 = vertices[vi + 2]
            v3 = vertices[vi + 3]
            x0 = Math.min(v0.x, v1.x).floor.to_i
            y0 = Math.min(v0.y, v2.y).floor.to_i
            x1 = Math.max(v1.x, v2.x).ceil.to_i
            y1 = Math.max(v2.y, v3.y).ceil.to_i
            qx0 = Math.max(x0, bx0)
            qy0 = Math.max(y0, by0)
            qx1 = Math.min(x1, bx1)
            qy1 = Math.min(y1, by1)
            fw = Math.max(1.0_f32, v1.x - v0.x)
            fh = Math.max(1.0_f32, v2.y - v1.y)
            y = qy0
            while y <= qy1
              x = qx0
              while x <= qx1
                unless atlas
                  x += 1
                  next
                end
                cx = x.to_f32 + 0.5_f32
                cy = y.to_f32 + 0.5_f32
                u = v0.u + (cx - v0.x) / fw * (v1.u - v0.u)
                v = v0.v + (cy - v0.y) / fh * (v2.v - v0.v)
                if b.color
                  tc = sample_rgba(atlas, b.page, u, v, page_size)
                  blend_pixel(x, y, tc[0], tc[1], tc[2], tc[3])
                else
                  cov = sample_r8(atlas, b.page, u, v, page_size).to_f32 / 255.0_f32
                  if cov > 0.0_f32
                    a = Tessell::Render::Theme.ab(v0.rgba).to_f32 / 255.0_f32
                    r = Tessell::Render::Theme.rb(v0.rgba).to_f32 / 255.0_f32 * a * cov
                    g = Tessell::Render::Theme.gb(v0.rgba).to_f32 / 255.0_f32 * a * cov
                    bl = Tessell::Render::Theme.bb(v0.rgba).to_f32 / 255.0_f32 * a * cov
                    blend_pixel(x, y, r, g, bl, cov * a)
                  end
                end
                x += 1
              end
              y += 1
            end
            @submitted_quads += 1
            vi += 4
          end
          i += 1
        end
      end

      private def sample_r8(atlas : Text::GlyphAtlas, page : Int32,
                            u : Float32, v : Float32, page_size : Int32) : UInt8
        return 0_u8 if page < 0 || page >= atlas.page_count || page_size <= 0
        tx = (u * page_size).floor.to_i.clamp(0, page_size - 1)
        ty = (v * page_size).floor.to_i.clamp(0, page_size - 1)
        atlas.page_data(page)[ty * page_size + tx]
      end

      private def sample_rgba(atlas : Text::GlyphAtlas, page : Int32,
                              u : Float32, v : Float32, page_size : Int32) : {Float32, Float32, Float32, Float32}
        return {0.0_f32, 0.0_f32, 0.0_f32, 0.0_f32} if page < 0 || page >= atlas.rgba_page_count || page_size <= 0
        tx = (u * page_size).floor.to_i.clamp(0, page_size - 1)
        ty = (v * page_size).floor.to_i.clamp(0, page_size - 1)
        data = atlas.rgba_page_data(page)
        i = (ty * page_size + tx) * 4
        # 预乘 RGBA 页：texel 即最终颜色（GL 路径不重复调制）
        {data[i].to_f32 / 255.0_f32, data[i + 1].to_f32 / 255.0_f32,
         data[i + 2].to_f32 / 255.0_f32, data[i + 3].to_f32 / 255.0_f32}
      end

      private def blend_pixel(x : Int32, y : Int32,
                              r : Float32, g : Float32, b : Float32, a : Float32) : Nil
        return if x < 0 || y < 0 || x >= @width || y >= @height
        i = (y * @width + x) * 4
        inv = 1.0_f32 - a
        dr = @pixels[i].to_f32 / 255.0_f32
        dg = @pixels[i + 1].to_f32 / 255.0_f32
        db = @pixels[i + 2].to_f32 / 255.0_f32
        da = @pixels[i + 3].to_f32 / 255.0_f32
        nr = (r + dr * inv).clamp(0.0_f32, 1.0_f32)
        ng = (g + dg * inv).clamp(0.0_f32, 1.0_f32)
        nb = (b + db * inv).clamp(0.0_f32, 1.0_f32)
        na = (a + da * inv).clamp(0.0_f32, 1.0_f32)
        @pixels[i] = (nr * 255.0_f32).round.to_u8
        @pixels[i + 1] = (ng * 255.0_f32).round.to_u8
        @pixels[i + 2] = (nb * 255.0_f32).round.to_u8
        @pixels[i + 3] = (na * 255.0_f32).round.to_u8
      end

      private def point_in_polygon?(px : Float32, py : Float32,
                                    points : Array(Tessell::Point)) : Bool
        inside = false
        j = points.size - 1
        i = 0
        while i < points.size
          pi = points[i]
          pj = points[j]
          if (pi.y > py) != (pj.y > py)
            xint = (pj.x - pi.x) * (py - pi.y) / (pj.y - pi.y) + pi.x
            inside = !inside if px < xint
          end
          j = i
          i += 1
        end
        inside
      end
    end
  end
end
