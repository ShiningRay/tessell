# Tessell::Platform::SDL2 — 可选 SDL2 平台宿主（issue #61 X1）。
#
# 入口：`require "tessell/platform/sdl2"`。核心入口 `require "tessell"`
# 不加载本文件，shard.yml 不新增 SDL2 依赖（plan §0.2 / §3.1）。
# 职责（plan §3.3）：窗口/GL context、SDL 事件 → Input::Event、
# 剪贴板、logical/drawable 尺寸与 DPI scale、committed-text IME 能力表、
# 帧循环时间源、GL 像素回读截图（PPM，测试/示例工具，不进组件 API）。
#
# 证据口径：macOS SDL2/OpenGL 真实窗口已在 #61 之前实测（cross-platform
# plan §1）；Windows/Linux 证据见 README 支持矩阵。
#
# 依赖：Render::GL 的 TessellGL 绑定做像素回读；Platform 不依赖 Kit
# （硬不变量，AGENTS.md #1）。

require "./host"
require "../input/event"
require "../render/gl/gl_backend"

module Tessell
  module Platform
    module SDL2
      @[Link("SDL2")]
      lib LibSDL
        struct Keysym
          scancode : Int32
          sym : Int32
          mod : UInt16
          unused : UInt32
        end

        struct KeyboardEvent
          type : UInt32
          timestamp : UInt32
          window_id : UInt32
          state : UInt8
          repeat : UInt8
          padding2 : UInt8
          padding3 : UInt8
          keysym : Keysym
        end

        struct TextInputEvent
          type : UInt32
          timestamp : UInt32
          window_id : UInt32
          text : StaticArray(UInt8, 32)
        end

        struct MouseMotionEvent
          type : UInt32
          timestamp : UInt32
          window_id : UInt32
          which : UInt32
          state : UInt32
          x : Int32
          y : Int32
          xrel : Int32
          yrel : Int32
        end

        struct MouseButtonEvent
          type : UInt32
          timestamp : UInt32
          window_id : UInt32
          which : UInt32
          button : UInt8
          state : UInt8
          clicks : UInt8
          padding1 : UInt8
          x : Int32
          y : Int32
        end

        struct MouseWheelEvent
          type : UInt32
          timestamp : UInt32
          window_id : UInt32
          which : UInt32
          x : Int32
          y : Int32
          direction : UInt32
          precise_x : Float32
          precise_y : Float32
          mouse_x : Int32
          mouse_y : Int32
        end

        struct WindowEvent
          type : UInt32
          timestamp : UInt32
          window_id : UInt32
          event : UInt8
          padding1 : UInt8
          padding2 : UInt8
          padding3 : UInt8
          data1 : Int32
          data2 : Int32
        end

        # SDL_Event is a 56-byte union on 64-bit builds. We only read the first
        # word and cast to the concrete event structs above.
        struct Event
          type : UInt32
          padding : StaticArray(UInt8, 52)
        end

        fun SDL_Init(flags : UInt32) : Int32
        fun SDL_Quit : Void
        fun SDL_GetError : UInt8*
        fun SDL_CreateWindow(title : UInt8*, x : Int32, y : Int32,
                             w : Int32, h : Int32, flags : UInt32) : Void*
        fun SDL_DestroyWindow(window : Void*) : Void
        fun SDL_GetWindowSize(window : Void*, w : Int32*, h : Int32*) : Void
        fun SDL_GL_SetAttribute(attr : Int32, value : Int32) : Int32
        fun SDL_GL_CreateContext(window : Void*) : Void*
        fun SDL_GL_DeleteContext(context : Void*) : Void
        fun SDL_GL_MakeCurrent(window : Void*, context : Void*) : Int32
        fun SDL_GL_SetSwapInterval(interval : Int32) : Int32
        fun SDL_GL_SwapWindow(window : Void*) : Void
        fun SDL_GL_GetDrawableSize(window : Void*, w : Int32*, h : Int32*) : Void
        fun SDL_PollEvent(event : Event*) : Int32
        fun SDL_StartTextInput : Void
        fun SDL_StopTextInput : Void
        fun SDL_Delay(ms : UInt32) : Void
        fun SDL_GetTicks : UInt32
        fun SDL_GetClipboardText : UInt8*
        fun SDL_SetClipboardText(text : UInt8*) : Int32
        fun SDL_free(ptr : Void*) : Void
      end

      SDL_INIT_VIDEO           = 0x00000020_u32
      SDL_INIT_EVENTS          = 0x00004000_u32
      SDL_WINDOW_OPENGL        = 0x00000002_u32
      SDL_WINDOW_SHOWN         = 0x00000004_u32
      SDL_WINDOW_RESIZABLE     = 0x00000020_u32
      SDL_WINDOW_ALLOW_HIGHDPI = 0x00002000_u32
      SDL_WINDOWPOS_CENTERED   = 0x2FFF0000_u32

      SDL_QUIT                     = 0x100_u32
      SDL_WINDOWEVENT              = 0x200_u32
      SDL_KEYDOWN                  = 0x300_u32
      SDL_KEYUP                    = 0x301_u32
      SDL_TEXTINPUT                = 0x303_u32
      SDL_MOUSEMOTION              = 0x400_u32
      SDL_MOUSEBUTTONDOWN          = 0x401_u32
      SDL_MOUSEBUTTONUP            = 0x402_u32
      SDL_MOUSEWHEEL               = 0x403_u32
      SDL_WINDOWEVENT_CLOSE        = 0x0E_u32
      SDL_WINDOWEVENT_RESIZED      = 0x201_u32
      SDL_WINDOWEVENT_SIZE_CHANGED = 0x202_u32

      SDL_GL_DOUBLEBUFFER                  = 5_i32
      SDL_GL_DEPTH_SIZE                    = 6_i32
      SDL_GL_STENCIL_SIZE                  = 7_i32
      SDL_GL_CONTEXT_MAJOR_VERSION         = 17_i32
      SDL_GL_CONTEXT_MINOR_VERSION         = 18_i32
      SDL_GL_CONTEXT_PROFILE_MASK          = 21_i32
      SDL_GL_CONTEXT_PROFILE_COMPATIBILITY = 0x0002_i32

      KMOD_SHIFT = 0x0003_u16
      KMOD_CTRL  = 0x00C0_u16
      KMOD_ALT   = 0x0100_u16
      KMOD_GUI   = 0x0400_u16

      class SdlClipboard < Tessell::Platform::Clipboard
        def get : String?
          ptr = LibSDL.SDL_GetClipboardText
          return nil if ptr.null?
          text = String.new(ptr)
          LibSDL.SDL_free(ptr.as(Void*))
          text
        end

        def set(text : String) : Nil
          LibSDL.SDL_SetClipboardText(text.to_unsafe)
        end
      end

      # OpenGL 2.1 兼容宿主（plan §3.5：GLBackend 固定管线路径不变）。
      class Host < Tessell::Platform::Host
        getter window : Void*
        getter context : Void*
        getter logical_width : Int32
        getter logical_height : Int32
        getter drawable_width : Int32
        getter drawable_height : Int32

        def initialize(@title : String, width : Int32, height : Int32)
          unless LibSDL.SDL_Init(SDL_INIT_VIDEO | SDL_INIT_EVENTS) == 0
            raise "SDL_Init failed: #{String.new(LibSDL.SDL_GetError)}"
          end

          LibSDL.SDL_GL_SetAttribute(SDL_GL_DOUBLEBUFFER, 1)
          LibSDL.SDL_GL_SetAttribute(SDL_GL_DEPTH_SIZE, 0)
          LibSDL.SDL_GL_SetAttribute(SDL_GL_STENCIL_SIZE, 8)
          LibSDL.SDL_GL_SetAttribute(SDL_GL_CONTEXT_MAJOR_VERSION, 2)
          LibSDL.SDL_GL_SetAttribute(SDL_GL_CONTEXT_MINOR_VERSION, 1)
          LibSDL.SDL_GL_SetAttribute(SDL_GL_CONTEXT_PROFILE_MASK, SDL_GL_CONTEXT_PROFILE_COMPATIBILITY)

          @window = LibSDL.SDL_CreateWindow(title.to_unsafe,
            SDL_WINDOWPOS_CENTERED.to_i32, SDL_WINDOWPOS_CENTERED.to_i32,
            width, height, SDL_WINDOW_OPENGL | SDL_WINDOW_SHOWN |
                           SDL_WINDOW_RESIZABLE | SDL_WINDOW_ALLOW_HIGHDPI)
          if @window.null?
            LibSDL.SDL_Quit
            raise "SDL_CreateWindow failed: #{String.new(LibSDL.SDL_GetError)}"
          end

          @context = LibSDL.SDL_GL_CreateContext(@window)
          if @context.null?
            LibSDL.SDL_DestroyWindow(@window)
            LibSDL.SDL_Quit
            raise "SDL_GL_CreateContext failed: #{String.new(LibSDL.SDL_GetError)}"
          end
          LibSDL.SDL_GL_MakeCurrent(@window, @context)
          LibSDL.SDL_GL_SetSwapInterval(1)
          LibSDL.SDL_StartTextInput

          @logical_width, @logical_height, @drawable_width, @drawable_height = read_sizes
          @mouse_x = 0
          @mouse_y = 0
          @resize_pending = false
          @quit_requested = false
          @closed = false
          @clipboard = SdlClipboard.new
        end

        def title : String
          @title
        end

        def viewport : Tessell::Rect
          Tessell::Rect.new(0.0_f32, 0.0_f32, @logical_width.to_f32, @logical_height.to_f32)
        end

        def scale : Float32
          return 1.0_f32 if @logical_width <= 0
          (@drawable_width.to_f32 / @logical_width.to_f32).clamp(1.0_f32, 4.0_f32)
        end

        # 消费式 resize 通知（issue #61 X1）。
        def resized? : Bool
          v = @resize_pending
          @resize_pending = false
          v
        end

        def quit_requested? : Bool
          @quit_requested
        end

        def poll_events(sink : Array(Tessell::Input::Event)) : Bool
          return false if @closed || @quit_requested
          event = uninitialized LibSDL::Event
          while LibSDL.SDL_PollEvent(pointerof(event)) != 0
            case event.type
            when SDL_QUIT
              @quit_requested = true
              return false
            when SDL_WINDOWEVENT
              window_event = pointerof(event).as(LibSDL::WindowEvent*).value
              if window_event.event == SDL_WINDOWEVENT_CLOSE
                @quit_requested = true
                return false
              elsif window_event.event == SDL_WINDOWEVENT_RESIZED ||
                    window_event.event == SDL_WINDOWEVENT_SIZE_CHANGED
                @logical_width, @logical_height, @drawable_width, @drawable_height = read_sizes
                @resize_pending = true
              end
            when SDL_KEYDOWN
              key = pointerof(event).as(LibSDL::KeyboardEvent*).value
              if code = map_key(key.keysym.sym)
                sink << Tessell::Input::Event.key_down(code, modifiers(key.keysym.mod),
                  key.timestamp.to_i64, key.repeat != 0)
              end
            when SDL_KEYUP
              key = pointerof(event).as(LibSDL::KeyboardEvent*).value
              if code = map_key(key.keysym.sym)
                sink << Tessell::Input::Event.key_up(code, modifiers(key.keysym.mod),
                  key.timestamp.to_i64)
              end
            when SDL_TEXTINPUT
              text_event = pointerof(event).as(LibSDL::TextInputEvent*).value
              sink << Tessell::Input::Event.text_input(String.new(text_event.text.to_unsafe))
            when SDL_MOUSEMOTION
              motion = pointerof(event).as(LibSDL::MouseMotionEvent*).value
              @mouse_x = motion.x
              @mouse_y = motion.y
              sink << Tessell::Input::Event.pointer_move(motion.x.to_f32, motion.y.to_f32)
            when SDL_MOUSEBUTTONDOWN
              button = pointerof(event).as(LibSDL::MouseButtonEvent*).value
              @mouse_x = button.x
              @mouse_y = button.y
              sink << Tessell::Input::Event.pointer_down(button.x.to_f32, button.y.to_f32,
                button.button.to_i32 - 1, modifiers(0), button.timestamp.to_i64)
            when SDL_MOUSEBUTTONUP
              button = pointerof(event).as(LibSDL::MouseButtonEvent*).value
              @mouse_x = button.x
              @mouse_y = button.y
              sink << Tessell::Input::Event.pointer_up(button.x.to_f32, button.y.to_f32,
                button.button.to_i32 - 1, modifiers(0), button.timestamp.to_i64)
            when SDL_MOUSEWHEEL
              wheel = pointerof(event).as(LibSDL::MouseWheelEvent*).value
              sink << Tessell::Input::Event.wheel(@mouse_x.to_f32, @mouse_y.to_f32,
                wheel.x.to_f32 * 40.0_f32, wheel.y.to_f32 * 40.0_f32)
            end
          end
          true
        end

        def present : Nil
          LibSDL.SDL_GL_SwapWindow(@window) unless @closed
        end

        def make_current : Nil
          LibSDL.SDL_GL_MakeCurrent(@window, @context) unless @closed
        end

        def clipboard : Platform::Clipboard
          @clipboard
        end

        # SDL2 只稳定提供 SDL_TEXTINPUT（committed text）；预编辑 Unsupported。
        def ime : Platform::ImeSupport
          Platform::ImeSupport::CommittedText
        end

        def ticks_ms : Int64
          LibSDL.SDL_GetTicks.to_i64
        end

        def delay(ms : Int32) : Nil
          LibSDL.SDL_Delay(ms.to_u32) if ms > 0
        end

        def refresh_sizes : Nil
          @logical_width, @logical_height, @drawable_width, @drawable_height = read_sizes
        end

        # GL 像素回读截图（PPM；测试/示例工具口径，plan §3.3 明确不进组件 API）。
        def screenshot(path : String) : Nil
          return if @drawable_width <= 0 || @drawable_height <= 0
          w = @drawable_width
          h = @drawable_height
          rgba = Bytes.new(w * h * 4)
          TessellGL.glFinish
          TessellGL.glPixelStorei(TessellGL::GL_PACK_ALIGNMENT, 1)
          TessellGL.glReadPixels(0, 0, w, h, TessellGL::GL_RGBA,
            TessellGL::GL_UNSIGNED_BYTE, rgba.to_unsafe.as(Void*))
          rgb = Bytes.new(w * h * 3)
          y = 0
          while y < h
            src_row = (h - 1 - y) * w * 4
            dst_row = y * w * 3
            x = 0
            while x < w
              si = src_row + x * 4
              di = dst_row + x * 3
              rgb[di] = rgba[si]
              rgb[di + 1] = rgba[si + 1]
              rgb[di + 2] = rgba[si + 2]
              x += 1
            end
            y += 1
          end
          dir = File.dirname(path)
          Dir.mkdir_p(dir) unless dir.empty? || Dir.exists?(dir)
          File.open(path, "wb") do |io|
            io << "P6\n#{w} #{h}\n255\n"
            io.write(rgb)
          end
        end

        def close : Nil
          return if @closed
          @closed = true
          LibSDL.SDL_StopTextInput
          LibSDL.SDL_GL_DeleteContext(@context)
          LibSDL.SDL_DestroyWindow(@window)
          LibSDL.SDL_Quit
        end

        private def read_sizes : Tuple(Int32, Int32, Int32, Int32)
          lw = 0
          lh = 0
          dw = 0
          dh = 0
          LibSDL.SDL_GetWindowSize(@window, pointerof(lw), pointerof(lh))
          LibSDL.SDL_GL_GetDrawableSize(@window, pointerof(dw), pointerof(dh))
          lw = 1 if lw <= 0
          lh = 1 if lh <= 0
          dw = lw if dw <= 0
          dh = lh if dh <= 0
          {lw, lh, dw, dh}
        end

        private def key_timestamp(ts : UInt32) : Int64
          ts.to_i64
        end

        private def modifiers(mod : UInt16) : Tessell::Input::Modifiers
          Tessell::Input::Modifiers.new(
            shift: (mod & KMOD_SHIFT) != 0,
            ctrl: (mod & KMOD_CTRL) != 0,
            alt: (mod & KMOD_ALT) != 0,
            meta: (mod & KMOD_GUI) != 0)
        end

        private def map_key(sym : Int32) : Tessell::Input::KeyCode?
          case sym
          when 8             then Tessell::Input::KeyCode::Backspace
          when 9             then Tessell::Input::KeyCode::Tab
          when 13            then Tessell::Input::KeyCode::Enter
          when 27            then Tessell::Input::KeyCode::Escape
          when 32            then Tessell::Input::KeyCode::Space
          when 127           then Tessell::Input::KeyCode::Delete
          when 0x40000050    then Tessell::Input::KeyCode::Left
          when 0x4000004F    then Tessell::Input::KeyCode::Right
          when 0x40000052    then Tessell::Input::KeyCode::Up
          when 0x40000051    then Tessell::Input::KeyCode::Down
          when 0x4000004A    then Tessell::Input::KeyCode::Home
          when 0x4000004D    then Tessell::Input::KeyCode::End
          when 0x4000004B    then Tessell::Input::KeyCode::PageUp
          when 0x4000004E    then Tessell::Input::KeyCode::PageDown
          when 97            then Tessell::Input::KeyCode::KeyA
          when 98            then Tessell::Input::KeyCode::KeyB
          when 99            then Tessell::Input::KeyCode::KeyC
          when 116           then Tessell::Input::KeyCode::KeyT
          when 118           then Tessell::Input::KeyCode::KeyV
          when 120           then Tessell::Input::KeyCode::KeyX
          when 122           then Tessell::Input::KeyCode::KeyZ
          when 48            then Tessell::Input::KeyCode::Digit0
          when 49            then Tessell::Input::KeyCode::Digit1
          when 50            then Tessell::Input::KeyCode::Digit2
          when 51            then Tessell::Input::KeyCode::Digit3
          when 52            then Tessell::Input::KeyCode::Digit4
          when 53            then Tessell::Input::KeyCode::Digit5
          when 54            then Tessell::Input::KeyCode::Digit6
          when 55            then Tessell::Input::KeyCode::Digit7
          when 56            then Tessell::Input::KeyCode::Digit8
          when 57            then Tessell::Input::KeyCode::Digit9
          when 0x40000058    then Tessell::Input::KeyCode::F1
          when 0x40000059    then Tessell::Input::KeyCode::F2
          when 0x4000005A    then Tessell::Input::KeyCode::F3
          when 0x4000005B    then Tessell::Input::KeyCode::F4
          else
            nil
          end
        end
      end
    end
  end
end
