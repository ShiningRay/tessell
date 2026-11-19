# Tessell::Kit — 基础容器与布局（K2）
#
# 只做组件层需要的线性布局：Column/Row + padding/spacing/alignment。
# 不替代核心 Layout 两遍内核；组件仍通过 measure/arrange 产出绝对 bounds。

module Tessell
  module Kit
    enum Alignment
      Start
      Center
      End
      Stretch
    end

    class Container < Component
      getter children : Array(Component)
      property padding : Insets
      property spacing : Float32
      property alignment : Alignment
      getter direction : Layout::Direction

      @measured_sizes : Array(Size)
      @flex : Hash(Component, Float32)

      def initialize(@key : UI::UiKey, @direction : Layout::Direction = Layout::Direction::Vertical,
                     @padding : Insets = Insets.new, @spacing : Float32 = 0.0_f32,
                     @alignment : Alignment = Alignment::Stretch,
                     enabled : Bool = true)
        super(@key, enabled)
        @children = [] of Component
        @measured_sizes = [] of Size
        @flex = {} of Component => Float32
      end

      def add(child : Component) : Component
        attach(child)
        @children << child
        # issue #51：结构变更向上打脏标记，Root#build 自动补 arrange
        mark_structure_dirty
        child
      end

      # 便捷重载（issue #49）：add 的同时登记弹性权重
      def add(child : Component, grow : Float32) : Component
        add(child)
        set_grow(child, grow)
        child
      end

      def add(children : Array(Component)) : Nil
        children.each { |child| add(child) }
      end

      # 弹性权重（issue #49）：weight>0 的子项在主轴有界时按权重分享
      # 「主轴 inner − 固定子项 − spacing」的剩余空间，紧约束（min=max=share，
      # Flutter Expanded 语义）；weight<=0 取消。可先 set 后 add。
      # 权重变化打结构脏标记，Root#build 自动补 arrange。
      def set_grow(child : Component, weight : Float32) : Component
        if weight > 0.0_f32
          @flex[child] = weight
        else
          @flex.delete(child)
        end
        mark_structure_dirty
        child
      end

      def grow_of(child : Component) : Float32
        @flex[child]? || 0.0_f32
      end

      # 移除子组件（动态树，issue #44）：detach + 断父链。返回是否存在。
      # Root#build 会对移出的组件调用 dispose（停其 Signal Owner）。
      def remove(child : Component) : Bool
        return false unless @children.includes?(child)
        @children.delete(child)
        child.parent = nil
        @flex.delete(child)
        # issue #51：移除同样是结构变更，剩余子项需要重排
        mark_structure_dirty
        true
      end

      # 统一子项测量（issue #49）：sink 与 @children 对齐。
      # 无弹性子项或主轴无界时为旧口径（全部松约束测量）；有弹性子项且
      # 主轴有界时：固定子项先测，剩余主轴空间按权重紧约束分给弹性子项
      # （最后一个弹性子项吃浮点余数，保证恰好填满）。剩余不足时弹性子项
      # 塌缩为 0，固定子项优先。
      private def measure_children(ctx : Context, inner_w : Float32, inner_h : Float32,
                                   sink : Array(Size)) : Nil
        sink.clear
        child_constraints = Constraints.new(0.0_f32, inner_w, 0.0_f32, inner_h)
        main_inner = vertical? ? inner_h : inner_w
        flex_total = 0.0_f32
        flex_count = 0
        fixed_main = 0.0_f32
        @children.each do |child|
          if wgt = @flex[child]?
            sink << Size.new(0.0_f32, 0.0_f32) # 弹性槽位占位，保持索引对齐
            flex_total += wgt
            flex_count += 1
          else
            s = child.measure(ctx, child_constraints)
            sink << s
            fixed_main += vertical? ? s.height : s.width
          end
        end
        return unless flex_count > 0 && flex_total > 0.0_f32 && main_inner.finite?
        spacing_total = @spacing * (@children.size - 1).clamp(0, Int32::MAX).to_f32
        remaining = main_inner - fixed_main - spacing_total
        return unless remaining > 0.0_f32
        distributed = 0.0_f32
        flex_seen = 0
        @children.each_with_index do |child, i|
          wgt = @flex[child]?
          next unless wgt
          flex_seen += 1
          share = if flex_seen == flex_count
                    r = remaining - distributed
                    r > 0.0_f32 ? r : 0.0_f32
                  else
                    remaining * wgt / flex_total
                  end
          distributed += share
          tight = if vertical?
                    Constraints.new(0.0_f32, inner_w, share, share)
                  else
                    Constraints.new(share, share, 0.0_f32, inner_h)
                  end
          sink[i] = child.measure(ctx, tight)
        end
      end

      def measure(ctx : Context, constraints : Constraints) : Size
        inner_w = inner_limit(constraints.max_width, @padding.horizontal)
        inner_h = inner_limit(constraints.max_height, @padding.vertical)
        measure_children(ctx, inner_w, inner_h, @measured_sizes)

        intrinsic_w = 0.0_f32
        intrinsic_h = 0.0_f32
        if vertical?
          @measured_sizes.each do |size|
            intrinsic_w = Math.max(intrinsic_w, size.width)
            intrinsic_h += size.height
          end
          intrinsic_h += @spacing * (@children.size - 1).clamp(0, Int32::MAX).to_f32
        else
          @measured_sizes.each do |size|
            intrinsic_w += size.width
            intrinsic_h = Math.max(intrinsic_h, size.height)
          end
          intrinsic_w += @spacing * (@children.size - 1).clamp(0, Int32::MAX).to_f32
        end
        constraints.constrain(Size.new(
          intrinsic_w + @padding.horizontal,
          intrinsic_h + @padding.vertical
        ))
      end

      def arrange(ctx : Context, bounds : Rect) : Nil
        @bounds = bounds
        inner = Geometry.inset(bounds, @padding)
        inner_w = inner.size.width.infinite? ? 0.0_f32 : inner.size.width
        inner_h = inner.size.height.infinite? ? 0.0_f32 : inner.size.height
        sizes = [] of Size
        measure_children(ctx, inner_w, inner_h, sizes)

        cursor = vertical? ? inner.origin.y : inner.origin.x
        @children.each_with_index do |child, index|
          size = sizes[index]
          rect = if vertical?
                   w = if @alignment == Alignment::Stretch && !inner_w.infinite?
                         inner_w
                       else
                         size.width
                       end
                   x = align_x(inner, w)
                   Rect.new(x, cursor, w, size.height)
                 else
                   h = if @alignment == Alignment::Stretch && !inner_h.infinite?
                         inner_h
                       else
                         size.height
                       end
                   y = align_y(inner, h)
                   Rect.new(cursor, y, size.width, h)
                 end
          child.arrange(ctx, rect)
          cursor += vertical? ? rect.size.height : rect.size.width
          cursor += @spacing unless index == @children.size - 1
        end
      end

      def emit(b : UI::Builder, ctx : Context) : Nil
        # 按用户所见驱动（issue #35）：不可见组件不进命中树——emit 即存在，
        # invisible 子树整棵跳过（与其 paint 守卫同口径）。
        return unless @visible
        b.group(@key, @bounds, paint: paint_token,
          a11y_role: a11y_role, a11y_name: a11y_name,
          a11y_focusable: focusable?, a11y_enabled: @enabled) do
          @children.each do |child|
            child.emit(b, ctx)
          end
        end
      end

      def paint(p : Painter, ctx : Context) : Nil
        return unless @visible
        @children.each do |child|
          child.paint(p, ctx)
        end
      end

      def collect_components(sink : Array(Component)) : Nil
        sink << self
        @children.each do |child|
          child.collect_components(sink)
        end
      end

      private def vertical? : Bool
        @direction == Layout::Direction::Vertical
      end

      private def inner_limit(max : Float32, padding : Float32) : Float32
        return Float32::INFINITY if max.infinite?
        value = max - padding
        value < 0.0_f32 ? 0.0_f32 : value
      end

      private def align_x(inner : Rect, width : Float32) : Float32
        case @alignment
        when Alignment::Center then inner.origin.x + (inner.size.width - width) / 2.0_f32
        when Alignment::End    then inner.max_x - width
        else                        inner.origin.x
        end
      end

      private def align_y(inner : Rect, height : Float32) : Float32
        case @alignment
        when Alignment::Center then inner.origin.y + (inner.size.height - height) / 2.0_f32
        when Alignment::End    then inner.max_y - height
        else                        inner.origin.y
        end
      end
    end

    class Column < Container
      def initialize(key : UI::UiKey, padding : Insets = Insets.new,
                     spacing : Float32 = 0.0_f32,
                     alignment : Alignment = Alignment::Stretch,
                     enabled : Bool = true)
        super(key, Layout::Direction::Vertical, padding, spacing, alignment, enabled)
      end
    end

    class Row < Container
      def initialize(key : UI::UiKey, padding : Insets = Insets.new,
                     spacing : Float32 = 0.0_f32,
                     alignment : Alignment = Alignment::Stretch,
                     enabled : Bool = true)
        super(key, Layout::Direction::Horizontal, padding, spacing, alignment, enabled)
      end
    end

    # 弹性占位（issue #49）：measure 尊重 min 约束——单独使用为 0×0，
    # 在弹性容器里被紧约束 share 撑开：`row.add(Spacer.new(key), grow: 1.0)`。
    # 不进命中树、不绘制。
    class Spacer < Component
      def measure(ctx : Context, constraints : Constraints) : Size
        Size.new(constraints.min_width, constraints.min_height)
      end

      def emit(b : UI::Builder, ctx : Context) : Nil
        # 占位组件：不进命中树（emit 即存在的口径下，这里显式不 emit）
      end
    end
  end
end
