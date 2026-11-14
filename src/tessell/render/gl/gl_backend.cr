# Tessell::Render::GL::GLBackend (M3-WP1)
# GL 1.1 backend: texture ownership, scissor by dirty rects, quad culling.

require "../backend"
require "../text_renderer"
require "../../geometry"
require "../../text/glyph_atlas"

{% if flag?(:windows) %}
  @[Link("opengl32")]
{% elsif flag?(:darwin) %}
  @[Link(framework: "OpenGL")]
{% else %}
  @[Link("GL")]
{% end %}
lib TessellGL
  alias GLenum = UInt32
  alias GLboolean = UInt8
  alias GLbitfield = UInt32
  alias GLbyte = Int8
  alias GLshort = Int16
  alias GLint = Int32
  alias GLsizei = Int32
  alias GLubyte = UInt8
  alias GLushort = UInt16
  alias GLuint = UInt32
  alias GLfloat = Float32
  alias GLclampf = Float32
  alias GLdouble = Float64
  alias GLclampd = Float64
  alias GLvoid = Void

  GL_COLOR_BUFFER_BIT   = 0x00004000_u32
  GL_STENCIL_BUFFER_BIT = 0x00000400_u32
  GL_LINES              =     0x0001_u32
  GL_LINE_LOOP          =     0x0002_u32
  GL_TRIANGLES          =     0x0004_u32
  GL_QUADS              =     0x0007_u32

  GL_TEXTURE_2D   = 0x0DE1_u32
  GL_BLEND        = 0x0BE2_u32
  GL_ALPHA_TEST   = 0x0BC0_u32
  GL_SCISSOR_TEST = 0x0C11_u32
  GL_STENCIL_TEST = 0x0B90_u32

  GL_RGBA          = 0x1908_u32
  GL_ALPHA         = 0x1906_u32
  GL_LUMINANCE     = 0x1909_u32
  GL_INTENSITY     = 0x8049_u32
  GL_UNSIGNED_BYTE = 0x1401_u32

  GL_UNPACK_ALIGNMENT = 0x0CF5_u32
  GL_PACK_ALIGNMENT   = 0x0D05_u32
  GL_STENCIL_BITS     = 0x0D57_u32

  GL_TEXTURE_MIN_FILTER = 0x2801_u32
  GL_TEXTURE_MAG_FILTER = 0x2800_u32
  GL_LINEAR             = 0x2601_u32
  GL_NEAREST            = 0x2600_u32
  GL_TEXTURE_WRAP_S     = 0x2802_u32
  GL_TEXTURE_WRAP_T     = 0x2803_u32
  GL_CLAMP              = 0x2900_u32

  GL_SRC_ALPHA           = 0x0302_u32
  GL_ONE_MINUS_SRC_ALPHA = 0x0303_u32
  GL_ONE                 =      1_u32
  GL_ZERO                =      0_u32

  GL_ALWAYS       = 0x0207_u32
  GL_NOTEQUAL     = 0x0205_u32
  GL_KEEP         = 0x1E00_u32
  GL_INVERT       = 0x150A_u32
  GL_TRIANGLE_FAN = 0x0006_u32

  GL_PROJECTION = 0x1701_u32
  GL_MODELVIEW  = 0x1700_u32

  fun glViewport(x : GLint, y : GLint, width : GLsizei, height : GLsizei) : Void
  fun glScissor(x : GLint, y : GLint, width : GLsizei, height : GLsizei) : Void
  fun glClearColor(red : GLfloat, green : GLfloat, blue : GLfloat, alpha : GLfloat) : Void
  fun glClearStencil(s : GLint) : Void
  fun glClear(mask : GLbitfield) : Void
  fun glFlush : Void
  fun glFinish : Void
  fun glGetError : GLenum
  fun glGetIntegerv(pname : GLenum, params : GLint*) : Void

  fun glEnable(cap : GLenum) : Void
  fun glDisable(cap : GLenum) : Void
  fun glBlendFunc(sfactor : GLenum, dfactor : GLenum) : Void
  fun glColor4f(red : GLfloat, green : GLfloat, blue : GLfloat, alpha : GLfloat) : Void
  fun glLineWidth(width : GLfloat) : Void
  fun glColorMask(red : GLboolean, green : GLboolean, blue : GLboolean, alpha : GLboolean) : Void
  fun glStencilFunc(func : GLenum, ref : GLint, mask : GLuint) : Void
  fun glStencilOp(fail : GLenum, zfail : GLenum, zpass : GLenum) : Void
  fun glStencilMask(mask : GLuint) : Void

  fun glMatrixMode(mode : GLenum) : Void
  fun glLoadIdentity : Void
  fun glOrtho(left : GLdouble, right : GLdouble, bottom : GLdouble, top : GLdouble, zNear : GLdouble, zFar : GLdouble) : Void

  fun glGenTextures(n : GLsizei, textures : GLuint*) : Void
  fun glBindTexture(target : GLenum, texture : GLuint) : Void
  fun glDeleteTextures(n : GLsizei, textures : GLuint*) : Void
  fun glTexImage2D(target : GLenum, level : GLint, internalformat : GLint,
                   width : GLsizei, height : GLsizei, border : GLint,
                   format : GLenum, type : GLenum, pixels : Void*) : Void
  fun glTexSubImage2D(target : GLenum, level : GLint, xoffset : GLint, yoffset : GLint,
                      width : GLsizei, height : GLsizei, format : GLenum, type : GLenum, pixels : Void*) : Void
  fun glTexParameteri(target : GLenum, pname : GLenum, param : GLint) : Void
  fun glPixelStorei(pname : GLenum, param : GLint) : Void

  fun glBegin(mode : GLenum) : Void
  fun glEnd : Void
  fun glTexCoord2f(s : GLfloat, t : GLfloat) : Void
  fun glVertex2f(x : GLfloat, y : GLfloat) : Void

  fun glReadPixels(x : GLint, y : GLint, width : GLsizei, height : GLsizei,
                   format : GLenum, type : GLenum, pixels : Void*) : Void
end

module Tessell
  module Render
    module GL
      class GLBackend < Tessell::Render::Backend
        @page_texture_ids_arr : Array(UInt32)
        @rgba_page_texture_ids_arr : Array(UInt32)
        @viewport_w : Int32
        @viewport_h : Int32
        @dirty : Array(Tessell::Rect)?
        @scissor_calls : Int32
        @culled_quads : Int32
        @submitted_quads : Int32
        @stencil_fills : Int32
        @stencil_bits : Int32
        @bg_r : Float32
        @bg_g : Float32
        @bg_b : Float32
        @bg_a : Float32
        @frame_active : Bool

        def initialize
          @page_texture_ids_arr = [] of UInt32
          @rgba_page_texture_ids_arr = [] of UInt32
          @viewport_w = 0
          @viewport_h = 0
          @dirty = nil
          @scissor_calls = 0
          @culled_quads = 0
          @submitted_quads = 0
          @stencil_fills = 0
          @stencil_bits = 0
          @bg_r = 1.0_f32
          @bg_g = 1.0_f32
          @bg_b = 1.0_f32
          @bg_a = 1.0_f32
          @frame_active = false
        end

        def init(width : Int32, height : Int32) : Nil
          @viewport_w = width
          @viewport_h = height
          # Query the actual stencil bits of the current GL context. If the pixel
          # format carried no stencil buffer this stays 0 and draw_polygon must
          # honestly report unsupported (return false) instead of silently
          # falling back to a wrong fill.
          bits = 0
          TessellGL.glGetIntegerv(TessellGL::GL_STENCIL_BITS, pointerof(bits))
          @stencil_bits = bits
        end

        getter stencil_bits : Int32

        def resize(width : Int32, height : Int32) : Nil
          @viewport_w = width
          @viewport_h = height
          TessellGL.glViewport(0, 0, width, height)
        end

        def set_clear_color(r : Float32, g : Float32, b : Float32, a : Float32 = 1.0_f32) : Nil
          @bg_r = r
          @bg_g = g
          @bg_b = b
          @bg_a = a
        end

        def begin_frame(dirty : Array(Tessell::Rect)? = nil, theme : Tessell::Render::Theme = Tessell::Render::Theme.light) : Nil
          @dirty = dirty
          @scissor_calls = 0
          @culled_quads = 0
          @submitted_quads = 0
          @stencil_fills = 0
          @frame_active = true

          @bg_r = Tessell::Render::Theme.r(theme.bg)
          @bg_g = Tessell::Render::Theme.g(theme.bg)
          @bg_b = Tessell::Render::Theme.b(theme.bg)
          @bg_a = Tessell::Render::Theme.a(theme.bg)

          TessellGL.glViewport(0, 0, @viewport_w, @viewport_h)
          TessellGL.glClearColor(@bg_r, @bg_g, @bg_b, @bg_a)

          TessellGL.glMatrixMode(TessellGL::GL_PROJECTION)
          TessellGL.glLoadIdentity
          TessellGL.glOrtho(0.0, @viewport_w.to_f64, @viewport_h.to_f64, 0.0, -1.0, 1.0)
          TessellGL.glMatrixMode(TessellGL::GL_MODELVIEW)
          TessellGL.glLoadIdentity

          TessellGL.glEnable(TessellGL::GL_TEXTURE_2D)
          TessellGL.glEnable(TessellGL::GL_BLEND)
          # Atlas uploaded as GL_INTENSITY coverage: texel=(I,I,I,I). Vertex color
          # (fg,1) is straight/non-premultiplied foreground, so modulation gives
          # fragment (fg*I, I). Premultiplied blend (GL_ONE, GL_ONE_MINUS_SRC_ALPHA):
          #   rgb   = src.rgb + dst.rgb*(1-src.a) = fg*I + bg*(1-I)
          #   alpha = src.a   + dst.a*(1-src.a)   = I + (1-I) = 1 (opaque canvas)
          # Using GL_SRC_ALPHA would multiply RGB by I again -> fg*I^2 (double coverage).
          TessellGL.glBlendFunc(TessellGL::GL_ONE, TessellGL::GL_ONE_MINUS_SRC_ALPHA)

          if dirty.nil?
            TessellGL.glDisable(TessellGL::GL_SCISSOR_TEST)
            TessellGL.glClearStencil(0)
            TessellGL.glClear(TessellGL::GL_COLOR_BUFFER_BIT | TessellGL::GL_STENCIL_BUFFER_BIT)
          else
            # Dirty/partial: do not clear full framebuffer here.
            # Each dirty rect is scissor-cleared in draw_batches_with_dirty so that
            # pixels outside dirty regions remain intact (double-buffer base preserved
            # when caller avoids SwapBuffers between frames).
            TessellGL.glEnable(TessellGL::GL_SCISSOR_TEST)
          end
        end

        def sync_atlas(atlas : Tessell::Text::GlyphAtlas) : Nil
          pc = atlas.page_count
          while @page_texture_ids_arr.size < pc
            id = 0_u32
            TessellGL.glGenTextures(1, pointerof(id))
            @page_texture_ids_arr << id
          end
          i = 0
          size = atlas.page_size
          while i < pc
            data = atlas.page_data(i)
            tex = @page_texture_ids_arr[i]
            TessellGL.glBindTexture(TessellGL::GL_TEXTURE_2D, tex)
            TessellGL.glPixelStorei(TessellGL::GL_UNPACK_ALIGNMENT, 1)
            TessellGL.glTexParameteri(TessellGL::GL_TEXTURE_2D, TessellGL::GL_TEXTURE_MIN_FILTER, TessellGL::GL_LINEAR.to_i32)
            TessellGL.glTexParameteri(TessellGL::GL_TEXTURE_2D, TessellGL::GL_TEXTURE_MAG_FILTER, TessellGL::GL_LINEAR.to_i32)
            TessellGL.glTexParameteri(TessellGL::GL_TEXTURE_2D, TessellGL::GL_TEXTURE_WRAP_S, TessellGL::GL_CLAMP.to_i32)
            TessellGL.glTexParameteri(TessellGL::GL_TEXTURE_2D, TessellGL::GL_TEXTURE_WRAP_T, TessellGL::GL_CLAMP.to_i32)
            # Upload R8 coverage as GL_INTENSITY so vertex color (rgba) tints text:
            # texel (I,I,I,I), modulate with vertex (R,G,B,A) -> (R*I,G*I,B*I,A*I).
            TessellGL.glTexImage2D(TessellGL::GL_TEXTURE_2D, 0, TessellGL::GL_INTENSITY.to_i32,
              size, size, 0,
              TessellGL::GL_LUMINANCE, TessellGL::GL_UNSIGNED_BYTE,
              data.to_unsafe.as(Void*))
            i += 1
          end
          # RGBA pages (color glyphs, premultiplied 4B/px): uploaded as-is. Color batches
          # draw with glColor4f(1,1,1,1) — the texel is already the final premultiplied
          # color, so vertex modulation must NOT multiply it again.
          rpc = atlas.rgba_page_count
          while @rgba_page_texture_ids_arr.size < rpc
            id = 0_u32
            TessellGL.glGenTextures(1, pointerof(id))
            @rgba_page_texture_ids_arr << id
          end
          i = 0
          while i < rpc
            data = atlas.rgba_page_data(i)
            tex = @rgba_page_texture_ids_arr[i]
            TessellGL.glBindTexture(TessellGL::GL_TEXTURE_2D, tex)
            TessellGL.glPixelStorei(TessellGL::GL_UNPACK_ALIGNMENT, 1)
            TessellGL.glTexParameteri(TessellGL::GL_TEXTURE_2D, TessellGL::GL_TEXTURE_MIN_FILTER, TessellGL::GL_LINEAR.to_i32)
            TessellGL.glTexParameteri(TessellGL::GL_TEXTURE_2D, TessellGL::GL_TEXTURE_MAG_FILTER, TessellGL::GL_LINEAR.to_i32)
            TessellGL.glTexParameteri(TessellGL::GL_TEXTURE_2D, TessellGL::GL_TEXTURE_WRAP_S, TessellGL::GL_CLAMP.to_i32)
            TessellGL.glTexParameteri(TessellGL::GL_TEXTURE_2D, TessellGL::GL_TEXTURE_WRAP_T, TessellGL::GL_CLAMP.to_i32)
            TessellGL.glTexImage2D(TessellGL::GL_TEXTURE_2D, 0, TessellGL::GL_RGBA.to_i32,
              size, size, 0,
              TessellGL::GL_RGBA, TessellGL::GL_UNSIGNED_BYTE,
              data.to_unsafe.as(Void*))
            i += 1
          end
        end

        def resolved_texture(page : Int32) : Int32
          return 0 if page < 0 || page >= @page_texture_ids_arr.size
          @page_texture_ids_arr[page].to_i32
        end

        # Color batches resolve RGBA pages; gray batches resolve R8 pages.
        def resolved_texture(page : Int32, color : Bool) : Int32
          if color
            return 0 if page < 0 || page >= @rgba_page_texture_ids_arr.size
            @rgba_page_texture_ids_arr[page].to_i32
          else
            resolved_texture(page)
          end
        end

        def draw_text(vertices : Array(Tessell::Render::Vertex), batches : Array(Tessell::Render::TextBatch), batch_count : Int32 = batches.size) : Int32
          if @dirty.nil?
            draw_batches_all(vertices, batches, batch_count)
          else
            rects = @dirty.not_nil!
            if rects.empty?
              @scissor_calls = 0
              @culled_quads = total_quads(batches, batch_count)
              @submitted_quads = 0
            else
              draw_batches_with_dirty(vertices, batches, batch_count, rects)
            end
          end
          @submitted_quads
        end

        # Draw Kit/core primitive commands. Colors are 0xRRGGBBAA, alpha-premultiplied
        # before submit because begin_frame uses (GL_ONE, GL_ONE_MINUS_SRC_ALPHA).
        # Text commands are skipped: text is submitted by draw_text with atlas batches.
        # Returns non-text commands submitted; clip is applied per command.
        def draw_draw_list(list : Tessell::Render::DrawList) : Int32
          submitted = 0
          TessellGL.glEnable(TessellGL::GL_BLEND)
          TessellGL.glBlendFunc(TessellGL::GL_ONE, TessellGL::GL_ONE_MINUS_SRC_ALPHA)
          TessellGL.glDisable(TessellGL::GL_TEXTURE_2D)
          i = 0
          while i < list.size
            cmd = list[i]
            apply_clip(cmd.clip)
            case cmd.kind
            when Tessell::Render::CmdKind::Rect
              fill_rect_cmd(cmd)
              submitted += 1
            when Tessell::Render::CmdKind::RoundRect
              fill_round_rect_cmd(cmd)
              submitted += 1
            when Tessell::Render::CmdKind::StrokeRect
              stroke_rect_cmd(cmd)
              submitted += 1
            when Tessell::Render::CmdKind::StrokeRoundRect
              stroke_round_rect_cmd(cmd)
              submitted += 1
            when Tessell::Render::CmdKind::Line
              stroke_line_cmd(cmd)
              submitted += 1
            when Tessell::Render::CmdKind::Text
              # Rendered via draw_text; keep the command list backend-agnostic.
            else
            end
            i += 1
          end
          TessellGL.glDisable(TessellGL::GL_SCISSOR_TEST)
          TessellGL.glLineWidth(1.0_f32)
          TessellGL.glEnable(TessellGL::GL_TEXTURE_2D)
          submitted
        end

        private def apply_clip(clip : Tessell::Rect?) : Nil
          if clip
            sx, sy, sw, sh = scissor_params(clip)
            TessellGL.glEnable(TessellGL::GL_SCISSOR_TEST)
            TessellGL.glScissor(sx, sy, sw, sh)
            @scissor_calls += 1
          else
            TessellGL.glDisable(TessellGL::GL_SCISSOR_TEST)
          end
        end

        private def fill_rect_cmd(cmd : Tessell::Render::DrawCmd) : Nil
          r = cmd.bounds
          TessellGL.glBegin(TessellGL::GL_QUADS)
          emit_cmd_color(cmd.color)
          TessellGL.glVertex2f(r.origin.x, r.origin.y)
          TessellGL.glVertex2f(r.max_x, r.origin.y)
          TessellGL.glVertex2f(r.max_x, r.max_y)
          TessellGL.glVertex2f(r.origin.x, r.max_y)
          TessellGL.glEnd
          @submitted_quads += 1
        end

        private def stroke_rect_cmd(cmd : Tessell::Render::DrawCmd) : Nil
          r = cmd.bounds
          TessellGL.glLineWidth(cmd.stroke_width > 0.0_f32 ? cmd.stroke_width : 1.0_f32)
          TessellGL.glBegin(TessellGL::GL_LINE_LOOP)
          emit_cmd_color(cmd.color)
          TessellGL.glVertex2f(r.origin.x, r.origin.y)
          TessellGL.glVertex2f(r.max_x, r.origin.y)
          TessellGL.glVertex2f(r.max_x, r.max_y)
          TessellGL.glVertex2f(r.origin.x, r.max_y)
          TessellGL.glEnd
        end

        private def fill_round_rect_cmd(cmd : Tessell::Render::DrawCmd) : Nil
          points = round_rect_points(cmd.bounds, cmd.radius)
          TessellGL.glBegin(TessellGL::GL_TRIANGLE_FAN)
          emit_cmd_color(cmd.color)
          center = cmd.bounds.origin.x + cmd.bounds.size.width / 2.0_f32
          center_y = cmd.bounds.origin.y + cmd.bounds.size.height / 2.0_f32
          TessellGL.glVertex2f(center, center_y)
          points.each { |p| TessellGL.glVertex2f(p.x, p.y) }
          first = points[0]
          TessellGL.glVertex2f(first.x, first.y)
          TessellGL.glEnd
          @submitted_quads += 1
        end

        private def stroke_round_rect_cmd(cmd : Tessell::Render::DrawCmd) : Nil
          points = round_rect_points(cmd.bounds, cmd.radius)
          TessellGL.glLineWidth(cmd.stroke_width > 0.0_f32 ? cmd.stroke_width : 1.0_f32)
          TessellGL.glBegin(TessellGL::GL_LINE_LOOP)
          emit_cmd_color(cmd.color)
          points.each { |p| TessellGL.glVertex2f(p.x, p.y) }
          TessellGL.glEnd
        end

        private def stroke_line_cmd(cmd : Tessell::Render::DrawCmd) : Nil
          TessellGL.glLineWidth(cmd.stroke_width > 0.0_f32 ? cmd.stroke_width : 1.0_f32)
          TessellGL.glBegin(TessellGL::GL_LINES)
          emit_cmd_color(cmd.color)
          TessellGL.glVertex2f(cmd.p1.x, cmd.p1.y)
          TessellGL.glVertex2f(cmd.p2.x, cmd.p2.y)
          TessellGL.glEnd
        end

        private def emit_cmd_color(color : UInt32) : Nil
          a = (color & 0xff).to_f32 / 255.0_f32
          r = ((color >> 24) & 0xff).to_f32 / 255.0_f32 * a
          g = ((color >> 16) & 0xff).to_f32 / 255.0_f32 * a
          b = ((color >> 8) & 0xff).to_f32 / 255.0_f32 * a
          TessellGL.glColor4f(r, g, b, a)
        end

        private def round_rect_points(rect : Tessell::Rect, radius : Float32) : Array(Tessell::Point)
          r = Math.min(radius, Math.min(rect.size.width, rect.size.height) / 2.0_f32)
          return [Tessell::Point.new(rect.origin.x, rect.origin.y),
                  Tessell::Point.new(rect.max_x, rect.origin.y),
                  Tessell::Point.new(rect.max_x, rect.max_y),
                  Tessell::Point.new(rect.origin.x, rect.max_y)] if r <= 0.0_f32
          points = [] of Tessell::Point
          segments = 6
          pi = Math::PI.to_f32
          add_arc(points, rect.origin.x + r, rect.origin.y + r, r, pi, pi * 1.5_f32, segments)
          add_arc(points, rect.max_x - r, rect.origin.y + r, r, pi * 1.5_f32, pi * 2.0_f32, segments)
          add_arc(points, rect.max_x - r, rect.max_y - r, r, 0.0_f32, pi * 0.5_f32, segments)
          add_arc(points, rect.origin.x + r, rect.max_y - r, r, pi * 0.5_f32, pi, segments)
          points
        end

        private def add_arc(points : Array(Tessell::Point), cx : Float32, cy : Float32,
                            radius : Float32, a0 : Float32, a1 : Float32,
                            segments : Int32) : Nil
          i = 0
          while i <= segments
            angle = a0 + (a1 - a0) * i.to_f32 / segments.to_f32
            points << Tessell::Point.new(cx + Math.cos(angle).to_f32 * radius,
              cy + Math.sin(angle).to_f32 * radius)
            i += 1
          end
        end

        private def total_quads(batches : Array(Tessell::Render::TextBatch), batch_count : Int32) : Int32
          sum = 0
          i = 0
          while i < batch_count
            b = batches[i]
            sum += b.count // 4 if b.count > 0
            i += 1
          end
          sum
        end

        private def draw_batches_all(vertices : Array(Tessell::Render::Vertex), batches : Array(Tessell::Render::TextBatch), batch_count : Int32) : Nil
          TessellGL.glDisable(TessellGL::GL_SCISSOR_TEST)
          @submitted_quads = 0
          @culled_quads = 0
          @scissor_calls = 0
          i = 0
          while i < batch_count
            b = batches[i]
            if b.count > 0
              if b.color
                tex = resolved_texture(b.page, true)
                TessellGL.glBindTexture(TessellGL::GL_TEXTURE_2D, tex.to_u32)
                # premultiplied RGBA texel is final color: submit unmodulated
                TessellGL.glColor4f(1.0_f32, 1.0_f32, 1.0_f32, 1.0_f32)
                TessellGL.glBegin(TessellGL::GL_QUADS)
                vi = b.start
                vend = b.start + b.count
                while vi < vend
                  v = vertices[vi]
                  emit_vertex_color(v)
                  vi += 1
                end
                TessellGL.glEnd
              else
                tex = resolved_texture(b.page)
                TessellGL.glBindTexture(TessellGL::GL_TEXTURE_2D, tex.to_u32)
                TessellGL.glBegin(TessellGL::GL_QUADS)
                vi = b.start
                vend = b.start + b.count
                while vi < vend
                  v = vertices[vi]
                  emit_vertex(v)
                  vi += 1
                end
                TessellGL.glEnd
              end
              @submitted_quads += b.count // 4
            end
            i += 1
          end
        end

        private def draw_batches_with_dirty(vertices : Array(Tessell::Render::Vertex), batches : Array(Tessell::Render::TextBatch), batch_count : Int32, rects : Array(Tessell::Rect)) : Nil
          @scissor_calls = 0
          @culled_quads = 0
          @submitted_quads = 0

          rcount = rects.size
          TessellGL.glEnable(TessellGL::GL_SCISSOR_TEST)

          # Pass 1: clear all dirty rects first (preserve outside pixels). Doing this
          # before any draw avoids a later rect's clear erasing boundary-spanning quads
          # already drawn into an earlier rect.
          ri = 0
          while ri < rcount
            r = rects[ri]
            sx, sy, sw, sh_i = scissor_params(r)
            TessellGL.glScissor(sx, sy, sw, sh_i)
            @scissor_calls += 1
            TessellGL.glClearStencil(0)
            TessellGL.glClear(TessellGL::GL_COLOR_BUFFER_BIT | TessellGL::GL_STENCIL_BUFFER_BIT)
            ri += 1
          end

          # Pass 2: for each rect, draw all quads intersecting it. Scissor clips to the
          # rect; quads spanning multiple dirty rects are redrawn per intersecting rect
          # so their pixels inside every cleared dirty region are restored.
          ri = 0
          while ri < rcount
            r = rects[ri]
            sx, sy, sw, sh_i = scissor_params(r)
            TessellGL.glScissor(sx, sy, sw, sh_i)

            bi = 0
            while bi < batch_count
              b = batches[bi]
              if b.count > 0
                if b.color
                  tex = resolved_texture(b.page, true)
                  TessellGL.glBindTexture(TessellGL::GL_TEXTURE_2D, tex.to_u32)
                  TessellGL.glColor4f(1.0_f32, 1.0_f32, 1.0_f32, 1.0_f32)
                  TessellGL.glBegin(TessellGL::GL_QUADS)
                  vi = b.start
                  vend = b.start + b.count
                  while vi < vend
                    v0 = vertices[vi]
                    v1 = vertices[vi + 1]
                    v2 = vertices[vi + 2]
                    v3 = vertices[vi + 3]
                    ql = min4(v0.x, v1.x, v2.x, v3.x)
                    qt = min4(v0.y, v1.y, v2.y, v3.y)
                    qr = max4(v0.x, v1.x, v2.x, v3.x)
                    qb = max4(v0.y, v1.y, v2.y, v3.y)
                    if quad_intersects_rect(ql, qt, qr, qb, r)
                      emit_vertex_color(v0)
                      emit_vertex_color(v1)
                      emit_vertex_color(v2)
                      emit_vertex_color(v3)
                      @submitted_quads += 1
                    end
                    vi += 4
                  end
                  TessellGL.glEnd
                else
                  tex = resolved_texture(b.page)
                  TessellGL.glBindTexture(TessellGL::GL_TEXTURE_2D, tex.to_u32)
                  TessellGL.glBegin(TessellGL::GL_QUADS)
                  vi = b.start
                  vend = b.start + b.count
                  while vi < vend
                    v0 = vertices[vi]
                    v1 = vertices[vi + 1]
                    v2 = vertices[vi + 2]
                    v3 = vertices[vi + 3]
                    ql = min4(v0.x, v1.x, v2.x, v3.x)
                    qt = min4(v0.y, v1.y, v2.y, v3.y)
                    qr = max4(v0.x, v1.x, v2.x, v3.x)
                    qb = max4(v0.y, v1.y, v2.y, v3.y)
                    if quad_intersects_rect(ql, qt, qr, qb, r)
                      emit_vertex(v0)
                      emit_vertex(v1)
                      emit_vertex(v2)
                      emit_vertex(v3)
                      @submitted_quads += 1
                    end
                    vi += 4
                  end
                  TessellGL.glEnd
                end
              end
              bi += 1
            end
            ri += 1
          end

          # culled = quads intersecting no dirty rect
          bi = 0
          while bi < batch_count
            b = batches[bi]
            if b.count > 0
              vi = b.start
              vend = b.start + b.count
              while vi < vend
                v0 = vertices[vi]
                v1 = vertices[vi + 1]
                v2 = vertices[vi + 2]
                v3 = vertices[vi + 3]
                ql = min4(v0.x, v1.x, v2.x, v3.x)
                qt = min4(v0.y, v1.y, v2.y, v3.y)
                qr = max4(v0.x, v1.x, v2.x, v3.x)
                qb = max4(v0.y, v1.y, v2.y, v3.y)
                unless intersects_any(ql, qt, qr, qb, rects)
                  @culled_quads += 1
                end
                vi += 4
              end
            end
            bi += 1
          end
        end

        private def scissor_params(r : Tessell::Rect) : {Int32, Int32, Int32, Int32}
          # OpenGL scissor uses window coords (origin bottom-left); ortho is y-down.
          sx = r.origin.x.floor.to_i
          sy_top = r.origin.y
          sh_f = r.size.height
          sy = (@viewport_h.to_f32 - (sy_top + sh_f)).floor.to_i
          sw = r.size.width.ceil.to_i
          sh_i = sh_f.ceil.to_i
          if sx < 0
            sw += sx
            sx = 0
          end
          if sy < 0
            sh_i += sy
            sy = 0
          end
          sw = @viewport_w - sx if sx + sw > @viewport_w
          sh_i = @viewport_h - sy if sy + sh_i > @viewport_h
          sw = 0 if sw < 0
          sh_i = 0 if sh_i < 0
          {sx, sy, sw, sh_i}
        end

        private def emit_vertex(v : Tessell::Render::Vertex) : Nil
          rgba = v.rgba
          TessellGL.glColor4f(((rgba >> 24) & 0xff).to_f32 / 255.0_f32,
            ((rgba >> 16) & 0xff).to_f32 / 255.0_f32,
            ((rgba >> 8) & 0xff).to_f32 / 255.0_f32,
            (rgba & 0xff).to_f32 / 255.0_f32)
          TessellGL.glTexCoord2f(v.u, v.v)
          TessellGL.glVertex2f(v.x, v.y)
        end

        # Color-page vertex: texture texel is already the final premultiplied RGBA,
        # so no glColor4f here (batch set glColor4f(1,1,1,1) before glBegin).
        private def emit_vertex_color(v : Tessell::Render::Vertex) : Nil
          TessellGL.glTexCoord2f(v.u, v.v)
          TessellGL.glVertex2f(v.x, v.y)
        end

        private def min4(a : Float32, b : Float32, c : Float32, d : Float32) : Float32
          m = a < b ? a : b
          m = c if c < m
          m = d if d < m
          m
        end

        private def max4(a : Float32, b : Float32, c : Float32, d : Float32) : Float32
          m = a > b ? a : b
          m = c if c > m
          m = d if d > m
          m
        end

        private def quad_intersects_rect(ql : Float32, qt : Float32, qr : Float32, qb : Float32, r : Tessell::Rect) : Bool
          rl = r.origin.x
          rt = r.origin.y
          rr = rl + r.size.width
          rb = rt + r.size.height
          !(qr <= rl || ql >= rr || qb <= rt || qt >= rb)
        end

        private def intersects_any(ql : Float32, qt : Float32, qr : Float32, qb : Float32, rects : Array(Tessell::Rect)) : Bool
          i = 0
          while i < rects.size
            return true if quad_intersects_rect(ql, qt, qr, qb, rects[i])
            i += 1
          end
          false
        end

        private def intersects_any_previous(ql : Float32, qt : Float32, qr : Float32, qb : Float32, rects : Array(Tessell::Rect), before_index : Int32) : Bool
          i = 0
          while i < before_index
            return true if quad_intersects_rect(ql, qt, qr, qb, rects[i])
            i += 1
          end
          false
        end

        def end_frame : Nil
          TessellGL.glDisable(TessellGL::GL_SCISSOR_TEST)
          TessellGL.glDisable(TessellGL::GL_BLEND)
          TessellGL.glDisable(TessellGL::GL_TEXTURE_2D)
          TessellGL.glFlush
          @frame_active = false
        end

        def close : Nil
          delete_textures
        end

        def delete_textures : Nil
          unless @page_texture_ids_arr.empty?
            TessellGL.glDeleteTextures(@page_texture_ids_arr.size, @page_texture_ids_arr.to_unsafe)
            @page_texture_ids_arr.clear
          end
          unless @rgba_page_texture_ids_arr.empty?
            TessellGL.glDeleteTextures(@rgba_page_texture_ids_arr.size, @rgba_page_texture_ids_arr.to_unsafe)
            @rgba_page_texture_ids_arr.clear
          end
        end

        def page_texture_ids : Array(Int32)
          ids = [] of Int32
          @page_texture_ids_arr.each { |id| ids << id.to_i32 }
          ids
        end

        def draw_polygon(points : Array(Tessell::Point), color : UInt32,
                         even_odd : Bool = true) : Bool
          n = points.size
          return false if n < 3
          # Honest capability reporting: only even-odd stencil/cover is implemented.
          # nonzero-rule (GL_INCR/GL_DECR winding) is NOT implemented; callers
          # asking for it get false, not a silently wrong fill.
          return false unless even_odd
          # No stencil buffer in the chosen pixel format -> cannot do stencil/cover.
          return false if @stencil_bits <= 0
          # Stencil/cover (even-odd): fill stencil with triangle fan parity,
          # then cover bounded region where stencil != 0.
          TessellGL.glDisable(TessellGL::GL_TEXTURE_2D)
          was_scissor = !@dirty.nil?
          TessellGL.glDisable(TessellGL::GL_SCISSOR_TEST) if was_scissor

          min_x = points[0].x
          max_x = points[0].x
          min_y = points[0].y
          max_y = points[0].y
          i = 1
          while i < n
            p = points.unsafe_fetch(i)
            min_x = p.x if p.x < min_x
            max_x = p.x if p.x > max_x
            min_y = p.y if p.y < min_y
            max_y = p.y if p.y > max_y
            i += 1
          end

          TessellGL.glEnable(TessellGL::GL_STENCIL_TEST)
          TessellGL.glClearStencil(0)
          TessellGL.glClear(TessellGL::GL_STENCIL_BUFFER_BIT)
          TessellGL.glColorMask(0_u8, 0_u8, 0_u8, 0_u8)
          TessellGL.glStencilFunc(TessellGL::GL_ALWAYS, 0, 0xFF_u32)
          TessellGL.glStencilOp(TessellGL::GL_KEEP, TessellGL::GL_KEEP, TessellGL::GL_INVERT)
          TessellGL.glStencilMask(0xFF_u32)

          TessellGL.glBegin(TessellGL::GL_TRIANGLE_FAN)
          i = 0
          while i < n
            p = points.unsafe_fetch(i)
            TessellGL.glVertex2f(p.x, p.y)
            i += 1
          end
          TessellGL.glEnd

          TessellGL.glColorMask(1_u8, 1_u8, 1_u8, 1_u8)
          TessellGL.glStencilFunc(TessellGL::GL_NOTEQUAL, 0, 0xFF_u32)
          TessellGL.glStencilOp(TessellGL::GL_KEEP, TessellGL::GL_KEEP, TessellGL::GL_KEEP)
          TessellGL.glStencilMask(0xFF_u32)

          r = ((color >> 24) & 0xFF).to_f32 / 255.0_f32
          g = ((color >> 16) & 0xFF).to_f32 / 255.0_f32
          b = ((color >> 8) & 0xFF).to_f32 / 255.0_f32
          a = (color & 0xFF).to_f32 / 255.0_f32
          TessellGL.glColor4f(r, g, b, a)
          TessellGL.glBegin(TessellGL::GL_QUADS)
          TessellGL.glVertex2f(min_x, min_y)
          TessellGL.glVertex2f(max_x, min_y)
          TessellGL.glVertex2f(max_x, max_y)
          TessellGL.glVertex2f(min_x, max_y)
          TessellGL.glEnd

          TessellGL.glDisable(TessellGL::GL_STENCIL_TEST)
          TessellGL.glStencilMask(0xFF_u32)
          TessellGL.glColorMask(1_u8, 1_u8, 1_u8, 1_u8)
          TessellGL.glEnable(TessellGL::GL_TEXTURE_2D)
          TessellGL.glEnable(TessellGL::GL_SCISSOR_TEST) if was_scissor

          @stencil_fills += 1
          true
        end

        def stats : Tessell::Render::FrameStats
          Tessell::Render::FrameStats.new(@submitted_quads, @scissor_calls, @culled_quads, @stencil_fills)
        end
      end
    end
  end
end
