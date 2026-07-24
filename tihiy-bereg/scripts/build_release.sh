#!/usr/bin/env bash
set -euo pipefail
GODOT_BIN="${GODOT_BIN:-godot4}"
"$GODOT_BIN" --headless --path "$(dirname "$0")/.." --editor --quit
"$GODOT_BIN" --headless --path "$(dirname "$0")/.." --export-release "Windows Desktop" "build/TihiyBereg.exe"
