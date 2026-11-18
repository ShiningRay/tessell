# Tessell::Kit::For(T) — keyed 行复用容器（issue #44，对照 asuka control.go
# 机制 4 的 Show/For）。
#
# 行身份 = key_of(item) 派生；数据变化走 reconcile：
#   - 存活行**只 Set 两个可写 signal**（item/index），组件实例跨帧复用
#     （行内编辑态、滚动位置等全部保留）；行内容经 watch effect 响应
#     signal 变更，下一帧 decl diff 自动产出失效（#44 part 2 对接方式）。
#   - 移除行：component.dispose + 行 owner.dispose（item/index signal 一并
#     停止）——此后任何 signal 写不再触发已卸载行的 effect（泄漏契约）。
#   - 新增行：行 owner 收编组件的 signal_owner，销毁路径单一。
#
# 与 asuka 的差异（研判后简化，commit 有记录）：asuka 用 LIS 决定 DOM
# 移动；Tessell 是 retained 树、每帧按子序重新 emit，重排 = 数组重排，
# 无逐行移动成本——LIS 省略，键控复用（真正的成本所在）完整保留。
# 重复行 key 与 #43 同性质（身份冲突），reconcile fail-fast。

module Tessell
  module Kit
    class For(T) < Container
      # 行句柄：组件 + 两个可写 signal + 行作用域（item/index/组件 watch 全在树上）。
      private class Row(T)
        getter component : Component
        getter item : Tessell::Signal::Signal(T)
        getter index : Tessell::Signal::Signal(Int32)
        getter owner : Tessell::Signal::Owner

        def initialize(@component, @item, @index, @owner)
        end

        def dispose : Nil
          @component.dispose # 停组件自己的 watch effect（幂等）
          @owner.dispose     # 停 item/index signal 的全部订阅
        end
      end

      @key_of : T -> UInt64
      @build : Proc(T, Tessell::Signal::Signal(T), Tessell::Signal::Signal(Int32), UI::UiKey, Component)
      @rows : Hash(UInt64, Row(T))
      @order : Array(UInt64)

      def initialize(key : UI::UiKey, @key_of : Proc(T, UInt64),
                     padding : Insets = Insets.new,
                     spacing : Float32 = 0.0_f32,
                     alignment : Alignment = Alignment::Start,
                     enabled : Bool = true,
                     &build : T, Tessell::Signal::Signal(T), Tessell::Signal::Signal(Int32), UI::UiKey -> Component)
        super(key, Layout::Direction::Vertical, padding, spacing, alignment, enabled)
        @rows = {} of UInt64 => Row(T)
        @order = [] of UInt64
        @build = build
      end

      # 数据入口：reconcile——只 Set 存活行、dispose 移除行、构建新增行。
      def items=(list : Array(T)) : Nil
        new_keys = list.map { |it| @key_of.call(it) }

        # 重复行 key = 身份冲突（#43 同性质），fail-fast
        seen = Set(UInt64).new
        new_keys.each do |k|
          unless seen.add?(k)
            raise ArgumentError.new("For: duplicate row key #{k} (same identity as #43); make key_of injective")
          end
        end

        # 移除：不在新集合的行 dispose（组件 + 行 owner）
        removed = Set(UInt64).new(@order.to_a)
        new_keys.each { |k| removed.delete(k) }
        removed.each do |k|
          if (row = @rows[k]?)
            row.dispose
            @rows.delete(k)
          end
        end

        children_buf = [] of Component
        list.each_with_index do |item, idx|
          k = @key_of.call(item)
          if (row = @rows[k]?)
            # 存活行：只 Set（值相等时 Signal#set 内部 no-op），实例不重建
            row.item.set(item)
            row.index.set(idx)
            children_buf << row.component
          else
            row_owner = Tessell::Signal::Owner.new
            item_sig = Tessell::Signal::Signal(T).new(item, "for.item", row_owner)
            index_sig = Tessell::Signal::Signal(Int32).new(idx, "for.index", row_owner)
            child_key = @key.child(k)
            component = @build.call(item, item_sig, index_sig, child_key)
            component.parent = self
            # 组件的响应式作用域收编到行 owner——销毁路径单一
            if (comp_owner = component.signal_owner?)
              row_owner.adopt_child(comp_owner)
            end
            @rows[k] = Row(T).new(component, item_sig, index_sig, row_owner)
            children_buf << component
          end
        end

        # 键序变化（增/删/重排）= 结构变更（issue #51 同口径）：沿父链打脏标记，
        # Root#build 消费后补 arrange——否则新增行停在零 bounds、命中不可达。
        # 只 Set item/index 的值更新（键序不变）不打标记，稳态不重排。
        structural = new_keys != @order
        @children = children_buf
        mark_structure_dirty if structural
        @order.clear
        @order.concat(new_keys)
      end

      # 当前行组件（测试断言实例身份用）。
      def row_components : Array(Component)
        @children
      end
    end
  end
end
