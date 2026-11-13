require "../core/node"
require "./key"
require "./builder"

module Tessell::UI
  # Per-node metadata for change detection and stable identity.
  struct Meta
    getter kind : DeclKind
    getter text : String
    getter bounds : Rect
    getter direction : Layout::Direction
    getter paint : UInt32
    getter seen : UInt32

    def initialize(@kind : DeclKind, @text : String, @bounds : Rect,
                   @direction : Layout::Direction, @paint : UInt32,
                   @seen : UInt32)
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
  def self.apply(decls : Array(Decl), root : Node, pool : Pool) : Nil
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
          if layout_changed
            existing.bounds = d.bounds
            existing.mark_dirty(Invalidation::Layout)
          elsif paint_changed
            existing.mark_dirty(Invalidation::Paint)
          end
          pool.meta[key] = Meta.new(d.kind, d.text, d.bounds, d.direction, d.paint, g)
          # reactivated from pool?
          if old.seen != g &- 1_u32 && !pool.active_index.has_key?(key)
            pool.activated << key
          end
        else
          existing.bounds = d.bounds
          existing.mark_dirty(Invalidation::Layout)
          pool.meta[key] = Meta.new(d.kind, d.text, d.bounds, d.direction, d.paint, g)
          unless pool.active_index.has_key?(key)
            pool.activated << key
          end
        end
      else
        # brand new key: create node (id allocated once per new key)
        id_str = key.id64.to_s
        node = Node.new(id_str, d.bounds)
        pool.map[key] = node
        pool.meta[key] = Meta.new(d.kind, d.text, d.bounds, d.direction, d.paint, g)
        pool.activated << key
      end
      # ensure meta seen is current (defensive)
      m = pool.meta[key]?
      if m && m.seen != g
        pool.meta[key] = Meta.new(m.kind, m.text, m.bounds, m.direction, m.paint, g)
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
      retire_subtree(k, pool)
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
  # for reuse if the same key reappears.
  private def self.retire_subtree(key : UiKey, pool : Pool) : Nil
    node = pool.map[key]?
    return unless node
    node.detach
    while node.children.size > 0
      ch = node.children.last
      node.remove_child(ch)
    end
    pool.remove_active(key)
    # keep in map/meta as pooled (meta.seen < g). Do not clean here.
  end
end
