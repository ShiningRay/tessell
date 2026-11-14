# Tessell::Kit — 组件基类（K0）
#
# 组件是长期存在的对象：状态、key、子组件跨帧复用。
# 每帧流程：measure → arrange → emit declarations → UI.apply → paint。
# 纯逻辑可脱离窗口测试。

module Tessell
  module Kit
    abstract class Component
      getter key : UI::UiKey
      property bounds : Rect
      property enabled : Bool
      property visible : Bool
      property focused : Bool
      getter parent : Component?

      def initialize(@key : UI::UiKey, @enabled : Bool = true, @visible : Bool = true)
        @bounds = Rect.new
        @focused = false
        @parent = nil
      end

      def parent=(value : Component?) : Nil
        @parent = value
      end

      def attach(child : Component) : Component
        child.parent = self
        child
      end

      abstract def measure(ctx : Context, constraints : Constraints) : Size

      def arrange(ctx : Context, bounds : Rect) : Nil
        @bounds = bounds
      end

      abstract def emit(b : UI::Builder, ctx : Context) : Nil

      def paint(p : Painter, ctx : Context) : Nil
      end

      def focusable? : Bool
        false
      end

      def handle(event : Event, ctx : Context) : Bool
        false
      end

      def tick(now_ms : Int64, ctx : Context) : Nil
      end

      def on_focus_changed(focused : Bool) : Nil
      end

      def hit?(point : Point) : Bool
        return false unless @visible
        return false unless @bounds.contains?(point)
        clip = clip_bounds
        clip.nil? || clip.contains?(point)
      end

      # 子组件可返回绝对坐标的裁切矩形；Root 会同步到 Node#clip。
      def clip_bounds : Rect?
        nil
      end

      # Root 用它遍历整棵树建立 Node ↔ Component 映射。
      def each_component(& : Component ->) : Nil
        yield self
      end

      # 声明里的 paint token：状态变化时改变，UI.apply 只把该节点标 Paint。
      def paint_token : UInt32
        0_u32
      end

      def a11y_role : A11y::Role
        A11y::Role::Group
      end

      def a11y_name : String
        ""
      end

      def a11y_value : String
        ""
      end

      def a11y_enabled : Bool
        @enabled
      end
    end
  end
end
