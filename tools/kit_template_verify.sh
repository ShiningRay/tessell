#!/usr/bin/env bash
# 第三方组件包模板验证（issue #68）：
# 拷贝 templates/kit-component 到临时目录（模拟真实外部仓），把 path 依赖
# 指回本仓，shards install + crystal spec——退出码 0 即模板门槛通过。
# 与 kit_consumer_verify.sh 同款隔离口径（不使用仓内相对 require）。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Windows shards 的 path 依赖要求盘符路径（MSYS 的 /c/... 会被误拼为
# C:\c\...）；cygpath 在 git bash/msys 均可用，Linux/macOS 下原样返回。
if command -v cygpath >/dev/null 2>&1; then
  ROOT="$(cygpath -m "$ROOT")"
fi

cp -r "$ROOT/templates/kit-component/." "$TMP/"
# 模板仓的 path 依赖指回本仓（真实发布时是 github: + version 约束）
cat >"$TMP/shard.yml" <<YAML
name: tessell-badge
version: 0.1.0
dependencies:
  tessell:
    path: $ROOT
YAML

cd "$TMP"
shards install >/dev/null
crystal spec
echo "KIT_TEMPLATE_VERIFY verify=pass"
