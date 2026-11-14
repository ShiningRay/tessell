require "spec"
require "../../src/tessell/kit"

describe "Tessell::Kit optional entry" do
  it "can be required independently and exposes a version" do
    Tessell::Kit::VERSION.should eq(Tessell::VERSION)
  end

  it "is not aggregated by the core entry" do
    source = File.read(File.join(__DIR__, "..", "..", "src", "tessell.cr"))
    source.should_not contain("kit")
  end
end
