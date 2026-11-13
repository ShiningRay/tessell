# Tessell::Render::TextRenderer (M2-WP2d 阶段 1)
# CPU 侧文本四边形生成：复用 GlyphAtlas + Rasterizer 产出的 placements，生成按图集页分段的顶点批次。
#
# 坐标约定：输入/输出顶点均为屏幕像素空间（y-down，viewport 左上为原点）。
#   pen 起点 (x, y) 为 baseline（y-down）。
#   字形矩形：left = pen_x + offset_x, top = pen_y - offset_y,
#            right = left + w,        bottom = top + h
#   （offset_y 来自 FT bitmap_top，即 baseline 上方距离，故 y-down 下 top = baseline_y - offset_y）
# NDC 转换不在此层完成；GL 后端可按视口做正交/即时模式映射（glOrtho 或 glVertex2f 映射）。
#
# Vertex 内存布局假设（值类型 struct，顺序字段，连续存储于 Array 缓冲中供后端读取）：
#   x : Float32, y : Float32, u : Float32, v : Float32, rgba : UInt32  => 20 bytes/vertex
# 四边形按 4 顶点存储（非索引）：(left,top),(right,top),(right,bottom),(left,bottom)
# UV 由 GlyphPlacement (u0,v0)-(u1,v1) 直接复用，∈[0,1]。
#
# 稳态零分配：vertices/batch_runs/placement_sink 由调用方复用；build_text 仅原位写与计数清零。
# 禁 FFI；不修改 src/tessell/text/*。

require "../text/glyph_atlas"
require "../text/rasterizer"

module Tessell
  module Render
    struct Vertex
      getter x : Float32
      getter y : Float32
      getter u : Float32
      getter v : Float32
      getter rgba : UInt32

      def initialize(@x : Float32, @y : Float32, @u : Float32, @v : Float32, @rgba : UInt32)
      end
    end

    # 批次：同一图集页（page）且同页面类型（color）的连续顶点段。纹理由后端占有，调用方不再传纹理 id。
    # color=false: R8 覆盖页（顶点色调制）；color=true: RGBA 预乘页（后端以 glColor4f(1,1,1,1) 提交，不再乘色）。
    struct TextBatch
      getter start : Int32 # vertices 起始下标
      getter count : Int32 # 顶点数（4 的倍数）
      getter page : Int32  # atlas page index（由 Backend#resolved_texture 解析为实际纹理）
      getter color : Bool  # atlas page type: true=RGBA color page, false=R8 coverage page

      def initialize(@start : Int32, @count : Int32, @page : Int32, @color : Bool = false)
      end
    end

    class TextRenderer
      getter vertex_count : Int32
      getter batch_count : Int32

      @atlas : Text::GlyphAtlas
      @rasterizer : Text::Rasterizer
      @vertices : Array(Vertex)
      @batches : Array(TextBatch)

      def initialize(@atlas : Text::GlyphAtlas, @rasterizer : Text::Rasterizer)
        @atlas = atlas
        @rasterizer = rasterizer
        @vertices = [] of Vertex
        @batches = [] of TextBatch
        @vertex_count = 0
        @batch_count = 0
      end

      def quad_capacity : Int32
        @vertices.size // 4
      end

      def vertices : Array(Vertex)
        @vertices
      end

      # 返回当前有效批次的逻辑视图（按 batch_count 截断）。
      def batch_runs : Array(TextBatch)
        # 复用底层数组；调用方应按 batch_count 读取前缀
        @batches
      end

      def stats : NamedTuple(quads: Int32, batches: Int32)
        {quads: @vertex_count // 4, batches: @batch_count}
      end

      # 预留容量以支持稳态零分配（可选：首次/扩容帧调用，热路径不应增长）。
      def reserve_quads(n : Int32) : Nil
        need_v = n * 4
        if @vertices.size < need_v
          (need_v - @vertices.size).times { @vertices << Vertex.new(0.0_f32, 0.0_f32, 0.0_f32, 0.0_f32, 0_u32) }
        end
      end

      def reserve_batches(n : Int32) : Nil
        if @batches.size < n
          (n - @batches.size).times { @batches << TextBatch.new(0, 0, 0) }
        end
      end

      # 逻辑清零（复用缓冲，稳态不分配）。
      def reset : Nil
        @vertex_count = 0
        @batch_count = 0
      end

      # 追加文本四边形到当前缓冲（不清零），用于同帧多段文本合批/拼场景。
      # placement_sink 由调用方复用；每段 shape_run_into 会覆写 placement_sink 后再转顶点。
      def append_text_cached(placement_sink : Array(Text::GlyphPlacement), text : String,
                             x : Float32, y : Float32, size_px : Int32,
                             viewport_w : Int32, viewport_h : Int32,
                             rgba : UInt32 = 0x000000ff_u32) : Float32
        @rasterizer.shape_run_into(text, size_px, placement_sink)
        build_text_from_placements(placement_sink, x, y, rgba)
      end

      # 生成文本四边形（M3-WP1：不再接受纹理 id；批次携带 page，由后端解析纹理）。
      # placement_sink: 调用方复用的 GlyphPlacement 缓冲。text/x/y: baseline 起点（y-down）。
      # size_px: 字号。viewport_w/h: 视口尺寸（当前用于边界安全，顶点仍为屏幕坐标）。
      # 返回 pen 末端 x（Float32）。
      # Uses per-call HB/FT shaping path (rasterize_into) to preserve existing behavior/stats.
      def build_text(placement_sink : Array(Text::GlyphPlacement), text : String,
                     x : Float32, y : Float32, size_px : Int32,
                     viewport_w : Int32, viewport_h : Int32,
                     rgba : UInt32 = 0x000000ff_u32) : Float32
        @vertex_count = 0
        @batch_count = 0

        @rasterizer.rasterize_into(text, size_px, placement_sink)
        build_text_from_placements(placement_sink, x, y, rgba)
      end

      # 兼容重载：接受并忽略 page_texture_ids（纹理由后端占有）。
      def build_text(placement_sink : Array(Text::GlyphPlacement), text : String,
                     x : Float32, y : Float32, size_px : Int32,
                     viewport_w : Int32, viewport_h : Int32,
                     page_texture_ids : Array(Int32),
                     rgba : UInt32 = 0x000000ff_u32) : Float32
        build_text(placement_sink, text, x, y, size_px, viewport_w, viewport_h, rgba)
      end

      # M2-WP4/task-73: uses Rasterizer shaped-run cache (shape_run_into) to skip HB/FT shaping on hit.
      # placement_sink is still reused; on cache hit only placement copy + vertex emission occur.
      def build_text_cached(placement_sink : Array(Text::GlyphPlacement), text : String,
                            x : Float32, y : Float32, size_px : Int32,
                            viewport_w : Int32, viewport_h : Int32,
                            rgba : UInt32 = 0x000000ff_u32) : Float32
        @vertex_count = 0
        @batch_count = 0

        @rasterizer.shape_run_into(text, size_px, placement_sink)
        build_text_from_placements(placement_sink, x, y, rgba)
      end

      # 兼容重载：接受并忽略 page_texture_ids（纹理由后端占有）。
      def build_text_cached(placement_sink : Array(Text::GlyphPlacement), text : String,
                            x : Float32, y : Float32, size_px : Int32,
                            viewport_w : Int32, viewport_h : Int32,
                            page_texture_ids : Array(Int32),
                            rgba : UInt32 = 0x000000ff_u32) : Float32
        build_text_cached(placement_sink, text, x, y, size_px, viewport_w, viewport_h, rgba)
      end

      private def build_text_from_placements(placement_sink : Array(Text::GlyphPlacement),
                                             x : Float32, y : Float32,
                                             rgba : UInt32) : Float32
        pen_x = x
        pen_y = y
        current_page = -1
        current_color = false
        batch_start = 0
        batch_vertices = 0
        batch_page = 0
        batch_color = false

        i = 0
        count = placement_sink.size
        while i < count
          p = placement_sink[i]

          # w==0||h==0 零位图字形：不产四边形，但推进 pen
          if p.w > 0 && p.h > 0
            page = p.page
            color = p.color

            if current_page != -1 && (page != current_page || color != current_color)
              # flush batch on page or page-type change: gray (R8) and color (RGBA)
              # glyphs never merge into one batch (different texture target + tint model)
              write_batch(batch_start, batch_vertices, batch_page, batch_color)
              batch_start = @vertex_count
              batch_vertices = 0
            end
            if current_page == -1
              batch_start = @vertex_count
              batch_vertices = 0
            end
            current_page = page
            current_color = color
            batch_page = page
            batch_color = color

            left = pen_x + p.offset_x.to_f32
            top = pen_y - p.offset_y.to_f32
            right = left + p.w.to_f32
            bottom = top + p.h.to_f32

            push_quad(left, top, right, bottom, p.u0, p.v0, p.u1, p.v1, rgba)
            batch_vertices += 4
          end

          pen_x += p.advance_px
          i += 1
        end

        if batch_vertices > 0
          write_batch(batch_start, batch_vertices, batch_page, batch_color)
        end

        pen_x
      end

      private def write_batch(start : Int32, count : Int32, page : Int32, color : Bool = false) : Nil
        if @batch_count < @batches.size
          @batches[@batch_count] = TextBatch.new(start, count, page, color)
        else
          @batches << TextBatch.new(start, count, page, color)
        end
        @batch_count += 1
      end

      private def push_quad(left : Float32, top : Float32, right : Float32, bottom : Float32,
                            u0 : Float32, v0 : Float32, u1 : Float32, v1 : Float32,
                            rgba : UInt32) : Nil
        # 4 vertices: (l,t),(r,t),(r,b),(l,b)
        v0v = Vertex.new(left, top, u0, v0, rgba)
        v1v = Vertex.new(right, top, u1, v0, rgba)
        v2v = Vertex.new(right, bottom, u1, v1, rgba)
        v3v = Vertex.new(left, bottom, u0, v1, rgba)
        write_vertex(@vertex_count, v0v)
        write_vertex(@vertex_count + 1, v1v)
        write_vertex(@vertex_count + 2, v2v)
        write_vertex(@vertex_count + 3, v3v)
        @vertex_count += 4
      end

      private def write_vertex(index : Int32, v : Vertex) : Nil
        if index < @vertices.size
          @vertices[index] = v
        else
          @vertices << v
        end
      end
    end
  end
end
