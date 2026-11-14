# Tessell::Kit — 可选组件库入口
#
# 使用：require "tessell/kit"
# 核心入口 require "tessell" 不加载本文件；核心不得反向依赖 Kit。

require "../tessell"
require "./kit/theme"
require "./kit/events"
require "./kit/painter"
require "./kit/draw_list_painter"
require "./kit/context"
require "./kit/component"
require "./kit/container"
require "./kit/button"
require "./kit/checkbox"
require "./kit/text"
require "./kit/scroll_view"
require "./kit/virtual_list"
require "./kit/root"

module Tessell
  module Kit
    VERSION = Tessell::VERSION
  end
end
