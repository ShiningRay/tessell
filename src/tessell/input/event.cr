# Tessell::Input — 输入事件（M2-WP1，K1 扩展）
#
# 事件表达选型：struct + enum（不用类层次）——值类型、零堆分配、不可变快照，
# 与 geometry 层风格一致；字段按种类选填（pointer 用 x/y/button，key 用 key，
# TextInput 用 text）。
#
# K1 扩展：modifiers、wheel delta、pointer enter/leave/cancel、常用键码。
# 所有新字段都有默认值，既有调用点保持兼容。
require "../geometry"

module Tessell
  module Input
    # 修饰键快照。跨平台后端自行映射 Shift/Ctrl/Alt/Meta。
    struct Modifiers
      getter shift : Bool
      getter ctrl : Bool
      getter alt : Bool
      getter meta : Bool

      def initialize(@shift : Bool = false, @ctrl : Bool = false,
                     @alt : Bool = false, @meta : Bool = false)
      end

      def self.none : Modifiers
        new
      end

      def none? : Bool
        !@shift && !@ctrl && !@alt && !@meta
      end
    end

    # 指针事件载荷：坐标 + 按钮（0=左键）。
    struct PointerEvent
      getter x : Float32
      getter y : Float32
      getter button : Int32

      def initialize(@x : Float32, @y : Float32, @button : Int32 = 0)
      end
    end

    # 键盘码。K1 补齐组件需要的常用键；平台层负责映射。
    # K2b（issue #4）：补 KeyT 与数字键——行情/表格类应用的快捷键与选股键。
    enum KeyCode
      Tab
      Enter
      Escape
      Space
      Left
      Right
      Up
      Down
      Home
      End
      PageUp
      PageDown
      Backspace
      Delete
      KeyA
      KeyB
      KeyC
      KeyT
      KeyV
      KeyX
      KeyZ
      Digit0
      Digit1
      Digit2
      Digit3
      Digit4
      Digit5
      Digit6
      Digit7
      Digit8
      Digit9
    end

    # 统一事件：单一 struct + kind 枚举，覆盖指针/键盘/文本/滚轮/焦点/窗口事件。
    struct Event
      enum Kind
        PointerEnter
        PointerLeave
        PointerMove
        PointerDown
        PointerUp
        PointerCancel
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
      getter modifiers : Modifiers
      getter wheel_dx : Float32
      getter wheel_dy : Float32
      # 平台时间戳（毫秒，单调即可）；0 表示平台未提供。双击判定等时间
      # 语义由消费方（Router/组件）基于它计算。
      getter timestamp_ms : Int64
      # 按住不放产生的自动重复按键（KeyDown 专用）。
      getter repeat : Bool

      def initialize(@kind : Kind, @x : Float32 = 0.0_f32, @y : Float32 = 0.0_f32,
                     @button : Int32 = 0, @key : KeyCode? = nil, @text : String? = nil,
                     @modifiers : Modifiers = Modifiers.none,
                     @wheel_dx : Float32 = 0.0_f32, @wheel_dy : Float32 = 0.0_f32,
                     @timestamp_ms : Int64 = 0_i64, @repeat : Bool = false)
      end

      def shift? : Bool
        @modifiers.shift
      end

      def ctrl? : Bool
        @modifiers.ctrl
      end

      def alt? : Bool
        @modifiers.alt
      end

      def meta? : Bool
        @modifiers.meta
      end

      def self.pointer(kind : Kind, pe : PointerEvent,
                       modifiers : Modifiers = Modifiers.none) : Event
        new(kind, pe.x, pe.y, pe.button, nil, nil, modifiers)
      end

      def self.pointer_move(x : Float32, y : Float32,
                            modifiers : Modifiers = Modifiers.none) : Event
        new(Kind::PointerMove, x, y, 0, nil, nil, modifiers)
      end

      def self.pointer_enter(x : Float32, y : Float32,
                             modifiers : Modifiers = Modifiers.none) : Event
        new(Kind::PointerEnter, x, y, 0, nil, nil, modifiers)
      end

      def self.pointer_leave(x : Float32, y : Float32,
                             modifiers : Modifiers = Modifiers.none) : Event
        new(Kind::PointerLeave, x, y, 0, nil, nil, modifiers)
      end

      def self.pointer_cancel(x : Float32, y : Float32, button : Int32 = 0,
                              modifiers : Modifiers = Modifiers.none) : Event
        new(Kind::PointerCancel, x, y, button, nil, nil, modifiers)
      end

      def self.pointer_down(x : Float32, y : Float32, button : Int32 = 0,
                            modifiers : Modifiers = Modifiers.none,
                            timestamp_ms : Int64 = 0_i64) : Event
        new(Kind::PointerDown, x, y, button, nil, nil, modifiers,
          0.0_f32, 0.0_f32, timestamp_ms)
      end

      def self.pointer_up(x : Float32, y : Float32, button : Int32 = 0,
                          modifiers : Modifiers = Modifiers.none,
                          timestamp_ms : Int64 = 0_i64) : Event
        new(Kind::PointerUp, x, y, button, nil, nil, modifiers,
          0.0_f32, 0.0_f32, timestamp_ms)
      end

      # x/y 是指针位置；dx/dy 是滚轮位移。旧调用 Event.wheel(x,y) 仍可用。
      def self.wheel(x : Float32, y : Float32, dx : Float32 = 0.0_f32,
                     dy : Float32 = 0.0_f32,
                     modifiers : Modifiers = Modifiers.none) : Event
        new(Kind::Wheel, x, y, 0, nil, nil, modifiers, dx, dy)
      end

      def self.key_down(key : KeyCode, modifiers : Modifiers = Modifiers.none,
                        timestamp_ms : Int64 = 0_i64, repeat : Bool = false) : Event
        new(Kind::KeyDown, 0.0_f32, 0.0_f32, 0, key, nil, modifiers,
          0.0_f32, 0.0_f32, timestamp_ms, repeat)
      end

      def self.key_up(key : KeyCode, modifiers : Modifiers = Modifiers.none,
                      timestamp_ms : Int64 = 0_i64) : Event
        new(Kind::KeyUp, 0.0_f32, 0.0_f32, 0, key, nil, modifiers,
          0.0_f32, 0.0_f32, timestamp_ms)
      end

      def self.text_input(text : String, modifiers : Modifiers = Modifiers.none,
                          timestamp_ms : Int64 = 0_i64) : Event
        new(Kind::TextInput, 0.0_f32, 0.0_f32, 0, nil, text, modifiers,
          0.0_f32, 0.0_f32, timestamp_ms)
      end

      def self.resize : Event
        new(Kind::Resize)
      end

      def self.blur : Event
        new(Kind::Blur)
      end
    end
  end
end
