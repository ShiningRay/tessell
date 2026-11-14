require "spec"
require "../../src/tessell/kit"

module KitSpecHelpers
  def self.key(local : UInt64 = 1_u64) : Tessell::UI::UiKey
    Tessell::UI::UiKey.root.child(local)
  end

  def self.context(theme : Tessell::Kit::Theme = Tessell::Kit::Theme.light) : Tessell::Kit::Context
    Tessell::Kit::Context.new(theme, Tessell::Kit::StubTextMetrics.new)
  end
end

# issue #16 测试件：声明 wants_tab? 的组件，Tab 交给 on_tab 决定是否消费。
class TabEaterComponent < Tessell::Kit::Component
  property on_tab : Proc(Bool)?

  def initialize(key : Tessell::UI::UiKey)
    super(key)
  end

  def wants_tab? : Bool
    true
  end

  def focusable? : Bool
    true
  end

  def measure(ctx : Tessell::Kit::Context, constraints : Tessell::Constraints) : Tessell::Size
    constraints.constrain(Tessell::Size.new(200.0_f32, 40.0_f32))
  end

  def emit(b : Tessell::UI::Builder, ctx : Tessell::Kit::Context) : Nil
    b.node(@key, @bounds)
  end

  def handle(event : Tessell::Kit::Event, ctx : Tessell::Kit::Context) : Bool
    if event.kind == Tessell::Kit::Event::Kind::KeyDown && event.key == Tessell::Kit::Key::Tab
      cb = @on_tab
      return cb ? cb.call : false
    end
    false
  end
end

module KitSpecHelpers
  # issue #16：TabEater + Button 组成的双焦点 Column；返回 [tab_eater, button]。
  def self.tab_eater_column(key : Tessell::UI::UiKey) : Tuple(TabEaterComponent, Tessell::Kit::Button)
    eater = TabEaterComponent.new(key.child(1_u64))
    button = Tessell::Kit::Button.new(key.child(2_u64), "Next")
    col = Tessell::Kit::Column.new(key, Tessell::Insets.all(8.0_f32), 4.0_f32)
    col.add(eater)
    col.add(button)
    {eater, button}
  end
end
