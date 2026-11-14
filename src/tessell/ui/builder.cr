require "../geometry"
require "../layout"
require "../a11y/tree"
require "./key"

module Tessell::UI
  enum DeclKind : UInt8
    Node   = 0
    Text   = 1
    Row    = 2
    Column = 3
  end

  # Flat declaration written by Builder into a caller-provided buffer.
  # Carries identity (key/parent), structure kind, text, geometry and a
  # paint token. Layout-affecting changes: kind, text, bounds, direction.
  # Paint-only change: paint token.
  # a11y_* fields carry the accessible metadata for this declaration; all of
  # them default so existing call sites keep working unchanged.
  #
  # Auto layout（issue #5）：auto=true 的声明不使用显式 bounds，由
  # `UI.apply_auto_layout` 依核心两遍内核（padding/gap/Fraction grow/
  # 文本测量）求解并把结果写回 Node.bounds——命中树与布局结果同源。
  # paint 是变更探测 token（状态变化时改变它触发 Paint 失效），不是颜色。
  struct Decl
    getter key : UiKey
    getter parent : UiKey
    getter kind : DeclKind
    getter text : String
    getter bounds : Rect
    getter direction : Layout::Direction
    getter paint : UInt32
    getter auto : Bool
    getter padding : Insets
    getter gap : Float32
    getter text_size : Float32
    getter a11y_role : A11y::Role
    getter a11y_name : String
    getter a11y_value : String
    getter a11y_focusable : Bool
    getter a11y_enabled : Bool

    def initialize(@key : UiKey, @parent : UiKey, @kind : DeclKind,
                   @text : String = "", @bounds : Rect = Rect.new,
                   @direction : Layout::Direction = Layout::Direction::Vertical,
                   @paint : UInt32 = 0_u32,
                   @auto : Bool = false,
                   @padding : Insets = Insets.new,
                   @gap : Float32 = 0.0_f32,
                   @text_size : Float32 = 0.0_f32,
                   @a11y_role : A11y::Role = A11y::Role::Group,
                   @a11y_name : String = "",
                   @a11y_value : String = "",
                   @a11y_focusable : Bool = false,
                   @a11y_enabled : Bool = true)
    end
  end

  # Chain builder that emits Decl records into preallocated buffers.
  # No Node is created and the hot build path performs no allocations when
  # buf and stack have sufficient pre-reserved capacity.
  class Builder
    getter buf : Array(Decl)
    getter stack : Array(UiKey)

    def initialize(@buf : Array(Decl), @stack : Array(UiKey))
      @depth = 0
    end

    def reset(root : UiKey) : Nil
      @buf.clear
      @depth = 0
      if @stack.size == 0
        @stack << root
      else
        @stack[0] = root
      end
    end

    def current_parent : UiKey
      @stack[@depth]
    end

    private def push_parent(k : UiKey) : Nil
      @depth += 1
      if @depth < @stack.size
        @stack[@depth] = k
      else
        @stack << k
      end
    end

    private def pop_parent : Nil
      @depth -= 1 if @depth > 0
    end

    private def emit(key : UiKey, kind : DeclKind, text : String,
                     bounds : Rect, dir : Layout::Direction,
                     paint : UInt32,
                     a11y_role : A11y::Role = A11y::Role::Group,
                     a11y_name : String = "",
                     a11y_value : String = "",
                     a11y_focusable : Bool = false,
                     a11y_enabled : Bool = true) : Nil
      @buf << Decl.new(key, current_parent, kind, text, bounds, dir, paint,
        false, Insets.new, 0.0_f32, 0.0_f32,
        a11y_role, a11y_name, a11y_value, a11y_focusable, a11y_enabled)
    end

    private def emit_auto(key : UiKey, kind : DeclKind, text : String,
                          dir : Layout::Direction, paint : UInt32,
                          padding : Insets, gap : Float32, text_size : Float32,
                          a11y_role : A11y::Role,
                          a11y_name : String,
                          a11y_value : String,
                          a11y_focusable : Bool,
                          a11y_enabled : Bool) : Nil
      @buf << Decl.new(key, current_parent, kind, text, Rect.new, dir, paint,
        true, padding, gap, text_size,
        a11y_role, a11y_name, a11y_value, a11y_focusable, a11y_enabled)
    end

    # Leaf/group node with explicit geometry and optional direction.
    def node(key : UiKey, bounds : Rect = Rect.new,
             dir : Layout::Direction = Layout::Direction::Vertical,
             paint : UInt32 = 0_u32,
             a11y_role : A11y::Role = A11y::Role::Group,
             a11y_name : String = "",
             a11y_value : String = "",
             a11y_focusable : Bool = false,
             a11y_enabled : Bool = true) : Nil
      emit(key, DeclKind::Node, "", bounds, dir, paint,
        a11y_role, a11y_name, a11y_value, a11y_focusable, a11y_enabled)
    end

    # Text leaf. Text change is layout-affecting.
    def text(key : UiKey, str : String, bounds : Rect = Rect.new,
             paint : UInt32 = 0_u32,
             a11y_role : A11y::Role = A11y::Role::Group,
             a11y_name : String = "",
             a11y_value : String = "",
             a11y_focusable : Bool = false,
             a11y_enabled : Bool = true) : Nil
      emit(key, DeclKind::Text, str, bounds, Layout::Direction::Vertical, paint,
        a11y_role, a11y_name, a11y_value, a11y_focusable, a11y_enabled)
    end

    # Directional container helpers. Optional direction argument; when a
    # block is given the container is nested.
    def row(key : UiKey, bounds : Rect = Rect.new, paint : UInt32 = 0_u32,
            dir : Layout::Direction = Layout::Direction::Horizontal,
            a11y_role : A11y::Role = A11y::Role::Group,
            a11y_name : String = "",
            a11y_value : String = "",
            a11y_focusable : Bool = false,
            a11y_enabled : Bool = true) : Nil
      emit(key, DeclKind::Row, "", bounds, dir, paint,
        a11y_role, a11y_name, a11y_value, a11y_focusable, a11y_enabled)
    end

    def row(key : UiKey, bounds : Rect = Rect.new, paint : UInt32 = 0_u32,
            dir : Layout::Direction = Layout::Direction::Horizontal,
            a11y_role : A11y::Role = A11y::Role::Group,
            a11y_name : String = "",
            a11y_value : String = "",
            a11y_focusable : Bool = false,
            a11y_enabled : Bool = true, & : Builder ->) : Nil
      emit(key, DeclKind::Row, "", bounds, dir, paint,
        a11y_role, a11y_name, a11y_value, a11y_focusable, a11y_enabled)
      push_parent(key)
      yield self
      pop_parent
    end

    def column(key : UiKey, bounds : Rect = Rect.new, paint : UInt32 = 0_u32,
               dir : Layout::Direction = Layout::Direction::Vertical,
               a11y_role : A11y::Role = A11y::Role::Group,
               a11y_name : String = "",
               a11y_value : String = "",
               a11y_focusable : Bool = false,
               a11y_enabled : Bool = true) : Nil
      emit(key, DeclKind::Column, "", bounds, dir, paint,
        a11y_role, a11y_name, a11y_value, a11y_focusable, a11y_enabled)
    end

    def column(key : UiKey, bounds : Rect = Rect.new, paint : UInt32 = 0_u32,
               dir : Layout::Direction = Layout::Direction::Vertical,
               a11y_role : A11y::Role = A11y::Role::Group,
               a11y_name : String = "",
               a11y_value : String = "",
               a11y_focusable : Bool = false,
               a11y_enabled : Bool = true, & : Builder ->) : Nil
      emit(key, DeclKind::Column, "", bounds, dir, paint,
        a11y_role, a11y_name, a11y_value, a11y_focusable, a11y_enabled)
      push_parent(key)
      yield self
      pop_parent
    end

  # Generic nested group.
  def group(key : UiKey, bounds : Rect = Rect.new,
            dir : Layout::Direction = Layout::Direction::Vertical,
            paint : UInt32 = 0_u32,
            a11y_role : A11y::Role = A11y::Role::Group,
            a11y_name : String = "",
            a11y_value : String = "",
            a11y_focusable : Bool = false,
            a11y_enabled : Bool = true, & : Builder ->) : Nil
    emit(key, DeclKind::Node, "", bounds, dir, paint,
      a11y_role, a11y_name, a11y_value, a11y_focusable, a11y_enabled)
    push_parent(key)
    yield self
    pop_parent
  end

  # ---- Auto layout 声明（issue #5）----
  # vstack/hstack 容器不写 bounds，由 UI.apply_auto_layout 依内核求解；
  # 子项可用 auto_text（测量定尺寸）或显式 bounds（Fixed）参与排布。
  def vstack(key : UiKey, padding : Insets = Insets.new, gap : Float32 = 0.0_f32,
             paint : UInt32 = 0_u32,
             a11y_role : A11y::Role = A11y::Role::Group,
             a11y_name : String = "",
             a11y_value : String = "",
             a11y_focusable : Bool = false,
             a11y_enabled : Bool = true, & : Builder ->) : Nil
    emit_auto(key, DeclKind::Column, "", Layout::Direction::Vertical, paint,
      padding, gap, 0.0_f32,
      a11y_role, a11y_name, a11y_value, a11y_focusable, a11y_enabled)
    push_parent(key)
    yield self
    pop_parent
  end

  def hstack(key : UiKey, padding : Insets = Insets.new, gap : Float32 = 0.0_f32,
             paint : UInt32 = 0_u32,
             a11y_role : A11y::Role = A11y::Role::Group,
             a11y_name : String = "",
             a11y_value : String = "",
             a11y_focusable : Bool = false,
             a11y_enabled : Bool = true, & : Builder ->) : Nil
    emit_auto(key, DeclKind::Row, "", Layout::Direction::Horizontal, paint,
      padding, gap, 0.0_f32,
      a11y_role, a11y_name, a11y_value, a11y_focusable, a11y_enabled)
    push_parent(key)
    yield self
    pop_parent
  end

  # 自动尺寸文本叶子：宽度/高度由注入的 Measurer 测量（Auto）。
  def auto_text(key : UiKey, str : String, size : Float32,
                paint : UInt32 = 0_u32,
                a11y_role : A11y::Role = A11y::Role::Group,
                a11y_name : String = "",
                a11y_value : String = "",
                a11y_focusable : Bool = false,
                a11y_enabled : Bool = true) : Nil
    emit_auto(key, DeclKind::Text, str, Layout::Direction::Vertical, paint,
      Insets.new, 0.0_f32, size,
      a11y_role, a11y_name, a11y_value, a11y_focusable, a11y_enabled)
  end

  # 自动尺寸叶子/容器节点（非文本）：宽高 Auto，可与 vstack/hstack 嵌套。
  def auto_node(key : UiKey, dir : Layout::Direction = Layout::Direction::Vertical,
                padding : Insets = Insets.new, gap : Float32 = 0.0_f32,
                paint : UInt32 = 0_u32,
                a11y_role : A11y::Role = A11y::Role::Group,
                a11y_name : String = "",
                a11y_value : String = "",
                a11y_focusable : Bool = false,
                a11y_enabled : Bool = true) : Nil
    emit_auto(key, DeclKind::Node, "", dir, paint,
      padding, gap, 0.0_f32,
      a11y_role, a11y_name, a11y_value, a11y_focusable, a11y_enabled)
  end
end

  # Build declarations into caller-provided reusable buffers.
  # Usage: UI.build(root_key, builder) { |b| b.text(k, "hi") }
  def self.build(root : UiKey, b : Builder, & : Builder ->) : Nil
    b.reset(root)
    yield b
  end
end

require "./apply"
