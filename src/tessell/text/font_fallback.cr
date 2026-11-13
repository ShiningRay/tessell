# Tessell::Text::FontRef / FontSet (M2 C1 S-EMOJI-1)
# Pure-logic fallback resolver: no filesystem dependencies.

module Tessell
  module Text
    struct FontRef
      getter path : String
      getter ttc_index : Int32
      getter family : String
      getter ranges : Array(Range(UInt32, UInt32))

      def initialize(@path : String, @ttc_index : Int32, @family : String,
                     @ranges : Array(Range(UInt32, UInt32)) = [] of Range(UInt32, UInt32))
        @path = path
        @ttc_index = ttc_index
        @family = family
        @ranges = ranges
      end

      def covers?(codepoint : UInt32) : Bool
        @ranges.each do |r|
          return true if r.includes?(codepoint)
        end
        false
      end
    end

    class FontSet
      def initialize
        @fonts = [] of FontRef
      end

      def add(font : FontRef) : Int32
        id = @fonts.size
        @fonts << font
        id
      end

      # Returns font_id (index in add order) of first covering font, or -1 if none.
      def resolve(codepoint : UInt32) : Int32
        i = 0
        while i < @fonts.size
          return i if @fonts[i].covers?(codepoint)
          i += 1
        end
        -1
      end

      def font_count : Int32
        @fonts.size
      end

      def font(id : Int32) : FontRef?
        return nil if id < 0 || id >= @fonts.size
        @fonts[id]
      end
    end
  end
end
