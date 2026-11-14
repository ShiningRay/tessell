# Tessell Kit headless gallery (K2)
#
# 该示例不依赖 Win32/WGL，可在 macOS/Linux 上构建与运行：
#   crystal run examples/kit_gallery.cr -- --verify
#   crystal run examples/kit_gallery.cr -- --frames=60 --theme=dark --dpi=1.5
#
# 它验证组件状态、声明、a11y、绘制命令与虚拟列表；真实窗口上屏仍以 Windows
# 证据为准。参数与输出 token 见 docs/kit/execution.md。

require "../src/tessell/kit"

module KitGallery
  class App
    getter root : Tessell::Kit::Root
    getter buttons : Array(Tessell::Kit::Button)
    getter checkbox : Tessell::Kit::Checkbox
    getter list : Tessell::Kit::VirtualList
    getter clicks : Int32
    getter changes : Int32

    @clicks = 0
    @changes = 0

    def initialize(theme : Tessell::Kit::Theme, scale : Float32)
      @buttons = [] of Tessell::Kit::Button
      @clicks = 0
      @changes = 0

      column = Tessell::Kit::Column.new(
        Tessell::UI::UiKey.root.child(1_u64),
        Tessell::Insets.all(16.0_f32), 12.0_f32
      )
      title = Tessell::Kit::Text.new(
        Tessell::UI::UiKey.root.child(2_u64),
        "Tessell Kit Gallery",
        size: Tessell::Kit::ControlSize::Large
      )
      subtitle = Tessell::Kit::Text.new(
        Tessell::UI::UiKey.root.child(3_u64),
        "Headless component matrix: buttons, checkbox, virtual list",
        tone: Tessell::Kit::TextTone::Muted,
        size: Tessell::Kit::ControlSize::Small
      )
      column.add(title)
      column.add(subtitle)

      row = Tessell::Kit::Row.new(
        Tessell::UI::UiKey.root.child(4_u64),
        Tessell::Insets.new, 8.0_f32,
        Tessell::Kit::Alignment::Start
      )
      primary = Tessell::Kit::Button.new(
        Tessell::UI::UiKey.root.child(5_u64), "Primary",
        Tessell::Kit::Variant::Primary
      )
      secondary = Tessell::Kit::Button.new(
        Tessell::UI::UiKey.root.child(6_u64), "Secondary",
        Tessell::Kit::Variant::Secondary
      )
      ghost = Tessell::Kit::Button.new(
        Tessell::UI::UiKey.root.child(7_u64), "Ghost",
        Tessell::Kit::Variant::Ghost
      )
      danger = Tessell::Kit::Button.new(
        Tessell::UI::UiKey.root.child(8_u64), "Danger",
        Tessell::Kit::Variant::Danger
      )
      @buttons = [primary, secondary, ghost, danger]
      @buttons.each do |button|
        button.on_click = -> { @clicks += 1; nil }
        row.add(button)
      end
      column.add(row)

      @checkbox = Tessell::Kit::Checkbox.new(
        Tessell::UI::UiKey.root.child(9_u64), "Enable notifications"
      )
      @checkbox.on_change = ->(value : Bool) { @changes += 1; nil }
      column.add(@checkbox)

      @list = Tessell::Kit::VirtualList.new(
        Tessell::UI::UiKey.root.child(10_u64), 1000, 22,
        ->(index : Int32) { "Row #{index + 1}" }, name: "Gallery rows"
      )
      column.add(@list)

      @root = Tessell::Kit::Root.new(column, theme, Tessell::Kit::StubTextMetrics.new,
        Tessell::Rect.new(0.0_f32, 0.0_f32, 800.0_f32, 600.0_f32), scale)
    end

    def layout : Nil
      root.layout(800.0_f32, 600.0_f32)
    end

    def build : Nil
      root.build
    end

    def paint(painter : Tessell::Kit::Painter) : Nil
      root.paint(painter)
    end

    def verify_actions : Nil
      first = @buttons[0]
      x = first.bounds.origin.x + first.bounds.size.width / 2.0_f32
      y = first.bounds.origin.y + first.bounds.size.height / 2.0_f32
      root.handle(Tessell::Input::Event.pointer_down(x, y))
      root.handle(Tessell::Input::Event.pointer_up(x, y))

      cx = @checkbox.bounds.origin.x + 8.0_f32
      cy = @checkbox.bounds.origin.y + @checkbox.bounds.size.height / 2.0_f32
      root.handle(Tessell::Input::Event.pointer_down(cx, cy))
      root.handle(Tessell::Input::Event.pointer_up(cx, cy))

      @list.list.scroll_by(220)
      @list.on_focus_changed(true)
      @list.handle(Tessell::Kit::Event.key_down(Tessell::Kit::Key::End), root.context)
    end

    def node_count : Int32
      root.pool.active.size
    end
  end

  def self.run(args : Array(String)) : Int32
    frames = 1
    theme = Tessell::Kit::Theme.light
    scale = 1.0_f32
    verify = false

    args.each do |arg|
      if arg.starts_with?("--frames=")
        frames = arg.split("=")[1].to_i
      elsif arg.starts_with?("--theme=")
        theme = arg.split("=")[1] == "dark" ? Tessell::Kit::Theme.dark : Tessell::Kit::Theme.light
      elsif arg.starts_with?("--dpi=")
        scale = arg.split("=")[1].to_f32
      elsif arg == "--verify"
        verify = true
      end
    end

    app = App.new(theme, scale)
    app.layout
    app.build

    painter = Tessell::Kit::DrawListPainter.new
    app.paint(painter)
    paint_count = painter.list.size
    clip_depth = painter.clip_depth

    frames.times do
      app.build
      painter = Tessell::Kit::DrawListPainter.new
      app.paint(painter)
    end

    a11y = [] of Tessell::A11y::Node
    app.root.a11y_emit(a11y)
    node_count = app.node_count
    visible = app.list.list.visible_last - app.list.list.visible_first + 1

    if verify
      app.verify_actions
      app.build
      painter = Tessell::Kit::DrawListPainter.new
      app.paint(painter)
      a11y = [] of Tessell::A11y::Node
      app.root.a11y_emit(a11y)
      list_node = a11y.find { |n| n.role == Tessell::A11y::Role::List }
      rows = a11y.count { |n| n.role == Tessell::A11y::Role::ListItem }
      ok = app.clicks == 1 &&
           app.changes == 1 &&
           app.checkbox.checked &&
           app.list.list.scroll_y == app.list.list.total_height - app.list.list.viewport_h &&
           rows > 0 && rows < 30 &&
           list_node && list_node.children_count == 1000 &&
           painter.clip_depth == 0

      puts "KIT_GALLERY_VERIFY verify=#{ok ? "pass" : "fail"} frames=#{frames} " \
           "nodes=#{node_count} paint=#{paint_count} a11y=#{a11y.size} " \
           "visible=#{visible} rows=#{rows} clicks=#{app.clicks} changes=#{app.changes} " \
           "scroll=#{app.list.list.scroll_y} clip=#{clip_depth} " \
           "theme=#{theme.dark ? "dark" : "light"} dpi=#{scale}"
      return ok ? 0 : 1
    end

    puts "KIT_GALLERY frames=#{frames} nodes=#{node_count} paint=#{paint_count} " \
         "a11y=#{a11y.size} visible=#{visible} " \
         "theme=#{theme.dark ? "dark" : "light"} dpi=#{scale}"
    0
  end
end

exit KitGallery.run(ARGV)
