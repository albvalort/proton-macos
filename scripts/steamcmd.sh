#!/usr/bin/env bash
# steamcmd.sh — runs steamcmd with its own data directory.
#
# On macOS steamcmd stores its data (config.vdf with the login token, steamapps, logs) in
# $HOME/Library/Application Support/Steam, the same place as the Steam client. Sharing it makes
# each client overwrite the other's cached login. A private HOME keeps them apart.
#
# Optional Steam Play activation for experiments (see docs/research/03-platform-and-launch.md):
#   STEAMPLAY_SHIM=<path to strnicmp_spy.dylib> SPY_FORCE_OFFSET=0x6913b8 scripts/steamcmd.sh ...
#
# Usage: scripts/steamcmd.sh [steamcmd args...]   e.g. +login <user> +quit
set -euo pipefail

STEAMCMD_DIR="${STEAMCMD_DIR:-$HOME/.local/opt/steamcmd}"
STEAMCMD_HOME="${STEAMCMD_HOME:-$HOME/.local/share/proton-macos/steamcmd-home}"
mkdir -p "$STEAMCMD_HOME"

export HOME="$STEAMCMD_HOME"
export DYLD_LIBRARY_PATH="$STEAMCMD_DIR" DYLD_FRAMEWORK_PATH="$STEAMCMD_DIR"
if [[ -n "${STEAMPLAY_SHIM:-}" ]]; then
  export DYLD_INSERT_LIBRARIES="$STEAMPLAY_SHIM"
fi
cd "$STEAMCMD_DIR"
exec ./steamcmd "$@"
