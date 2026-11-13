# Tessell::Render::Dpi (M3-WP5)
# 纯函数 DPI 缩放；不调 FFI。

module Tessell
  module Render
    module Dpi
      def self.scale_for(dpi : UInt32) : Float32
        s = dpi.to_f32 / 96.0f32
        s = 0.5f32 if s < 0.5f32
        s = 4.0f32 if s > 4.0f32
        s
      end

      def self.size_px(point_size : Float32, scale : Float32) : Float32
        v = (point_size * scale).round.to_f32
        v = 1.0f32 if v < 1.0f32
        v
      end

      def self.logical_to_device(v : Float32, scale : Float32) : Float32
        v * scale
      end
    end
  end
end
