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
      CheckBox
      RadioButton
      TextField
      ComboBox
      Dialog
      Tooltip
      List
      ListItem
      ListBox
      Option
      ScrollView
      Scrollbar
      # 二维网格语义（issue #31）：命名对齐 UIA DataItem/Grid /
      # NSAccessibility GridCell / AT-SPI TableCell，平台 provider 可直接映射。
      Grid
      GridCell
      RowHeader
      ColumnHeader
    end

    struct Meta
      getter role : Role
      getter name : String
      getter value : String
      getter focusable : Bool
      getter enabled : Bool
      # nil = 使用 retained 子节点数；虚拟列表等可覆盖为逻辑总数。
      getter children_count : Int32?
      getter scroll_offset : Int32
      # 二维网格语义（issue #31）：全部默认 nil/false，既有节点零改动。
      # 虚拟化大控件可只报逻辑总量 + first_visible_index（可视窗口起点），
      # provider 能算出可视窗口在逻辑总量中的位置。
      getter row : Int32?
      getter col : Int32?
      getter row_count : Int32?
      getter col_count : Int32?
      getter row_index_text : String?
      getter col_index_text : String?
      getter selected : Bool?
      getter active : Bool?
      getter first_visible_index : Int32?

      def initialize(@role : Role = Role::Group,
                     @name : String = "",
                     @value : String = "",
                     @focusable : Bool = false,
                     @enabled : Bool = true,
                     @children_count : Int32? = nil,
                     @scroll_offset : Int32 = 0,
                     @row : Int32? = nil,
                     @col : Int32? = nil,
                     @row_count : Int32? = nil,
                     @col_count : Int32? = nil,
                     @row_index_text : String? = nil,
                     @col_index_text : String? = nil,
                     @selected : Bool? = nil,
                     @active : Bool? = nil,
                     @first_visible_index : Int32? = nil)
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
      # 二维网格语义（issue #31）：nil = 非 grid 场景。
      getter row : Int32?
      getter col : Int32?
      getter row_count : Int32?
      getter col_count : Int32?
      getter row_index_text : String?
      getter col_index_text : String?
      getter selected : Bool?
      getter active : Bool?
      getter first_visible_index : Int32?

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
                     @scroll_offset : Int32 = 0,
                     @row : Int32? = nil,
                     @col : Int32? = nil,
                     @row_count : Int32? = nil,
                     @col_count : Int32? = nil,
                     @row_index_text : String? = nil,
                     @col_index_text : String? = nil,
                     @selected : Bool? = nil,
                     @active : Bool? = nil,
                     @first_visible_index : Int32? = nil)
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
                   focusable : Bool = false, enabled : Bool = true,
                   children_count : Int32? = nil,
                   scroll_offset : Int32 = 0,
                   row : Int32? = nil, col : Int32? = nil,
                   row_count : Int32? = nil, col_count : Int32? = nil,
                   row_index_text : String? = nil, col_index_text : String? = nil,
                   selected : Bool? = nil, active : Bool? = nil,
                   first_visible_index : Int32? = nil) : Nil
        @meta[id] = Meta.new(role, name, value, focusable, enabled,
          children_count, scroll_offset, row, col, row_count, col_count,
          row_index_text, col_index_text, selected, active, first_visible_index)
      end

      def meta_for(id : UInt64) : Meta?
        @meta[id]?
      end

      # 删除指定节点的旁挂元数据，返回是否存在并已删除。
      # UI.apply 在节点被移除时必须调用，避免 id 复用（object_id）残留旧语义。
      def remove_meta(id : UInt64) : Bool
        !@meta.delete(id).nil?
      end

      # 焦点实时查询：与 build 内 focused 同源，供 UI.a11y_emit 复用。
      def focused?(node : Tessell::Node) : Bool
        @focus.try(&.focused?(node)) || false
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
        children_count = m && m.children_count ? m.children_count.not_nil! : node.children.size
        scroll_offset = m ? m.scroll_offset : 0
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
          scroll_offset: scroll_offset,
          row: m.try(&.row),
          col: m.try(&.col),
          row_count: m.try(&.row_count),
          col_count: m.try(&.col_count),
          row_index_text: m.try(&.row_index_text),
          col_index_text: m.try(&.col_index_text),
          selected: m.try(&.selected),
          active: m.try(&.active),
          first_visible_index: m.try(&.first_visible_index)
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
