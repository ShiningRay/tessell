# Tessell::Kit::Image — 位图控件（issue #28）
#
# 消费 Backend#create_texture 的外部纹理通道；fit 表达三种缩放语义。
# 纹理像素所有权：create_texture 时后端复制；内容更新走 update_texture
# 增量区域；handle 跨帧稳定（resize 不失效，纹理尺寸变更需重建）。
# 线程纪律：create/update/destroy 只在 UI 执行上下文调用。

module Tessell
  module Kit
    class Image < Component
      enum Fit
        # 拉伸填满 bounds（宽高比不保留）
        Stretch
        # 等比缩放至完整容纳在 bounds 内（信箱留白）
        Contain
        # 等比缩放至覆盖 bounds（居中裁掉溢出部分）
        Cover
      end

      property fit : Fit
      getter texture_id : Int32
      # 纹理逻辑尺寸（px）：aspect 计算与 src rect 换算用。
      getter texture_width : Int32
      getter texture_height : Int32

      def initialize(@key : UI::UiKey, texture_id : Int32,
                     @texture_width : Int32, @texture_height : Int32,
                     @fit : Fit = Fit::Stretch, enabled : Bool = true)
        super(@key, enabled)
        @texture_id = texture_id
      end

      # 重绑纹理（handle/尺寸变更时调用；paint token 随之变化驱动 Paint 失效）
      def set_texture(handle : Int32, width : Int32, height : Int32) : Nil
        @texture_id = handle
        @texture_width = width
        @texture_height = height
      end

      # paint token 随纹理 handle/fit 变化：UI.apply 据此标 Paint 失效（#28 接入）。
      def paint_token : UInt32
        # 回绕运算（&*）：hash 溢出属预期，不许 raise
        h = 0xcbf29ce484222325_u64
        h = (h ^ @texture_id.to_u64) &* 0x100000001b3_u64
        h = (h ^ @fit.value.to_u64) &* 0x100000001b3_u64
        h = (h ^ @texture_width.to_u64) &* 0x100000001b3_u64
        h = (h ^ @texture_height.to_u64) &* 0x100000001b3_u64
        ((h >> 32) & 0xffffffff_u64).to_u32! ^ h.to_u32!
      end

      def measure(ctx : Context, constraints : Constraints) : Size
        return constraints.constrain(Size.new(0.0_f32, 0.0_f32)) if @texture_id == 0
        case @fit
        when Fit::Stretch
          # 拉伸填满可用区
          constraints.constrain(Size.new(constraints.max_width,
            constraints.max_height.infinite? ? @texture_height.to_f32 : constraints.max_height))
        else
          # Contain/Cover 保比例：以可用区与纹理 aspect 的最小/最大缩放
          aw = constraints.max_width.infinite? ? @texture_width.to_f32 : constraints.max_width
          ah = constraints.max_height.infinite? ? @texture_height.to_f32 : constraints.max_height
          return constraints.constrain(Size.new(0.0_f32, 0.0_f32)) if aw <= 0 || ah <= 0
          scale = if @fit == Fit::Contain
                    Math.min(aw / @texture_width, ah / @texture_height)
                  else
                    Math.max(aw / @texture_width, ah / @texture_height)
                  end
          size = Size.new(@texture_width * scale, @texture_height * scale)
          # Cover 刻意溢出容器（CSS object-fit: cover 语义）——不经过
          # constrain 钳制；Contain 在约束内，钳制无副作用。
          @fit == Fit::Contain ? constraints.constrain(size) : size
        end
      end

      def emit(b : UI::Builder, ctx : Context) : Nil
        return unless @visible
        b.node(@key, @bounds, paint: paint_token,
          a11y_role: A11y::Role::Image, a11y_name: a11y_name,
          a11y_focusable: false, a11y_enabled: @enabled)
      end

      def paint(p : Painter, ctx : Context) : Nil
        return unless @visible
        return if @texture_id == 0
        return if @bounds.size.width <= 0 || @bounds.size.height <= 0
        src = fit_source_rect
        p.image(@texture_id, @bounds, 0xffffffff_u32, src)
      end

      def a11y_role : A11y::Role
        A11y::Role::Image
      end

      def a11y_name : String
        "image #{@texture_width}x#{@texture_height}"
      end

      # fit → 源矩形：Cover 时居中裁掉超出 bounds aspect 的部分；
      # Stretch/Contain 用整图。返回纹理像素坐标（后端换算 uv）。
      private def fit_source_rect : Rect
        return Rect.new(0.0_f32, 0.0_f32, @texture_width.to_f32, @texture_height.to_f32) if @fit != Fit::Cover
        return Rect.new(0.0_f32, 0.0_f32, @texture_width.to_f32, @texture_height.to_f32) if @bounds.size.width <= 0 || @bounds.size.height <= 0
        bounds_aspect = @bounds.size.width / @bounds.size.height
        texture_aspect = @texture_width.to_f32 / @texture_height.to_f32
        if texture_aspect > bounds_aspect
          # 纹理更宽：左右裁
          crop_w = (@texture_height.to_f32 * bounds_aspect).round.to_i
          x = (@texture_width - crop_w) // 2
          Rect.new(x.to_f32, 0.0_f32, crop_w.to_f32, @texture_height.to_f32)
        else
          # 纹理更高：上下裁
          crop_h = (@texture_width.to_f32 / bounds_aspect).round.to_i
          y = (@texture_height - crop_h) // 2
          Rect.new(0.0_f32, y.to_f32, @texture_width.to_f32, crop_h.to_f32)
        end
      end
    end
  end
end
