require "../core/node"
require "../a11y/tree"
require "./key"
require "./builder"

module Tessell::UI
  # Per-node metadata for change detection and stable identity.
  # a11y_* fields mirror the declaration so that a11y meta is only rewritten
  # when the accessible surface actually changes (steady state: never).
  struct Meta
    getter kind : DeclKind
    getter text : String
    getter bounds : Rect
    getter direction : Layout::Direction
    getter paint : UInt32
    getter seen : UInt32
    getter a11y_role : A11y::Role
    getter a11y_name : String
    getter a11y_value : String
    getter a11y_focusable : Bool
    getter a11y_enabled : Bool

    def initialize(@kind : DeclKind, @text : String, @bounds : Rect,
                   @direction : Layout::Direction, @paint : UInt32,
                   @seen : UInt32,
                   @a11y_role : A11y::Role = A11y::Role::Group,
                   @a11y_name : String = "",
                   @a11y_value : String = "",
                   @a11y_focusable : Bool = false,
                   @a11y_enabled : Bool = true)
    end
  end

  # Reusable state for apply. Reuse the same instance across frames so that
  # steady-state (no structural/value changes, buffers pre-sized) allocates 0.
  class Pool
    getter map : Hash(UiKey, Node)
    getter meta : Hash(UiKey, Meta)
    getter desired : Hash(UiKey, Array(UiKey))
    getter dmark : Hash(UiKey, UInt32)
    getter active : Array(UiKey)
    getter active_index : Hash(UiKey, Int32)
    getter remove_buf : Array(UiKey)
    getter activated : Array(UiKey)
    property gen : UInt32

    def initialize
      @map = Hash(UiKey, Node).new
      @meta = Hash(UiKey, Meta).new
      @desired = Hash(UiKey, Array(UiKey)).new
      @dmark = Hash(UiKey, UInt32).new
      @active = [] of UiKey
      @active_index = Hash(UiKey, Int32).new(initial_capacity: 0)
      @remove_buf = [] of UiKey
      @activated = [] of UiKey
      @gen = 0_u32
    end

    # Desired-children buffer for parent key in current gen (cleared on first touch).
    def touch_desired(key : UiKey, g : UInt32) : Array(UiKey)
      buf = @desired[key]?
      unless buf
        buf = [] of UiKey
        @desired[key] = buf
      end
      mark = @dmark[key]?
      if mark != g
        buf.clear
        @dmark[key] = g
      end
      buf
    end

    # Desired buffer only if touched this gen, else nil (treated as empty).
    def desired_for(key : UiKey, g : UInt32) : Array(UiKey)?
      if @dmark[key]? == g
        @desired[key]?
      else
        nil
      end
    end

    def add_active(key : UiKey) : Nil
      unless @active_index.has_key?(key)
        @active_index[key] = @active.size
        @active << key
      end
    end

    def remove_active(key : UiKey) : Nil
      idx = @active_index[key]?
      return unless idx
      last_i = @active.size - 1
      if idx != last_i
        last_key = @active.unsafe_fetch(last_i)
        @active[idx] = last_key
        @active_index[last_key] = idx
      end
      @active.pop
      @active_index.delete(key)
    end
  end

  # Apply flat DFS-preorder declarations to an existing root Node.
  # - Reuse nodes by UiKey (stable id); removed subtrees stay pooled for reuse.
  # - Dirty only on changes: layout-affecting -> Layout, paint-only -> Paint.
  # - apply never clears dirty flags. Dirty flags must be consumed (cleared)
  #   by the caller after the dirty set is processed, via UI.consume.
  # - No-change steady state is zero-alloc when buffers are pre-sized.
  # - When `a11y` is given, accessible meta is synced for new/changed nodes and
  #   removed for deleted nodes (keyed by node.object_id, the same id a11y uses).
  def self.apply(decls : Array(Decl), root : Node, pool : Pool,
                 a11y : A11y::Builder? = nil) : Nil
    pool.gen &+= 1_u32
    g = pool.gen
    pool.activated.clear

    # Pass 1: update/create nodes, record desired children, mark seen.
    i = 0
    n = decls.size
    while i < n
      d = decls.unsafe_fetch(i)
      key = d.key
      parent_key = d.parent

      # desired child relationship for this frame
      pbuf = pool.touch_desired(parent_key, g)
      pbuf << key

      existing = pool.map[key]?
      if existing
        old = pool.meta[key]?
        if old
          layout_changed = old.kind != d.kind || old.text != d.text ||
                           old.bounds != d.bounds || old.direction != d.direction
          paint_changed = old.paint != d.paint
          a11y_changed = old.a11y_role != d.a11y_role ||
                         old.a11y_name != d.a11y_name ||
                         old.a11y_value != d.a11y_value ||
                         old.a11y_focusable != d.a11y_focusable ||
                         old.a11y_enabled != d.a11y_enabled
          reactivated = old.seen != (g &- 1_u32) && !pool.active_index.has_key?(key)
          if layout_changed
            existing.bounds = d.bounds
            existing.mark_dirty(Invalidation::Layout)
          elsif paint_changed
            existing.mark_dirty(Invalidation::Paint)
          end
          if a11y && (layout_changed || paint_changed || a11y_changed || reactivated)
            sync_a11y(a11y, existing, d)
          end
          pool.meta[key] = Meta.new(d.kind, d.text, d.bounds, d.direction,
            d.paint, g, d.a11y_role, d.a11y_name, d.a11y_value,
            d.a11y_focusable, d.a11y_enabled)
          # reactivated from pool?
          if reactivated
            pool.activated << key
          end
        else
          existing.bounds = d.bounds
          existing.mark_dirty(Invalidation::Layout)
          sync_a11y(a11y, existing, d) if a11y
          pool.meta[key] = Meta.new(d.kind, d.text, d.bounds, d.direction,
            d.paint, g, d.a11y_role, d.a11y_name, d.a11y_value,
            d.a11y_focusable, d.a11y_enabled)
          unless pool.active_index.has_key?(key)
            pool.activated << key
          end
        end
      else
        # brand new key: create node (id allocated once per new key)
        id_str = key.id64.to_s
        node = Node.new(id_str, d.bounds)
        pool.map[key] = node
        sync_a11y(a11y, node, d) if a11y
        pool.meta[key] = Meta.new(d.kind, d.text, d.bounds, d.direction,
          d.paint, g, d.a11y_role, d.a11y_name, d.a11y_value,
          d.a11y_focusable, d.a11y_enabled)
        pool.activated << key
      end
      # ensure meta seen is current (defensive)
      m = pool.meta[key]?
      if m && m.seen != g
        pool.meta[key] = Meta.new(m.kind, m.text, m.bounds, m.direction,
          m.paint, g, m.a11y_role, m.a11y_name, m.a11y_value,
          m.a11y_focusable, m.a11y_enabled)
      end
      i += 1
    end

    # Pass 2: reconcile structure DFS from root.
    reconcile_children(UiKey.root, root, pool, g)

    # Pass 3: remove keys not seen this gen.
    rb = pool.remove_buf
    rb.clear
    active = pool.active
    ai = 0
    asz = active.size
    while ai < asz
      k = active.unsafe_fetch(ai)
      mk = pool.meta[k]?
      if mk.nil? || mk.seen != g
        rb << k
      end
      ai += 1
    end
    ri = 0
    rsz = rb.size
    while ri < rsz
      k = rb.unsafe_fetch(ri)
      retire_subtree(k, pool, a11y)
      ri += 1
    end

    # Add newly activated keys to active set.
    act = pool.activated
    aj = 0
    ac = act.size
    while aj < ac
      k = act.unsafe_fetch(aj)
      mk = pool.meta[k]?
      if mk && mk.seen == g
        pool.add_active(k)
      end
      aj += 1
    end
  end

  # Consume (clear) dirty flags on nodes whose dirty set has been handled
  # (layout/paint/composite processed). MUST be called after the dirty set is
  # processed; calling before consumption causes missed drawing/updates.
  # Only the provided nodes are cleaned; other dirty nodes remain dirty.
  def self.consume(nodes : Array(Node)) : Nil
    i = 0
    n = nodes.size
    while i < n
      nodes.unsafe_fetch(i).clean!
      i += 1
    end
  end

  # Reconcile node.children to match desired[parent_key] for this gen.
  private def self.reconcile_children(parent_key : UiKey, parent_node : Node,
                                      pool : Pool, g : UInt32) : Nil
    desired = pool.desired_for(parent_key, g)
    desired_size = desired ? desired.size : 0
    children = parent_node.children
    cur_size = children.size

    # Fast path: identical sequence
    if desired && desired_size == cur_size
      same = true
      j = 0
      while j < desired_size
        dk = desired.unsafe_fetch(j)
        dn = pool.map[dk]?
        if dn.nil? || children.unsafe_fetch(j) != dn
          same = false
          break
        end
        j += 1
      end
      if same
        j = 0
        while j < desired_size
          dk = desired.unsafe_fetch(j)
          dn = pool.map[dk]
          reconcile_children(dk, dn, pool, g)
          j += 1
        end
        return
      end
    end

    # Structural path
    if desired
      di = 0
      while di < desired_size
        dk = desired.unsafe_fetch(di)
        dn = pool.map[dk]?
        if dn
          if di < parent_node.children.size
            cur = parent_node.children.unsafe_fetch(di)
            if cur != dn
              if dn.parent
                dn.parent.not_nil!.remove_child(dn)
              end
              parent_node.children.insert(di, dn)
              dn.parent = parent_node
              parent_node.mark_dirty(Invalidation::Layout)
            end
          else
            if dn.parent
              dn.parent.not_nil!.remove_child(dn)
            end
            parent_node.add_child(dn)
            parent_node.mark_dirty(Invalidation::Layout)
          end
        end
        di += 1
      end
    end

    # Trim extras
    while parent_node.children.size > desired_size
      extra = parent_node.children.last
      parent_node.remove_child(extra)
      parent_node.mark_dirty(Invalidation::Layout)
    end

    # Recurse/fix positions
    if desired
      j = 0
      while j < desired_size
        dk = desired.unsafe_fetch(j)
        dn = pool.map[dk]?
        if dn
          if j < parent_node.children.size
            cur = parent_node.children.unsafe_fetch(j)
            if cur != dn
              if dn.parent
                dn.parent.not_nil!.remove_child(dn)
              end
              parent_node.children.insert(j, dn)
              dn.parent = parent_node
              parent_node.mark_dirty(Invalidation::Layout)
            end
          end
          reconcile_children(dk, dn, pool, g)
        end
        j += 1
      end
      while parent_node.children.size > desired_size
        extra = parent_node.children.last
        parent_node.remove_child(extra)
        parent_node.mark_dirty(Invalidation::Layout)
      end
    end
  end

  # Detach a removed subtree from the live tree but keep it pooled in map/meta
  # for reuse if the same key reappears. Accessible meta is dropped here (the
  # node id is derived from object_id, so stale meta must not survive a retire).
  private def self.retire_subtree(key : UiKey, pool : Pool,
                                  a11y : A11y::Builder? = nil) : Nil
    node = pool.map[key]?
    return unless node
    a11y.try(&.remove_meta(node.object_id.to_u64))
    node.detach
    while node.children.size > 0
      ch = node.children.last
      node.remove_child(ch)
    end
    pool.remove_active(key)
    # keep in map/meta as pooled (meta.seen < g). Do not clean here.
  end

  # Copy the declaration's accessible fields onto the node's a11y meta.
  private def self.sync_a11y(a11y : A11y::Builder, node : Node, d : Decl) : Nil
    a11y.set_meta(node.object_id.to_u64, d.a11y_role, d.a11y_name,
      d.a11y_value, d.a11y_focusable, d.a11y_enabled)
  end

  # Emit the accessible tree (preorder DFS) into a caller-provided sink.
  # The sink is cleared and reused; no intermediate array is allocated and
  # steady state (pre-sized sink, unchanged meta) performs no allocations.
  # Must be called after UI.apply so that a11y meta is in sync.
  def self.a11y_emit(root : Node, a11y : A11y::Builder,
                     sink : Array(A11y::Node)) : Int32
    sink.clear
    emit_walk(root, a11y, 0, sink, nil, nil, nil, A11y::Role::ListItem)
    sink.size
  end

  # Virtual-list aware overload. When DFS reaches `container`, that node is
  # emitted with VirtualList semantics: children_count = logical row count,
  # scroll_offset = scroll_y, and only the visible window is emitted as item
  # children (Role::ListItem). The full 10k rows are never materialized.
  def self.a11y_emit(root : Node, a11y : A11y::Builder,
                     sink : Array(A11y::Node),
                     vlist : Widgets::VirtualList, container : Node,
                     name_for : Proc(Int32, String)? = nil,
                     item_role : A11y::Role = A11y::Role::ListItem) : Int32
    sink.clear
    emit_walk(root, a11y, 0, sink, vlist, container, name_for, item_role)
    sink.size
  end

  private def self.emit_walk(node : Node, a11y : A11y::Builder,
                             idx : Int32, sink : Array(A11y::Node),
                             vlist : Widgets::VirtualList?,
                             container : Node?,
                             name_for : Proc(Int32, String)?,
                             item_role : A11y::Role) : Nil
    nid = node.object_id.to_u64
    m = a11y.meta_for(nid)
    role = m ? m.role : A11y::Role::Group
    name = m ? m.name : ""
    value = m ? m.value : ""
    focusable = m ? m.focusable : false
    enabled = m ? m.enabled : true
    focused = a11y.focused?(node)

    if vlist && container && node.same?(container)
      sink << A11y::Node.new(
        id: nid, role: role, name: name, value: value, bounds: node.bounds,
        focusable: focusable, focused: focused, enabled: enabled,
        children_count: vlist.row_count, index_in_parent: idx,
        scroll_offset: vlist.scroll_y)
      first = vlist.visible_first
      last = vlist.visible_last
      if last >= first
        i = first
        j = 0
        while i <= last
          nm = name_for ? name_for.call(i) : ""
          sink << A11y::Node.new(
            id: emit_item_id(vlist, i), role: item_role, name: nm, value: "",
            bounds: Rect.new(0.0_f32, 0.0_f32, 0.0_f32, 0.0_f32),
            focusable: false, focused: false, enabled: true,
            children_count: 0, index_in_parent: j, scroll_offset: 0)
          i += 1
          j += 1
        end
      end
      return
    end

    sink << A11y::Node.new(
      id: nid, role: role, name: name, value: value, bounds: node.bounds,
      focusable: focusable, focused: focused, enabled: enabled,
      children_count: node.children.size, index_in_parent: idx,
      scroll_offset: 0)
    children = node.children
    i = 0
    while i < children.size
      emit_walk(children.unsafe_fetch(i), a11y, i, sink, vlist, container,
        name_for, item_role)
      i += 1
    end
  end

  # Stable synthetic id for a virtual row (same formula as A11y::VirtualWindow).
  private def self.emit_item_id(list : Widgets::VirtualList, index : Int32) : UInt64
    base = list.object_id.to_u64
    (base &* 131542391_u64) ^ index.to_u64 ^ 0x9e3779b97f4a7c15_u64
  end
end
