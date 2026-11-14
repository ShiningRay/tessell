require "./spec_helper"
require "../src/tessell/signal"

# issue #33：Signal(T) 响应式内核六不变量 + API 面。
# 机制对照 asuka signal 包，见 src/tessell/signal.cr 文件头。

S = Tessell::Signal

describe "Tessell::Signal kernel (issue #33)" do
  it "supports get/peek/set/update with tracked reads" do
    sig = S.signal(1)
    runs = 0
    observed = 0
    S.effect { observed = sig.get; runs += 1 }

    runs.should eq(1) # 创建即首跑
    sig.set(2)
    runs.should eq(2)
    observed.should eq(2)
    sig.peek.should eq(2)
    sig.update { |v| v + 1 }
    observed.should eq(3)
    sig.set(3) # 相等写：无传播
    runs.should eq(3)
  end

  it "diamond dependency is glitch-free: effect runs once per source write" do
    a = S.signal(1)
    b = Tessell::Signal.memo { a.get * 10 }
    c = Tessell::Signal.memo { a.get + 1 }
    d = Tessell::Signal.memo { b.get + c.get }
    runs = 0
    last = 0
    S.effect { last = d.get; runs += 1 }

    runs.should eq(1)
    a.set(2) # 菱形：b/c 各算一次，d 一轮内只重算一次，effect 一次
    runs.should eq(2)
    last.should eq((2 * 10) + (2 + 1))
  end

  it "memo equality truncates: no recompute when derived value is unchanged" do
    a = S.signal(1)
    parity = Tessell::Signal.memo { a.get % 2 }
    computes = 0
    parity_effect = Tessell::Signal.memo do
      parity.get
      computes += 1
      computes
    end
    parity_effect.get
    computes_after_first = computes

    a.set(3) # 奇偶不变 → parity 值相等 → 下游 memo 不重算
    parity_effect.peek
    computes.should eq(computes_after_first)

    a.set(4) # 奇偶翻转 → 下游重算一次
    parity_effect.peek
    computes.should eq(computes_after_first + 1)
  end

  it "dynamic dependencies: leaving a branch unsubscribes the stale source" do
    flag = S.signal(true)
    x = S.signal(10)
    y = S.signal(20)
    chosen = Tessell::Signal.memo { flag.get ? x.get : y.get }
    runs = 0
    S.effect { chosen.get; runs += 1 }

    x.set(11)
    runs.should eq(2)

    flag.set(false)   # 依赖切换到 y
    runs.should eq(3)

    x.set(12)         # 旧上游已退订：不再触发
    runs.should eq(3)

    y.set(21)
    runs.should eq(4)
  end

  it "dispose stops effects and detaches subscriptions" do
    sig = S.signal(1)
    runs = 0
    owner = Tessell::Signal::Owner.new
    S.effect(owner: owner) { sig.get; runs += 1 }

    owner.dispose
    owner.disposed?.should be_true

    sig.set(2)
    runs.should eq(1) # dispose 后不再重跑
    sig.peek.should eq(2)

    # dispose 幂等
    owner.dispose
  end

  it "effect rerun cleans the previous child scope (OnCleanup LIFO)" do
    sig = S.signal(0)
    log = [] of String
    S.effect do
      # effect 体内经模块级 on_cleanup 挂当前（每轮重跑）作用域
      Tessell::Signal.on_cleanup { log << "cleanup" }
      log << "run:#{sig.get}"
    end
    log.should eq(["run:0"])

    sig.set(1)
    # 先清理上一轮（LIFO），再执行新一轮
    log.should eq(["run:0", "cleanup", "run:1"])
  end

  it "bounded flush raises FlushOverflow naming the culprit effect" do
    loop_sig = S.signal(0)
    effect = nil
    expect_raises(Tessell::Signal::FlushOverflow, "culprit: cascader") do
      # 自激必须先读后写：读才建立依赖，写不建（update 内部不 track）
      effect = S.effect(label: "cascader") { loop_sig.set(loop_sig.get + 1) }
    end
    # 异常后图仍可用：新 effect 正常
    sig = S.signal(5)
    seen = 0
    S.effect { seen = sig.get }
    sig.set(6)
    seen.should eq(6)
  end

  it "render effects run before user effects in one flush" do
    order = [] of String
    sig = S.signal(0)
    S.effect(label: "user") { sig.get; order << "user" }
    order.clear
    S.render_effect(label: "render") { sig.get; order << "render" }
    order.clear

    sig.set(1)
    order.should eq(["render", "user"])
  end

  it "batch defers effects until the outermost batch closes" do
    sig = S.signal(0)
    runs = 0
    S.effect { sig.get; runs += 1 }
    runs.should eq(1)

    S.batch do
      S.batch do
        sig.set(1)
        sig.set(2)
        runs.should eq(1) # batch 内不跑
      end
      runs.should eq(1) # 内层 batch 结束仍不跑
    end
    runs.should eq(2) # 外层闭合只跑一次
    sig.peek.should eq(2)
  end

  it "untrack reads never create dependencies" do
    sig = S.signal(1)
    other = S.signal(100)
    runs = 0
    S.effect do
      seen = S.untrack { other.get }
      sig.get
      runs += 1
    end
    runs.should eq(1)
    other.set(101)
    runs.should eq(1) # untrack 读不建依赖
    sig.set(2)
    runs.should eq(2)
  end

  it "reuses links across reruns: steady-state set/effect cycle is zero-alloc" do
    sig = S.signal(0)
    derived = Tessell::Signal.memo { sig.get * 2 }
    runs = 0
    S.effect { derived.get; runs += 1 }
    runs.should eq(1)

    # 预热：扩容/首次路径全部走完
    i = 0
    while i < 50
      sig.set(i + 1)
      i += 1
    end

    GC.collect
    before = GC.stats.bytes_since_gc
    j = 0
    while j < 100
      sig.set(1000 + j)
      j += 1
    end
    after = GC.stats.bytes_since_gc

    runs.should eq(151)
    delta = after - before
    delta.should eq(0_i64), "steady-state signal cycle allocated #{delta} bytes"
  end

  it "owner disposes memos and child owners recursively (idempotent)" do
    a = S.signal(1)
    owner = Tessell::Signal::Owner.new
    memo = Tessell::Signal.memo(owner: owner) { a.get + 1 }
    child = Tessell::Signal::Owner.new
    owner.adopt_child(child)
    cleanup_ran = 0
    child.on_cleanup { cleanup_ran += 1 }

    memo.get.should eq(2)
    owner.dispose
    cleanup_ran.should eq(1)

    a.set(10)
    memo.peek.should eq(2) # 已停止：值冻结
    owner.dispose # 幂等
    cleanup_ran.should eq(1)
  end
end
