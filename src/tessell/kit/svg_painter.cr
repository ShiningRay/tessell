# Tessell::Kit::SvgPainter — 无窗口 SVG 预览（K5）
#
# 将 Kit::Painter 命令输出为静态 SVG，用于文档预览与人工检查。
# 不是截图替代品：文本由浏览器字体渲染，不证明核心 HarfBuzz/FreeType 上屏。
# 裁切通过 SVG clipPath 表达。

require "html"
require "./painter"

module Tessell
  module Kit
    class SvgPainter < Painter
      getter width : Int32
      getter height : Int32
      getter elements : Int32
      property background : UInt32

      @body : String::Builder
      @defs : String::Builder
      @clips : Array(Rect?)
      @clip_seq : Int32
      @group_depth : Int32

      def initialize(@width : Int32, @height : Int32)
        @body = String::Builder.new
        @defs = String::Builder.new
        @clips = [] of Rect?
        @clip_seq = 0
        @group_depth = 0
        @elements = 0
        @background = 0xf6f7f9ff_u32
      end

      def fill_rect(rect : Rect, color : UInt32) : Nil
        emit %(<rect x="#{f(rect.origin.x)}" y="#{f(rect.origin.y)}" width="#{f(rect.size.width)}" height="#{f(rect.size.height)}" fill="#{css(color)}"/>)
      end

      def stroke_rect(rect : Rect, color : UInt32, width : Float32 = 1.0_f32) : Nil
        emit %(<rect x="#{f(rect.origin.x)}" y="#{f(rect.origin.y)}" width="#{f(rect.size.width)}" height="#{f(rect.size.height)}" fill="none" stroke="#{css(color)}" stroke-width="#{f(width)}"/>)
      end

      def fill_round_rect(rect : Rect, radius : Float32, color : UInt32) : Nil
        emit %(<rect x="#{f(rect.origin.x)}" y="#{f(rect.origin.y)}" width="#{f(rect.size.width)}" height="#{f(rect.size.height)}" rx="#{f(radius)}" fill="#{css(color)}"/>)
      end

      def stroke_round_rect(rect : Rect, radius : Float32, color : UInt32, width : Float32 = 1.0_f32) : Nil
        emit %(<rect x="#{f(rect.origin.x)}" y="#{f(rect.origin.y)}" width="#{f(rect.size.width)}" height="#{f(rect.size.height)}" rx="#{f(radius)}" fill="none" stroke="#{css(color)}" stroke-width="#{f(width)}"/>)
      end

      def line(x1 : Float32, y1 : Float32, x2 : Float32, y2 : Float32,
               color : UInt32, width : Float32 = 1.0_f32) : Nil
        emit %(<line x1="#{f(x1)}" y1="#{f(y1)}" x2="#{f(x2)}" y2="#{f(y2)}" stroke="#{css(color)}" stroke-width="#{f(width)}" stroke-linecap="round"/>)
      end

      def text(x : Float32, baseline_y : Float32, text : String,
               color : UInt32, size : Float32) : Nil
        emit %(<text x="#{f(x)}" y="#{f(baseline_y)}" font-family="-apple-system, BlinkMacSystemFont, 'Segoe UI', 'Hiragino Sans GB', 'Microsoft YaHei', sans-serif" font-size="#{f(size)}" fill="#{css(color)}">#{HTML.escape(text)}</text>)
      end

      def push_clip(rect : Rect) : Nil
        effective = if parent = @clips.last?
                      Geometry.intersect(parent, rect)
                    else
                      rect
                    end
        @clips << effective
        id = "clip#{@clip_seq}"
        @clip_seq += 1
        @defs << %(<clipPath id="#{id}"><rect x="#{f(effective.origin.x)}" y="#{f(effective.origin.y)}" width="#{f(effective.size.width)}" height="#{f(effective.size.height)}"/></clipPath>)
        @body << %(<g clip-path="url(##{id})">)
        @group_depth += 1
      end

      def pop_clip : Nil
        return if @clips.empty?
        @clips.pop
        @body << "</g>"
        @group_depth -= 1
      end

      def clip_depth : Int32
        @clips.size
      end

      def svg : String
        <<-SVG
<svg xmlns="http://www.w3.org/2000/svg" width="#{@width}" height="#{@height}" viewBox="0 0 #{@width} #{@height}">
<defs>#{@defs.to_s}</defs>
<rect width="100%" height="100%" fill="#{css(@background)}"/>
#{@body.to_s}
</svg>
SVG
      end

      private def emit(element : String) : Nil
        @body << element << "\n"
        @elements += 1
      end

      private def css(color : UInt32) : String
        r = ((color >> 24) & 0xff).to_u8
        g = ((color >> 16) & 0xff).to_u8
        b = ((color >> 8) & 0xff).to_u8
        a = (color & 0xff).to_u8
        "rgba(#{r},#{g},#{b},#{(a.to_f32 / 255.0_f32).round(3)})"
      end

      private def f(value : Float32) : String
        value.round(2).to_s
      end
    end
  end
end
