require "./spec_helper"

describe "Tessell::Kit::Graphemes" do
  it "returns byte boundaries for ASCII" do
    Tessell::Kit::Graphemes.boundaries("abc").should eq([0, 1, 2, 3])
    Tessell::Kit::Graphemes.count("abc").should eq(3)
  end

  it "keeps combining marks with their base" do
    text = "e\u0301"
    Tessell::Kit::Graphemes.boundaries(text).should eq([0, text.bytesize])
    Tessell::Kit::Graphemes.count(text).should eq(1)
  end

  it "keeps a ZWJ emoji family as one cluster" do
    text = "a👨‍👩‍👧‍👦b"
    Tessell::Kit::Graphemes.count(text).should eq(3)
    bounds = Tessell::Kit::Graphemes.boundaries(text)
    bounds.size.should eq(4)
  end

  it "keeps emoji modifiers, variation selectors, regional pairs and keycaps" do
    Tessell::Kit::Graphemes.count("👍🏽").should eq(1)
    Tessell::Kit::Graphemes.count("❤️").should eq(1)
    Tessell::Kit::Graphemes.count("🇨🇳").should eq(1)
    Tessell::Kit::Graphemes.count("1️⃣").should eq(1)
  end

  it "walks previous/next boundaries and clamps inside a cluster" do
    text = "a👍🏽b"
    bounds = Tessell::Kit::Graphemes.boundaries(text)
    middle = bounds[1] + 1
    Tessell::Kit::Graphemes.clamp(text, middle).should eq(bounds[1])
    Tessell::Kit::Graphemes.prev_boundary(bounds, bounds[2]).should eq(bounds[1])
    Tessell::Kit::Graphemes.next_boundary(bounds, bounds[1]).should eq(bounds[2])
  end
end
