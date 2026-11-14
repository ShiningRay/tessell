# Tessell::Kit — 组件层输入事件（K0）
#
# Kit 不直接读平台消息。Root 把核心 Input::Event 适配成 Kit::Event，
# 这样组件测试不需要窗口、Win32 或 GL。

require "../input/event"

module Tessell
  module Kit
    enum Key
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
      KeyV
      KeyX
      KeyZ
      Unknown
    end

    # 复用核心 Input::Modifiers，避免两套修饰键类型漂移。
    alias Modifiers = Tessell::Input::Modifiers

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
        Focus
        Blur
        Resize
      end

      getter kind : Kind
      getter x : Float32
      getter y : Float32
      getter button : Int32
      getter key : Key?
      getter text : String?
      getter modifiers : Modifiers
      getter wheel_dx : Float32
      getter wheel_dy : Float32

      def initialize(@kind : Kind, @x : Float32 = 0.0_f32, @y : Float32 = 0.0_f32,
                     @button : Int32 = 0, @key : Key? = nil, @text : String? = nil,
                     @modifiers : Modifiers = Modifiers.none,
                     @wheel_dx : Float32 = 0.0_f32, @wheel_dy : Float32 = 0.0_f32)
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

      def self.pointer(kind : Kind, x : Float32, y : Float32, button : Int32 = 0,
                       modifiers : Modifiers = Modifiers.none) : Event
        new(kind, x, y, button, nil, nil, modifiers)
      end

      def self.wheel(x : Float32, y : Float32, dx : Float32, dy : Float32,
                     modifiers : Modifiers = Modifiers.none) : Event
        new(Kind::Wheel, x, y, 0, nil, nil, modifiers, dx, dy)
      end

      def self.key_down(key : Key, modifiers : Modifiers = Modifiers.none) : Event
        new(Kind::KeyDown, 0.0_f32, 0.0_f32, 0, key, nil, modifiers)
      end

      def self.key_up(key : Key, modifiers : Modifiers = Modifiers.none) : Event
        new(Kind::KeyUp, 0.0_f32, 0.0_f32, 0, key, nil, modifiers)
      end

      def self.text_input(text : String, modifiers : Modifiers = Modifiers.none) : Event
        new(Kind::TextInput, 0.0_f32, 0.0_f32, 0, nil, text, modifiers)
      end

      def self.blur : Event
        new(Kind::Blur)
      end

      def self.focus : Event
        new(Kind::Focus)
      end
    end
  end
end
