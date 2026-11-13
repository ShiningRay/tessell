# Tessell::Render::GL::GlRenderer — M3-WP1 thin adapter delegating to GLBackend.
# 保留旧 API 以兼容既有示例/调用点：sync_atlas_textures/begin_frame(w,h,bg...)/draw_text(renderer)/end_frame/delete_textures/page_texture_ids。

require "./gl_backend"

module Tessell
  module Render
    module GL
      class GlRenderer
        getter page_texture_ids : Array(Int32)

        @atlas : Text::GlyphAtlas
        @backend : GLBackend
        @initialized : Bool

        def initialize(@atlas : Text::GlyphAtlas)
          @backend = GLBackend.new
          @page_texture_ids = [] of Int32
          @initialized = false
        end

        # 同步并上传图集页纹理（R8 -> GL_ALPHA）。纹理由后端占有。
        # 返回 page_texture_ids（按 page index 索引）供旧调用点兼容（不应再用于提交）。
        def sync_atlas_textures : Array(Int32)
          @backend.sync_atlas(@atlas)
          @page_texture_ids = @backend.page_texture_ids
          @page_texture_ids
        end

        # 配置 2D 正交投影（屏幕像素，y-down：top=0,bottom=h）与文本混合状态，整帧清屏。
        def begin_frame(viewport_w : Int32, viewport_h : Int32,
                        bg_r : Float32 = 1.0_f32, bg_g : Float32 = 1.0_f32, bg_b : Float32 = 1.0_f32, bg_a : Float32 = 1.0_f32) : Nil
          unless @initialized
            @backend.init(viewport_w, viewport_h)
            @initialized = true
          end
          @backend.resize(viewport_w, viewport_h)
          @backend.set_clear_color(bg_r, bg_g, bg_b, bg_a)
          @backend.begin_frame(nil)
        end

        # 绘制 TextRenderer 产出的批次（整帧，无脏区裁剪）。
        def draw_text(renderer : TextRenderer) : Nil
          @backend.draw_text(renderer.vertices, renderer.batch_runs, renderer.batch_count)
        end

        def end_frame : Nil
          @backend.end_frame
        end

        def delete_textures : Nil
          @backend.close
          @page_texture_ids.clear
        end
      end
    end
  end
end
