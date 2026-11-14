# Tessell::Kit — 单行文本编辑状态（K4）
#
# 光标/选区以 UTF-8 byte offset 表示，但所有移动与删除都按 Graphemes 边界。
# 文档内容修改才改变 text；preedit 只作为组合输入预览，commit 后才写入。

require "./graphemes"

module Tessell
  module Kit
    abstract class Clipboard
      abstract def get : String?
      abstract def set(text : String) : Nil
    end

    class MemoryClipboard < Clipboard
      @value : String?

      def initialize(@value : String? = nil)
      end

      def get : String?
        @value
      end

      def set(text : String) : Nil
        @value = text
      end
    end

    # 编辑态 Tab 语义（issue #32）：真正在编辑文本的组件，Tab 是「插入制表
    # 宽度」还是「提交」由 API 声明，不再各自在 key_down 里手写分支。
    #   Reject —— 默认。insert 遇 \t 整体拒绝（返回 false），Tab 交给组件/
    #             父级处理（表单由 Input#submit_on_tab 提交，表格由父容器接管）。
    #   Insert —— \t 换成 tab_width 个空格插入；文本里永不出现 \t 字形，
    #             measure/光标定位按空格自然一致（不与制表字形宽度耦合）。
    # 提交语义（Submit）属于组件回调层（Input#submit_on_tab），不进编辑状态。
    enum TabBehavior
      Reject
      Insert
    end

    class TextEditing
      getter text : String
      getter cursor : Int32
      getter anchor : Int32?
      getter preedit : String

      # Tab 行为选项（issue #32）；tab_width 仅 Insert 生效。
      property tabs : TabBehavior
      property tab_width : Int32

      @bounds : Array(Int32)
      @bounds_valid : Bool

      def initialize(@text : String = "")
        @cursor = @text.bytesize
        @anchor = nil
        @preedit = ""
        @tabs = TabBehavior::Reject
        @tab_width = 4
        @bounds = [] of Int32
        @bounds_valid = false
      end

      def set_text(value : String) : Nil
        @text = value
        @cursor = value.bytesize
        @anchor = nil
        @preedit = ""
        invalidate_bounds
      end

      def preedit? : Bool
        !@preedit.empty?
      end

      def selection? : Bool
        anchor = @anchor
        !anchor.nil? && anchor != @cursor
      end

      def selection_start : Int32
        anchor = @anchor
        return @cursor unless anchor
        Math.min(anchor, @cursor)
      end

      def selection_end : Int32
        anchor = @anchor
        return @cursor unless anchor
        Math.max(anchor, @cursor)
      end

      def selected_text : String
        return "" unless selection?
        start = selection_start
        @text.byte_slice(start, selection_end - start)
      end

      def select_all : Nil
        @anchor = 0
        @cursor = @text.bytesize
      end

      def collapse_selection : Nil
        @anchor = nil
      end

      def set_cursor(position : Int32, extending : Bool = false) : Nil
        pos = Graphemes.clamp(@text, position)
        if extending
          @anchor ||= @cursor
        else
          @anchor = nil
        end
        @cursor = pos
      end

      def move_left(extending : Bool = false) : Nil
        if !extending && selection?
          @cursor = selection_start
          @anchor = nil
          return
        end
        if extending
          @anchor ||= @cursor
        else
          @anchor = nil
        end
        @cursor = Graphemes.prev_boundary(@text, @cursor)
      end

      def move_right(extending : Bool = false) : Nil
        if !extending && selection?
          @cursor = selection_end
          @anchor = nil
          return
        end
        if extending
          @anchor ||= @cursor
        else
          @anchor = nil
        end
        @cursor = Graphemes.next_boundary(@text, @cursor)
      end

      def move_home(extending : Bool = false) : Nil
        if extending
          @anchor ||= @cursor
        else
          @anchor = nil
        end
        @cursor = 0
      end

      def move_end(extending : Bool = false) : Nil
        if extending
          @anchor ||= @cursor
        else
          @anchor = nil
        end
        @cursor = @text.bytesize
      end

      # 返回 text 是否变化。包含 \t 的插入按 tabs 语义守住（issue #32）：
      # Reject 整体拒绝；Insert 把每个 \t 展开为 tab_width 个空格——文本
      # 里永不出现 \t 字形，宽度与光标不依赖字体制表位。
      def insert(value : String) : Bool
        return false if value.empty?
        if value.includes?('\t')
          return false if @tabs == TabBehavior::Reject
          value = value.gsub('\t', " " * @tab_width)
        end
        replace_selection(value)
        true
      end

      def backspace : Bool
        if selection?
          replace_selection("")
          return true
        end
        return false if @cursor <= 0
        start = Graphemes.prev_boundary(@text, @cursor)
        replace_range(start, @cursor, "")
        true
      end

      def delete : Bool
        if selection?
          replace_selection("")
          return true
        end
        return false if @cursor >= @text.bytesize
        finish = Graphemes.next_boundary(@text, @cursor)
        replace_range(@cursor, finish, "")
        true
      end

      def copy(clipboard : Clipboard) : Bool
        value = selected_text
        return false if value.empty?
        clipboard.set(value)
        true
      end

      def cut(clipboard : Clipboard) : Bool
        return false unless copy(clipboard)
        replace_selection("")
        true
      end

      def paste(clipboard : Clipboard) : Bool
        value = clipboard.get
        return false unless value
        insert(value)
      end

      def set_preedit(value : String) : Nil
        @preedit = value
      end

      def commit_preedit : Bool
        return false if @preedit.empty?
        value = @preedit
        @preedit = ""
        insert(value)
      end

      def boundaries : Array(Int32)
        unless @bounds_valid
          @bounds = Graphemes.boundaries(@text)
          @bounds_valid = true
        end
        @bounds
      end

      private def replace_selection(value : String) : Nil
        if selection?
          replace_range(selection_start, selection_end, value)
        else
          replace_range(@cursor, @cursor, value)
        end
      end

      private def replace_range(start : Int32, finish : Int32, value : String) : Nil
        before = start > 0 ? @text.byte_slice(0, start) : ""
        after = finish < @text.bytesize ? @text.byte_slice(finish, @text.bytesize - finish) : ""
        @text = "#{before}#{value}#{after}"
        @cursor = start + value.bytesize
        @anchor = nil
        @preedit = ""
        invalidate_bounds
      end

      private def invalidate_bounds : Nil
        @bounds_valid = false
      end
    end
  end
end
