require "../geometry"
require "../layout"
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
  struct Decl
    getter key : UiKey
    getter parent : UiKey
    getter kind : DeclKind
    getter text : String
    getter bounds : Rect
    getter direction : Layout::Direction
    getter paint : UInt32

    def initialize(@key : UiKey, @parent : UiKey, @kind : DeclKind,
                   @text : String = "", @bounds : Rect = Rect.new,
                   @direction : Layout::Direction = Layout::Direction::Vertical,
                   @paint : UInt32 = 0_u32)
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
                     paint : UInt32) : Nil
      @buf << Decl.new(key, current_parent, kind, text, bounds, dir, paint)
    end

    # Leaf/group node with explicit geometry and optional direction.
    def node(key : UiKey, bounds : Rect = Rect.new,
             dir : Layout::Direction = Layout::Direction::Vertical,
             paint : UInt32 = 0_u32) : Nil
      emit(key, DeclKind::Node, "", bounds, dir, paint)
    end

    # Text leaf. Text change is layout-affecting.
    def text(key : UiKey, str : String, bounds : Rect = Rect.new,
             paint : UInt32 = 0_u32) : Nil
      emit(key, DeclKind::Text, str, bounds, Layout::Direction::Vertical, paint)
    end

    # Directional container helpers. Optional direction argument; when a
    # block is given the container is nested.
    def row(key : UiKey, bounds : Rect = Rect.new, paint : UInt32 = 0_u32,
            dir : Layout::Direction = Layout::Direction::Horizontal) : Nil
      emit(key, DeclKind::Row, "", bounds, dir, paint)
    end

    def row(key : UiKey, bounds : Rect = Rect.new, paint : UInt32 = 0_u32,
            dir : Layout::Direction = Layout::Direction::Horizontal,
            & : Builder ->) : Nil
      emit(key, DeclKind::Row, "", bounds, dir, paint)
      push_parent(key)
      yield self
      pop_parent
    end

    def column(key : UiKey, bounds : Rect = Rect.new, paint : UInt32 = 0_u32,
               dir : Layout::Direction = Layout::Direction::Vertical) : Nil
      emit(key, DeclKind::Column, "", bounds, dir, paint)
    end

    def column(key : UiKey, bounds : Rect = Rect.new, paint : UInt32 = 0_u32,
               dir : Layout::Direction = Layout::Direction::Vertical,
               & : Builder ->) : Nil
      emit(key, DeclKind::Column, "", bounds, dir, paint)
      push_parent(key)
      yield self
      pop_parent
    end

    # Generic nested group.
    def group(key : UiKey, bounds : Rect = Rect.new,
              dir : Layout::Direction = Layout::Direction::Vertical,
              paint : UInt32 = 0_u32, & : Builder ->) : Nil
      emit(key, DeclKind::Node, "", bounds, dir, paint)
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
