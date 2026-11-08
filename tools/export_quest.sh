#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
touch build/.gdignore
tools/godot.sh --headless --xr-mode off --editor --import --quit
tools/godot.sh --headless --xr-mode off --export-debug 'Quest 3' build/webs-liberty-quest3.apk
