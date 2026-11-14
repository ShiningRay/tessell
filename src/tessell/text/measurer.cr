# Tessell::Text 文本测量抽象与缓存（M1-WP2）
# 契约：measure(font_id, size, text_hash, max_width) : Size
# 缓存 key：(font_id, size, text_hash, max_width)
# 约束：不引用 FFI/FreeType/HarfBuzz（真实 shaping 属 M2）；
#       StubMeasurer 桩值为确定性桩，不得当真实度量使用
# hash 选择：自实现 FNV-1a（跨运行稳定；String#hash 依赖运行时随机种子，不满足缓存键稳定要求）

module Tessell
  module Text
    # 缓存键：(font_id, size, text_hash, max_width)
    # text_hash 由 FNV-1a 计算，保证同文本不同 String 实例同 hash、跨运行稳定
    struct MeasureKey
      getter font_id : Int32
      getter size : Float32
      getter text_hash : UInt64
      getter max_width : Float32

      def initialize(@font_id : Int32, @size : Float32, @text_hash : UInt64, @max_width : Float32)
      end

      def ==(other : MeasureKey) : Bool
        font_id == other.font_id &&
          size == other.size &&
          text_hash == other.text_hash &&
          max_width == other.max_width
      end

      def hash : UInt64
        {font_id, size, text_hash, max_width}.hash
      end

      # FNV-1a 64 位文本哈希（跨运行稳定）
      def self.text_hash(text : String) : UInt64
        h = 0xcbf29ce484222325_u64
        text.each_byte do |b|
          h = h ^ b
          h = h &* 0x100000001b3_u64
        end
        h
      end
    end

    # 字体度量（issue #6）：设备像素单位，与 measure 的 size 口径一致。
    # ascent/descent 以 baseline 为界（ascent 向上为正），line_height 为
    # 推荐行距（FT size metrics height，回退 (ascent-descent)）。
    struct FontMetrics
      getter ascent : Float32
      getter descent : Float32
      getter line_height : Float32

      def initialize(@ascent : Float32, @descent : Float32, @line_height : Float32)
      end
    end

    # 文本测量抽象。真实实现（M2 FreeType/HarfBuzz）不得引用本文件
    abstract class Measurer
      # 主接口：按文本内容、字体、字号、可用宽测量
      abstract def measure(text : String, font_id : Int32, size : Float32, max_width : Float32) : Size
      # 可选接口：按缓存键测量，内部使用；默认未实现
      def measure(key : MeasureKey) : Size
        raise NotImplementedError.new("measure(key) not implemented")
      end

      # 字体度量（issue #6）：默认按比例桩值；真实实现应读 FT size metrics。
      def font_metrics(font_id : Int32, size : Float32) : FontMetrics
        FontMetrics.new(size * 0.8_f32, size * 0.2_f32, size * 1.2_f32)
      end
    end

    # 确定性桩：width = chars * size * 0.6，height = size * 1.2，尊重 max_width 换行
    # 仅用于布局与单测；不得当真实度量
    class StubMeasurer < Measurer
      def measure(text : String, font_id : Int32, size : Float32, max_width : Float32) : Size
        char_w = size * 0.6_f32
        total_w = text.size * char_w
        if max_width > 0.0_f32 && total_w > max_width
          lines = (total_w / max_width).ceil
          Size.new(max_width, size * 1.2_f32 * lines)
        else
          Size.new(total_w, size * 1.2_f32)
        end
      end
    end

    # 缓存装饰器：先查后算，统计 hits/misses/evictions
    class CachingMeasurer < Measurer
      def initialize(@inner : Measurer)
        @cache = Hash(MeasureKey, Size).new
        @hits = 0
        @misses = 0
        @evictions = 0
      end

      def measure(text : String, font_id : Int32, size : Float32, max_width : Float32) : Size
        key = MeasureKey.new(font_id, size, MeasureKey.text_hash(text), max_width)
        if @cache.has_key?(key)
          @hits += 1
          @cache[key]
        else
          @misses += 1
          sz = @inner.measure(text, font_id, size, max_width)
          @cache[key] = sz
          sz
        end
      end

      def measure(key : MeasureKey) : Size
        if @cache.has_key?(key)
          @hits += 1
          @cache[key]
        else
          @misses += 1
          raise KeyError.new("cache miss for key")
        end
      end

      def stats : NamedTuple(hits: Int32, misses: Int32, evictions: Int32)
        {hits: @hits, misses: @misses, evictions: @evictions}
      end

      def invalidate_font(font_id : Int32) : Nil
        before = @cache.size
        @cache.reject! { |k, _| k.font_id == font_id }
        @evictions += (before - @cache.size)
      end

      def clear : Nil
        @cache.clear
      end
    end
  end
end
