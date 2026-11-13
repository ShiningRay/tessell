# Tessell::Render::GL::GLBackend (M3-WP1)
# GL 1.1 backend: texture ownership, scissor by dirty rects, quad culling.

require "../backend"
require "../text_renderer"
require "../../geometry"
require "../../text/glyph_atlas"

@[Link("opengl32")]
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

  GL_COLOR_BUFFER_BIT = 0x00004000_u32
  GL_TRIANGLES        = 0x0004_u32
  GL_QUADS            = 0x0007_u32

  GL_TEXTURE_2D   = 0x0DE1_u32
  GL_BLEND        = 0x0BE2_u32
  GL_ALPHA_TEST   = 0x0BC0_u32
  GL_SCISSOR_TEST = 0x0C11_u32

  GL_RGBA          = 0x1908_u32
  GL_ALPHA         = 0x1906_u32
  GL_UNSIGNED_BYTE = 0x1401_u32

  GL_UNPACK_ALIGNMENT = 0x0CF5_u32
  GL_PACK_ALIGNMENT   = 0x0D05_u32

  GL_TEXTURE_MIN_FILTER = 0x2801_u32
  GL_TEXTURE_MAG_FILTER = 0x2800_u32
  GL_LINEAR             = 0x2601_u32
  GL_NEAREST            = 0x2600_u32
  GL_TEXTURE_WRAP_S     = 0x2802_u32
  GL_TEXTURE_WRAP_T     = 0x2803_u32
  GL_CLAMP              = 0x2900_u32

  GL_SRC_ALPHA           = 0x0302_u32
  GL_ONE_MINUS_SRC_ALPHA = 0x0303_u32
  GL_ONE                 = 1_u32
  GL_ZERO                = 0_u32

  GL_PROJECTION = 0x1701_u32
  GL_MODELVIEW  = 0x1700_u32

  fun glViewport(x : GLint, y : GLint, width : GLsizei, height : GLsizei) : Void
  fun glScissor(x : GLint, y : GLint, width : GLsizei, height : GLsizei) : Void
  fun glClearColor(red : GLfloat, green : GLfloat, blue : GLfloat, alpha : GLfloat) : Void
  fun glClear(mask : GLbitfield) : Void
  fun glFlush : Void
  fun glFinish : Void
  fun glGetError : GLenum

  fun glEnable(cap : GLenum) : Void
  fun glDisable(cap : GLenum) : Void
  fun glBlendFunc(sfactor : GLenum, dfactor : GLenum) : Void
  fun glColor4f(red : GLfloat, green : GLfloat, blue : GLfloat, alpha : GLfloat) : Void

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
        @viewport_w : Int32
        @viewport_h : Int32
        @dirty : Array(Tessell::Rect)?
        @scissor_calls : Int32
        @culled_quads : Int32
        @submitted_quads : Int32
        @bg_r : Float32
        @bg_g : Float32
        @bg_b : Float32
        @bg_a : Float32
        @frame_active : Bool

        def initialize
          @page_texture_ids_arr = [] of UInt32
          @viewport_w = 0
          @viewport_h = 0
          @dirty = nil
          @scissor_calls = 0
          @culled_quads = 0
          @submitted_quads = 0
          @bg_r = 1.0_f32
          @bg_g = 1.0_f32
          @bg_b = 1.0_f32
          @bg_a = 1.0_f32
          @frame_active = false
        end

        def init(width : Int32, height : Int32) : Nil
          @viewport_w = width
          @viewport_h = height
        end

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

        def begin_frame(dirty : Array(Tessell::Rect)? = nil) : Nil
          @dirty = dirty
          @scissor_calls = 0
          @culled_quads = 0
          @submitted_quads = 0
          @frame_active = true

          TessellGL.glViewport(0, 0, @viewport_w, @viewport_h)
          TessellGL.glClearColor(@bg_r, @bg_g, @bg_b, @bg_a)

          TessellGL.glMatrixMode(TessellGL::GL_PROJECTION)
          TessellGL.glLoadIdentity
          TessellGL.glOrtho(0.0, @viewport_w.to_f64, @viewport_h.to_f64, 0.0, -1.0, 1.0)
          TessellGL.glMatrixMode(TessellGL::GL_MODELVIEW)
          TessellGL.glLoadIdentity

          TessellGL.glEnable(TessellGL::GL_TEXTURE_2D)
          TessellGL.glEnable(TessellGL::GL_BLEND)
          TessellGL.glBlendFunc(TessellGL::GL_SRC_ALPHA, TessellGL::GL_ONE_MINUS_SRC_ALPHA)
          TessellGL.glColor4f(0.0_f32, 0.0_f32, 0.0_f32, 1.0_f32)

          if dirty.nil?
            TessellGL.glDisable(TessellGL::GL_SCISSOR_TEST)
            TessellGL.glClear(TessellGL::GL_COLOR_BUFFER_BIT)
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
            TessellGL.glTexImage2D(TessellGL::GL_TEXTURE_2D, 0, TessellGL::GL_ALPHA.to_i32,
                                   size, size, 0,
                                   TessellGL::GL_ALPHA, TessellGL::GL_UNSIGNED_BYTE,
                                   data.to_unsafe.as(Void*))
            i += 1
          end
        end

        def resolved_texture(page : Int32) : Int32
          return 0 if page < 0 || page >= @page_texture_ids_arr.size
          @page_texture_ids_arr[page].to_i32
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
              tex = resolved_texture(b.page)
              TessellGL.glBindTexture(TessellGL::GL_TEXTURE_2D, tex.to_u32)
              TessellGL.glBegin(TessellGL::GL_QUADS)
              vi = b.start
              vend = b.start + b.count
              while vi < vend
                v = vertices[vi]
                TessellGL.glTexCoord2f(v.u, v.v)
                TessellGL.glVertex2f(v.x, v.y)
                vi += 1
              end
              TessellGL.glEnd
              @submitted_quads += b.count // 4
            end
            i += 1
          end
        end

        private def draw_batches_with_dirty(vertices : Array(Tessell::Render::Vertex), batches : Array(Tessell::Render::TextBatch), batch_count : Int32, rects : Array(Tessell::Rect)) : Nil
          @scissor_calls = 0
          @culled_quads = 0
          @submitted_quads = 0

          ri = 0
          rcount = rects.size
          TessellGL.glEnable(TessellGL::GL_SCISSOR_TEST)
          while ri < rcount
            r = rects[ri]
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
            TessellGL.glScissor(sx, sy, sw, sh_i)
            @scissor_calls += 1
            # Clear only this dirty rect (preserve pixels outside dirty regions).
            TessellGL.glClear(TessellGL::GL_COLOR_BUFFER_BIT)

            bi = 0
            while bi < batch_count
              b = batches[bi]
              if b.count > 0
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
                    unless intersects_any_previous(ql, qt, qr, qb, rects, ri)
                      TessellGL.glTexCoord2f(v0.u, v0.v); TessellGL.glVertex2f(v0.x, v0.y)
                      TessellGL.glTexCoord2f(v1.u, v1.v); TessellGL.glVertex2f(v1.x, v1.y)
                      TessellGL.glTexCoord2f(v2.u, v2.v); TessellGL.glVertex2f(v2.x, v2.y)
                      TessellGL.glTexCoord2f(v3.u, v3.v); TessellGL.glVertex2f(v3.x, v3.y)
                      @submitted_quads += 1
                    end
                  end
                  vi += 4
                end
                TessellGL.glEnd
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
          return if @page_texture_ids_arr.empty?
          TessellGL.glDeleteTextures(@page_texture_ids_arr.size, @page_texture_ids_arr.to_unsafe)
          @page_texture_ids_arr.clear
        end

        def page_texture_ids : Array(Int32)
          ids = [] of Int32
          @page_texture_ids_arr.each { |id| ids << id.to_i32 }
          ids
        end

        def stats : Tessell::Render::FrameStats
          Tessell::Render::FrameStats.new(@submitted_quads, @scissor_calls, @culled_quads)
        end
      end
    end
  end
end