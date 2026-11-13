# Tessell::Render::Theme (M3-WP5)
# 值类型主题 token：bg/fg/accent/muted/border/selection，RGBA (0xRRGGBBAA)。
# 纯数据 + 无分配通道拆解；不触 atlas/纹理。

module Tessell
  module Render
    struct Theme
      getter bg : UInt32
      getter fg : UInt32
      getter accent : UInt32
      getter muted : UInt32
      getter border : UInt32
      getter selection : UInt32

      def initialize(@bg : UInt32, @fg : UInt32, @accent : UInt32,
                     @muted : UInt32, @border : UInt32, @selection : UInt32)
      end

      # 通道拆解（0xRRGGBBAA → 0..255）。
      def self.rb(c : UInt32) : UInt8; ((c >> 24) & 0xff).to_u8; end
      def self.gb(c : UInt32) : UInt8; ((c >> 16) & 0xff).to_u8; end
      def self.bb(c : UInt32) : UInt8; ((c >> 8) & 0xff).to_u8; end
      def self.ab(c : UInt32) : UInt8; (c & 0xff).to_u8; end

      # 归一化通道（0..1，任务要求的静态取通道方法）。
      def self.r(c : UInt32) : Float32; self.rb(c).to_f32 / 255.0f32; end
      def self.g(c : UInt32) : Float32; self.gb(c).to_f32 / 255.0f32; end
      def self.b(c : UInt32) : Float32; self.bb(c).to_f32 / 255.0f32; end
      def self.a(c : UInt32) : Float32; self.ab(c).to_f32 / 255.0f32; end

      def self.light : Theme
        Theme.new(0xffffffff_u32, 0x000000ff_u32, 0x2f6fedff_u32,
                  0x8a8a8aff_u32, 0xd0d0d0ff_u32, 0xbcd4ffff_u32)
      end

      def self.dark : Theme
        Theme.new(0x1e1e1eff_u32, 0xe0e0e0ff_u32, 0x4c8dffff_u32,
                  0x9a9a9aff_u32, 0x3a3a3aff_u32, 0x2b4a7dff_u32)
      end
    end
  end
end
