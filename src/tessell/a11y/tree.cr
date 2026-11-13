# Tessell::A11y (M2-WP5)
#
# 平台无关的最小无障碍树（只读镜像），不做 UIA COM provider。
# - focused 单一真相：由 FocusManager#focused?(node) 实时查询，不另存。
# - core/node.cr 不改；通过 Meta 旁挂提供 name/value/focusable/enabled。
# - VirtualWindow 仅暴露虚拟列表可见窗口节点（children_count=逻辑总行数）。
require "../geometry"
require "../core/node"
require "../input/focus"
require "../widgets/virtual_list"

module Tessell
  module A11y
    enum Role
      Window
      Group
      Text
      Button
      List
      ListItem
      ScrollView
      Scrollbar
    end

    struct Meta
      getter role : Role
      getter name : String
      getter value : String
      getter focusable : Bool
      getter enabled : Bool

      def initialize(@role : Role = Role::Group,
                     @name : String = "",
                     @value : String = "",
                     @focusable : Bool = false,
                     @enabled : Bool = true)
      end
    end

    struct Node
      getter id : UInt64
      getter role : Role
      getter name : String
      getter value : String
      getter bounds : Tessell::Rect
      getter focusable : Bool
      getter focused : Bool
      getter enabled : Bool
      getter children_count : Int32
      getter index_in_parent : Int32
      getter scroll_offset : Int32

      def initialize(@id : UInt64,
                     @role : Role,
                     @name : String,
                     @value : String,
                     @bounds : Tessell::Rect,
                     @focusable : Bool,
                     @focused : Bool,
                     @enabled : Bool,
                     @children_count : Int32,
                     @index_in_parent : Int32,
                     @scroll_offset : Int32 = 0)
      end
    end

    class Builder
      @focus : Input::FocusManager?
      @meta : Hash(UInt64, Meta)

      def initialize(@focus : Input::FocusManager? = nil)
        @meta = {} of UInt64 => Meta
      end

      def set_meta(id : UInt64, role : Role = Role::Group,
                   name : String = "", value : String = "",
                   focusable : Bool = false, enabled : Bool = true) : Nil
        @meta[id] = Meta.new(role, name, value, focusable, enabled)
      end

      def meta_for(id : UInt64) : Meta?
        @meta[id]?
      end

      # DFS 先序遍历 retained 树，向复用 sink 追加 A11y::Node。
      # 调用方/内部约定：每次 build 前先 clear sink（本方法内部也 clear，保证复用）。
      def build(root : Tessell::Node, sink : Array(A11y::Node)) : Nil
        sink.clear
        walk(root, 0, sink)
      end

      # J1: 空树 → sink 空
      def build(root : Nil, sink : Array(A11y::Node)) : Nil
        sink.clear
      end

      private def walk(node : Tessell::Node, index_in_parent : Int32, sink : Array(A11y::Node)) : Nil
        nid = node_id(node)
        m = @meta[nid]?
        role = m ? m.role : Role::Group
        name = m ? m.name : ""
        value = m ? m.value : ""
        focusable = m ? m.focusable : false
        enabled = m ? m.enabled : true
        focused = @focus.try(&.focused?(node)) || false
        children_count = node.children.size
        sink << A11y::Node.new(
          id: nid,
          role: role,
          name: name,
          value: value,
          bounds: node.bounds,
          focusable: focusable,
          focused: focused,
          enabled: enabled,
          children_count: children_count,
          index_in_parent: index_in_parent,
          scroll_offset: 0
        )
        children = node.children
        i = 0
        while i < children.size
          walk(children[i], i, sink)
          i += 1
        end
      end

      private def node_id(node : Tessell::Node) : UInt64
        node.object_id.to_u64
      end
    end

    # 虚拟列表 a11y 适配：只产出可见窗口对应的节点，不物化全部行。
    # children_count 反映逻辑总行数；scroll_offset 反映当前滚动位置。
    class VirtualWindow
      @focus : Input::FocusManager?

      def initialize(@focus : Input::FocusManager? = nil)
      end

      def emit(list : Widgets::VirtualList, sink : Array(A11y::Node),
               container_bounds : Tessell::Rect = Tessell::Rect.new(0.0_f32, 0.0_f32, 0.0_f32, 0.0_f32),
               item_role : Role = Role::ListItem,
               name_for : Proc(Int32, String)? = nil) : Nil
        sink.clear
        visible = list.prepare_visible
        # 容器节点（List/ScrollView 语义：携带 children_count 与 scroll_offset）
        sink << A11y::Node.new(
          id: list.object_id.to_u64,
          role: Role::List,
          name: "",
          value: "",
          bounds: container_bounds,
          focusable: false,
          focused: false,
          enabled: true,
          children_count: list.row_count,
          index_in_parent: 0,
          scroll_offset: list.scroll_y
        )
        return if visible <= 0
        first = list.visible_first
        last = list.visible_last
        i = first
        idx = 0
        while i <= last
          nm = name_for ? name_for.call(i) : ""
          sink << A11y::Node.new(
            id: item_id(list, i),
            role: item_role,
            name: nm,
            value: "",
            bounds: Tessell::Rect.new(0.0_f32, 0.0_f32, 0.0_f32, 0.0_f32),
            focusable: false,
            focused: false,
            enabled: true,
            children_count: 0,
            index_in_parent: idx,
            scroll_offset: 0
          )
          i += 1
          idx += 1
        end
      end

      private def item_id(list : Widgets::VirtualList, index : Int32) : UInt64
        # 稳定合成 id（不依赖行对象物化）：list 身份混入行索引
        base = list.object_id.to_u64
        (base &* 131542391_u64) ^ index.to_u64 ^ 0x9e3779b97f4a7c15_u64
      end
    end
  end
end