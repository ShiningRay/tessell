require "./spec_helper"

describe Tessell::Text::FontSet do
  it "resolves CJK codepoint to msyh" do
    fs = Tessell::Text::FontSet.new
    msyh = Tessell::Text::FontRef.new(
      "C:/Windows/Fonts/msyh.ttc", 0, "msyh",
      [0x4E00_u32..0x9FFF_u32]
    )
    emoji = Tessell::Text::FontRef.new(
      "C:/Windows/Fonts/seguiemj.ttf", 0, "seguiemj",
      [0x1F600_u32..0x1F64F_u32]
    )
    fs.add(msyh)
    fs.add(emoji)
    fs.resolve(0x4E2D_u32).should eq(0) # 中
    fs.font_count.should eq(2)
  end

  it "resolves emoji U+1F600 and U+1F44D to seguiemj" do
    fs = Tessell::Text::FontSet.new
    msyh = Tessell::Text::FontRef.new(
      "C:/Windows/Fonts/msyh.ttc", 0, "msyh",
      [0x4E00_u32..0x9FFF_u32]
    )
    emoji = Tessell::Text::FontRef.new(
      "C:/Windows/Fonts/seguiemj.ttf", 0, "seguiemj",
      [0x1F300_u32..0x1FAFF_u32]
    )
    fs.add(msyh)
    fs.add(emoji)
    fs.resolve(0x1F600_u32).should eq(1) # 😀
    fs.resolve(0x1F44D_u32).should eq(1) # 👍
  end

  it "returns -1 for uncovered codepoint" do
    fs = Tessell::Text::FontSet.new
    fs.add(Tessell::Text::FontRef.new(
      "C:/Windows/Fonts/msyh.ttc", 0, "msyh",
      [0x4E00_u32..0x9FFF_u32]
    ))
    fs.resolve(0x0041_u32).should eq(-1) # 'A'
    fs.resolve(0x1F600_u32).should eq(-1)
  end

  it "returns -1 for empty FontSet" do
    fs = Tessell::Text::FontSet.new
    fs.font_count.should eq(0)
    fs.resolve(0x0041_u32).should eq(-1)
    fs.resolve(0x1F600_u32).should eq(-1)
  end

  it "uses first covering font when ranges overlap" do
    fs = Tessell::Text::FontSet.new
    first = Tessell::Text::FontRef.new(
      "A.ttf", 0, "first",
      [0x0041_u32..0x007A_u32]
    )
    second = Tessell::Text::FontRef.new(
      "B.ttf", 0, "second",
      [0x0061_u32..0x007A_u32] # overlaps a-z
    )
    fs.add(first)
    fs.add(second)
    fs.resolve(0x0061_u32).should eq(0) # 'a' covered by both, first wins
    fs.resolve(0x0041_u32).should eq(0) # 'A' only in first
  end

  it "matches boundary codepoints (start/end) and rejects end+1" do
    fs = Tessell::Text::FontSet.new
    f = Tessell::Text::FontRef.new(
      "X.ttf", 0, "x",
      [0x0100_u32..0x01FF_u32]
    )
    fs.add(f)
    fs.resolve(0x0100_u32).should eq(0) # start
    fs.resolve(0x01FF_u32).should eq(0) # end
    fs.resolve(0x00FF_u32).should eq(-1) # start-1
    fs.resolve(0x0200_u32).should eq(-1) # end+1
  end
end
