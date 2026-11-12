# Tessell::Core — retained 节点树与三级失效传播（M1-WP3）。
#
# Invalidation 语义（先定语义再落码）：
#   Layout         子尺寸/结构变化，向上传播：自身 + 全部祖先标 Layout 脏（父需重排）。
#   Paint          仅视觉内容变化、几何不变：只标自身 Paint 脏，不动祖先/兄弟。
#   CompositeOnly  仅合成层变化：不触发 Layout/Paint，仅提交阶段处理。
#
# 选型说明：用普通 enum（plan.md:91）+ 三个独立 Bool 标记，而不是单一 enum 字段或 flags enum：
#   1) 单一 enum 字段无法表达「Layout 与 Paint 同时脏」；
#   2) flags enum 的合并/优先级需手工位运算，易把 CompositeOnly 误升为 Paint；
#   3) 三 Bool + dirty? 显式按 Layout > Paint > CompositeOnly 取最高级，传播规则逐分支可审计。
# propagate_to_parent 只标祖先「需要重排」（Layout），绝不把祖先 Paint 标脏，避免过度失效。
# 本文件不依赖 Platform/FFI/Render；纯内存状态，可单测。
# node.cr 自身依赖 geometry 的 Rect，显式 require 保证单独加载本文件也可编译。
require "../geometry"

module Tessell
  # 三级失效（plan.md:91 用 enum）。枚举值顺序不代表优先级；优先级在 Node#dirty? 显式判定。
  enum Invalidation
    Layout
    Paint
    CompositeOnly
  end

  # retained 树节点：父子双向引用、bounds 几何、三级脏标记。
  class Node
    getter id : String
    property bounds : Rect
    property parent : Node?
    getter children : Array(Node)

    def initialize(@id : String, @bounds : Rect = Rect.new)
      @parent = nil
      @children = [] of Node
      @layout_dirty = false
      @paint_dirty = false
      @composite_dirty = false
    end

    def layout_dirty? : Bool
      @layout_dirty
    end

    def paint_dirty? : Bool
      @paint_dirty
    end

    def composite_dirty? : Bool
      @composite_dirty
    end

    # 当前最高脏级别；全净返回 nil。优先级 Layout > Paint > CompositeOnly。
    def dirty? : Invalidation?
      if @layout_dirty
        Invalidation::Layout
      elsif @paint_dirty
        Invalidation::Paint
      elsif @composite_dirty
        Invalidation::CompositeOnly
      else
        nil
      end
    end

    # 标记失效。Layout 向上传播父链；Paint/CompositeOnly 仅自身。
    def mark_dirty(kind : Invalidation) : Nil
      case kind
      when Invalidation::Layout
        @layout_dirty = true
        propagate_to_parent
      when Invalidation::Paint
        @paint_dirty = true
      when Invalidation::CompositeOnly
        @composite_dirty = true
      end
    end

    # 清除自身三级脏标记（逐级清除由调用方对每层调用）。
    def clean! : Nil
      @layout_dirty = false
      @paint_dirty = false
      @composite_dirty = false
    end

    # 收集子树内全部脏节点（含 root 自身）；静态全净树返回空数组。
    def self.dirty_subtree(root : Node) : Array(Node)
      result = [] of Node
      collect_dirty(root, result)
      result
    end

    # M1-WP5 稳态零分配路径：复用调用方缓冲 sink 的脏节点收集。
    # 约定：进入时 sink.clear（保留容量，不释放）；DFS 写入脏节点；静态全净树 sink 保持空。
    # 不新分配：不用 Array.new/字符串拼接/闭包捕获；子树遍历用 while 索引而非 each+block
    # （块闭包可能分配）。前提：调用方预分配 sink 容量 ≥ 子树节点数；容量不足时 Array#<<
    # 仍会一次性扩容，故 zero_alloc_frame 中按节点数预填槽位保证稳态不扩容。
    def self.collect_dirty(root : Node, sink : Array(Node)) : Nil
      sink.clear
      collect_dirty_impl(root, sink)
    end
    # 挂载子节点：重挂载时先从旧父移除（保证双向一致）；同父重复 add 幂等（不重复追加）。
    # 只改父子引用，不传播/清除脏标记（与 detach 一致：脏失效由调用方负责）。
    def add_child(child : Node) : Node
      old_parent = child.parent
      if old_parent && old_parent != self
        old_parent.remove_child(child)
      end
      if @children.includes?(child)
        child.parent = self
        return child
      end
      child.parent = self
      @children << child
      child
    end

    # 移除子节点并置其 parent=nil；成功返回 true，未挂载返回 false。
    # 不改任何脏标记（保留子树原脏状态，由调用方负责失效决策）。
    def remove_child(child : Node) : Bool
      idx = @children.index(child)
      if idx
        @children.delete_at(idx)
        child.parent = nil
        true
      else
        false
      end
    end

    # 从父节点 detach（根节点无副作用）；只改父子引用，不传播脏标记。
    # 调用方负责决定是否需要额外失效（detach 本身不把子树标脏，也不碰祖先脏标记）。
    def detach : Nil
      parent = @parent
      if parent
        parent.remove_child(self)
      end
    end

    private def propagate_to_parent : Nil
      node = @parent
      while node
        node.mark_layout_only
        node = node.parent
      end
    end

    # 只标 Layout 脏（供 propagate_to_parent 使用）；不碰 Paint/CompositeOnly。
    # Crystal private 为对象级（不能跨实例调用），故设为 public 但仅限内部传播语义。
    def mark_layout_only : Nil
      @layout_dirty = true
    end

    # collect_dirty 的递归实现（不清理 sink，由调用方约定）。
    private def self.collect_dirty_impl(node : Node, sink : Array(Node)) : Nil
      sink << node if node.dirty?
      children = node.children
      i = 0
      while i < children.size
        collect_dirty_impl(children[i], sink)
        i += 1
      end
    end
  end
end
