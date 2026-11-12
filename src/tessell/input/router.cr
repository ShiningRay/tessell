# Tessell::Input::Router — 输入路由（M2-WP1）。
#
# 规则（handle 返回事件目标）：
#   PointerDown            → deepest 命中；可聚焦时 focus；记 pressed=命中目标
#   PointerMove            → hover = deepest 命中（只读 getter）
#   PointerUp              → 返回最近一次 pressed（按压目标，不重新命中）后清空 pressed（单次手势结束）
#   Wheel                  → hover || 焦点
#   KeyDown/KeyUp/TextInput → 当前焦点
#   Resize                 → nil（焦点不变）
#   Blur                   → nil 且清焦点
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
      when Event::Kind::PointerMove
        @hover = HitTest.deepest(root, Point.new(event.x, event.y))
        @hover
      when Event::Kind::PointerUp
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
        nil
      end
    end
  end
end
