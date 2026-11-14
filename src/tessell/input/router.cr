# Tessell::Input::Router — 输入路由（M2-WP1，K1 扩展）。
#
# 规则（handle 返回事件目标）：
#   PointerEnter/Move   → hover = deepest 命中
#   PointerLeave        → 清 hover，返回 nil
#   PointerDown         → deepest 命中；可聚焦时 focus；记 pressed=命中目标
#   PointerUp           → 返回最近一次 pressed（按压目标，不重新命中）后清空 pressed
#   PointerCancel       → 返回 pressed 并清空
#   Wheel               → hover || 焦点（delta 在 Event 上）
#   KeyDown/KeyUp/TextInput → 当前焦点
#   Resize              → nil（焦点不变）
#   Blur                → nil 且清焦点
# 不分配每事件 Array：deepest 为递归无缓冲，焦点为字段读；hover/pressed 只读。
require "./event"
require "./hit_test"
require "./focus"

module Tessell::Input
  class Router
    getter focus_manager : FocusManager
    getter hover : Node?
    getter pressed : Node?

    # 点击语义（issue #4）：最近一次 PointerUp 的结果。
    #   last_click_count：0=非点击（无按压目标），1=单击，2=双击
    #     （同目标、double_click_window_ms 内、double_click_max_dist 内）。
    #   last_press_target：最近一次 PointerDown 命中的节点（= pressed 快照）。
    #   last_drag_distance：按下到释放的位移（拖拽判定的语义辅助）。
    getter last_click_count : Int32
    getter last_drag_distance : Float32

    # 双击判定参数：时间窗（毫秒）与位移上限（逻辑像素）。
    property double_click_window_ms : Int64
    property double_click_max_dist : Float32

    @last_up_target : Node?
    @last_up_ts : Int64
    @last_up_x : Float32
    @last_up_y : Float32
    # 修饰键参与双击判定（issue #20）：Shift/Ctrl 等变化打断双击链，
    # 否则组件层无法区分「双击」与「两次带修饰的单击」。
    @last_up_modifiers : Modifiers
    @down_x : Float32
    @down_y : Float32

    def initialize
      @focus_manager = FocusManager.new
      @hover = nil
      @pressed = nil
      @last_click_count = 0
      @last_drag_distance = 0.0_f32
      @double_click_window_ms = 500_i64
      @double_click_max_dist = 6.0_f32
      @last_up_target = nil
      @last_up_ts = 0_i64
      @last_up_x = 0.0_f32
      @last_up_y = 0.0_f32
      @last_up_modifiers = Modifiers.none
      @down_x = 0.0_f32
      @down_y = 0.0_f32
    end

    def initialize(&focusable : Node -> Bool)
      @focus_manager = FocusManager.new { |node| focusable.call(node) }
      @hover = nil
      @pressed = nil
      @last_click_count = 0
      @last_drag_distance = 0.0_f32
      @double_click_window_ms = 500_i64
      @double_click_max_dist = 6.0_f32
      @last_up_target = nil
      @last_up_ts = 0_i64
      @last_up_x = 0.0_f32
      @last_up_y = 0.0_f32
      @last_up_modifiers = Modifiers.none
      @down_x = 0.0_f32
      @down_y = 0.0_f32
    end

    def handle(event : Event, root : Node) : Node?
      case event.kind
      when Event::Kind::PointerDown
        target = HitTest.deepest(root, Point.new(event.x, event.y))
        if target && @focus_manager.focusable?(target)
          @focus_manager.focus(target)
        end
        @pressed = target
        @down_x = event.x
        @down_y = event.y
        target
      when Event::Kind::PointerEnter, Event::Kind::PointerMove
        @hover = HitTest.deepest(root, Point.new(event.x, event.y))
        @hover
      when Event::Kind::PointerLeave
        @hover = nil
        nil
      when Event::Kind::PointerUp
        target = @pressed
        @pressed = nil
        register_click(target, event)
        target
      when Event::Kind::PointerCancel
        target = @pressed
        @pressed = nil
        @last_click_count = 0
        @last_drag_distance = 0.0_f32
        target
      when Event::Kind::Wheel
        @hover || @focus_manager.focused
      when Event::Kind::KeyDown, Event::Kind::KeyUp, Event::Kind::TextInput
        @focus_manager.focused
      when Event::Kind::Resize
        nil
      when Event::Kind::Blur
        @focus_manager.blur
        @hover = nil
        nil
      else
        nil
      end
    end

    private def register_click(target : Node?, event : Event) : Nil
      unless target
        @last_click_count = 0
        @last_drag_distance = 0.0_f32
        return
      end
      # 按下→释放位移（拖拽判定），不是与上次释放位置的距离。
      dx = event.x - @down_x
      dy = event.y - @down_y
      @last_drag_distance = Math.sqrt(dx * dx + dy * dy)
      # 按压-释放位移超过上限不算点击（拖拽收尾）。
      if @last_drag_distance > @double_click_max_dist * 10.0_f32
        @last_click_count = 0
      else
        double = target == @last_up_target &&
                 event.timestamp_ms > 0 &&
                 @last_up_ts > 0 &&
                 (event.timestamp_ms - @last_up_ts) <= @double_click_window_ms &&
                 @last_drag_distance <= @double_click_max_dist &&
                 event.modifiers == @last_up_modifiers
        @last_click_count = double ? 2 : 1
      end
      @last_up_target = target
      @last_up_ts = event.timestamp_ms
      @last_up_x = event.x
      @last_up_y = event.y
      @last_up_modifiers = event.modifiers
    end
  end
end
