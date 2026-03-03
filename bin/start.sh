#!/bin/bash

DAEMON_MODE=false

while [[ "$#" -gt 0 ]]; do
    case $1 in
        -d|--daemon) DAEMON_MODE=true; shift ;;
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
done

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR/SpacePill"

# Kill existing instances
pkill -x SpacePill 2>/dev/null

# Build release
swift build -c release &>/dev/null

if [ "$DAEMON_MODE" = true ]; then
    nohup ./.build/release/SpacePill >/dev/null 2>&1 &
    echo "SpacePill started in the background."
else
    exec ./.build/release/SpacePill
fi
