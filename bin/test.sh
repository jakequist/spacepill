#!/bin/bash
#
# Run the SpacePill unit tests.
#
# `swift test` needs XCTest, which ships with Xcode but NOT with the standalone
# Command Line Tools. On a machine whose active developer directory is
# CommandLineTools -- the common case, and this repo's dev box -- a bare
# `swift test` fails with `no such module 'XCTest'`.
#
# Rather than mutate the machine globally with `sudo xcode-select -s`, this
# script points DEVELOPER_DIR at a full Xcode for the duration of the run only.
# That keeps the fix local, needs no sudo, and is exactly what CI does too.
#
# Override the Xcode location with DEVELOPER_DIR if yours lives elsewhere:
#   DEVELOPER_DIR=/Applications/Xcode-16.app/Contents/Developer ./bin/test.sh

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Honour an inherited DEVELOPER_DIR (CI sets one); otherwise find an Xcode.
if [ -z "${DEVELOPER_DIR:-}" ]; then
    for candidate in \
        /Applications/Xcode.app/Contents/Developer \
        /Applications/Xcode-beta.app/Contents/Developer; do
        if [ -d "$candidate" ]; then
            export DEVELOPER_DIR="$candidate"
            break
        fi
    done
fi

if [ -z "${DEVELOPER_DIR:-}" ] || [ ! -x "$DEVELOPER_DIR/usr/bin/xctest" ]; then
    echo "❌ No full Xcode found (need XCTest, which Command Line Tools lack)." >&2
    echo "   Install Xcode, or set DEVELOPER_DIR to one that has it." >&2
    exit 1
fi

echo "🧪 Testing with DEVELOPER_DIR=$DEVELOPER_DIR"
cd "$PROJECT_DIR/SpacePill"
exec swift test "$@"
