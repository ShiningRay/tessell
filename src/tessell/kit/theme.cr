# Tessell::Kit — 主题与设计 token（K0）
#
# 三层：语义色 Palette → 组件解析（button_colors 等）→ 绘制。
# 颜色统一为 0xRRGGBBAA，与核心 Render::Theme 一致。
# 本文件不依赖窗口/GL/FFI，可纯逻辑测试。

require "../render/theme"

module Tessell
  module Kit
    enum Variant
      Primary
      Secondary
      Ghost
      Danger
    end

    enum ControlSize
      Small
      Medium
      Large
    end

    # 组件绘制需要的状态快照。组件可以只使用其中适用的字段。
    struct InteractionState
      getter hovered : Bool
      getter pressed : Bool
      getter focused : Bool
      getter disabled : Bool
      getter invalid : Bool
      getter selected : Bool
      getter open : Bool
      getter read_only : Bool

      def initialize(@hovered : Bool = false, @pressed : Bool = false,
                     @focused : Bool = false, @disabled : Bool = false,
                     @invalid : Bool = false, @selected : Bool = false,
                     @open : Bool = false, @read_only : Bool = false)
      end

      def self.normal : InteractionState
        new
      end
    end

    struct ButtonColors
      getter background : UInt32
      getter foreground : UInt32
      getter border : UInt32
      getter focus : UInt32

      def initialize(@background : UInt32, @foreground : UInt32,
                     @border : UInt32, @focus : UInt32)
      end
    end

    # 语义色。组件不得在绘制代码里直接写最终色值。
    struct Palette
      getter canvas : UInt32
      getter surface : UInt32
      getter surface_raised : UInt32
      getter foreground : UInt32
      getter muted : UInt32
      getter border : UInt32
      getter accent : UInt32
      getter accent_hover : UInt32
      getter accent_pressed : UInt32
      getter accent_foreground : UInt32
      getter danger : UInt32
      getter danger_hover : UInt32
      getter danger_pressed : UInt32
      getter danger_foreground : UInt32
      getter success : UInt32
      getter focus : UInt32
      getter selection : UInt32
      getter scrim : UInt32

      def initialize(@canvas : UInt32, @surface : UInt32, @surface_raised : UInt32,
                     @foreground : UInt32, @muted : UInt32, @border : UInt32,
                     @accent : UInt32, @accent_hover : UInt32,
                     @accent_pressed : UInt32, @accent_foreground : UInt32,
                     @danger : UInt32, @danger_hover : UInt32,
                     @danger_pressed : UInt32, @danger_foreground : UInt32,
                     @success : UInt32, @focus : UInt32, @selection : UInt32,
                     @scrim : UInt32)
      end
    end

    # 尺寸/排版 token。所有长度是逻辑单位；DPI 只在文本设备字号与边框下限处理。
    struct Metrics
      getter spacing_xs : Float32
      getter spacing_sm : Float32
      getter spacing_md : Float32
      getter spacing_lg : Float32
      getter radius_sm : Float32
      getter radius_md : Float32
      getter radius_lg : Float32
      getter border_width : Float32
      getter focus_ring_width : Float32
      getter font_size_sm : Float32
      getter font_size_md : Float32
      getter font_size_lg : Float32
      getter line_height_factor : Float32
      getter control_height_sm : Float32
      getter control_height_md : Float32
      getter control_height_lg : Float32
      getter padding_x_sm : Float32
      getter padding_x_md : Float32
      getter padding_x_lg : Float32

      def initialize(@spacing_xs : Float32 = 2.0_f32, @spacing_sm : Float32 = 4.0_f32,
                     @spacing_md : Float32 = 8.0_f32, @spacing_lg : Float32 = 12.0_f32,
                     @radius_sm : Float32 = 3.0_f32, @radius_md : Float32 = 4.0_f32,
                     @radius_lg : Float32 = 6.0_f32,
                     @border_width : Float32 = 1.0_f32,
                     @focus_ring_width : Float32 = 2.0_f32,
                     @font_size_sm : Float32 = 12.0_f32,
                     @font_size_md : Float32 = 14.0_f32,
                     @font_size_lg : Float32 = 16.0_f32,
                     @line_height_factor : Float32 = 1.25_f32,
                     @control_height_sm : Float32 = 28.0_f32,
                     @control_height_md : Float32 = 32.0_f32,
                     @control_height_lg : Float32 = 40.0_f32,
                     @padding_x_sm : Float32 = 8.0_f32,
                     @padding_x_md : Float32 = 12.0_f32,
                     @padding_x_lg : Float32 = 16.0_f32)
      end
    end

    struct Theme
      getter palette : Palette
      getter metrics : Metrics
      getter dark : Bool

      def initialize(@palette : Palette, @metrics : Metrics = Metrics.new,
                     @dark : Bool = false)
      end

      def self.light : Theme
        new(Palette.new(
          0xf6f7f9ff_u32, # canvas
          0xffffffff_u32, # surface
          0xf0f2f5ff_u32, # surface_raised
          0x1f2328ff_u32, # foreground
          0x6b7280ff_u32, # muted
          0xd5d9e0ff_u32, # border
          0x2f6fedff_u32, # accent
          0x275fd4ff_u32, # accent_hover
          0x1f4fb5ff_u32, # accent_pressed
          0xffffffff_u32, # accent_foreground
          0xd92d20ff_u32, # danger
          0xbf251aff_u32, # danger_hover
          0xa61f16ff_u32, # danger_pressed
          0xffffffff_u32, # danger_foreground
          0x1f8f4eff_u32, # success
          0x2f6fedff_u32, # focus
          0xbcd4ffff_u32, # selection
          0x00000066_u32  # scrim
        ), dark: false)
      end

      def self.dark : Theme
        new(Palette.new(
          0x171a1fff_u32,
          0x1e2228ff_u32,
          0x262b33ff_u32,
          0xe7eaf0ff_u32,
          0x9aa4b2ff_u32,
          0x3a414cff_u32,
          0x5b8dffff_u32,
          0x78a2ffff_u32,
          0x4878e0ff_u32,
          0x10151cff_u32,
          0xf05a4fff_u32,
          0xff7469ff_u32,
          0xd9483eff_u32,
          0x1a1010ff_u32,
          0x4cc97cff_u32,
          0x78a2ffff_u32,
          0x2b4a7dff_u32,
          0x00000099_u32
        ), dark: true)
      end

      # Kit Theme → 核心 Theme：用于清屏/后端 begin_frame 的 6 个基础色。
      def to_render : Tessell::Render::Theme
        Tessell::Render::Theme.new(palette.canvas, palette.foreground,
          palette.accent, palette.muted, palette.border, palette.selection)
      end

      # 核心 Theme → Kit Theme 适配器。核心只有 6 个颜色，其余语义色取
      # 同模式默认主题，保证组件不会出现“半套主题”。
      def self.from_render(render : Tessell::Render::Theme, dark : Bool = false) : Theme
        base = dark ? Theme.dark : Theme.light
        palette = Palette.new(
          render.bg,
          render.bg,
          base.palette.surface_raised,
          render.fg,
          render.muted,
          render.border,
          render.accent,
          dark ? 0x78a2ffff_u32 : 0x275fd4ff_u32,
          dark ? 0x4878e0ff_u32 : 0x1f4fb5ff_u32,
          base.palette.accent_foreground,
          base.palette.danger,
          base.palette.danger_hover,
          base.palette.danger_pressed,
          base.palette.danger_foreground,
          base.palette.success,
          render.accent,
          render.selection,
          base.palette.scrim
        )
        new(palette, base.metrics, dark)
      end

      def control_height(size : ControlSize) : Float32
        case size
        when ControlSize::Small  then metrics.control_height_sm
        when ControlSize::Medium then metrics.control_height_md
        when ControlSize::Large  then metrics.control_height_lg
        else                          metrics.control_height_md
        end
      end

      def font_size(size : ControlSize) : Float32
        case size
        when ControlSize::Small  then metrics.font_size_sm
        when ControlSize::Medium then metrics.font_size_md
        when ControlSize::Large  then metrics.font_size_lg
        else                          metrics.font_size_md
        end
      end

      def padding_x(size : ControlSize) : Float32
        case size
        when ControlSize::Small  then metrics.padding_x_sm
        when ControlSize::Medium then metrics.padding_x_md
        when ControlSize::Large  then metrics.padding_x_lg
        else                          metrics.padding_x_md
        end
      end

      def radius(size : ControlSize) : Float32
        case size
        when ControlSize::Small  then metrics.radius_sm
        when ControlSize::Medium then metrics.radius_md
        when ControlSize::Large  then metrics.radius_lg
        else                          metrics.radius_md
        end
      end

      # Button 解析：语义色 + variant + 状态 → 实际颜色。
      def button_colors(variant : Variant, size : ControlSize, state : InteractionState) : ButtonColors
        return disabled_button_colors if state.disabled

        case variant
        when Variant::Primary
          bg = state.pressed ? palette.accent_pressed : (state.hovered ? palette.accent_hover : palette.accent)
          ButtonColors.new(bg, palette.accent_foreground, bg, palette.focus)
        when Variant::Secondary
          bg = state.pressed ? palette.surface : (state.hovered ? palette.surface_raised : palette.surface)
          ButtonColors.new(bg, palette.foreground, palette.border, palette.focus)
        when Variant::Ghost
          bg = state.pressed ? palette.surface_raised : (state.hovered ? palette.surface : 0x00000000_u32)
          ButtonColors.new(bg, palette.foreground, 0x00000000_u32, palette.focus)
        when Variant::Danger
          bg = state.pressed ? palette.danger_pressed : (state.hovered ? palette.danger_hover : palette.danger)
          ButtonColors.new(bg, palette.danger_foreground, bg, palette.focus)
        else
          ButtonColors.new(palette.surface, palette.foreground, palette.border, palette.focus)
        end
      end

      private def disabled_button_colors : ButtonColors
        ButtonColors.new(palette.surface_raised, palette.muted, palette.border, palette.focus)
      end

      # 通道工具：与核心 Render::Theme 的打包顺序一致（0xRRGGBBAA）。
      def self.r(c : UInt32) : UInt8
        ((c >> 24) & 0xff).to_u8
      end

      def self.g(c : UInt32) : UInt8
        ((c >> 16) & 0xff).to_u8
      end

      def self.b(c : UInt32) : UInt8
        ((c >> 8) & 0xff).to_u8
      end

      def self.a(c : UInt32) : UInt8
        (c & 0xff).to_u8
      end
    end
  end
end
