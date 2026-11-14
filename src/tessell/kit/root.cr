# Tessell::Kit::Root — 组件树宿主（K0–K3）
#
# 职责：布局 → 声明 → UI.apply → Node/Component 映射 → 输入路由 → 绘制。
# 不新建平行焦点系统：焦点仍由核心 Tessell::Input::Router/FocusManager 管，Kit 只做
# Node ↔ Component 映射与组件状态同步。
# Overlay：Root 持有 OverlayHost；模态屏障、焦点圈定/恢复、Tooltip 延迟在这里统一处理。

module Tessell
  module Kit
    class Root
      getter content : Component
      getter theme : Theme
      getter metrics : TextMetrics
      getter context : Context
      getter node : Node
      getter pool : UI::Pool
      getter router : Tessell::Input::Router
      getter a11y : A11y::Builder
      getter overlay_host : OverlayHost

      @buf : Array(UI::Decl)
      @builder : UI::Builder
      @node_components : Hash(Node, Component)
      @component_roots : Hash(Node, Component)
      @component_nodes : Hash(Component, Node)
      @component_buf : Array(Component)
      @last_hover : Component?
      @focused_component : Component?
      @viewport : Rect
      @overlay_focus_before : Hash(OverlayEntry, Node?)
      @pending_focus_entry : OverlayEntry?
      @tooltip_owner : Component?
      @tooltip_due_ms : Int64
      @tooltip_entry : OverlayEntry?
      @debug_overlay : DebugOverlay
      @debug_info : DebugInfo?

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
        @viewport = viewport
        @overlay_focus_before = {} of OverlayEntry => Node?
        @pending_focus_entry = nil
        @tooltip_owner = nil
        @tooltip_due_ms = 0_i64
        @tooltip_entry = nil
        @debug_overlay = DebugOverlay.new
        @debug_info = nil
        @router = Tessell::Input::Router.new do |target|
          component = @component_roots[target]?
          component ? component.focusable? : false
        end
        @a11y = A11y::Builder.new(@router.focus_manager)
        @overlay_host = OverlayHost.new(viewport)
        @overlay_host.context = @context
        @overlay_host.on_open = ->(entry : OverlayEntry) { handle_overlay_open(entry) }
        @overlay_host.on_close = ->(entry : OverlayEntry) { handle_overlay_close(entry) }
        @context.overlay_host = @overlay_host
      end

      def layout(viewport : Rect) : Nil
        @viewport = viewport
        @node.bounds = viewport
        @content.arrange(@context, viewport)
        @overlay_host.layout(@context, viewport)
      end

      def layout(width : Float32, height : Float32) : Nil
        layout(Rect.new(0.0_f32, 0.0_f32, width, height))
      end

      def build : Nil
        @builder.reset(UI::UiKey.root)
        @content.emit(@builder, @context)
        @overlay_host.entries.each do |entry|
          entry.barrier.try(&.emit(@builder, @context))
          entry.component.emit(@builder, @context)
        end
        UI.apply(@builder.buf, @node, @pool, @a11y)
        rebuild_node_map
        apply_pending_overlay_focus
      end

      def paint(painter : Painter) : Nil
        @content.paint(painter, @context)
        @overlay_host.entries.each do |entry|
          entry.barrier.try(&.paint(painter, @context))
          entry.component.paint(painter, @context)
        end
        @debug_overlay.paint(painter, @context, @debug_info, @viewport) if @debug_overlay.visible
      end

      # 帧调试 overlay（issue #11）：宿主每帧塞入 DebugInfo，F1 开关显示。
      def debug_info=(info : DebugInfo?) : Nil
        @debug_info = info
      end

      def debug_info : DebugInfo?
        @debug_info
      end

      def debug_overlay : DebugOverlay
        @debug_overlay
      end

      def a11y_emit(sink : Array(A11y::Node)) : Int32
        refresh_a11y_meta
        UI.a11y_emit(@node, @a11y, sink)
      end

      def theme=(theme : Theme) : Nil
        @theme = theme
        @context.theme = theme
        @overlay_host.layout(@context, @viewport)
      end

      def advance_time(now_ms : Int64) : Nil
        @context.advance_time(now_ms)
        @content.tick(now_ms, @context)
        @overlay_host.entries.each { |entry| entry.component.tick(now_ms, @context) }
        update_tooltip(now_ms)
      end

      def open_dialog(dialog : Dialog) : OverlayEntry
        entry = OverlayEntry.new(dialog, OverlayKind::Dialog, modal: true,
          center: true, dismiss_on_outside: true, dismiss_on_escape: true,
          dismiss_on_blur: false, margin: 24.0_f32)
        entry.on_close = -> { dialog.on_close.try(&.call) }
        @overlay_host.open(entry)
        entry
      end

      def close_overlay(entry : OverlayEntry) : Bool
        @overlay_host.close(entry)
      end

      def close_all_overlays : Nil
        while entry = @overlay_host.top
          close_overlay(entry)
        end
      end

      # 核心事件入口。优先使用 Event 自带的 modifiers；显式参数用于旧调用点。
      def handle(event : Tessell::Input::Event, modifiers : Modifiers? = nil) : Bool
        mods = modifiers || event.modifiers

        if event.kind == Tessell::Input::Event::Kind::KeyDown && event.key == Tessell::Input::KeyCode::Escape
          if entry = @overlay_host.top
            if entry.dismiss_on_escape
              close_overlay(entry)
              return true
            end
          end
        end

        if event.kind == Tessell::Input::Event::Kind::PointerDown
          if entry = @overlay_host.top
            if !entry.modal && entry.dismiss_on_outside &&
               !entry.contains?(Point.new(event.x, event.y))
              close_overlay(entry)
              return true
            end
          end
        end

        if event.kind == Tessell::Input::Event::Kind::Blur
          while entry = @overlay_host.top
            break unless entry.dismiss_on_blur
            close_overlay(entry)
          end
        end

        # F1：帧调试 overlay 开关（issue #11），优先于一切组件投递。
        if event.kind == Tessell::Input::Event::Kind::KeyDown && event.key == Tessell::Input::KeyCode::F1
          @debug_overlay.toggle
          return true
        end

        if event.kind == Tessell::Input::Event::Kind::KeyDown && event.key == Tessell::Input::KeyCode::Tab
          # issue #16：声明 wants_tab? 的焦点组件先拿到 Tab/Shift+Tab，消费即止；
          # 未声明或未消费再走焦点环。Ctrl/Meta+Tab 恒定走焦点环——组件吃掉
          # 普通 Tab 后键盘用户的退出路径。
          unless mods.ctrl || mods.meta
            if (focused = @focused_component) && focused.wants_tab?
              kit_tab = to_kit(event, Event::Kind::KeyDown, mods)
              return true if deliver(focused, kit_tab)
            end
          end
          scope = focus_scope_node
          if mods.shift
            @router.focus_manager.prev(scope)
          else
            @router.focus_manager.next(scope)
          end
          sync_focus
          return true
        end

        case event.kind
        when Tessell::Input::Event::Kind::PointerEnter
          target = @router.handle(event, @node)
          component = target ? component_for_node(target) : nil
          sync_hover(component)
          true
        when Tessell::Input::Event::Kind::PointerMove
          target = @router.handle(event, @node)
          component = target ? component_for_node(target) : nil
          sync_hover(component)
          return true if deliver(component, to_kit(event, Event::Kind::PointerMove, mods))
        when Tessell::Input::Event::Kind::PointerLeave
          @router.handle(event, @node)
          sync_hover(nil)
          true
        when Tessell::Input::Event::Kind::PointerDown
          target = @router.handle(event, @node)
          component = target ? component_for_node(target) : nil
          focus_component(component)
          sync_focus
          return true if deliver(component, to_kit(event, Event::Kind::PointerDown, mods))
        when Tessell::Input::Event::Kind::PointerUp
          target = @router.handle(event, @node)
          component = target ? component_for_node(target) : nil
          sync_focus
          return true if deliver(component, to_kit(event, Event::Kind::PointerUp, mods))
        when Tessell::Input::Event::Kind::PointerCancel
          target = @router.handle(event, @node)
          component = target ? component_for_node(target) : nil
          return true if deliver(component, to_kit(event, Event::Kind::PointerCancel, mods))
        when Tessell::Input::Event::Kind::Wheel
          target = @router.handle(event, @node)
          component = target ? component_for_node(target) : nil
          return true if deliver(component, to_kit(event, Event::Kind::Wheel, mods))
        when Tessell::Input::Event::Kind::KeyDown
          target = @router.handle(event, @node)
          component = target ? component_for_node(target) : nil
          return true if deliver(component, to_kit(event, Event::Kind::KeyDown, mods))
        when Tessell::Input::Event::Kind::KeyUp
          target = @router.handle(event, @node)
          component = target ? component_for_node(target) : nil
          return true if deliver(component, to_kit(event, Event::Kind::KeyUp, mods))
        when Tessell::Input::Event::Kind::TextInput
          target = @router.handle(event, @node)
          component = target ? component_for_node(target) : nil
          return true if deliver(component, to_kit(event, Event::Kind::TextInput, mods))
        when Tessell::Input::Event::Kind::Blur
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

      # 程序化聚焦：组件必须已经 build 过（Root#build 建立了 Node 映射）。
      def focus(component : Component) : Bool
        if target = @component_nodes[component]?
          @router.focus_manager.focus(target)
          sync_focus
          true
        else
          false
        end
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
        @overlay_host.entries.each do |entry|
          entry.component.collect_components(@component_buf)
          entry.barrier.try(&.collect_components(@component_buf))
        end
        @component_buf.each do |component|
          if target = @pool.map[component.key]?
            target.clip = component.clip_bounds
            @node_components[target] = component
            @component_roots[target] = component
            @component_nodes[component] = target
            write_a11y_meta(target, component)
          end
        end
      end

      private def write_a11y_meta(target : Node, component : Component) : Nil
        @a11y.set_meta(target.object_id.to_u64, component.a11y_role,
          component.a11y_name, component.a11y_value, component.focusable?,
          component.a11y_enabled, component.a11y_children_count,
          component.a11y_scroll_offset)
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
            write_a11y_meta(target, component)
          end
        end
      end

      # 焦点投递契约（issue #26）：
      #   组件间转移 A→B：A.on_focus_changed(false) → B.handle(Focus) → B.on_focus_changed(true)。
      #   窗口级失焦（Input::Event::Kind::Blur）：handle#blur 分支先 B/A.handle(Blur)，
      #   再经本方法 on_focus_changed(false)。Blur 事件语义 = 窗口失焦，转移不投递。
      # 两条路径的顺序都有 spec/kit/focus_events_spec.cr 锁住。
      private def sync_focus : Nil
        new_component = component_for_node?(@router.focus_manager.focused)
        return if new_component == @focused_component
        @focused_component.try(&.on_focus_changed(false))
        @focused_component = new_component
        if new_component
          new_component.handle(Event.focus, @context)
          new_component.on_focus_changed(true)
        end
      end

      private def sync_hover(component : Component?) : Nil
        return if component == @last_hover
        if entry = @tooltip_entry
          close_overlay(entry)
          @tooltip_entry = nil
        end
        @tooltip_owner = nil
        @last_hover.try(&.handle(Event.new(Event::Kind::PointerLeave), @context))
        @last_hover = component
        component.try(&.handle(Event.new(Event::Kind::PointerEnter), @context))
        if component && component.tooltip_text
          @tooltip_owner = component
          @tooltip_due_ms = @context.now_ms + component.tooltip_delay_ms
        end
      end

      private def update_tooltip(now_ms : Int64) : Nil
        return if @tooltip_entry
        owner = @tooltip_owner
        return unless owner
        return unless owner == @last_hover
        return if now_ms < @tooltip_due_ms
        text = owner.tooltip_text
        return unless text
        tooltip = Tooltip.new(owner.key.child(0x7001_u64), text)
        entry = OverlayEntry.new(tooltip, OverlayKind::Tooltip, owner: owner,
          anchor: owner.bounds, preferred: OverlaySide::Above, modal: false,
          dismiss_on_outside: true, dismiss_on_escape: true, gap: 6.0_f32)
        entry.on_close = -> { @tooltip_entry = nil }
        @tooltip_entry = entry
        @overlay_host.open(entry)
      end

      private def handle_overlay_open(entry : OverlayEntry) : Nil
        return if entry.kind == OverlayKind::Tooltip
        @overlay_focus_before[entry] = @router.focus_manager.focused
        @pending_focus_entry = entry
      end

      private def handle_overlay_close(entry : OverlayEntry) : Nil
        previous = @overlay_focus_before.delete(entry)
        if previous && attached?(previous.not_nil!)
          @router.focus_manager.focus(previous)
        elsif entry.kind != OverlayKind::Tooltip
          @router.focus_manager.blur
        end
        @tooltip_entry = nil if @tooltip_entry == entry
        sync_focus
      end

      private def apply_pending_overlay_focus : Nil
        entry = @pending_focus_entry
        return unless entry
        @pending_focus_entry = nil
        candidates = [] of Component
        entry.component.collect_components(candidates)
        candidates.each do |component|
          next unless component.focusable?
          if target = @component_nodes[component]?
            @router.focus_manager.focus(target)
            sync_focus
            return
          end
        end
        if target = @component_nodes[entry.component]?
          @router.focus_manager.focus(target)
          sync_focus
        end
      end

      private def focus_scope_node : Node
        if entry = @overlay_host.top_modal
          @component_nodes[entry.component]? || @node
        elsif entry = @overlay_host.top
          return @node if entry.kind == OverlayKind::Tooltip
          @component_nodes[entry.component]? || @node
        else
          @node
        end
      end

      private def attached?(node : Node) : Bool
        current : Node? = node
        while current
          return true if current == @node
          current = current.parent
        end
        false
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

      # Kit::Key 是 Input::KeyCode 的 alias（issue #27）：核心事件原样透传，
      # 不再经过手工映射表——映射表正是两套枚举漂移的源头。
      # 输入语义（issue #20）：click_count/drag_distance 只在 PointerUp 有效，
      # 读 Router 的点击判定结果；timestamp_ms/repeat 全 kind 透传。
      private def to_kit(event : Tessell::Input::Event, kind : Event::Kind,
                         modifiers : Modifiers) : Event
        if kind == Event::Kind::PointerUp
          Event.new(kind, event.x, event.y, event.button,
            event.key, event.text, modifiers,
            event.wheel_dx, event.wheel_dy,
            @router.last_click_count, event.timestamp_ms, event.repeat,
            @router.last_drag_distance)
        else
          Event.new(kind, event.x, event.y, event.button,
            event.key, event.text, modifiers,
            event.wheel_dx, event.wheel_dy,
            1, event.timestamp_ms, event.repeat, 0.0_f32)
        end
      end
    end
  end
end
