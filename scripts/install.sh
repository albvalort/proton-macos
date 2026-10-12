#!/usr/bin/env bash
# install.sh — installs a Proton-macOS release package for the current user.
#
# Shipped at the root of the release archive, next to the proton_macos/ directory:
#
#   tar -xJf proton-macos-<version>.tar.xz && cd proton-macos-<version> && ./install.sh
#
# What it does (nothing needs sudo):
#   1. Copies proton_macos/ into Steam's compatibilitytools.d.
#   2. Downloads DepotDownloader (GPL-2.0, used by `pmac login/install`) into ~/.local/opt.
#   3. Links `pmac` into ~/.local/bin.
#
# Env overrides (mainly for testing): PROTON_MACOS_STEAM_DIR, PROTON_MACOS_OPT_DIR, PROTON_MACOS_BIN_DIR,
# PROTON_MACOS_SKIP_DEPOTDOWNLOADER=1.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
TOOL_SRC="$HERE/proton_macos"
STEAM_DIR="${PROTON_MACOS_STEAM_DIR:-$HOME/Library/Application Support/Steam}"
OPT_DIR="${PROTON_MACOS_OPT_DIR:-$HOME/.local/opt}"
BIN_DIR="${PROTON_MACOS_BIN_DIR:-$HOME/.local/bin}"
TOOL_DST="$STEAM_DIR/compatibilitytools.d/proton_macos"

DD_VERSION=3.4.0
DD_URL="https://github.com/SteamRE/DepotDownloader/releases/download/DepotDownloader_$DD_VERSION/DepotDownloader-macos-arm64.zip"
DD_SHA256=60e80c7c496f3f9a079cd3c62036b35d088c27bc0149baf38f009eb57a52f6a5

log() { printf '\033[1m==> %s\033[0m\n' "$*"; }
die() { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }

[[ -d "$TOOL_SRC" && -x "$TOOL_SRC/proton" ]] || die "run this from the extracted release (proton_macos/ not found next to install.sh)"

# --- Requirements -----------------------------------------------------------------------------
[[ "$(uname -m)" == arm64 ]] || die "Proton-macOS needs an Apple Silicon Mac"
/usr/bin/arch -x86_64 /usr/bin/true 2>/dev/null \
  || die "Rosetta 2 is not installed: run 'softwareupdate --install-rosetta --agree-to-license'"
if ! /usr/bin/xcode-select -p >/dev/null 2>&1 || ! /usr/bin/arch -arm64 /usr/bin/python3 -c '' 2>/dev/null; then
  die "the Xcode Command Line Tools (python3) are missing: run 'xcode-select --install'"
fi
[[ -d "$STEAM_DIR" ]] || die "Steam not found in '$STEAM_DIR': install Steam for Mac and open it once"

# --- Compatibility tool -----------------------------------------------------------------------
log "Installing the compatibility tool into $TOOL_DST"
mkdir -p "$(dirname "$TOOL_DST")"
if [[ -L "$TOOL_DST" ]]; then rm "$TOOL_DST"; else rm -rf "$TOOL_DST"; fi
cp -R "$TOOL_SRC" "$TOOL_DST"
# Archives downloaded with a browser are quarantined; Gatekeeper would block the unsigned binaries.
/usr/bin/xattr -dr com.apple.quarantine "$TOOL_DST" 2>/dev/null || true

# --- DepotDownloader ----------------------------------------------------------------------------
DD_DIR="$OPT_DIR/depotdownloader"
if [[ "${PROTON_MACOS_SKIP_DEPOTDOWNLOADER:-0}" != 1 && ! -x "$DD_DIR/DepotDownloader" ]]; then
  log "Downloading DepotDownloader $DD_VERSION"
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  curl -fsSL -o "$tmp/dd.zip" "$DD_URL"
  echo "$DD_SHA256  $tmp/dd.zip" | shasum -a 256 -c --quiet - || die "DepotDownloader checksum mismatch"
  mkdir -p "$DD_DIR"
  unzip -qo "$tmp/dd.zip" -d "$DD_DIR"
  chmod +x "$DD_DIR/DepotDownloader"
fi

# --- pmac -----------------------------------------------------------------------------------------
mkdir -p "$BIN_DIR"
ln -sfn "$TOOL_DST/bin/pmac" "$BIN_DIR/pmac"
log "Installed $(cat "$TOOL_DST/version")"

# shellcheck disable=SC2016  # $PATH is meant literally in the suggested line
case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *) printf '\nAdd %s to your PATH, e.g.:\n  echo '\''export PATH="%s:$PATH"'\'' >> ~/.zshrc\n' "$BIN_DIR" "$BIN_DIR" ;;
esac
cat <<'EOF'

Next steps (Steam must be running for achievements and the Steam API):
  pmac login              # once: scan the QR code with the Steam mobile app
  pmac list               # Windows-only games in your library
  pmac install <appid>    # download the Windows version
  pmac run <appid>        # play
  pmac shortcut <appid>   # add it to the Steam library (quit Steam first)
EOF
