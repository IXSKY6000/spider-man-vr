#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Cloud filesystem: keep editor caches and ADB state in a writable location.
if [[ -d /workspace && -w /workspace ]]; then
  task_runtime_root="${WEB_LIBERTY_RUNTIME:-/workspace/.runtime}"
else
  task_runtime_root="${WEB_LIBERTY_RUNTIME:-${HOME}/.local/share/webs-liberty}"
fi
export XDG_DATA_HOME="${XDG_DATA_HOME:-$task_runtime_root/godot/data}"
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$task_runtime_root/godot/config}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$task_runtime_root/godot/cache}"
export ANDROID_USER_HOME="${ANDROID_USER_HOME:-$task_runtime_root/android-user}"
export GRADLE_USER_HOME="${GRADLE_USER_HOME:-$task_runtime_root/gradle}"
mkdir -p "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" "$ANDROID_USER_HOME"
exec godot --path "$PWD" "$@"
