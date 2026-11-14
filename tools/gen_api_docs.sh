#!/bin/sh
# 生成 API reference 到 site/api（issue #12；输出已 gitignore）
set -e
cd "$(dirname "$0")/.."
crystal docs --output=site/api --project-name=Tessell \
  --project-version="$(cat src/tessell/version.cr | grep -o '"[^"]*"' | head -1 | tr -d '"')" \
  --source-url-pattern="https://github.com/ShiningRay/tessell/blob/main/%{path}#L%{line}"
echo "API docs → site/api"
