#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
blender --background --python tests/map_fixture.py
blender --background --python tools/prepare_map.py -- \
  --source /tmp/liberty-test-source.glb --output assets/maps/test_fixture.glb \
  --terrain-regex '^TerrainTest$' --overwrite
tools/godot.sh --headless --xr-mode off --editor --import --quit
tools/godot.sh --headless --xr-mode off --script tests/smoke.gd
if [[ -f assets/maps/liberty_city.glb ]]; then
  tools/godot.sh --headless --xr-mode off --script tests/city_smoke.gd
else
  echo 'CITY_SMOKE_SKIPPED: Liberty City asset is not present'
fi
