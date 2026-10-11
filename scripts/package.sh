#!/usr/bin/env bash
# package.sh — assembles the Steam compatibility tool (dist/proton-macos) from the Wine build and
# Proton's scripts, in the same layout Proton uses on Linux:
#
#   proton, filelock.py, ...      Proton's launcher script (external/proton, macos branch)
#   toolmanifest.vdf              "commandline" "/proton %verb%" (no Steam Linux Runtime)
#   compatibilitytool.vdf         from_oslist windows → to_oslist macos
#   version
#   files/{bin,lib,share}         Wine + lsteamclient + steam.exe (dist/wine)
#   bin/pmac                      the launcher (launcher/), if cargo is available
#
# Usage: scripts/package.sh [--install]
#   --install  symlink the tool into the compatibilitytools.d of the Steam client and of steamcmd
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WINE_DIST="${DIST_DIR:-$ROOT/dist/wine}"
TOOL_DIR="${TOOL_DIR:-$ROOT/dist/proton-macos}"
TOOL_NAME="${TOOL_NAME:-proton_macos}"
DISPLAY_NAME="${DISPLAY_NAME:-Proton-macOS (dev)}"
PROTON_SRC="$ROOT/external/proton"

log() { printf '\033[1m==> %s\033[0m\n' "$*" >&2; }

[[ -x "$WINE_DIST/bin/wineserver" ]] || { echo "No Wine build in $WINE_DIST" >&2; exit 1; }
[[ -f "$WINE_DIST/lib/wine/x86_64-windows/steam.exe" ]] || { echo "Run build-proton-modules.sh first" >&2; exit 1; }

log "Assembling $TOOL_DIR"
mkdir -p "$TOOL_DIR/files"
rsync -a --delete "$WINE_DIST/" "$TOOL_DIR/files/"
# Proton symlinks these into the prefix; our fonts come from Wine for now.
mkdir -p "$TOOL_DIR/files/share/fonts"

for f in filelock.py steampipe_fixups.py user_settings.sample.py; do
  install -m 644 "$PROTON_SRC/$f" "$TOOL_DIR/$f"
done
# Steam spawns compatibility tools as x86_64 (Rosetta) for Windows games, but on macOS 27 the
# /usr/bin/python3 shim needs libxcrun, which is arm64-only. Proton's script becomes proton.py and
# `proton` is a launcher that runs it as arm64; Wine itself is still started as x86_64.
install -m 755 "$PROTON_SRC/proton" "$TOOL_DIR/proton.py"
cat > "$TOOL_DIR/proton" <<'LAUNCHER'
#!/bin/sh
exec /usr/bin/arch -arm64 /usr/bin/python3 "$(dirname "$0")/proton.py" "$@"
LAUNCHER
chmod 755 "$TOOL_DIR/proton"
install -m 644 "$PROTON_SRC/toolmanifest_macos.vdf" "$TOOL_DIR/toolmanifest.vdf"
sed -e "s/##INTERNAL_TOOL_NAME##/$TOOL_NAME/" -e "s/##BUILD_NAME##/$DISPLAY_NAME/" \
    -e 's/"to_oslist"    "linux"/"to_oslist"    "macos"/' \
    "$PROTON_SRC/compatibilitytool.vdf.template" > "$TOOL_DIR/compatibilitytool.vdf"
grep -q '"to_oslist"    "macos"' "$TOOL_DIR/compatibilitytool.vdf"

if command -v cargo >/dev/null; then
  log "Building pmac"
  cargo build --release --quiet --manifest-path "$ROOT/launcher/Cargo.toml"
  install -d "$TOOL_DIR/bin"
  install -m 755 "$ROOT/launcher/target/release/pmac" "$TOOL_DIR/bin/pmac"
fi

proton_rev="$(git -C "$PROTON_SRC" describe --tags --always 2>/dev/null || echo unknown)"
wine_rev="$(git -C "$ROOT/external/wine" describe --tags --always 2>/dev/null || echo unknown)"
echo "$(date +%s) proton-macos-$proton_rev (wine $wine_rev)" > "$TOOL_DIR/version"

if [[ "${1:-}" == "--install" ]]; then
  for d in "$HOME/Library/Application Support/Steam/compatibilitytools.d" "$HOME/.local/opt/steamcmd/compatibilitytools.d"; do
    [[ -d "$(dirname "$d")" ]] || continue
    mkdir -p "$d"
    ln -sfn "$TOOL_DIR" "$d/$TOOL_NAME"
    log "Installed: $d/$TOOL_NAME -> $TOOL_DIR"
  done
fi
log "Done: $(cat "$TOOL_DIR/version")"
