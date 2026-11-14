#!/usr/bin/env bash
# Run a Tessell Kit SDL demo with the right link flags.
# Usage:
#   ./tools/run_kit_demo.sh examples/app_calculator.cr
#   ./tools/run_kit_demo.sh examples/app_text_editor.cr --frames=120
set -euo pipefail

FILE="${1:?usage: $0 <demo.cr> [args...]}"
shift || true

if [[ "$(uname -s)" == "Darwin" ]]; then
  crystal run "$FILE" --link-flags "-L/opt/homebrew/lib" -- "$@"
else
  crystal run "$FILE" -- "$@"
fi
