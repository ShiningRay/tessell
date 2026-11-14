require "./spec_helper"

# issue #21：DrawList 的 Text 命令携带文本内容与字号。
# 此前 text 参数被整体丢弃，宿主只能另维护平行 batch 边界数组，编译期
# 无法发现错位。现在宿主只遍历这一份列表即可按命令序提交。

describe "DrawCmd text payload (issue #21)" do
  it "carries text content, font size and clip on Text commands" do
    p = Tessell::Kit::DrawListPainter.new
    p.push_clip(Tessell::Rect.new(0.0_f32, 0.0_f32, 100.0_f32, 100.0_f32))
    p.text(10.0_f32, 20.0_f32, "Revenue", 0xff112233_u32, 14.0_f32)
    p.pop_clip

    cmd = p.list[0]
    cmd.kind.should eq(Tessell::Render::CmdKind::Text)
    cmd.text.should eq("Revenue")
    cmd.font_size.should eq(14.0_f32)
    cmd.bounds.origin.x.should eq(10.0_f32)
    cmd.bounds.origin.y.should eq(20.0_f32)
    cmd.clip.should eq(Tessell::Rect.new(0.0_f32, 0.0_f32, 100.0_f32, 100.0_f32))
    cmd.color.should eq(0xff112233_u32)
  end

  it "keeps non-text commands at empty payload defaults" do
    p = Tessell::Kit::DrawListPainter.new
    p.fill_rect(Tessell::Rect.new(0.0_f32, 0.0_f32, 4.0_f32, 4.0_f32), 0xff000000_u32)
    cmd = p.list[0]
    cmd.text.should eq("")
    cmd.font_size.should eq(0.0_f32)
  end

  it "exposes text_commands as a read-only view over the list" do
    p = Tessell::Kit::DrawListPainter.new
    p.fill_rect(Tessell::Rect.new(0.0_f32, 0.0_f32, 4.0_f32, 4.0_f32), 0xff000000_u32)
    p.text(1.0_f32, 2.0_f32, "a", 0xff000000_u32, 12.0_f32)
    p.fill_rect(Tessell::Rect.new(0.0_f32, 0.0_f32, 4.0_f32, 4.0_f32), 0xff000000_u32)
    p.text(3.0_f32, 4.0_f32, "b", 0xff000000_u32, 12.0_f32)

    texts = p.list.text_commands
    texts.size.should eq(2)
    texts.map(&.text).should eq(["a", "b"])
    texts.all? { |c| c.kind == Tessell::Render::CmdKind::Text }.should be_true
  end

  it "lets a host submit purely from the command list (no parallel arrays)" do
    # 宿主视角演练：按命令序遍历，文本内容从命令本身读取。
    p = Tessell::Kit::DrawListPainter.new
    p.fill_rect(Tessell::Rect.new(0.0_f32, 0.0_f32, 4.0_f32, 4.0_f32), 0xff000000_u32)
    p.text(1.0_f32, 2.0_f32, "hello", 0xff000000_u32, 12.0_f32)
    p.fill_rect(Tessell::Rect.new(0.0_f32, 0.0_f32, 4.0_f32, 4.0_f32), 0xff000000_u32)

    submitted = [] of String
    list = p.list
    i = 0
    while i < list.size
      cmd = list[i]
      submitted << "text:#{cmd.text}@#{cmd.font_size}" if cmd.kind == Tessell::Render::CmdKind::Text
      i += 1
    end
    submitted.should eq(["text:hello@12.0"])
  end
end
