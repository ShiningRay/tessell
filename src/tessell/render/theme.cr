# Tessell::Render::Theme (M3-WP5, issue #8 扩展语义 token)
# 值类型主题 token，RGBA (0xRRGGBBAA)。纯数据 + 无分配通道拆解；不触 atlas/纹理。
#
# 基础六元（既有）：bg/fg/accent/muted/border/selection。
# 扩展语义 token（issue #8，行情/面板类应用不再自建平行 Palette）：
#   panel / panel_alt / card  —— 面板与卡片底色两档
#   grid / divider            —— 1px 网格线与分隔线
#   up / down / up_soft / down_soft —— 涨跌语义（预设为 A 股口径：涨红跌绿，
#                                       应用可整体替换 token）
#   hover / focus_ring        —— 悬停高亮与焦点环
#   warning / danger / success —— 状态色
#   faint                     —— 更弱一级的次文本（fg > muted > faint）
#
# 构造：6 参 initialize 从基础六元推导扩展 token（既有调用点零改动，质量
# 一般）；自定义主题建议用 light/dark 预设整体替换，或以全参 initialize
# 显式给出所有 token。颜色工具 mix/with_alpha 供派生使用。

module Tessell
  module Render
    struct Theme
      getter bg : UInt32
      getter fg : UInt32
      getter accent : UInt32
      getter muted : UInt32
      getter border : UInt32
      getter selection : UInt32

      getter panel : UInt32
      getter panel_alt : UInt32
      getter card : UInt32
      getter grid : UInt32
      getter divider : UInt32
      getter up : UInt32
      getter down : UInt32
      getter up_soft : UInt32
      getter down_soft : UInt32
      getter hover : UInt32
      getter focus_ring : UInt32
      getter warning : UInt32
      getter danger : UInt32
      getter success : UInt32
      getter faint : UInt32

      # 全参构造：显式给出所有 token。
      def initialize(@bg : UInt32, @fg : UInt32, @accent : UInt32,
                     @muted : UInt32, @border : UInt32, @selection : UInt32,
                     @panel : UInt32, @panel_alt : UInt32, @card : UInt32,
                     @grid : UInt32, @divider : UInt32,
                     @up : UInt32, @down : UInt32,
                     @up_soft : UInt32, @down_soft : UInt32,
                     @hover : UInt32, @focus_ring : UInt32,
                     @warning : UInt32, @danger : UInt32, @success : UInt32,
                     @faint : UInt32)
      end

      # 兼容构造（M3-WP5 口径）：只给基础六元，扩展 token 按规则推导。
      def initialize(@bg : UInt32, @fg : UInt32, @accent : UInt32,
                     @muted : UInt32, @border : UInt32, @selection : UInt32)
        @panel = Theme.mix(@bg, @fg, 0.045_f32)
        @panel_alt = Theme.mix(@bg, @fg, 0.09_f32)
        @card = Theme.mix(@bg, @fg, 0.02_f32)
        @grid = Theme.mix(@border, @bg, 0.35_f32)
        @divider = @border
        @up = Theme.mix(0xd64545ff_u32, @fg, 0.25_f32)
        @down = Theme.mix(0x2e9e5bff_u32, @fg, 0.25_f32)
        @up_soft = Theme.with_alpha(@up, 0x66_u8)
        @down_soft = Theme.with_alpha(@down, 0x66_u8)
        @hover = Theme.with_alpha(Theme.mix(@fg, @bg, 0.5_f32), 0x14_u8)
        @focus_ring = @accent
        @warning = Theme.mix(0xe0a13cff_u32, @fg, 0.25_f32)
        @danger = @up
        @success = @down
        @faint = Theme.mix(@fg, @bg, 0.55_f32)
      end

      # 线性插值（rgb 插值，alpha 取 a 的 alpha）。
      def self.mix(a : UInt32, b : UInt32, t : Float32) : UInt32
        t = t.clamp(0.0_f32, 1.0_f32)
        ra = rb(a).to_f32; ga = gb(a).to_f32; ba = bb(a).to_f32
        rb_ = rb(b).to_f32; gb_ = gb(b).to_f32; bb_ = bb(b).to_f32
        r = (ra + (rb_ - ra) * t).round.to_u8
        g = (ga + (gb_ - ga) * t).round.to_u8
        b = (ba + (bb_ - ba) * t).round.to_u8
        (r.to_u32 << 24) | (g.to_u32 << 16) | (b.to_u32 << 8) | ab(a).to_u32
      end

      # 替换 alpha 通道。
      def self.with_alpha(c : UInt32, alpha : UInt8) : UInt32
        (c & 0xffffff00_u32) | alpha.to_u32
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
        Theme.new(
          0xffffffff_u32, 0x000000ff_u32, 0x2f6fedff_u32,
          0x8a8a8aff_u32, 0xd0d0d0ff_u32, 0xbcd4ffff_u32,
          0xf5f6f8ff_u32, 0xeceef1ff_u32, 0xffffffff_u32,
          0xe3e5e9ff_u32, 0xd0d0d0ff_u32,
          0xd64545ff_u32, 0x2e9e5bff_u32,
          0xd6454566_u32, 0x2e9e5b66_u32,
          0x00000014_u32, 0x2f6fedff_u32,
          0xe0a13cff_u32, 0xd64545ff_u32, 0x2e9e5bff_u32,
          0xb4b4b4ff_u32)
      end

      def self.dark : Theme
        Theme.new(
          0x1e1e1eff_u32, 0xe0e0e0ff_u32, 0x4c8dffff_u32,
          0x9a9a9aff_u32, 0x3a3a3aff_u32, 0x2b4a7dff_u32,
          0x252527ff_u32, 0x2c2c2fff_u32, 0x252527ff_u32,
          0x333336ff_u32, 0x3a3a3aff_u32,
          0xe05c5cff_u32, 0x3db06cff_u32,
          0xe05c5c66_u32, 0x3db06c66_u32,
          0xffffff14_u32, 0x4c8dffff_u32,
          0xe6b04cff_u32, 0xe05c5cff_u32, 0x3db06cff_u32,
          0x6e6e6eff_u32)
      end
    end
  end
end
