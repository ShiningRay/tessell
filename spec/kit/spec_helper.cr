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
