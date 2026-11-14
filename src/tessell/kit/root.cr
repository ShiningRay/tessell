# Tessell::Kit::Root — 组件树宿主（K0）
#
# 职责：布局 → 声明 → UI.apply → Node/Component 映射 → 输入路由 → 绘制。
# 不新建平行焦点系统：焦点仍由核心 Input::Router/FocusManager 管，Kit 只做
# Node ↔ Component 映射与组件状态同步。

module Tessell
  module Kit
    class Root
      getter content : Component
      getter theme : Theme
      getter metrics : TextMetrics
      getter context : Context
      getter node : Node
      getter pool : UI::Pool
      getter router : Input::Router
      getter a11y : A11y::Builder

      @buf : Array(UI::Decl)
      @builder : UI::Builder
      @node_components : Hash(Node, Component)
      @component_roots : Hash(Node, Component)
      @component_nodes : Hash(Component, Node)
      @component_buf : Array(Component)
      @last_hover : Component?
      @focused_component : Component?

      def initialize(@content : Component, @theme : Theme = Theme.light,
                     @metrics : TextMetrics = StubTextMetrics.new,
                     viewport : Rect = Rect.new(0.0_f32, 0.0_f32, 800.0_f32, 600.0_f32),
                     scale : Float32 = 1.0_f32)
        @node = Node.new("kit-root", viewport)
        @pool = UI::Pool.new
        @buf = [] of UI::Decl
        @builder = UI::Builder.new(@buf, [] of UI::UiKey)
        @context = Context.new(@theme, @metrics, scale)
        @node_components = {} of Node => Component
        @component_roots = {} of Node => Component
        @component_nodes = {} of Component => Node
        @component_buf = [] of Component
        @last_hover = nil
        @focused_component = nil
        @router = Input::Router.new do |target|
          component = @component_roots[target]?
          component ? component.focusable? : false
        end
        @a11y = A11y::Builder.new(@router.focus_manager)
      end

      def layout(viewport : Rect) : Nil
        @node.bounds = viewport
        @content.arrange(@context, viewport)
      end

      def layout(width : Float32, height : Float32) : Nil
        layout(Rect.new(0.0_f32, 0.0_f32, width, height))
      end

      def build : Nil
        @builder.reset(UI::UiKey.root)
        @content.emit(@builder, @context)
        UI.apply(@builder.buf, @node, @pool, @a11y)
        rebuild_node_map
      end

      def paint(painter : Painter) : Nil
        @content.paint(painter, @context)
      end

      def a11y_emit(sink : Array(A11y::Node)) : Int32
        refresh_a11y_meta
        UI.a11y_emit(@node, @a11y, sink)
      end

      def theme=(theme : Theme) : Nil
        @theme = theme
        @context.theme = theme
      end

      def advance_time(now_ms : Int64) : Nil
        @context.advance_time(now_ms)
        @content.tick(now_ms, @context)
      end

      # 核心事件入口。优先使用 Event 自带的 modifiers；显式参数用于旧调用点。
      def handle(event : Input::Event, modifiers : Modifiers? = nil) : Bool
        mods = modifiers || event.modifiers
        if event.kind == Input::Event::Kind::KeyDown && event.key == Input::KeyCode::Tab
          if mods.shift
            @router.focus_manager.prev(@node)
          else
            @router.focus_manager.next(@node)
          end
          sync_focus
          return true
        end

        case event.kind
        when Input::Event::Kind::PointerEnter
          target = @router.handle(event, @node)
          component = target ? component_for_node(target) : nil
          sync_hover(component)
          true
        when Input::Event::Kind::PointerMove
          target = @router.handle(event, @node)
          component = target ? component_for_node(target) : nil
          sync_hover(component)
          return true if deliver(component, to_kit(event, Event::Kind::PointerMove, mods))
        when Input::Event::Kind::PointerLeave
          @router.handle(event, @node)
          sync_hover(nil)
          true
        when Input::Event::Kind::PointerDown
          target = @router.handle(event, @node)
          component = target ? component_for_node(target) : nil
          focus_component(component)
          sync_focus
          return true if deliver(component, to_kit(event, Event::Kind::PointerDown, mods))
        when Input::Event::Kind::PointerUp
          target = @router.handle(event, @node)
          component = target ? component_for_node(target) : nil
          sync_focus
          return true if deliver(component, to_kit(event, Event::Kind::PointerUp, mods))
        when Input::Event::Kind::PointerCancel
          target = @router.handle(event, @node)
          component = target ? component_for_node(target) : nil
          return true if deliver(component, to_kit(event, Event::Kind::PointerCancel, mods))
        when Input::Event::Kind::Wheel
          target = @router.handle(event, @node)
          component = target ? component_for_node(target) : nil
          return true if deliver(component, to_kit(event, Event::Kind::Wheel, mods))
        when Input::Event::Kind::KeyDown
          target = @router.handle(event, @node)
          component = target ? component_for_node(target) : nil
          return true if deliver(component, to_kit(event, Event::Kind::KeyDown, mods))
        when Input::Event::Kind::KeyUp
          target = @router.handle(event, @node)
          component = target ? component_for_node(target) : nil
          return true if deliver(component, to_kit(event, Event::Kind::KeyUp, mods))
        when Input::Event::Kind::TextInput
          target = @router.handle(event, @node)
          component = target ? component_for_node(target) : nil
          return true if deliver(component, to_kit(event, Event::Kind::TextInput, mods))
        when Input::Event::Kind::Blur
          old = @router.focus_manager.focused
          @router.handle(event, @node)
          if old
            component_for_node(old).try(&.handle(Event.blur, @context))
          end
          sync_focus
          return true
        end
        false
      end

      def focused_component : Component?
        @focused_component
      end

      def hover_component : Component?
        @last_hover
      end

      def component_for_node(target : Node) : Component?
        current : Node? = target
        while current
          if component = @node_components[current]?
            return component
          end
          current = current.parent
        end
        nil
      end

      private def rebuild_node_map : Nil
        @node_components.clear
        @component_roots.clear
        @component_nodes.clear
        @component_buf.clear
        @content.collect_components(@component_buf)
        @component_buf.each do |component|
          if target = @pool.map[component.key]?
            target.clip = component.clip_bounds
            @node_components[target] = component
            @component_roots[target] = component
            @component_nodes[component] = target
            @a11y.set_meta(target.object_id.to_u64, component.a11y_role,
              component.a11y_name, component.a11y_value, component.focusable?,
              component.a11y_enabled, component.a11y_children_count,
              component.a11y_scroll_offset)
          end
        end
      end

      private def focus_component(component : Component?) : Nil
        current = component
        while current
          if current.focusable?
            if target = @component_nodes[current]?
              @router.focus_manager.focus(target)
            end
            return
          end
          current = current.parent
        end
      end

      private def refresh_a11y_meta : Nil
        @component_buf.each do |component|
          if target = @component_nodes[component]?
            @a11y.set_meta(target.object_id.to_u64, component.a11y_role,
              component.a11y_name, component.a11y_value, component.focusable?,
              component.a11y_enabled, component.a11y_children_count,
              component.a11y_scroll_offset)
          end
        end
      end

      private def sync_focus : Nil
        new_component = component_for_node?(@router.focus_manager.focused)
        return if new_component == @focused_component
        @focused_component.try(&.on_focus_changed(false))
        @focused_component = new_component
        new_component.try(&.on_focus_changed(true))
      end

      private def sync_hover(component : Component?) : Nil
        return if component == @last_hover
        @last_hover.try(&.handle(Event.new(Event::Kind::PointerLeave), @context))
        @last_hover = component
        component.try(&.handle(Event.new(Event::Kind::PointerEnter), @context))
      end

      private def component_for_node?(target : Node?) : Component?
        target ? component_for_node(target) : nil
      end

      private def deliver(component : Component?, event : Event) : Bool
        current = component
        while current
          return true if current.handle(event, @context)
          current = current.parent
        end
        false
      end

      private def to_kit(event : Input::Event, kind : Event::Kind,
                         modifiers : Modifiers) : Event
        Event.new(kind, event.x, event.y, event.button,
          map_key(event.key), event.text, modifiers,
          event.wheel_dx, event.wheel_dy)
      end

      private def map_key(key : Input::KeyCode?) : Key?
        return nil unless key
        case key
        when Input::KeyCode::Tab       then Key::Tab
        when Input::KeyCode::Enter     then Key::Enter
        when Input::KeyCode::Escape    then Key::Escape
        when Input::KeyCode::Space     then Key::Space
        when Input::KeyCode::Left      then Key::Left
        when Input::KeyCode::Right     then Key::Right
        when Input::KeyCode::Up        then Key::Up
        when Input::KeyCode::Down      then Key::Down
        when Input::KeyCode::Home      then Key::Home
        when Input::KeyCode::End       then Key::End
        when Input::KeyCode::PageUp    then Key::PageUp
        when Input::KeyCode::PageDown  then Key::PageDown
        when Input::KeyCode::Backspace then Key::Backspace
        when Input::KeyCode::Delete    then Key::Delete
        when Input::KeyCode::KeyA      then Key::KeyA
        when Input::KeyCode::KeyB      then Key::KeyB
        when Input::KeyCode::KeyC      then Key::KeyC
        when Input::KeyCode::KeyV      then Key::KeyV
        when Input::KeyCode::KeyX      then Key::KeyX
        when Input::KeyCode::KeyZ      then Key::KeyZ
        else
          Key::Unknown
        end
      end
    end
  end
end
