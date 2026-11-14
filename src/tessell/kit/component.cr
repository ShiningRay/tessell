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
      property tooltip_text : String?
      property tooltip_delay_ms : Int32
      getter parent : Component?

      def initialize(@key : UI::UiKey, @enabled : Bool = true, @visible : Bool = true)
        @bounds = Rect.new
        @focused = false
        @tooltip_text = nil
        @tooltip_delay_ms = 600
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

      # Tab 键语义（issue #16）：默认 false——Tab 由 Root 走焦点环。
      # 内部自带 Tab 导航的组件（表格、代码编辑器、树控件）覆盖为 true，
      # Root 会先把 Tab/Shift+Tab 投递给当前焦点组件，组件返回 true 即消费。
      # Ctrl/Meta+Tab 恒定保留给焦点环，是键盘用户离开该组件的出口。
      def wants_tab? : Bool
        false
      end

      def handle(event : Event, ctx : Context) : Bool
        false
      end

      def tick(now_ms : Int64, ctx : Context) : Nil
      end

      def on_focus_changed(focused : Bool) : Nil
        @focused = focused
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
      # 用显式 sink 而不是递归 block：Crystal 对 yield 转发块会内联展开。
      def collect_components(sink : Array(Component)) : Nil
        sink << self
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

      # 虚拟列表等需要报告逻辑子节点总数的组件覆盖此值。
      def a11y_children_count : Int32?
        nil
      end

      def a11y_scroll_offset : Int32
        0
      end

      # ---- 二维网格语义（issue #31）----
      # 虚拟化大控件的 a11y 契约：坐标/选区/表头语义经结构化字段声明，
      # 不再把坐标拼进 a11y_value 字符串。全部默认 nil/false——既有组件
      # 零改动；表格类组件按需覆盖。
      def a11y_row : Int32?
        nil
      end

      def a11y_col : Int32?
        nil
      end

      def a11y_row_count : Int32?
        nil
      end

      def a11y_col_count : Int32?
        nil
      end

      # 行列表头的朗读文本（如 "A"/"1"）；nil = 非表头。
      def a11y_row_index_text : String?
        nil
      end

      def a11y_col_index_text : String?
        nil
      end

      def a11y_selected : Bool?
        nil
      end

      def a11y_active_cell : Bool?
        nil
      end

      # 可视窗口在逻辑总量中的起点（虚拟化网格用）。
      def a11y_first_visible_index : Int32?
        nil
      end
    end
  end
end
