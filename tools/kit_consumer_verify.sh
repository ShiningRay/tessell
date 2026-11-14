#!/usr/bin/env bash
# Tessell Kit 外部消费者验证（K5）
#
# 在临时目录创建独立 shard，以 Shards path 依赖引用本仓，分别验证：
#   1) require "tessell" 核心入口可编译；
#   2) require "tessell/kit" + Root/Input/a11y 可编译运行。
# 不使用仓内相对 require，避免把“能跑”误判为外部消费者可用。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/core/src" "$TMP/kit/src"

cat >"$TMP/core/shard.yml" <<YAML
name: tessell_consumer_core
version: 0.1.0
dependencies:
  tessell:
    path: $ROOT
YAML
cat >"$TMP/core/src/main.cr" <<'CR'
require "tessell"

puts "CORE_CONSUMER_OK version=#{Tessell::VERSION}"
CR

cat >"$TMP/kit/shard.yml" <<YAML
name: tessell_consumer_kit
version: 0.1.0
dependencies:
  tessell:
    path: $ROOT
YAML
cat >"$TMP/kit/src/main.cr" <<'CR'
require "tessell/kit"

input = Tessell::Kit::Input.new(
  Tessell::UI::UiKey.root.child(1_u64), "", "Type here", "Name"
)
root = Tessell::Kit::Root.new(input)
root.layout(320.0_f32, 160.0_f32)
root.build
root.handle(Tessell::Input::Event.key_down(Tessell::Input::KeyCode::Tab))
root.handle(Tessell::Input::Event.text_input("hi"))
sink = [] of Tessell::A11y::Node
root.a11y_emit(sink)
ok = input.text == "hi" && sink.any? { |n| n.role == Tessell::A11y::Role::TextField }
puts "KIT_CONSUMER_VERIFY verify=#{ok ? "pass" : "fail"} text=#{input.text} a11y=#{sink.size}"
exit ok ? 0 : 1
CR

(cd "$TMP/core" && shards install >/dev/null && crystal run src/main.cr)
(cd "$TMP/kit" && shards install >/dev/null && crystal run src/main.cr)
