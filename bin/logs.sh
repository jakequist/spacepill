#!/bin/bash
#
# Stream or dump SpacePill's unified log.
#
# SpacePill logs through os.Logger (see SpacePill/Utils/Log.swift), not stdout,
# so `print`-style tailing does not work -- and would not work in a packaged app
# anyway, since a menu bar app has no attached terminal.
#
# Usage:
#   ./bin/logs.sh                 follow live (default)
#   ./bin/logs.sh --last 10m      dump the last 10 minutes and exit
#   ./bin/logs.sh hotkeys         follow only the "hotkeys" category
#   ./bin/logs.sh --last 5m spaces
#   ./bin/logs.sh --enable-debug  persist debug-level messages (once, needs sudo)
#
# Categories: app, spaces, hotkeys, ui, settings, notes
#
# NOTE: macOS discards debug-level messages for a subsystem unless you opt in.
# Until you run --enable-debug, Log.*.debug(...) calls are invisible to BOTH
# `log show` and `log stream`, and only .info and above will appear.

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SUBSYSTEM=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" \
    "$PROJECT_DIR/SpacePill/SpacePill/Resources/Info.plist")

SINCE=""
CATEGORY=""

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --last) SINCE="$2"; shift 2 ;;
        --enable-debug)
            echo "Enabling debug + info logging for $SUBSYSTEM (persists across reboots)..."
            sudo log config --mode "level:debug" --subsystem "$SUBSYSTEM"
            echo "✅ Done. Undo with: sudo log config --mode 'level:default' --subsystem $SUBSYSTEM"
            exit 0 ;;
        -h|--help) sed -n '2,21p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) CATEGORY="$1"; shift ;;
    esac
done

PREDICATE="subsystem == \"$SUBSYSTEM\""
if [ -n "$CATEGORY" ]; then
    PREDICATE="$PREDICATE AND category == \"$CATEGORY\""
fi

if [ -n "$SINCE" ]; then
    exec log show --predicate "$PREDICATE" --last "$SINCE" --info --debug \
        --style compact
else
    echo "Streaming $SUBSYSTEM${CATEGORY:+ / $CATEGORY} ... (Ctrl-C to stop)" >&2
    exec log stream --predicate "$PREDICATE" --level debug --style compact
fi
