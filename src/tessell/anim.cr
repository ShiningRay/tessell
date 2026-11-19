# Tessell::Anim — CompositeOnly 组合动画（issue #63）
#
# 边界（诚实口径）：
# - 只覆盖**合成态**（opacity / translate / scale）。布局动画（bounds 变化）
#   不属于本模块——bounds 变化触发 Layout 传播，与纯合成动画的提交协议分离，
#   需要另立协议（issue #63 建议范围原文）。
# - 采样全部**闭式**（时刻 → 值），无积分器：同一时刻的值与掉帧历史无关。
# - **manual clock**：宿主驱动 Clock#advance / Runner#tick。宿主停止推进
#   （离屏/最小化）动画即冻结——不存在隐式 wall-clock；不宣称 rAF 零开销。
# - CompositeOnly 状态由提交层承载（Node 属性 + 失效级别）；GL 层合成消费
#   为后续工作。无活动动画时 Runner#active? 为 false——宿主据此停帧。
#
# 本文件不依赖 Platform/FFI/Render/Kit；纯内存状态，可单测。

require "./core/node"
require "./ui/key"
require "./geometry"

module Tessell
  module Anim
    # 采样时刻的合成态（不可变值）。
    struct CompositeState
      getter opacity : Float32
      getter tx : Float32
      getter ty : Float32
      getter scale : Float32

      def initialize(@opacity : Float32, @tx : Float32, @ty : Float32, @scale : Float32)
      end
    end

    # manual clock：宿主唯一时间来源。暂停时不推进（离屏/最小化冻结语义）；
    # reduced_motion 时动画直接落到终值（首 tick 即完成）。
    class Clock
      getter now_ms : Int64
      getter? reduced_motion : Bool
      getter? paused : Bool

      def initialize(@now_ms : Int64 = 0_i64, @reduced_motion : Bool = false)
        @paused = false
      end

      def advance(delta_ms : Int64) : Nil
        return if @paused || delta_ms <= 0
        @now_ms += delta_ms
      end

      def pause : Nil
        @paused = true
      end

      def resume : Nil
        @paused = false
      end
    end

    # 闭式时间函数：t ∈ [0,1] → 进度。spring 为解析解（阻尼谐振动），
    # 非数值积分——轨迹由时刻唯一决定。
    module Easing
      def self.linear(t : Float32) : Float32
        t
      end

      def self.quad_in(t : Float32) : Float32
        t * t
      end

      def self.quad_out(t : Float32) : Float32
        1.0_f32 - (1.0_f32 - t) * (1.0_f32 - t)
      end

      def self.quad_in_out(t : Float32) : Float32
        t < 0.5_f32 ? 2.0_f32 * t * t : 1.0_f32 - 2.0_f32 * (1.0_f32 - t) * (1.0_f32 - t)
      end

      def self.cubic_out(t : Float32) : Float32
        1.0_f32 - (1.0_f32 - t) * (1.0_f32 - t) * (1.0_f32 - t)
      end

      # 阻尼弹簧解析解（ζ=0.545，ω≈11，t01=1 时收敛到 1±0.1%）。
      # 轻微过冲是弹簧语义的一部分；t ≥ duration 时终值精确取 to。
      def self.spring(t : Float32) : Float32
        e = Math.exp(-6.0_f32 * t)
        1.0_f32 - e * Math.cos(11.0_f32 * t) - (6.0_f32 / 11.0_f32) * e * Math.sin(11.0_f32 * t)
      end
    end

    # 单条合成动画轨。state_at 为闭式采样：结果只依赖时刻，不依赖采样历史。
    class Track(O)
      getter key : UI::UiKey
      getter owner : O?
      getter duration_ms : Int64
      getter delay_ms : Int64
      getter easing : Proc(Float32, Float32)
      property on_finish : Proc(Nil)?
      property on_cancel : Proc(Nil)?

      @start_ms : Int64
      @opacity_from : Float32
      @opacity_to : Float32
      @tx_from : Float32
      @tx_to : Float32
      @ty_from : Float32
      @ty_to : Float32
      @scale_from : Float32
      @scale_to : Float32

      def initialize(@key : UI::UiKey, @start_ms : Int64,
                     @opacity_from : Float32 = 1.0_f32, @opacity_to : Float32 = 1.0_f32,
                     @tx_from : Float32 = 0.0_f32, @tx_to : Float32 = 0.0_f32,
                     @ty_from : Float32 = 0.0_f32, @ty_to : Float32 = 0.0_f32,
                     @scale_from : Float32 = 1.0_f32, @scale_to : Float32 = 1.0_f32,
                     @duration_ms : Int64 = 300_i64, @delay_ms : Int64 = 0_i64,
                     @easing : Proc(Float32, Float32) = ->Anim::Easing.linear(Float32),
                     @owner : O? = nil)
      end

      # 闭式采样：t = clamp((now - start - delay) / duration)。
      # reduced_motion 直接取终值（无过渡）。
      def state_at(now_ms : Int64, reduced_motion : Bool = false) : CompositeState
        p = progress(now_ms, reduced_motion)
        CompositeState.new(
          lerp(@opacity_from, @opacity_to, p),
          lerp(@tx_from, @tx_to, p),
          lerp(@ty_from, @ty_to, p),
          lerp(@scale_from, @scale_to, p)
        )
      end

      def finished?(now_ms : Int64, reduced_motion : Bool = false) : Bool
        progress(now_ms, reduced_motion) >= 1.0_f32
      end

      private def progress(now_ms : Int64, reduced_motion : Bool) : Float32
        return 1.0_f32 if reduced_motion
        return 1.0_f32 if @duration_ms <= 0
        elapsed = now_ms - @start_ms - @delay_ms
        return 0.0_f32 if elapsed <= 0
        t = elapsed.to_f32 / @duration_ms.to_f32
        t = 1.0_f32 if t > 1.0_f32
        @easing.call(t)
      end

      private def lerp(a : Float32, b : Float32, p : Float32) : Float32
        a + (b - a) * p
      end
    end

    # 把合成态写入目标的抽象（虚调用，不用闭包——稳态 tick 零分配）。
    # 返回 false 表示目标已不在树（组件 detach）：Runner 静默收口该轨，
    # 不触发 on_finish/on_cancel（回调可能引用已卸载对象）。
    abstract class Applier
      abstract def apply(key : UI::UiKey, state : CompositeState) : Bool
    end

    # 轨注册表：animate（替换语义）/ cancel / cancel_owner / tick。
    # 同 key 重复 animate 会替换旧轨并触发其 on_cancel（无泄漏）。
    class Runner(O)
      @tracks : Array(Track(O))
      @finished : Array(Track(O)) # 复用缓冲（稳态零分配）
      @detached : Array(Track(O)) # 复用缓冲：目标不在树，静默收口

      def initialize
        @tracks = [] of Track(O)
        @finished = [] of Track(O)
        @detached = [] of Track(O)
      end

      def track_count : Int32
        @tracks.size
      end

      def active? : Bool
        @tracks.size > 0
      end

      # 注册/替换。旧轨触发 on_cancel；返回生效轨。
      def animate(track : Track) : Track
        i = index_of(track.key)
        if i >= 0
          old = @tracks[i]
          @tracks[i] = track
          old.on_cancel.try(&.call)
        else
          @tracks << track
        end
        track
      end

      # 取消：触发 on_cancel。返回是否存在。
      def cancel(key : UI::UiKey) : Bool
        i = index_of(key)
        return false if i < 0
        old = @tracks.delete_at(i)
        old.on_cancel.try(&.call)
        true
      end

      # owner dispose 收口：取消该 owner 名下全部轨（各触发 on_cancel）。
      def cancel_owner(owner : O) : Int32
        n = 0
        i = @tracks.size - 1
        while i >= 0
          t = @tracks[i]
          if t.owner.same?(owner)
            @tracks.delete_at(i)
            t.on_cancel.try(&.call)
            n += 1
          end
          i -= 1
        end
        n
      end

      # 推进：对每条轨闭式采样并交给 applier。目标缺失（detach）→ 静默移除
      # （不触发任何回调——回调可能引用已卸载对象）；完成 → 应用终值后移除
      # 并触发 on_finish。返回仍活动轨数。
      def tick(now_ms : Int64, reduced_motion : Bool, applier : Applier) : Int32
        @finished.clear
        @detached.clear
        i = 0
        size = @tracks.size
        while i < size
          t = @tracks[i]
          state = t.state_at(now_ms, reduced_motion)
          applied = applier.apply(t.key, state)
          if !applied
            @detached << t
          elsif t.finished?(now_ms, reduced_motion)
            @finished << t
          end
          i += 1
        end
        j = 0
        fsize = @finished.size
        while j < fsize
          t = @finished.unsafe_fetch(j)
          idx = @tracks.index(t)
          if idx
            @tracks.delete_at(idx)
            t.on_finish.try(&.call)
          end
          j += 1
        end
        k = 0
        dsize = @detached.size
        while k < dsize
          t = @detached.unsafe_fetch(k)
          idx = @tracks.index(t)
          @tracks.delete_at(idx) if idx
          k += 1
        end
        @tracks.size
      end

      private def index_of(key : UI::UiKey) : Int32
        i = 0
        size = @tracks.size
        while i < size
          return i if @tracks.unsafe_fetch(i).key == key
          i += 1
        end
        -1
      end
    end
  end
end
