# tessell-badge — 第三方组件包模板（issue #68 脚手架）
#
# 演示「自绘 leaf」路径的最小完整组件（docs/kit/extending.md 路径三）：
# measure/arrange/emit/paint 四件套 + a11y 元数据 + dispose 契约。
# 入口 `require "tessell-badge"`（= 包名，shards 约定）。

require "tessell/kit"

module TessellBadge
  VERSION = "0.1.0"

  # 徽章：语义 tone 的小圆角标签。状态归属应用（value 由调用方改），
  # 组件只持绘制所需字段——状态归属约定（#57 调研结论）。
  class Badge < Tessell::Kit::Component
    property text : String
    property tone : Symbol # :accent | :muted

    # 外部资源示例： dispose 契约演示（AGENTS #9：持有资源必须有释放 spec）。
    # 真实组件里这里通常是 Signal watch / 定时器 / 缓存。
    getter disposed : Bool = false

    def initialize(key : Tessell::UI::UiKey, @text : String,
                   @tone : Symbol = :accent, enabled : Bool = true)
      super(key, enabled)
    end

    def measure(ctx : Tessell::Kit::Context, constraints : Tessell::Constraints) : Tessell::Size
      s = ctx.measure_text(@text, font_size(ctx))
      constraints.constrain(Tessell::Size.new(s.width + 12.0_f32, 20.0_f32))
    end

    def emit(b : Tessell::UI::Builder, ctx : Tessell::Kit::Context) : Nil
      # 坑 2（visible 双守卫）：emit 即存在——不可见不进命中树
      return unless @visible
      b.node(@key, @bounds, paint: paint_token,
        a11y_role: Tessell::A11y::Role::Text, a11y_name: @text,
        a11y_focusable: focusable?, a11y_enabled: @enabled)
    end

    def paint(p : Tessell::Kit::Painter, ctx : Tessell::Kit::Context) : Nil
      return unless @visible
      # 坑 6（主题 token）：颜色取 ctx.theme 语义 token，不硬编码
      bg = @tone == :accent ? ctx.theme.palette.accent : ctx.theme.palette.muted
      fg = @tone == :accent ? ctx.theme.palette.accent_foreground : ctx.theme.palette.foreground
      p.fill_round_rect(@bounds, 6.0_f32, bg)
      fs = font_size(ctx)
      baseline = Tessell::Kit::TextDrawing.middle_baseline(@bounds, ctx.text_metrics(fs))
      p.text(@bounds.origin.x + 6.0_f32, baseline, @text, fg, fs)
    end

    def dispose : Nil
      # 坑 3（生命周期）：停掉 watch/资源；Root#build 对移出树的组件调用
      @disposed = true
      super
    end

    def a11y_role : Tessell::A11y::Role
      Tessell::A11y::Role::Text
    end

    def a11y_name : String
      @text
    end

    private def font_size(ctx : Tessell::Kit::Context) : Float32
      ctx.theme.font_size(Tessell::Kit::ControlSize::Small)
    end
  end
end
