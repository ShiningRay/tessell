# Tessell::Kit::ScrollModel — 可复用滚动数学（issue #17）
#
# 单轴滚动模型：内容尺寸、viewport、offset clamp、滚动条 thumb 几何、
# 等高行/列的可见区间与坐标↔索引换算。ScrollView 内部使用；二维控件
# （表格、Grid）按 x/y 各持一个实例，不再各自实现 clamp/travel 数学。
#
# 用法：
#   m = ScrollModel.new
#   m.content_size = 2000.0_f32
#   m.viewport_size = 400.0_f32
#   m.offset = 100.0_f32                       # 自动 clamp
#   m.scroll_by(-40.0_f32)
#   first, last = m.visible_range(24.0_f32, 1000)  # 等高行可见区间（含端点）
#   y = m.offset_at(index, 24.0_f32)           # 索引 → 坐标
#   idx = m.index_at(360.0_f32, 24.0_f32)      # 视口内坐标 → 索引

module Tessell
  module Kit
    struct ScrollThumb
      getter pos : Float32
      getter size : Float32

      def initialize(@pos : Float32, @size : Float32)
      end
    end

    class ScrollModel
      property content_size : Float32
      property viewport_size : Float32
      property min_thumb_size : Float32

      @offset : Float32

      def initialize(content_size : Float32 = 0.0_f32,
                     viewport_size : Float32 = 0.0_f32)
        @content_size = content_size
        @viewport_size = viewport_size
        @offset = 0.0_f32
        @min_thumb_size = 20.0_f32
      end

      def offset : Float32
        @offset
      end

      # 写入即 clamp 到 [0, max_offset]。
      def offset=(value : Float32) : Nil
        @offset = clamp(value)
      end

      def max_offset : Float32
        value = @content_size - @viewport_size
        value < 0.0_f32 ? 0.0_f32 : value
      end

      def scrollable? : Bool
        max_offset > 0.0_f32
      end

      def scroll_to(value : Float32) : Float32
        @offset = clamp(value)
        @offset
      end

      def scroll_by(delta : Float32) : Float32
        scroll_to(@offset + delta)
      end

      # 滚动条 thumb：在 track 长度内的位置与长度（按 viewport/content 比例）。
      def thumb(track_len : Float32) : ScrollThumb
        return ScrollThumb.new(0.0_f32, track_len) unless scrollable?
        ratio = @viewport_size / @content_size
        size = (track_len * ratio).clamp(@min_thumb_size, track_len)
        travel = track_len - size
        pos = travel * (@offset / max_offset)
        ScrollThumb.new(pos, size)
      end

      # 把 track 上的点击位置（滑块中心语义）换算为 offset。
      def offset_for_thumb(pos_in_track : Float32, track_len : Float32) : Float32
        return 0.0_f32 unless scrollable?
        t = track_len > 0.0_f32 ? (pos_in_track / track_len).clamp(0.0_f32, 1.0_f32) : 0.0_f32
        t * max_offset
      end

      # 等高条目的可见索引区间（含端点）；total_count 为逻辑总数。
      def visible_range(item_size : Float32, total_count : Int32) : {Int32, Int32}
        return {0, -1} if total_count <= 0 || item_size <= 0.0_f32
        first = (@offset / item_size).floor.to_i
        first = 0 if first < 0
        last = ((@offset + @viewport_size) / item_size).floor.to_i
        last = total_count - 1 if last >= total_count
        {first, last}
      end

      # 索引 → 内容坐标（该行的起始位置）。
      def offset_at(index : Int32, item_size : Float32) : Float32
        index.to_f32 * item_size
      end

      # 视口内坐标（相对 viewport 起点，负值视为视口外）→ 索引；越界返回 -1。
      def index_at(coord : Float32, item_size : Float32) : Int32
        return -1 if item_size <= 0.0_f32 || coord < 0.0_f32
        idx = ((@offset + coord) / item_size).floor.to_i
        return -1 if idx < 0
        last = ((@content_size / item_size).floor.to_i) - 1
        idx > last ? -1 : idx
      end

      private def clamp(value : Float32) : Float32
        value.clamp(0.0_f32, max_offset)
      end
    end
  end
end
