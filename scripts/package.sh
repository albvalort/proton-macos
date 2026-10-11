#!/usr/bin/env bash
# package.sh — assembles the Steam compatibility tool (dist/proton-macos) from the Wine build and
# Proton's scripts, in the same layout Proton uses on Linux:
#
#   proton, filelock.py, ...      Proton's launcher script (external/proton, macos branch)
#   toolmanifest.vdf              "commandline" "/proton %verb%" (no Steam Linux Runtime)
#   compatibilitytool.vdf         from_oslist windows → to_oslist macos
#   version
#   files/{bin,lib,share}         Wine + lsteamclient + steam.exe (dist/wine)
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

for f in proton filelock.py steampipe_fixups.py user_settings.sample.py; do
  install -m "$([[ $f == proton ]] && echo 755 || echo 644)" "$PROTON_SRC/$f" "$TOOL_DIR/$f"
done
install -m 644 "$PROTON_SRC/toolmanifest_macos.vdf" "$TOOL_DIR/toolmanifest.vdf"
sed -e "s/##INTERNAL_TOOL_NAME##/$TOOL_NAME/" -e "s/##BUILD_NAME##/$DISPLAY_NAME/" \
    -e 's/"to_oslist"    "linux"/"to_oslist"    "macos"/' \
    "$PROTON_SRC/compatibilitytool.vdf.template" > "$TOOL_DIR/compatibilitytool.vdf"
grep -q '"to_oslist"    "macos"' "$TOOL_DIR/compatibilitytool.vdf"

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
