#!/bin/sh
# Stop the ossia-score instances this repository's tests launched (and only
# those: other score instances on the machine are left alone).
pkill -f "ossia-score --u[i] (qml/Main\.qml|tools/)" 2>/dev/null
rm -f "$HOME/.config/ossia/failsafe.bit"
exit 0
