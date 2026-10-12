#!/usr/bin/env bash
# release.sh — builds the release archive from an existing build (build-macos.sh + build-proton-modules.sh):
#
#   dist/proton-macos-<version>.tar.xz        proton-macos-<version>/{proton_macos/, install.sh, README.md}
#   dist/proton-macos-<version>.tar.xz.sha256
#
# Usage: scripts/release.sh <version>      e.g. scripts/release.sh 0.1.0
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:?usage: release.sh <version>}"
VERSION="${VERSION#v}"
NAME="proton-macos-$VERSION"
STAGE="$ROOT/dist/release/$NAME"

log() { printf '\033[1m==> %s\033[0m\n' "$*" >&2; }

rm -rf "$STAGE"
mkdir -p "$STAGE"
TOOL_DIR="$STAGE/proton_macos" DISPLAY_NAME="Proton-macOS $VERSION" "$ROOT/scripts/package.sh"
install -m 755 "$ROOT/scripts/install.sh" "$STAGE/install.sh"
install -m 644 "$ROOT/README.md" "$STAGE/README.md"

log "Creating $NAME.tar.xz"
tar -C "$ROOT/dist/release" -cJf "$ROOT/dist/$NAME.tar.xz" "$NAME"
(cd "$ROOT/dist" && shasum -a 256 "$NAME.tar.xz" > "$NAME.tar.xz.sha256")
log "Done: dist/$NAME.tar.xz ($(du -h "$ROOT/dist/$NAME.tar.xz" | cut -f1))"
