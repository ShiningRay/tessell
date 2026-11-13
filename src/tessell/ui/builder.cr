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
  struct Decl
    getter key : UiKey
    getter parent : UiKey
    getter kind : DeclKind
    getter text : String
    getter bounds : Rect
    getter direction : Layout::Direction
    getter paint : UInt32
    getter a11y_role : A11y::Role
    getter a11y_name : String
    getter a11y_value : String
    getter a11y_focusable : Bool
    getter a11y_enabled : Bool

    def initialize(@key : UiKey, @parent : UiKey, @kind : DeclKind,
                   @text : String = "", @bounds : Rect = Rect.new,
                   @direction : Layout::Direction = Layout::Direction::Vertical,
                   @paint : UInt32 = 0_u32,
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
  end

  # Build declarations into caller-provided reusable buffers.
  # Usage: UI.build(root_key, builder) { |b| b.text(k, "hi") }
  def self.build(root : UiKey, b : Builder, & : Builder ->) : Nil
    b.reset(root)
    yield b
  end
end

require "./apply"
