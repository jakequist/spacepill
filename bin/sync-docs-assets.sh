#!/usr/bin/env bash
#
# Copy the site screenshots from .assets/ (where they are captured) into
# docs/assets/ (where GitHub Pages serves them from).
#
# The docs site references these by exact filename; anything missing simply
# renders as a placeholder frame until it is captured.
#
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
src="$repo_root/.assets"
dst="$repo_root/docs/assets"

files=(
    pill-menubar.png
    pill-variants.png
    quick-edit.png
    quick-switch.png
    quick-switch-unreachable.png
    notes.png
    preferences.png
    setup-shortcuts.png
    demo-switch.gif
    demo.gif
    demo.mp4
    logo.png
)

mkdir -p "$dst"

missing=0
for f in "${files[@]}"; do
    if [[ -f "$src/$f" ]]; then
        cp "$src/$f" "$dst/$f"
        echo "  copied  $f"
    else
        echo "  MISSING $f"
        missing=$((missing + 1))
    fi
done

echo
if (( missing > 0 )); then
    echo "$missing file(s) not yet in .assets/; the site shows a placeholder for each."
else
    echo "All site assets are in place."
fi
