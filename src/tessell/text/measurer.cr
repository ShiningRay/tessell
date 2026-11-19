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

    # 宽度无关 shaping 结果（issue #56）：glyph advance 序列（px，含与
    # measure 相同的零 advance 回退口径）+ 推荐行高（px）。
    struct ShapeRun
      getter advances : Array(Float32)
      getter line_height : Float32

      def initialize(@advances : Array(Float32), @line_height : Float32)
      end
    end

    # L2 shaping 缓存键（issue #56）：宽度无关，max_width 不参与。
    struct ShapeKey
      getter font_id : Int32
      getter size : Float32
      getter text_hash : UInt64

      def initialize(@font_id : Int32, @size : Float32, @text_hash : UInt64)
      end

      def ==(other : ShapeKey) : Bool
        font_id == other.font_id &&
          size == other.size &&
          text_hash == other.text_hash
      end

      def hash : UInt64
        {font_id, size, text_hash}.hash
      end
    end

    # 换行重排（issue #56）：measure 的断行口径唯一来源——累计 advance，
    # 行非空且超宽即断行；行数 × line_height；结果钳到 max_width。
    # FtMeasurer#measure 与 CachingMeasurer L2 reflow 共用它，保证两条
    # 路径几何一致。
    def self.reflow_run(advances : Array(Float32), line_height : Float32,
                        max_width : Float32) : Size
      lines = 1
      line_w = 0.0_f32
      max_line_w = 0.0_f32
      advances.each do |adv|
        if line_w > 0.0_f32 && (line_w + adv) > max_width
          max_line_w = line_w if line_w > max_line_w
          lines += 1
          line_w = adv
        else
          line_w += adv
        end
      end
      max_line_w = line_w if line_w > max_line_w
      max_line_w = max_width if max_line_w > max_width
      Size.new(max_line_w, line_height * lines)
    end

    # 文本测量抽象。真实实现（M2 FreeType/HarfBuzz）不得引用本文件
    abstract class Measurer
      # 主接口：按文本内容、字体、字号、可用宽测量
      abstract def measure(text : String, font_id : Int32, size : Float32, max_width : Float32) : Size
      # 可选接口：按缓存键测量，内部使用；默认未实现
      def measure(key : MeasureKey) : Size
        raise NotImplementedError.new("measure(key) not implemented")
      end

      # 可选接口（issue #56 L2）：宽度无关 shaping——advance 序列与行高。
      # 返回 nil 表示不支持（CachingMeasurer 退回全量 measure 路径）。
      def shape_run(text : String, font_id : Int32, size : Float32) : ShapeRun?
        nil
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

    # 缓存装饰器（issue #56 重构）：两层缓存 + 分段 LRU。
    # - L1：结果缓存 (font_id, size, text_hash, max_width) → Size，
    #   按 font_id 分段，段内 tick-LRU（段容量 SEGMENT_CAP），总量 CACHE_CAP。
    #   一次 resize 风暴只挤占该字体自己的段，不再全有全无清空（旧口径）。
    # - L2：宽度无关 shaping 缓存 (font_id, size, text_hash) → ShapeRun
    #   （advance 序列 + 行高）。宽度变化只走 reflow（计 reflows），不重 shape。
    #   不支持 shape_run 的底层（桩、计数桩）自动走全量 measure 路径。
    # 断行口径唯一来源：Tessell::Text.reflow_run（FtMeasurer#measure 与本层共用）。
    class CachingMeasurer < Measurer
      CACHE_CAP  = 8192 # L1 总容量（对齐 issue #34 口径）
      SEGMENT_CAP = 2048 # 每 font_id 段容量（4 字面满载 ≈ 8192）
      SHAPE_CAP  = 2048 # L2 shaping 结果容量

      struct L1Entry
        getter size : Size
        getter tick : UInt64

        def initialize(@size : Size, @tick : UInt64)
        end
      end

      struct L2Entry
        getter run : ShapeRun
        getter tick : UInt64

        def initialize(@run : ShapeRun, @tick : UInt64)
        end
      end

      def initialize(@inner : Measurer)
        @l1 = Hash(Int32, Hash(MeasureKey, L1Entry)).new
        @l2 = Hash(ShapeKey, L2Entry).new
        @total = 0
        @tick = 0_u64
        @hits = 0
        @misses = 0
        @evictions = 0
        @shapes = 0
        @reflows = 0
      end

      def measure(text : String, font_id : Int32, size : Float32, max_width : Float32) : Size
        key = MeasureKey.new(font_id, size, MeasureKey.text_hash(text), max_width)
        if seg = @l1[font_id]?
          if e = seg[key]?
            @hits += 1
            @tick += 1
            seg[key] = L1Entry.new(e.size, @tick)
            return e.size
          end
        end
        @misses += 1
        sz = compute(text, font_id, size, max_width)
        l1_put(font_id, key, sz)
        sz
      end

      def measure(key : MeasureKey) : Size
        if seg = @l1[key.font_id]?
          if e = seg[key]?
            @hits += 1
            @tick += 1
            seg[key] = L1Entry.new(e.size, @tick)
            return e.size
          end
        end
        @misses += 1
        raise KeyError.new("cache miss for key")
      end

      private def compute(text : String, font_id : Int32, size : Float32,
                          max_width : Float32) : Size
        # 无宽度约束或底层不支持 shaping：全量 measure（与旧路径一致）
        return @inner.measure(text, font_id, size, max_width) if max_width <= 0.0_f32
        skey = ShapeKey.new(font_id, size, MeasureKey.text_hash(text))
        if l2e = @l2[skey]?
          # 宽度变化：只重算断点，不重 shape（reflow 计数）
          @reflows += 1
          @tick += 1
          @l2[skey] = L2Entry.new(l2e.run, @tick)
          return reflow_of(l2e.run, max_width)
        end
        run = @inner.shape_run(text, font_id, size)
        if run
          @shapes += 1
          @tick += 1
          l2_evict
          @l2[skey] = L2Entry.new(run, @tick)
          reflow_of(run, max_width)
        else
          @inner.measure(text, font_id, size, max_width)
        end
      end

      private def reflow_of(run : ShapeRun, max_width : Float32) : Size
        Text.reflow_run(run.advances, run.line_height, max_width)
      end

      private def l1_put(font_id : Int32, key : MeasureKey, sz : Size) : Nil
        seg = @l1[font_id]?
        unless seg
          seg = Hash(MeasureKey, L1Entry).new
          @l1[font_id] = seg
        end
        if seg.size >= SEGMENT_CAP
          l1_evict_segment(seg)
        end
        seg[key] = L1Entry.new(sz, @tick)
        @total += 1
        if @total > CACHE_CAP
          l1_evict_global
        end
      end

      # 段内 LRU：按 tick 淘汰最旧一条
      private def l1_evict_segment(seg : Hash(MeasureKey, L1Entry)) : Nil
        victim_key = nil
        victim_tick = UInt64::MAX
        seg.each do |k, e|
          if e.tick < victim_tick
            victim_tick = e.tick
            victim_key = k
          end
        end
        if vk = victim_key
          seg.delete(vk)
          @total -= 1
          @evictions += 1
        end
      end

      # 总量超限：全段扫描淘汰全局最旧一条，回到 CACHE_CAP 以内
      private def l1_evict_global : Nil
        while @total > CACHE_CAP
          victim_seg : Hash(MeasureKey, L1Entry)? = nil
          victim_key : MeasureKey? = nil
          victim_tick = UInt64::MAX
          @l1.each do |fid, s|
            s.each do |k, e|
              if e.tick < victim_tick
                victim_tick = e.tick
                victim_key = k
                victim_seg = s
              end
            end
          end
          if vs = victim_seg
            if vk = victim_key
              vs.delete(vk)
              @total -= 1
              @evictions += 1
            end
          else
            break
          end
        end
      end

      # L2 超限：淘汰最旧一条 shaping 结果
      private def l2_evict : Nil
        return if @l2.size < SHAPE_CAP
        victim_key = nil
        victim_tick = UInt64::MAX
        @l2.each do |k, e|
          if e.tick < victim_tick
            victim_tick = e.tick
            victim_key = k
          end
        end
        if vk = victim_key
          @l2.delete(vk)
          @evictions += 1
        end
      end

      def stats : NamedTuple(hits: Int32, misses: Int32, evictions: Int32,
                             shapes: Int32, reflows: Int32)
        {hits: @hits, misses: @misses, evictions: @evictions,
         shapes: @shapes, reflows: @reflows}
      end

      def invalidate_font(font_id : Int32) : Nil
        if seg = @l1.delete(font_id)
          @evictions += seg.size
          @total -= seg.size
        end
        before = @l2.size
        @l2.reject! { |k, _| k.font_id == font_id }
        @evictions += (before - @l2.size)
      end

      def clear : Nil
        @l1.clear
        @l2.clear
        @total = 0
      end

      # 观测面（issue #56）：L1 命中率之外的 shape/reflow 计数。
      def shape_cache_size : Int32
        @l2.size
      end

      def l1_size : Int32
        @total
      end
    end
  end
end
