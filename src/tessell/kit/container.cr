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

      def initialize(@key : UI::UiKey, @direction : Layout::Direction = Layout::Direction::Vertical,
                     @padding : Insets = Insets.new, @spacing : Float32 = 0.0_f32,
                     @alignment : Alignment = Alignment::Stretch,
                     enabled : Bool = true)
        super(@key, enabled)
        @children = [] of Component
        @measured_sizes = [] of Size
      end

      def add(child : Component) : Component
        attach(child)
        @children << child
        child
      end

      def add(children : Array(Component)) : Nil
        children.each { |child| add(child) }
      end

      def measure(ctx : Context, constraints : Constraints) : Size
        inner_w = inner_limit(constraints.max_width, @padding.horizontal)
        inner_h = inner_limit(constraints.max_height, @padding.vertical)
        child_constraints = Constraints.new(0.0_f32, inner_w, 0.0_f32, inner_h)
        @measured_sizes.clear
        @children.each do |child|
          @measured_sizes << child.measure(ctx, child_constraints)
        end

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
        child_constraints = Constraints.new(0.0_f32, inner_w, 0.0_f32, inner_h)
        sizes = [] of Size
        @children.each do |child|
          sizes << child.measure(ctx, child_constraints)
        end

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
  end
end
