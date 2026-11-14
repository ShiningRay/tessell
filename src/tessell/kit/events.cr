# Tessell::Kit — 组件层输入事件（K0）
#
# Kit 不直接读平台消息。Root 把核心 Input::Event 适配成 Kit::Event，
# 这样组件测试不需要窗口、Win32 或 GL。

require "../input/event"

module Tessell
  module Kit
    # 键盘键的唯一真相是核心 `Tessell::Input::KeyCode`（issue #27）。
    # Kit 不再维护第二套枚举——两套映射表本身就是漂移源头（v0.2.0 时 KeyT/
    # Digit0-9/F1-F4 在核心已存在，Kit 侧却全部落到 Unknown）。alias 之后
    # 核心新增键自动对组件可见，spec/kit/key_mapping_spec.cr 断言全量透传。
    # 例外：F1 被 Root 预留给帧调试 overlay 开关，不投递给组件。
    alias Key = Tessell::Input::KeyCode

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
