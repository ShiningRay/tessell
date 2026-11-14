# Tessell::Signal — 拉取式响应式内核（issue #33，architecture §5.3）。
#
# 机制对照 asuka signal 包（docs/research/asuka-comparison.md）：
#   1. 侵入式双向链表依赖图 + version 戳复用：Link 同时挂在 source 的订阅链
#      与 dependent 的依赖链上；重跑时按 source 复用旧 link 并盖两枚戳
#      （run 戳用于清理死链、version 戳用于真变验证），跑完摘除没走到的链。
#      动态依赖与稳态零分配的全部成本来源，与宿主语言无关。
#   2. 两级脏标 push dirty / pull value：写时对直接订阅者 push dirty、向下游
#      push 更廉价的 pending 并剪枝（已 pending 即停）；memo 惰性重算，被
#      pull 时先按 version 戳验证上游真变；派生值相等即截断传播
#      （memo 不重算、下游 pending 清除）。菱形依赖一轮 flush effect 只跑
#      一次——天然 glitch-free，无需拓扑排序。
#   3. 有界 flush + 双优先级：一轮 flush 内循环消化 effect 写 effect 的级联，
#      100 pass 上限 raise FlushOverflow 并点名肇事 effect；render effect
#      先于用户 effect、同级按入队序。
#   4. Owner 树 + effect 重跑前 clean()：子 owner 树、cleanups LIFO、dispose
#      幂等；effect 每次重跑先销毁上一轮的子作用域（listener/token 挂
#      OnCleanup 的资源不泄漏）。
#
# 单线程纪律：一个图只在其创建的执行上下文使用（UI 循环在 Isolated
# context；跨线程各自建图，跨界用 Channel 传不可变快照——architecture §4.2）。

module Tessell
  module Signal
    # 一轮追踪运行的 id；link.run_stamp != 当前 id 的链在 run 结束时摘除。
    # link.source_version 记录上次读到该上游时的 version，用于 pull 验证。
    class Link
      getter source : Node
      getter dependent : Node
      property next_sub : Link?
      property prev_sub : Link?
      property next_dep : Link?
      property prev_dep : Link?
      property run_stamp : Int32
      property source_version : Int32

      def initialize(@source : Node, @dependent : Node, @run_stamp : Int32)
        @source_version = @source.version
        @source.add_sub(self)
        @dependent.add_dep(self)
      end
    end

    abstract class Node
      property first_sub : Link? = nil
      property last_sub : Link? = nil
      property first_dep : Link? = nil
      property last_dep : Link? = nil
      property version : Int32 = 0
      property pending : Bool = false
      property dirty : Bool = false
      property disposed : Bool = false
      property owner : Owner? = nil
      property label : String = ""

      def add_sub(link : Link) : Nil
        link.prev_sub = @last_sub
        link.next_sub = nil
        if (tail = @last_sub)
          tail.next_sub = link
        else
          @first_sub = link
        end
        @last_sub = link
      end

      def remove_sub(link : Link) : Nil
        if (prev = link.prev_sub)
          prev.next_sub = link.next_sub
        else
          @first_sub = link.next_sub
        end
        if (nxt = link.next_sub)
          nxt.prev_sub = link.prev_sub
        else
          @last_sub = link.prev_sub
        end
        link.prev_sub = nil
        link.next_sub = nil
      end

      def add_dep(link : Link) : Nil
        link.prev_dep = @last_dep
        link.next_dep = nil
        if (tail = @last_dep)
          tail.next_dep = link
        else
          @first_dep = link
        end
        @last_dep = link
      end

      def remove_dep(link : Link) : Nil
        if (prev = link.prev_dep)
          prev.next_dep = link.next_dep
        else
          @first_dep = link.next_dep
        end
        if (nxt = link.next_dep)
          nxt.prev_dep = link.prev_dep
        else
          @last_dep = link.prev_dep
        end
        link.prev_dep = nil
        link.next_dep = nil
      end

      # dispose：从所有上游退订（双向链摘除），幂等。
      def dispose : Nil
        return if @disposed
        @disposed = true
        link = @first_dep
        while link
          nxt = link.next_dep
          link.source.remove_sub(link)
          remove_dep(link)
          link = nxt
        end
      end
    end

    class Signal(T) < Node
      @value : T

      def initialize(@value : T, label : String = "", owner : Owner? = nil)
        @label = label
        Tessell::Signal.bind(self, owner)
      end

      # 追踪读：处于 effect/memo 计算内时建立依赖。
      def get : T
        Tessell::Signal.track_read(self)
        @value
      end

      # 非追踪读：永不建立依赖（asuka 的故意一次出口）。
      def peek : T
        @value
      end

      def set(value : T) : Nil
        return if @disposed
        return if value == @value
        @value = value
        @version += 1
        Tessell::Signal.push_dirty(self)
        Tessell::Signal.flush
      end

      def update(&f : T -> T) : Nil
        set(f.call(@value))
      end
    end

    class Memo(T) < Node
      @compute : Proc(T)
      @value : T
      @prev : T? = nil
      @has_value = false

      def initialize(@compute : Proc(T), label : String = "", owner : Owner? = nil)
        # 惰性求值：@value 由首次 settle!/recompute! 赋值（@has_value 守卫）。
        @value = uninitialized T
        @label = label
        Tessell::Signal.bind(self, owner)
      end

      def get : T
        settle!
        # settle 之后盖戳：version 已定，下游的真变验证才可靠
        Tessell::Signal.track_read(self)
        @value
      end

      def peek : T
        settle!
        @value
      end

      # 未计算/dirty → 重算；pending → 按 version 戳验证上游真变再决定。
      # protected：上游 memo 拉直时同类实例间调用。
      protected def settle! : Nil
        return if @disposed
        if !@has_value || @dirty
          recompute!
        elsif @pending
          if upstream_changed?
            recompute!
          else
            @pending = false
          end
        end
      end

      private def upstream_changed? : Bool
        link = @first_dep
        while link
          src = link.source
          if src.is_a?(Memo)
            src.settle! # memo 上游先拉直，version 才可信
          end
          return true if src.version != link.source_version
          link = link.next_dep
        end
        false
      end

      private def recompute! : Nil
        @dirty = false
        @pending = false
        had = @has_value
        @prev = @value if had
        prev_tracker = Tessell::Signal.begin_tracking(self)
        graph = Tessell::Signal::GRAPH
        prev_pulling = graph.pulling
        graph.pulling = true
        begin
          @value = @compute.call
          @has_value = true
          changed = if had
                      @value != @prev.not_nil!
                    else
                      true
                    end
          if changed
            @version += 1
            # pull 路径的传播必须在 pulling 窗口内：运行中的 effect 自身
            # 不重复入队（它本次读已拿到新值）。
            Tessell::Signal.push_dirty(self)
          else
            Tessell::Signal.clear_pending_downstream(self) # 派生值相等：截断传播
          end
        ensure
          graph.pulling = prev_pulling
        end
        Tessell::Signal.end_tracking(self, prev_tracker)
        @prev = nil
      end
    end

    class Effect < Node
      property run : Proc(Nil)
      property render : Bool
      property queued = false
      property has_run = false
      # 上一轮重跑的子作用域；重跑前 dispose（cleanups LIFO）。
      property scope : Owner? = nil

      def initialize(@run : Proc(Nil), @render : Bool = false,
                     label : String = "", owner : Owner? = nil)
        @label = label
        Tessell::Signal.bind(self, owner)
        # Solid 语义：创建即首跑（batch 内则排队，flush 时跑）。
        Tessell::Signal.queue_effect(self)
        Tessell::Signal.flush
      end

      def dispose : Nil
        super
        @queued = false
        @scope.try(&.dispose)
        @scope = nil
      end
    end

    class Owner
      property parent : Owner? = nil
      @children = [] of Owner
      @nodes = [] of Node
      @cleanups = [] of Proc(Nil)
      @disposed = false

      def disposed? : Bool
        @disposed
      end

      # 注册清理回调（LIFO）。effect 重跑与 dispose 时执行。
      def on_cleanup(&block : -> Nil) : Nil
        return if @disposed
        @cleanups << block
      end

      def adopt(node : Node) : Nil
        return if @disposed
        @nodes << node
        node.owner = self
      end

      def adopt_child(child : Owner) : Nil
        return if @disposed
        @children << child
        child.parent = self
      end

      # 清空作用域内容（cleanups LIFO、子节点停止、缓冲保留）——effect 重跑前
      # 调用（asuka 的 clean()）：对象与数组复用，稳态零分配。幂等。
      def clean : Nil
        until @cleanups.empty?
          @cleanups.pop.call
        end
        @nodes.each(&.dispose)
        @children.each(&.dispose)
        @nodes.clear
        @children.clear
        @disposed = false
      end

      def dispose : Nil
        return if @disposed
        clean
        @disposed = true
        if (p = @parent)
          p.forget(self)
        end
        @parent = nil
      end

      protected def forget(child : Owner) : Nil
        @children.delete(child)
      end
    end

    class FlushOverflow < ::Exception
    end

    # 单图状态：绑定创建它的执行上下文（单线程纪律见文件头）。
    private class Graph
      property tracking : Node? = nil
      property current_owner : Owner? = nil
      property run_id = 0
      property batch_depth = 0
      property flushing = false
      # memo 拉取重算进行中（pull 路径）；push_dirty 用于抑制正在运行的
      # effect 自身的重复入队。
      property pulling = false
      property seq = 0
      getter render_queue = [] of Effect
      getter user_queue = [] of Effect
      getter render_head = 0
      getter user_head = 0

      def queue(render : Bool, effect : Effect) : Nil
        if render
          render_queue << effect
        else
          user_queue << effect
        end
      end

      # 弹出下一个待跑 effect（render 先于 user、同级 FIFO）；耗尽即复位缓冲
      # （clear 保留容量——稳态零分配）。
      def next_effect : Effect?
        if render_head < render_queue.size
          e = render_queue[render_head]
          @render_head += 1
          return e
        end
        if user_head < user_queue.size
          e = user_queue[user_head]
          @user_head += 1
          return e
        end
        render_queue.clear
        user_queue.clear
        @render_head = 0
        @user_head = 0
        nil
      end

      def reset_queues : Nil
        render_queue.each { |e| e.queued = false }
        user_queue.each { |e| e.queued = false }
        render_queue.clear
        user_queue.clear
        @render_head = 0
        @user_head = 0
      end
    end

    GRAPH = Graph.new

    def self.current_tracker : Node?
      GRAPH.tracking
    end

    def self.batching? : Bool
      GRAPH.batch_depth > 0
    end

    def self.bind(node : Node, owner : Owner?) : Nil
      target = owner || GRAPH.current_owner
      target.try(&.adopt(node))
    end

    def self.run_under(node : Node, &) : Nil
      prev = GRAPH.tracking
      GRAPH.tracking = node
      yield
    ensure
      GRAPH.tracking = prev
    end

    # 开启一轮追踪：分配新 run id，link 的 run_stamp 以此对齐。
    def self.begin_tracking(node : Node) : Node?
      prev = GRAPH.tracking
      GRAPH.run_id += 1
      GRAPH.tracking = node
      prev
    end

    # 追踪读登记：复用同 source 的既有 link（盖两枚戳），没有才新建。
    # 稳态零分配的关键路径。
    def self.track_read(node : Node) : Nil
      tracker = GRAPH.tracking
      return unless tracker
      link = tracker.first_dep
      while link
        if link.source.same?(node)
          link.run_stamp = GRAPH.run_id
          link.source_version = node.version
          return
        end
        link = link.next_dep
      end
      Link.new(node, tracker, GRAPH.run_id)
    end

    # 一轮追踪结束：摘除没走到的 link（动态依赖收缩）。run_id 已由
    # begin_tracking 分配，本方法不再递增——否则本轮 link 会被误杀。
    def self.end_tracking(tracker : Node, restore : Node?) : Nil
      GRAPH.tracking = restore
      link = tracker.first_dep
      while link
        nxt = link.next_dep
        if link.run_stamp != GRAPH.run_id
          link.source.remove_sub(link)
          tracker.remove_dep(link)
        end
        link = nxt
      end
    end

    # 直接订阅者 push dirty（version 真变的源头调用）。
    # 例外：memo 拉取（pull）路径的重算触达「正在运行的 effect 自身」时不
    # 入队——本次变更是该 effect 自己的读触发的，读已返回新值，再跑一次
    # 是纯空跑。signal.set（写路径）不受此抑制：effect 写自己的依赖必须
    # 级联（有界 flush 保护自激）。
    def self.push_dirty(source : Node) : Nil
      link = source.first_sub
      while link
        dep = link.dependent
        unless dep.disposed
          if dep.is_a?(Memo)
            dep.dirty = true
            unless dep.pending
              dep.pending = true
              push_pending(dep)
            end
          elsif dep.is_a?(Effect)
            unless GRAPH.pulling && (t = GRAPH.tracking) && dep.same?(t)
              queue_effect(dep)
            end
          end
        end
        link = link.next_sub
      end
    end

    # 下游 push 更廉价的 pending；已 pending 即剪枝。effect 也在此时入队
    # （queued 去重）——宁可空跑一次也不许漏更新。
    private def self.push_pending(source : Node) : Nil
      link = source.first_sub
      while link
        dep = link.dependent
        unless dep.disposed
          if dep.is_a?(Memo)
            unless dep.pending
              dep.pending = true
              push_pending(dep)
            end
          elsif dep.is_a?(Effect)
            # 与 push_dirty 同一抑制：拉取路径不重复入队运行中的 effect。
            # pending 标志只属于 memo 簿记，effect 入队去重靠 queued。
            unless GRAPH.pulling && (t = GRAPH.tracking) && dep.same?(t)
              queue_effect(dep)
            end
          end
        end
        link = link.next_sub
      end
    end

    # 派生值相等：清除下游 pending（不重算、不 dirty）。Memo 重算后回调。
    def self.clear_pending_downstream(source : Node) : Nil
      link = source.first_sub
      while link
        dep = link.dependent
        if dep.is_a?(Memo) && dep.pending && !dep.dirty
          dep.pending = false
          clear_pending_downstream(dep)
        end
        link = link.next_sub
      end
    end

    def self.queue_effect(effect : Effect) : Nil
      return if effect.queued || effect.disposed
      effect.queued = true
      GRAPH.queue(effect.render, effect)
    end

    # 有界 flush：render effect 先于用户 effect，同级 FIFO；级联上限 100 pass。
    def self.flush : Nil
      return if GRAPH.flushing || GRAPH.batch_depth > 0
      GRAPH.flushing = true
      passes = 0
      begin
        loop do
          e = GRAPH.next_effect
          break unless e
          passes += 1
          if passes > 100
            culprit = e.label.empty? ? "effect@0x#{e.object_id.to_s(16)}" : e.label
            GRAPH.reset_queues
            raise FlushOverflow.new("Signal flush exceeded 100 passes; culprit: #{culprit}")
          end
          run_effect(e)
        end
      ensure
        GRAPH.flushing = false
        GRAPH.reset_queues
      end
    end

    # effect 的依赖在上一轮运行后是否真的变了（memo 先拉直再比对 version）。
    # 首跑不受此检（依赖未建立）。
    private def self.effect_deps_changed?(effect : Effect) : Bool
      link = effect.first_dep
      while link
        src = link.source
        if src.is_a?(Memo)
          src.settle!
        end
        return true if src.version != link.source_version
        link = link.next_dep
      end
      false
    end

    private def self.run_effect(effect : Effect) : Nil
      effect.queued = false
      effect.pending = false
      if effect.has_run
        # 预检置 pulling+tracking=effect：预检中的 memo 拉直等同 effect 自己
        # 的读，不重复入队。依赖 version 未变 → 写路径 pending 入队的是空跑，
        # 跳过（不漏更新：真变时 version 必不同）。
        prev_pull = GRAPH.pulling
        prev_track = GRAPH.tracking
        GRAPH.pulling = true
        GRAPH.tracking = effect
        changed = effect_deps_changed?(effect)
        GRAPH.pulling = prev_pull
        GRAPH.tracking = prev_track
        return unless changed
      end
      # 重跑前 clean：清空上一轮子作用域（cleanups LIFO、子 effect 停止）。
      # Owner 对象与内部缓冲跨轮复用——稳态零分配。
      if (scope = effect.scope)
        scope.clean
      else
        scope = Owner.new
        effect.owner.try(&.adopt_child(scope))
        effect.scope = scope
      end
      prev_owner = GRAPH.current_owner
      GRAPH.current_owner = scope
      prev_tracker = begin_tracking(effect)
      begin
        effect.run.call
        effect.has_run = true
      ensure
        GRAPH.current_owner = prev_owner
        end_tracking(effect, prev_tracker)
      end
    end

    def self.batch(&) : Nil
      GRAPH.batch_depth += 1
      begin
        yield
      ensure
        GRAPH.batch_depth -= 1
        flush if GRAPH.batch_depth == 0
      end
    end

    def self.untrack(&) : Nil
      prev = GRAPH.tracking
      GRAPH.tracking = nil
      begin
        yield
      ensure
        GRAPH.tracking = prev
      end
    end

    # ---- 构造入口 ----

    def self.signal(value, label : String = "", owner : Owner? = nil)
      Signal(typeof(value)).new(value, label, owner)
    end

    # memo 的类型参数从块体静态推导：宏把块体包进显式 lambda，再以
    # typeof(%proc.call) 在调用点求返回类型。本工具链的自由方法不支持
    # 类型变量推断（x : T 在方法签名上不可用），typeof(compute.call) 对
    # 未注解块恒为 Nil——这是绕开该限制的写法。
    macro memo(label = "", owner = nil, &compute)
      %proc = -> do
        {{ compute.body }}
      end
      Tessell::Signal::Memo(typeof(%proc.call)).new(%proc, {{ label }}, {{ owner }})
    end

    def self.effect(label : String = "", owner : Owner? = nil, &run : -> Nil) : Effect
      Effect.new(run, false, label, owner)
    end

    def self.render_effect(label : String = "", owner : Owner? = nil, &run : -> Nil) : Effect
      Effect.new(run, true, label, owner)
    end

    # 在当前响应式作用域注册清理（effect 体内/owner 下）。
    def self.on_cleanup(&block : -> Nil) : Nil
      owner = GRAPH.current_owner
      raise ::RuntimeError.new("on_cleanup outside a reactive scope") unless owner
      owner.on_cleanup(&block)
    end
  end
end
