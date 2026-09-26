#!/usr/bin/env bash
# Static checks and hardware-free tests. Never sends lighting commands.
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."

omarchy plugin validate .
mapfile -d '' qml_files < <(find qml -name '*.qml' -print0)
"${QMLLINT:-/usr/lib/qt6/bin/qmllint}" Panel.qml "${qml_files[@]}"
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests -v
for test in tests/js/test_*.cjs; do node "$test"; done
QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 \
  "${QMLTESTRUNNER:-/usr/lib/qt6/bin/qmltestrunner}" -input tests/qml
timeout --kill-after=2s 15s env -u WAYLAND_DISPLAY QT_QPA_PLATFORM=offscreen AURA_TEST_ROOT="$PWD" \
  quickshell -p tests/quickshell/shell.qml --no-color
git diff --check
