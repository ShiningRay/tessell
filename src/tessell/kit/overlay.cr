# Tessell::Kit — Overlay 栈、定位与模态屏障（K3）
#
# Root 持有 OverlayHost；Tooltip/Select/Dialog 通过各自 entry 打开。
# 本文件只做定位、层级、dismiss 策略与屏障组件，不直接读平台事件。

module Tessell
  module Kit
    enum OverlayKind
      Tooltip
      Popover
      Dialog
    end

    enum OverlaySide
      Below
      Above
      Right
      Left
    end

    module OverlayPlacement
      # 将浮层放在 anchor 的指定侧；越界时翻转并夹紧到 viewport。
      def self.place(anchor : Rect, size : Size, viewport : Rect,
                     preferred : OverlaySide = OverlaySide::Below,
                     gap : Float32 = 4.0_f32,
                     margin : Float32 = 8.0_f32) : Rect
        width = Math.min(size.width, Math.max(0.0_f32, viewport.size.width - margin * 2.0_f32))
        height = Math.min(size.height, Math.max(0.0_f32, viewport.size.height - margin * 2.0_f32))
        case preferred
        when OverlaySide::Below
          if anchor.max_y + gap + height <= viewport.max_y - margin
            place_xy(anchor.origin.x, anchor.max_y + gap, width, height, viewport, margin)
          elsif anchor.origin.y - gap - height >= viewport.origin.y + margin
            place_xy(anchor.origin.x, anchor.origin.y - gap - height, width, height, viewport, margin)
          else
            place_xy(anchor.origin.x, anchor.max_y + gap, width, height, viewport, margin)
          end
        when OverlaySide::Above
          if anchor.origin.y - gap - height >= viewport.origin.y + margin
            place_xy(anchor.origin.x, anchor.origin.y - gap - height, width, height, viewport, margin)
          else
            place_xy(anchor.origin.x, anchor.max_y + gap, width, height, viewport, margin)
          end
        when OverlaySide::Right
          if anchor.max_x + gap + width <= viewport.max_x - margin
            place_xy(anchor.max_x + gap, anchor.origin.y, width, height, viewport, margin)
          else
            place_xy(anchor.origin.x - gap - width, anchor.origin.y, width, height, viewport, margin)
          end
        when OverlaySide::Left
          if anchor.origin.x - gap - width >= viewport.origin.x + margin
            place_xy(anchor.origin.x - gap - width, anchor.origin.y, width, height, viewport, margin)
          else
            place_xy(anchor.max_x + gap, anchor.origin.y, width, height, viewport, margin)
          end
        else
          place_xy(anchor.origin.x, anchor.max_y + gap, width, height, viewport, margin)
        end
      end

      def self.center(size : Size, viewport : Rect, margin : Float32 = 8.0_f32) : Rect
        width = Math.min(size.width, Math.max(0.0_f32, viewport.size.width - margin * 2.0_f32))
        height = Math.min(size.height, Math.max(0.0_f32, viewport.size.height - margin * 2.0_f32))
        place_xy(viewport.origin.x + (viewport.size.width - width) / 2.0_f32,
          viewport.origin.y + (viewport.size.height - height) / 2.0_f32,
          width, height, viewport, margin)
      end

      private def self.place_xy(x : Float32, y : Float32, width : Float32,
                                height : Float32, viewport : Rect,
                                margin : Float32) : Rect
        max_x = viewport.max_x - margin - width
        max_y = viewport.max_y - margin - height
        px = x.clamp(viewport.origin.x + margin, Math.max(viewport.origin.x + margin, max_x))
        py = y.clamp(viewport.origin.y + margin, Math.max(viewport.origin.y + margin, max_y))
        Rect.new(px, py, width, height)
      end
    end

    class Barrier < Component
      property on_click : Proc(Nil)?

      def initialize(@key : UI::UiKey)
        super(@key)
        @on_click = nil
      end

      def measure(ctx : Context, constraints : Constraints) : Size
        constraints.constrain(Size.new(constraints.max_width, constraints.max_height))
      end

      def arrange(ctx : Context, bounds : Rect) : Nil
        @bounds = bounds
      end

      def emit(b : UI::Builder, ctx : Context) : Nil
        b.node(@key, @bounds, paint: paint_token,
          a11y_role: A11y::Role::Group, a11y_name: "Modal barrier",
          a11y_focusable: false, a11y_enabled: true)
      end

      def paint(p : Painter, ctx : Context) : Nil
        p.fill_rect(@bounds, ctx.theme.palette.scrim)
      end

      def handle(event : Event, ctx : Context) : Bool
        case event.kind
        when Event::Kind::PointerUp
          @on_click.try(&.call)
          true
        when Event::Kind::PointerDown
          true
        else
          false
        end
      end
    end

    class OverlayEntry
      getter component : Component
      getter kind : OverlayKind
      getter owner : Component?
      getter anchor : Rect
      getter preferred : OverlaySide
      property modal : Bool
      property center : Bool
      property dismiss_on_outside : Bool
      property dismiss_on_escape : Bool
      property dismiss_on_blur : Bool
      property gap : Float32
      property margin : Float32
      property on_close : Proc(Nil)?
      getter bounds : Rect
      getter barrier : Barrier?
      getter measured_size : Size

      def initialize(@component : Component, @kind : OverlayKind,
                     @owner : Component? = nil, @anchor : Rect = Rect.new,
                     @preferred : OverlaySide = OverlaySide::Below,
                     @modal : Bool = false, @center : Bool = false,
                     @dismiss_on_outside : Bool = true,
                     @dismiss_on_escape : Bool = true,
                     @dismiss_on_blur : Bool = true,
                     @gap : Float32 = 4.0_f32, @margin : Float32 = 8.0_f32)
        @bounds = Rect.new
        @measured_size = Size.new
        @on_close = nil
        @barrier = @modal ? Barrier.new(@component.key.child(0xffff_0001_u64)) : nil
      end

      def measure(ctx : Context, viewport : Rect) : Nil
        max_w = Math.max(0.0_f32, viewport.size.width - @margin * 2.0_f32)
        max_h = Math.max(0.0_f32, viewport.size.height - @margin * 2.0_f32)
        @measured_size = @component.measure(ctx, Constraints.new(0.0_f32, max_w, 0.0_f32, max_h))
      end

      def place(viewport : Rect) : Nil
        if @center
          @bounds = OverlayPlacement.center(@measured_size, viewport, @margin)
        else
          @bounds = OverlayPlacement.place(@anchor, @measured_size, viewport,
            @preferred, @gap, @margin)
        end
        @component.arrange(@context_for_arrange.not_nil!, @bounds) if @context_for_arrange
        @barrier.try(&.arrange(@context_for_arrange.not_nil!, viewport)) if @context_for_arrange
      end

      # 由 OverlayHost 在 layout 时注入，避免 entry 持有 Root。
      def arrange_with(ctx : Context, viewport : Rect) : Nil
        @context_for_arrange = ctx
        measure(ctx, viewport)
        place(viewport)
      end

      @context_for_arrange : Context?

      def contains?(point : Point) : Bool
        @bounds.contains?(point)
      end
    end

    class OverlayHost
      getter entries : Array(OverlayEntry)
      property viewport : Rect
      property context : Context?
      property on_open : Proc(OverlayEntry, Nil)?
      property on_close : Proc(OverlayEntry, Nil)?

      def initialize(@viewport : Rect = Rect.new(0.0_f32, 0.0_f32, 800.0_f32, 600.0_f32))
        @entries = [] of OverlayEntry
        @context = nil
        @on_open = nil
        @on_close = nil
      end

      def empty? : Bool
        @entries.empty?
      end

      def any? : Bool
        !@entries.empty?
      end

      def top : OverlayEntry?
        @entries.last?
      end

      def modal? : Bool
        @entries.any? { |entry| entry.modal }
      end

      def top_modal : OverlayEntry?
        @entries.reverse_each do |entry|
          return entry if entry.modal
        end
        nil
      end

      def open(entry : OverlayEntry) : Nil
        if ctx = @context
          entry.arrange_with(ctx, @viewport)
        end
        if barrier = entry.barrier
          barrier.on_click = -> { close(entry) }
        end
        @entries << entry
        @on_open.try(&.call(entry))
      end

      def close(entry : OverlayEntry) : Bool
        index = @entries.index(entry)
        return false unless index
        @entries.delete_at(index)
        entry.on_close.try(&.call)
        @on_close.try(&.call(entry))
        true
      end

      def close_top : Bool
        if entry = @entries.last?
          close(entry)
        else
          false
        end
      end

      def close_owner(owner : Component) : Nil
        i = @entries.size - 1
        while i >= 0
          entry = @entries[i]
          close(entry) if entry.owner == owner
          i -= 1
        end
      end

      def clear : Nil
        @entries.clear
      end

      def layout(ctx : Context, viewport : Rect) : Nil
        @context = ctx
        @viewport = viewport
        @entries.each do |entry|
          entry.arrange_with(ctx, viewport)
        end
      end

      # 找到包含点的最上层 entry；屏外点击返回 nil。
      def hit(point : Point) : OverlayEntry?
        i = @entries.size - 1
        while i >= 0
          entry = @entries[i]
          return entry if entry.contains?(point)
          i -= 1
        end
        nil
      end
    end
  end
end
