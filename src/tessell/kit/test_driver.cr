# Tessell::Kit::TestDriver — 面向用户的操作测试驱动（issue #59）。
#
# 借 NSGo nsgotest 的理念：同一套 press/type/focus/scroll 语义测试可跑
# headless（FakeHost 管道）也可在真实宿主直投组件层（合成输入不经 OS，
# 组件行为一致）——测试定义一次，两个后端执行（同一 journey proc）。
#
# selector 用组件现有 a11y 元数据（a11y_role / a11y_name）——「按用户
# 所见」定位；无匹配 / 多匹配（歧义）/ 禁用 / 不可见目标一律失败并给出
# 可定位诊断（列出当前树全部可见组件的 role+name）。
#
# 有界推进：FakeHost 后端走 inject → pump_frame（虚拟时钟，绝不 sleep）；
# Raw 后端直投 root.handle。失败时输出首个失败 step 与组件证据
# （可定位的 op/组件证据，不输出时间分布）。
#
# 不把 headless 执行当平台支持证据——真实平台行为仍按支持矩阵分级报告。

require "./root"
require "../input/event"

module Tessell
  module Kit
    class SelectorError < Exception
    end

    struct ComponentRef
      getter role : Tessell::A11y::Role
      getter name : String
      getter bounds : Rect
      getter enabled : Bool

      def initialize(@role : Tessell::A11y::Role, @name : String,
                     @bounds : Rect, @enabled : Bool)
      end
    end

    class TestDriver
      getter root : Root
      getter steps : Array(String)

      # 后端：:fake 走 FakeHost.inject → pump_frame → root.handle 完整管道；
      # :raw 直投 root.handle（真实宿主用——合成输入不经 OS）。
      def initialize(@root : Root, @host : Platform::Host? = nil,
                     @backend : Symbol = :raw)
        @steps = [] of String
      end

      # ---------- selector ----------

      def collect(sink : Array(ComponentRef)) : Nil
        buf = [] of Component
        @root.each_component { |c| buf << c }
        buf.each do |c|
          next unless c.visible
          sink << ComponentRef.new(c.a11y_role, c.a11y_name, c.bounds, c.enabled)
        end
      end

      def find(name : String,
               role : Tessell::A11y::Role? = nil) : Component
        buf = [] of Component
        @root.each_component { |c| buf << c }
        matches = buf.select do |c|
          c.visible && c.a11y_name == name && (role.nil? || c.a11y_role == role)
        end
        if matches.empty?
          listing = IO::Memory.new
          refs = [] of ComponentRef
          collect(refs)
          refs.each { |r| listing << "  #{r.role}: \"#{r.name}\"#{r.enabled ? "" : " [disabled]"}\n" }
          raise SelectorError.new("selector 无匹配 name=#{name.inspect} role=#{role ? role : "any"}；当前可见组件：\n#{listing}")
        end
        if matches.size > 1
          listing = matches.map { |c| "  #{c.a11y_role}: \"#{c.a11y_name}\" bounds=#{c.bounds}" }.join("\n")
          raise SelectorError.new("selector 歧义 name=#{name.inspect}：#{matches.size} 个匹配\n#{listing}")
        end
        c = matches.first
        unless c.enabled
          raise SelectorError.new("目标禁用 name=#{name.inspect}（#{c.a11y_role}）——禁用组件不可操作")
        end
        c
      end

      # ---------- 操作（有界推进，无 sleep）----------

      def press(name : String, role : Tessell::A11y::Role = Tessell::A11y::Role::Button) : Nil
        step("press #{role}:#{name.inspect}") do
          c = find(name, role)
          center = center_of(c.bounds)
          dispatch(Tessell::Input::Event.pointer_down(center.x, center.y, 0,
            Tessell::Input::Modifiers.none, timestamp_ms: now_ms))
          dispatch(Tessell::Input::Event.pointer_up(center.x, center.y, 0,
            Tessell::Input::Modifiers.none, timestamp_ms: now_ms + 30_i64))
        end
      end

      def focus(name : String) : Nil
        step("focus #{name.inspect}") do
          c = find(name)
          center = center_of(c.bounds)
          dispatch(Tessell::Input::Event.pointer_move(center.x, center.y))
          dispatch(Tessell::Input::Event.pointer_down(center.x, center.y, 0,
            Tessell::Input::Modifiers.none, timestamp_ms: now_ms))
          dispatch(Tessell::Input::Event.pointer_up(center.x, center.y, 0,
            Tessell::Input::Modifiers.none, timestamp_ms: now_ms + 30_i64))
        end
      end

      def type(text : String) : Nil
        step("type #{text.inspect}") do
          dispatch(Tessell::Input::Event.text_input(text, timestamp_ms: now_ms + 1_i64))
        end
      end

      def key(code : Tessell::Input::KeyCode, modifiers : Tessell::Input::Modifiers = Tessell::Input::Modifiers.none) : Nil
        step("key #{code}") do
          dispatch(Tessell::Input::Event.key_down(code, modifiers, timestamp_ms: now_ms + 1_i64))
          dispatch(Tessell::Input::Event.key_up(code, modifiers, timestamp_ms: now_ms + 11_i64))
        end
      end

      def scroll(x : Float32, y : Float32, dx : Float32, dy : Float32) : Nil
        step("scroll (#{x},#{y}) d=(#{dx},#{dy})") do
          dispatch(Tessell::Input::Event.wheel(x, y, dx, dy))
        end
      end

      # ---------- 断言（组件树证据，可定位）----------

      def assert_text(name : String, expected : String) : Nil
        step("assert text #{name.inspect}==#{expected.inspect}") do
          c = find(name, Tessell::A11y::Role::TextField)
          input = c.as?(Input)
          if input
            actual = input.text
            unless actual == expected
              raise SelectorError.new("断言失败 #{name.inspect}: text=#{actual.inspect} 期望 #{expected.inspect}")
            end
          else
            raise SelectorError.new("断言失败 #{name.inspect}: 不是 Kit::Input（#{c.class}）")
          end
        end
      end

      def steps_log : String
        @steps.join("\n")
      end

      # ---------- 内部 ----------

      private def step(label : String, &) : Nil
        begin
          yield
          @steps << "ok   #{label}"
        rescue e : SelectorError
          @steps << "FAIL #{label}"
          raise SelectorError.new("[step #{@steps.size}] #{e.message}\n已执行步骤：\n#{@steps.join("\n")}")
        end
      end

      private def center_of(bounds : Rect) : Point
        Point.new(bounds.origin.x + bounds.size.width / 2.0_f32,
          bounds.origin.y + bounds.size.height / 2.0_f32)
      end

      private def now_ms : Int64
        @host ? @host.not_nil!.ticks_ms : 0_i64
      end

      private def dispatch(event : Tessell::Input::Event) : Nil
        # :fake：走 FakeHost 完整管道（inject → pump_frame 虚拟时钟 →
        # root.handle），与组件契约 spec 同一口径，绝不 sleep。
        # 其余（含真实宿主）：合成输入直投组件层——不经 OS，组件行为一致。
        if @backend == :fake && @host.is_a?(Platform::FakeHost)
          host = @host.as(Platform::FakeHost)
          host.inject(event)
          host.pump_frame.each { |e| @root.handle(e) }
        else
          @root.handle(event)
        end
      end
    end
  end
end
