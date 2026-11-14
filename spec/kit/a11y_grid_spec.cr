require "./spec_helper"

# issue #31：二维网格 a11y 语义——Role 补 Grid/GridCell/RowHeader/ColumnHeader，
# Meta/Node 补结构化二维字段。虚拟化大控件不再把坐标拼进 value 字符串。

private class GridProbe < Tessell::Kit::Component
  def measure(ctx : Tessell::Kit::Context, constraints : Tessell::Constraints) : Tessell::Size
    Tessell::Size.new(constraints.max_width, 200.0_f32)
  end

  def emit(b : Tessell::UI::Builder, ctx : Tessell::Kit::Context) : Nil
    b.node(@key, Tessell::Rect.new(0.0_f32, 0.0_f32, 200.0_f32, 200.0_f32))
  end

  def a11y_role : Tessell::A11y::Role
    Tessell::A11y::Role::Grid
  end

  def a11y_name : String
    "Sheet grid"
  end

  def a11y_row_count : Int32?
    200
  end

  def a11y_col_count : Int32?
    26
  end

  def a11y_first_visible_index : Int32?
    52 # 可视起点 (2,0)
  end
end

private class CellProbe < Tessell::Kit::Component
  def measure(ctx : Tessell::Kit::Context, constraints : Tessell::Constraints) : Tessell::Size
    Tessell::Size.new(constraints.max_width, 24.0_f32)
  end

  def emit(b : Tessell::UI::Builder, ctx : Tessell::Kit::Context) : Nil
    b.node(@key, Tessell::Rect.new(0.0_f32, 0.0_f32, 60.0_f32, 24.0_f32))
  end

  def a11y_role : Tessell::A11y::Role
    Tessell::A11y::Role::GridCell
  end

  def a11y_name : String
    "42"
  end

  def a11y_row : Int32?
    3
  end

  def a11y_col : Int32?
    1
  end

  def a11y_row_index_text : String?
    "4"
  end

  def a11y_col_index_text : String?
    "B"
  end

  def a11y_selected : Bool?
    true
  end

  def a11y_active_cell : Bool?
    true
  end
end

private class HeaderProbe < Tessell::Kit::Component
  def measure(ctx : Tessell::Kit::Context, constraints : Tessell::Constraints) : Tessell::Size
    Tessell::Size.new(constraints.max_width, 20.0_f32)
  end

  def emit(b : Tessell::UI::Builder, ctx : Tessell::Kit::Context) : Nil
    b.node(@key, Tessell::Rect.new(0.0_f32, 0.0_f32, 60.0_f32, 20.0_f32))
  end

  def a11y_role : Tessell::A11y::Role
    Tessell::A11y::Role::ColumnHeader
  end

  def a11y_col_index_text : String?
    "A"
  end
end

describe "A11y 2D grid semantics (issue #31)" do
  it "emits Grid/GridCell/Header roles with structured 2D fields" do
    grid = GridProbe.new(KitSpecHelpers.key.child(1_u64))
    cell = CellProbe.new(KitSpecHelpers.key.child(2_u64))
    header = HeaderProbe.new(KitSpecHelpers.key.child(3_u64))
    col = Tessell::Kit::Column.new(KitSpecHelpers.key, Tessell::Insets.all(0.0_f32), 0.0_f32)
      .tap do |c|
        c.add(grid)
        c.add(cell)
        c.add(header)
      end
    root = Tessell::Kit::Root.new(col)
    root.layout(300.0_f32, 300.0_f32)
    root.build

    sink = [] of Tessell::A11y::Node
    root.a11y_emit(sink).should be >= 3

    g = sink.find { |n| n.role == Tessell::A11y::Role::Grid }
    g.should_not be_nil
    grid_node = g.not_nil!
    grid_node.row_count.should eq(200)
    grid_node.col_count.should eq(26)
    grid_node.first_visible_index.should eq(52)
    grid_node.row.should be_nil

    c = sink.find { |n| n.role == Tessell::A11y::Role::GridCell }
    c.should_not be_nil
    cell_node = c.not_nil!
    cell_node.row.should eq(3)
    cell_node.col.should eq(1)
    cell_node.row_index_text.should eq("4")
    cell_node.col_index_text.should eq("B")
    cell_node.selected.should eq(true)
    cell_node.active.should eq(true)

    h = sink.find { |n| n.role == Tessell::A11y::Role::ColumnHeader }
    h.should_not be_nil
    h.not_nil!.col_index_text.should eq("A")
  end

  it "keeps non-grid components untouched (nil 2D fields)" do
    button = Tessell::Kit::Button.new(KitSpecHelpers.key, "Save")
    root = Tessell::Kit::Root.new(button)
    root.layout(200.0_f32, 100.0_f32)
    root.build

    sink = [] of Tessell::A11y::Node
    root.a11y_emit(sink)
    btn = sink.find { |n| n.role == Tessell::A11y::Role::Button }
    btn.should_not be_nil
    b = btn.not_nil!
    b.row.should be_nil
    b.col.should be_nil
    b.row_count.should be_nil
    b.col_count.should be_nil
    b.selected.should be_nil
    b.active.should be_nil
    b.first_visible_index.should be_nil
  end

  it "reports the virtual-list container with first_visible_index" do
    fetch = ->(i : Int32) { nil }
    list = Tessell::Widgets::VirtualList.new(10_000, 24, 240, fetch, 100)
    sink = [] of Tessell::A11y::Node
    a11y = Tessell::A11y::Builder.new
    node = Tessell::Node.new("vl", Tessell::Rect.new(0.0_f32, 0.0_f32, 100.0_f32, 240.0_f32))
    count = Tessell::UI.a11y_emit(node, a11y, sink, list, node,
      name_for: ->(i : Int32) { "row #{i}" })
    count.should be >= 1
    container = sink[0]
    container.children_count.should eq(10_000)
    container.first_visible_index.should eq(0)
  end
end
