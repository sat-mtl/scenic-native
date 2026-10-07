#!/bin/sh
# qmllint over all app QML, filtering warnings that cannot be resolved today:
# score's QML API (Score, Util, System, Library globals, libossia's Protocols
# socket API, and the Score.UI / Score modules) is registered at runtime from
# C++ and ships no qmltypes,
# so qmllint cannot see it. Everything else is reported and fails the script.
#
# TODO(upstream): generate qmltypes for score-plugin-js so this filter and
# the import warnings can go away entirely.
set -eu
cd "$(dirname "$0")/.."

# Find qmllint. Candidates are tried in order and each is *executed* before
# being accepted: a distro can leave a /usr/bin/qmllint wrapper pointing at a
# Qt5 install that has been removed, and PATH order alone would pick it.
if [ -z "${QMLLINT:-}" ]; then
  for c in "${QT_ROOT_DIR:-}/bin/qmllint" \
           "$(command -v qmllint-qt6 2>/dev/null || true)" \
           "$(command -v qmllint6 2>/dev/null || true)" \
           "$(command -v qmllint 2>/dev/null || true)"; do
    if [ -n "$c" ] && [ -x "$c" ] && "$c" --version >/dev/null 2>&1; then
      QMLLINT="$c"; break
    fi
  done
fi
if [ -z "${QMLLINT:-}" ]; then
  echo "lint: no working qmllint found. Set \$QMLLINT or put a Qt6 one on PATH." >&2
  exit 1
fi

FILES=$(find qml tools -name "*.qml")

# Filter blocks: a warning line mentioning a runtime-registered score global
# or module, followed by its code excerpt / hint lines.
OUT=$("$QMLLINT" -I qml $FILES 2>&1 | awk '
  /Warning:|Info:/ {
    skip = /Score\.UI|"Score"|Failed to import Score|UI\.[A-Za-z]+ was not found|Unqualified access/ && prev_global
    prev_global = 0
  }
  /Unqualified access/ {
    getline code
    if (code ~ /(Score|Util|System|Library|Device|Protocols)\./) { skip = 1; next }
    print; print code; next
  }
  /Warnings occurred while importing module "Score/ { skip = 1 }
  /Warnings occurred while importing module "QtWebSockets"/ { skip = 1 }
  /Meta object revision and export version differ/ { skip = 1 }
  /Revision [0-9]+ corresponds to version/ { skip = 1 }
  /Failed to import Score/ { skip = 1 }
  /UI\.(TextureSource|DeviceEnumerator|PortSource|PortSink|AddressSource|DeviceListener|Process) was not found/ { skip = 1 }
  # missing-property / unresolved-type cascades inside unresolved UI.* items
  /Could not find property "(deviceType|enumerate|process|port|visible|fill|margins)"/ { skip = 1 }
  # qmllint suggestion tails ("Did you mean X?" + code + caret). The warning
  # they belong to is printed or filtered on its own merits; the suggestion
  # itself is noise, and it mis-resolves the score globals. Bounded skip of
  # exactly the 3 lines of the block - never an until-blank-line swallow.
  /Info: Did you mean/ { getline; getline; next }
  # UI.* is unresolved, so qmllint cannot know it derives from QObject
  /Cannot assign binding of type UI\.[A-Za-z]+ to QObject/ { skip = 1 }
  /unknown grouped property scope anchors/ { skip = 1 }
  /Type anchors is used but it is not resolved/ { skip = 1 }
  skip { if (/^$/) skip = 0; next }
  { print }
')

if [ -n "$OUT" ]; then
  echo "$OUT"
  echo "--- qmllint: unfiltered warnings above"
  exit 1
fi
echo "qmllint: clean (score runtime globals filtered)"
