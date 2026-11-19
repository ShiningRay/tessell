require "spec"
require "../src/tessell"

# Crystal 1.22：`pending` DSL 宏不能在运行中的 example 里调用
# （Spec::NestingSpecError "Can't nest `it` or `pending`"，issue #61 CI 首轮实测）。
# 运行期缺前置跳过统一用本 helper：runner 捕获 ExamplePending 并把该用例记为 pending。
def pending_skip(message : String) : NoReturn
  raise Spec::ExamplePending.new(message, __FILE__, __LINE__)
end
