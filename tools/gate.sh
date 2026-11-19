#!/usr/bin/env bash
# 跨平台 L0 门禁（issue #61 X2，cross-platform-plan §5.1）。
# 与 tools/gate.ps1 共享同一组判据：编译 0 退出、spec 0 failures、
# headless gallery 输出 KIT_GALLERY_VERIFY verify=pass。
# Windows 保留 gate.ps1；Linux/macOS/CI 用本脚本。
#
# 用法：bash tools/gate.sh [--quick]
#   --quick 只跑选定套件（spec/kit + spec/apps + 平台契约 + 文本）；
#   默认全量 crystal spec（X0 之后三平台字体均由 TestFonts 解析）。

set -e
cd "$(dirname "$0")/.."

echo "== build =="
crystal build src/tessell.cr --no-codegen
crystal build src/tessell/kit.cr --no-codegen
crystal build examples/app_calculator.cr --no-codegen
crystal build examples/app_text_editor.cr --no-codegen

echo "== spec =="
if [ "${1:-}" = "--quick" ]; then
  crystal spec spec/kit spec/apps spec/platform_host_spec.cr spec/font_stack_spec.cr spec/font_ttc_face_spec.cr
else
  crystal spec
fi

echo "== headless gallery =="
crystal run examples/kit_gallery.cr -- --verify --frames=30

echo "GATE [PASS]"
