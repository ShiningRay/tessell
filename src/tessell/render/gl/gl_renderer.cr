# Tessell::Render::GL::GlRenderer (M2-WP2d 阶段 2)
# 纯 FFI OpenGL 文本绘制（默认 GL 1.1 兼容路径，无 shader）。
#
# 路径选择：R8 字形位图页上传为 GL_ALPHA + 固定管线调制 (glTexEnv MODULATE, 默认白色顶点)
# 使用 glTexCoord2f/glVertex2f 立即模式四边形提交。理由：GL 1.1 在 Windows opengl32 上
# 普遍可用（含软件/兼容实现），无需扩展加载即可验证 R8 atlas 上屏；GL_ALPHA 直接承载
# 覆盖度/alpha 蒙版，配合混合输出可见文本。后续可升级为纹理数组/着色器路径，但不在本阶段。
#
# 关键约束：上传前必须 glPixelStorei(GL_UNPACK_ALIGNMENT, 1)，因为 R8 页紧密打包（行宽=page_size，
# 非 4 字节对齐时默认 UNPACK_ALIGNMENT=4 会读错行）。本文件在每次 tex image/upload 前显式设置。
#
# 禁改 src/tessell/text/*；不依赖扩展加载器（WGL/GL 扩展）——仅 GL 1.1 核心符号。

require "../text_renderer"
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

  GL_TEXTURE_2D       = 0x0DE1_u32
  GL_BLEND            = 0x0BE2_u32
  GL_ALPHA_TEST       = 0x0BC0_u32

  GL_RGBA             = 0x1908_u32
  GL_ALPHA            = 0x1906_u32
  GL_UNSIGNED_BYTE    = 0x1401_u32

  GL_UNPACK_ALIGNMENT = 0x0CF5_u32
  GL_PACK_ALIGNMENT   = 0x0D05_u32

  GL_TEXTURE_MIN_FILTER = 0x2801_u32
  GL_TEXTURE_MAG_FILTER = 0x2800_u32
  GL_LINEAR             = 0x2601_u32
  GL_NEAREST            = 0x2600_u32
  GL_TEXTURE_WRAP_S     = 0x2802_u32
  GL_TEXTURE_WRAP_T     = 0x2803_u32
  GL_CLAMP              = 0x2900_u32
  GL_CLAMP_TO_EDGE      = 0x812F_u32 # core in 1.2, but safe to try; fallback clamp logic not needed here

  GL_SRC_ALPHA           = 0x0302_u32
  GL_ONE_MINUS_SRC_ALPHA = 0x0303_u32
  GL_ONE                 = 1_u32
  GL_ZERO                = 0_u32

  GL_PROJECTION = 0x1701_u32
  GL_MODELVIEW  = 0x1700_u32

  fun glViewport(x : GLint, y : GLint, width : GLsizei, height : GLsizei) : Void
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
      class GlRenderer
        getter page_texture_ids : Array(Int32)

        @atlas : Text::GlyphAtlas
        @page_texture_ids_arr : Array(UInt32)

        def initialize(@atlas : Text::GlyphAtlas)
          @page_texture_ids_arr = [] of UInt32
          @page_texture_ids = [] of Int32
        end

        # 同步并上传图集页纹理（R8 -> GL_ALPHA）。每次上传前强制 glPixelStorei(GL_UNPACK_ALIGNMENT,1)。
        # 返回 page_texture_ids（按 page index 索引）。
        def sync_atlas_textures : Array(Int32)
          pc = @atlas.page_count
          # grow texture ids if needed
          while @page_texture_ids_arr.size < pc
            id = 0_u32
            TessellGL.glGenTextures(1, pointerof(id))
            @page_texture_ids_arr << id
            @page_texture_ids << id.to_i32
          end
          # upload each page
          i = 0
          size = @atlas.page_size
          while i < pc
            data = @atlas.page_data(i)
            tex = @page_texture_ids_arr[i]
            TessellGL.glBindTexture(TessellGL::GL_TEXTURE_2D, tex)
            # CRITICAL: R8 pages are tightly packed (no row padding). Default UNPACK_ALIGNMENT=4
            # would misread rows when page_size % 4 != 0; force 1 for correctness.
            TessellGL.glPixelStorei(TessellGL::GL_UNPACK_ALIGNMENT, 1)
            TessellGL.glTexParameteri(TessellGL::GL_TEXTURE_2D, TessellGL::GL_TEXTURE_MIN_FILTER, TessellGL::GL_LINEAR.to_i32)
            TessellGL.glTexParameteri(TessellGL::GL_TEXTURE_2D, TessellGL::GL_TEXTURE_MAG_FILTER, TessellGL::GL_LINEAR.to_i32)
            # GL_CLAMP (1.1) is sufficient for atlas edge behavior here
            TessellGL.glTexParameteri(TessellGL::GL_TEXTURE_2D, TessellGL::GL_TEXTURE_WRAP_S, TessellGL::GL_CLAMP.to_i32)
            TessellGL.glTexParameteri(TessellGL::GL_TEXTURE_2D, TessellGL::GL_TEXTURE_WRAP_T, TessellGL::GL_CLAMP.to_i32)
            TessellGL.glTexImage2D(TessellGL::GL_TEXTURE_2D, 0, TessellGL::GL_ALPHA.to_i32,
                                   size, size, 0,
                                   TessellGL::GL_ALPHA, TessellGL::GL_UNSIGNED_BYTE,
                                   data.to_unsafe.as(Void*))
            i += 1
          end
          @page_texture_ids
        end

        # 配置 2D 正交投影（屏幕像素，y-down：top=0,bottom=h）与文本混合状态
        def begin_frame(viewport_w : Int32, viewport_h : Int32,
                        bg_r : Float32 = 1.0_f32, bg_g : Float32 = 1.0_f32, bg_b : Float32 = 1.0_f32, bg_a : Float32 = 1.0_f32) : Nil
          TessellGL.glViewport(0, 0, viewport_w, viewport_h)
          TessellGL.glClearColor(bg_r, bg_g, bg_b, bg_a)
          TessellGL.glClear(TessellGL::GL_COLOR_BUFFER_BIT)

          TessellGL.glMatrixMode(TessellGL::GL_PROJECTION)
          TessellGL.glLoadIdentity
          # y-down: origin top-left
          TessellGL.glOrtho(0.0, viewport_w.to_f64, viewport_h.to_f64, 0.0, -1.0, 1.0)
          TessellGL.glMatrixMode(TessellGL::GL_MODELVIEW)
          TessellGL.glLoadIdentity

          TessellGL.glEnable(TessellGL::GL_TEXTURE_2D)
          TessellGL.glEnable(TessellGL::GL_BLEND)
          TessellGL.glBlendFunc(TessellGL::GL_SRC_ALPHA, TessellGL::GL_ONE_MINUS_SRC_ALPHA)
          TessellGL.glColor4f(0.0_f32, 0.0_f32, 0.0_f32, 1.0_f32) # text color: black
        end

        # 绘制 TextRenderer 产出的批次（立即模式 GL_QUADS）
        def draw_text(renderer : TextRenderer) : Nil
          bc = renderer.batch_count
          bi = 0
          verts = renderer.vertices
          batches = renderer.batch_runs
          while bi < bc
            b = batches[bi]
            next if b.count <= 0
            TessellGL.glBindTexture(TessellGL::GL_TEXTURE_2D, b.texture.to_u32)
            TessellGL.glBegin(TessellGL::GL_QUADS)
            vi = b.start
            vend = b.start + b.count
            while vi < vend
              v = verts[vi]
              TessellGL.glTexCoord2f(v.u, v.v)
              TessellGL.glVertex2f(v.x, v.y)
              vi += 1
            end
            TessellGL.glEnd
            bi += 1
          end
        end

        def end_frame : Nil
          TessellGL.glDisable(TessellGL::GL_BLEND)
          TessellGL.glDisable(TessellGL::GL_TEXTURE_2D)
          TessellGL.glFlush
        end

        def delete_textures : Nil
          return if @page_texture_ids_arr.empty?
          TessellGL.glDeleteTextures(@page_texture_ids_arr.size, @page_texture_ids_arr.to_unsafe)
          @page_texture_ids_arr.clear
          @page_texture_ids.clear
        end
      end
    end
  end
end
