# Tessell::Render — DrawList：值类型绘制命令 + 可复用缓冲 + 最小批处理（M1-WP4）。
#
# 选型说明：
#   DrawCmd 用 struct（值语义、批处理遍历友好、避免每条命令一次堆分配）；
#   clip 用可选 Rect（草图阶段简单直接；atlas 索引化留 M1-WP5/M2）。
# 容量策略：clear 只重置逻辑计数（@size=0），不缩减物理槽位（@commands.size 即容量）；
#   push 先复用物理槽位（@size < 物理 size 时原位写），物理槽位用尽才扩容。
#   Crystal Array 无公开 capacity/reserve，故容量由物理槽数自控。
#   稳态 push/clear 循环不产生再分配（用 capacity 前后断言验证）。
# 批处理规则（build_batches）：相邻命令 atlas_id 相同且 clip 相同 → 同一批；
#   kind/color 不参与批键（批内由后端逐命令绘制）；atlas 或 clip 任一变化即切批。

require "../geometry"

module Tessell
  module Render
    # 最小绘制命令集合（plan.md:100-103，K1 增加圆角/描边）。
    # Rect/Text/Line 保持原语义；RoundRect/StrokeRect/StrokeRoundRect 由后端
    # 按自身能力实现，不支持时必须显式跳过或报错，不得静默画成直角/填充。
    enum CmdKind
      Rect
      Text
      Line
      RoundRect
      StrokeRect
      StrokeRoundRect
    end

    struct DrawCmd
      getter kind : CmdKind
      getter bounds : Rect
      # RGBA8 打包：0xAABBGGRR 风格的 UInt32（打包顺序由后端解释，此处只存值）。
      getter color : UInt32
      # -1 表示无 atlas（纯色/矢量命令）。
      getter atlas_id : Int32
      getter clip : Rect?
      getter radius : Float32
      getter stroke_width : Float32

      def initialize(@kind : CmdKind, @bounds : Rect, @color : UInt32,
                     @atlas_id : Int32 = -1, @clip : Rect? = nil,
                     @radius : Float32 = 0.0_f32,
                     @stroke_width : Float32 = 0.0_f32)
      end
    end

    # 批：一段相邻命令的 [start, count) 区间，批内 atlas/clip 一致。
    struct Batch
      getter start : Int32
      getter count : Int32

      def initialize(@start : Int32, @count : Int32)
      end
    end

    class DrawList
      getter size : Int32

      def initialize
        @commands = [] of DrawCmd
        @size = 0
        @batches = [] of Batch
        @batch_result_count = 0
      end

      # 逻辑清零；底层容量保留（复用缓冲，不释放）。
      def clear : Nil
        @size = 0
      end

      def push(cmd : DrawCmd) : Nil
        if @size < @commands.size
          @commands[@size] = cmd
        else
          @commands << cmd
        end
        @size += 1
      end

      # 逻辑视图：按下标读取（越界抛出 IndexError）；物理槽位内的陈旧数据不可见。
      def [](index : Int) : DrawCmd
        raise IndexError.new if index < 0 || index >= @size
        @commands[index]
      end

      # 物理槽位数（= 自控容量）：只增不减，clear 不缩减。
      def capacity : Int32
        @commands.size
      end

      # 容量提示：物理槽位不足 n 时补足到 n（槽位内容为零值占位，
      # 逻辑上不可见——push 会原位覆写）；已有 n 个槽位则直接返回。
      def reserve(n : Int32) : Nil
        return if n <= @commands.size
        (n - @commands.size).times do
          @commands << DrawCmd.new(CmdKind::Rect, Rect.new, 0_u32)
        end
      end

      # 零分配热路径：将批区间写入 sink（复用容量），返回批数。逻辑大小为返回值。
      def build_batches_into(sink : Array(Batch)) : Int32
        count = 0
        i = 0
        while i < @size
          start = i
          n = 1
          while i + n < @size && same_batch_key?(@commands[i], @commands[i + n])
            n += 1
          end
          b = Batch.new(start, n)
          if count < sink.size
            sink[count] = b
          else
            sink << b
          end
          count += 1
          i += n
        end
        @batch_result_count = count
        count
      end

      # 兼容接口：返回新数组（分配）。热路径请用 build_batches_into。
      def build_batches : Array(Batch)
        tmp = [] of Batch
        build_batches_into(tmp)
        tmp
      end

      def batch_count : Int32
        build_batches_into(@batches)
        @batch_result_count
      end

      # capacity 前后对比用（复用证据）。
      def reuse_stats : NamedTuple(capacity: Int32, size: Int32, physical: Int32)
        {capacity: @commands.size, size: @size, physical: @commands.size}
      end

      private def same_batch_key?(a : DrawCmd, b : DrawCmd) : Bool
        a.atlas_id == b.atlas_id && a.clip == b.clip
      end
    end
  end
end
