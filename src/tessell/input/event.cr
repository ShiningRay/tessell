# Tessell::Input — 输入事件（M2-WP1）。
#
# 事件表达选型：struct + enum（不用类层次）——值类型、零堆分配、不可变快照，
# 与 geometry 层风格一致；字段按种类选填（pointer 用 x/y/button，key 用 key，
# TextInput 用 text）。PointerEvent 为指针事件载荷 struct。
require "../geometry"

module Tessell::Input
  # 指针事件载荷：坐标 + 按钮（0=左键）。
  struct PointerEvent
    getter x : Float32
    getter y : Float32
    getter button : Int32

    def initialize(@x : Float32, @y : Float32, @button : Int32 = 0)
    end
  end

  # 键盘码（够测试即可；完整枚举留 M2 后续）。
  enum KeyCode
    Tab
    Enter
    Escape
    Left
    Right
    Up
    Down
    Backspace
    Delete
    KeyA
    KeyB
    KeyZ
  end

  # 统一事件：单一 struct + kind 枚举，覆盖
  # PointerMove/PointerDown/PointerUp/Wheel/KeyDown/KeyUp/TextInput/Resize/Blur。
  struct Event
    enum Kind
      PointerMove
      PointerDown
      PointerUp
      Wheel
      KeyDown
      KeyUp
      TextInput
      Resize
      Blur
    end

    getter kind : Kind
    getter x : Float32
    getter y : Float32
    getter button : Int32
    getter key : KeyCode?
    getter text : String?

    def initialize(@kind : Kind, @x : Float32 = 0.0_f32, @y : Float32 = 0.0_f32,
                   @button : Int32 = 0, @key : KeyCode? = nil, @text : String? = nil)
    end

    def self.pointer(kind : Kind, pe : PointerEvent) : Event
      new(kind, pe.x, pe.y, pe.button)
    end

    def self.pointer_move(x : Float32, y : Float32) : Event
      new(Kind::PointerMove, x, y)
    end

    def self.pointer_down(x : Float32, y : Float32, button : Int32 = 0) : Event
      new(Kind::PointerDown, x, y, button)
    end

    def self.pointer_up(x : Float32, y : Float32, button : Int32 = 0) : Event
      new(Kind::PointerUp, x, y, button)
    end

    def self.wheel(x : Float32, y : Float32) : Event
      new(Kind::Wheel, x, y)
    end

    def self.key_down(key : KeyCode) : Event
      new(Kind::KeyDown, 0.0_f32, 0.0_f32, 0, key)
    end

    def self.key_up(key : KeyCode) : Event
      new(Kind::KeyUp, 0.0_f32, 0.0_f32, 0, key)
    end

    def self.text_input(text : String) : Event
      new(Kind::TextInput, 0.0_f32, 0.0_f32, 0, nil, text)
    end

    def self.resize : Event
      new(Kind::Resize)
    end

    def self.blur : Event
      new(Kind::Blur)
    end
  end
end
