# Tessell::Kit — grapheme cluster 边界（K4）
#
# Crystal stdlib 没有 grapheme cluster API。这里实现覆盖常见组合：
# combining mark、variation selector、emoji modifier、ZWJ 序列、regional
# indicator 对、keycap、tag 字符。
#
# 这不是完整 UAX #29 实现；未覆盖的脚本按 codepoint 边界处理，并在
# docs/kit/components/input.md 记录限制。

module Tessell
  module Kit
    module Graphemes
      # 返回 UTF-8 byte 边界，包含 0 与 text.bytesize。
      def self.boundaries(text : String) : Array(Int32)
        result = [] of Int32
        result << 0
        return result if text.empty?

        offset = 0
        prev_cp = -1
        join_next = false
        ri_count = 0

        text.each_char do |ch|
          cp = ch.ord
          if offset > 0
            extending = false
            if join_next
              extending = true
              join_next = false
            elsif cp == 0x200D
              extending = true
              join_next = true
            elsif combining?(cp) || variation?(cp) || modifier?(cp) || keycap?(cp) || tag?(cp)
              extending = true
            elsif regional?(cp)
              if regional?(prev_cp) && ri_count.odd?
                extending = true
                ri_count += 1
              else
                extending = false
                ri_count = 1
              end
            end
            unless regional?(cp)
              ri_count = 0
            end
            result << offset unless extending
          elsif regional?(cp)
            ri_count = 1
          end
          prev_cp = cp
          offset += ch.bytesize
        end
        result << text.bytesize
        result
      end

      def self.prev_boundary(text : String, position : Int32) : Int32
        prev_boundary(boundaries(text), position)
      end

      def self.prev_boundary(bounds : Array(Int32), position : Int32) : Int32
        idx = index_of(bounds, position)
        if idx
          return bounds[idx - 1] if idx > 0
          return 0
        end
        greatest_below(bounds, position)
      end

      def self.next_boundary(text : String, position : Int32) : Int32
        next_boundary(boundaries(text), position)
      end

      def self.next_boundary(bounds : Array(Int32), position : Int32) : Int32
        idx = index_of(bounds, position)
        if idx
          return bounds[idx + 1] if idx + 1 < bounds.size
          return bounds.last
        end
        smallest_above(bounds, position)
      end

      def self.count(text : String) : Int32
        b = boundaries(text)
        b.size - 1
      end

      # 光标位置近似：返回距离 position 最近的合法边界（偏向左侧）。
      def self.clamp(text : String, position : Int32) : Int32
        bounds = boundaries(text)
        return 0 if position <= 0
        return text.bytesize if position >= text.bytesize
        idx = index_of(bounds, position)
        return position if idx
        greatest_below(bounds, position)
      end

      private def self.index_of(bounds : Array(Int32), position : Int32) : Int32?
        lo = 0
        hi = bounds.size - 1
        while lo <= hi
          mid = (lo + hi) >> 1
          value = bounds[mid]
          if value == position
            return mid
          elsif value < position
            lo = mid + 1
          else
            hi = mid - 1
          end
        end
        nil
      end

      private def self.greatest_below(bounds : Array(Int32), position : Int32) : Int32
        result = 0
        bounds.each do |b|
          break if b >= position
          result = b
        end
        result
      end

      private def self.smallest_above(bounds : Array(Int32), position : Int32) : Int32
        bounds.each do |b|
          return b if b > position
        end
        bounds.last
      end

      private def self.combining?(cp : Int32) : Bool
        (cp >= 0x0300 && cp <= 0x036F) ||
          (cp >= 0x1AB0 && cp <= 0x1AFF) ||
          (cp >= 0x1DC0 && cp <= 0x1DFF) ||
          (cp >= 0x20D0 && cp <= 0x20FF) ||
          (cp >= 0xFE20 && cp <= 0xFE2F)
      end

      private def self.variation?(cp : Int32) : Bool
        (cp >= 0xFE00 && cp <= 0xFE0F) || (cp >= 0xE0100 && cp <= 0xE01EF)
      end

      private def self.modifier?(cp : Int32) : Bool
        cp >= 0x1F3FB && cp <= 0x1F3FF
      end

      private def self.regional?(cp : Int32) : Bool
        cp >= 0x1F1E6 && cp <= 0x1F1FF
      end

      private def self.keycap?(cp : Int32) : Bool
        cp == 0x20E3
      end

      private def self.tag?(cp : Int32) : Bool
        cp >= 0xE0020 && cp <= 0xE007F
      end
    end
  end
end
