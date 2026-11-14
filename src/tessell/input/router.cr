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

    def initialize
      @focus_manager = FocusManager.new
      @hover = nil
      @pressed = nil
    end

    def initialize(&focusable : Node -> Bool)
      @focus_manager = FocusManager.new { |node| focusable.call(node) }
      @hover = nil
      @pressed = nil
    end

    def handle(event : Event, root : Node) : Node?
      case event.kind
      when Event::Kind::PointerDown
        target = HitTest.deepest(root, Point.new(event.x, event.y))
        if target && @focus_manager.focusable?(target)
          @focus_manager.focus(target)
        end
        @pressed = target
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
        target
      when Event::Kind::PointerCancel
        target = @pressed
        @pressed = nil
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
  end
end
