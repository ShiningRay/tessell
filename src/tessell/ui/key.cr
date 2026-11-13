module Tessell::UI
  # Stable non-string key: (parent, local). Derivation mixes identity so that
  # (same parent, diff local) and (diff parent, same local) never collide.
  struct UiKey
    getter parent : UInt64
    getter local : UInt64

    def initialize(@parent : UInt64, @local : UInt64)
    end

    def self.root : UiKey
      UiKey.new(0_u64, 0_u64)
    end

    # Derive a child key: mix this key's identity with the child's local id.
    # FNV-1a 64-bit mix over the pair (combined self, local) for stable spread.
    def child(local : UInt64) : UiKey
      p = 0xcbf29ce484222325_u64
      p ^= @parent
      p &*= 0x100000001b3_u64
      p ^= @local
      p &*= 0x100000001b3_u64
      UiKey.new(p, local)
    end

    # Stable 64-bit identity of this key (for Node id derivation / maps).
    def id64 : UInt64
      h = 0xcbf29ce484222325_u64
      h ^= @parent
      h &*= 0x100000001b3_u64
      h ^= @local
      h &*= 0x100000001b3_u64
      h
    end

    def hash(hasher)
      hasher = @parent.hash(hasher)
      hasher = @local.hash(hasher)
      hasher
    end

    def ==(other : UiKey) : Bool
      @parent == other.parent && @local == other.local
    end

    def ==(other) : Bool
      false
    end
  end
end
