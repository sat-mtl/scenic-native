#!/bin/sh
# Run Scenic from this checkout: ossia score with the QML shell.
# See tools/env.sh for SCORE_BIN and SCENIC_GST_SDK.
# --debug also opens score's own editor beside the shell.
set -eu
cd "$(dirname "$0")"
. tools/env.sh
require_score

UI_FLAG=--ui
if [ "${1:-}" = "--debug" ]; then
  UI_FLAG=--ui-debug
  shift
fi

export QML_IMPORT_PATH="$PWD/qml${QML_IMPORT_PATH:+:$QML_IMPORT_PATH}"
export QML2_IMPORT_PATH="$QML_IMPORT_PATH"

exec "$SCORE_BIN" "$UI_FLAG" qml/Main.qml --no-restore "$@"
