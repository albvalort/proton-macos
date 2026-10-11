#!/usr/bin/env bash
# build-proton-modules.sh — builds Proton's Wine modules against our Wine build, the same way
# Proton's make/rules-makedep.mk does: reuse Wine's generated Makefile, point SUBDIRS at the module
# sources and let Wine's makedep generate the rules.
#
#   lsteamclient  external/proton/lsteamclient → lsteamclient.dll (i386 + x86_64) + lsteamclient.so
#                 (the unix side dlopen()s the Steam client's steamclient.dylib)
#   steamexe      external/proton/steam_helper → steam.exe (i386 + x86_64), Proton's launcher stub
#
# Usage: scripts/build-proton-modules.sh [module...]   (default: all)
# Requires: scripts/build-macos.sh (tools + wine) to have run.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-$ROOT/build}"
DIST_DIR="${DIST_DIR:-$ROOT/dist/wine}"
LLVM_MINGW="${LLVM_MINGW:-$HOME/.local/opt/llvm-mingw}"
JOBS="$(sysctl -n hw.ncpu)"

WINE_OBJ="$BUILD_DIR/wine-x86_64"
TOOLS="$BUILD_DIR/wine-tools"

export PATH="/opt/homebrew/opt/bison/bin:/opt/homebrew/opt/flex/bin:$PATH:$LLVM_MINGW/bin"
export MACOSX_DEPLOYMENT_TARGET=11.0

log() { printf '\033[1m==> %s\033[0m\n' "$*" >&2; }

[[ -f "$WINE_OBJ/Makefile" ]] || { echo "Wine build not found in $WINE_OBJ; run build-macos.sh" >&2; exit 1; }

build_module() {
  local name=$1 srcdir=$2
  local SRC="$BUILD_DIR/src-$name" OBJ="$BUILD_DIR/obj-$name-x86_64"
  log "Syncing $name sources"
  rsync -a --delete --exclude .git "$ROOT/external/proton/$srcdir/" "$SRC/"
  mkdir -p "$OBJ"

  log "Generating Makefile from Wine's"
  WINE_OBJ="$WINE_OBJ" SRC="$SRC" OBJ="$OBJ" python3 - <<'EOF'
import os
wine_obj, src, obj = os.environ["WINE_OBJ"], os.environ["SRC"], os.environ["OBJ"]
out, skip_continuation = [], False
for line in open(f"{wine_obj}/Makefile").read().split("\n"):
    if skip_continuation:
        skip_continuation = line.endswith("\\")
        continue
    if line == "all:":                 # drop Wine's own generated rules
        out.append("all:")
        break
    if line.startswith("SUBDIRS"):
        out.append(f"SUBDIRS = {src}")
        skip_continuation = line.endswith("\\")
        continue
    if line.startswith("TOP_INSTALL_LIB"):
        out.append("TOP_INSTALL_LIB =")
        continue
    if line.startswith("CXXFLAGS ="):
        out.append("CXXFLAGS = -std=c++17 -g -O2")
        continue
    if line.startswith("LDFLAGS ="):
        # unix side links against Wine's ntdll.so (Proton passes it as UNIX_LIBS)
        out.append(f"LDFLAGS = {wine_obj}/dlls/ntdll/ntdll.so")
        continue
    out.append(line)
    if line.startswith("srcdir ="):
        out.append(f"objdir = {wine_obj}")
    if line.startswith("x86_64_CC ="):
        out.append("x86_64_CXX = x86_64-w64-mingw32-g++")
    if line.startswith("i386_CC ="):
        out.append("i386_CXX = i686-w64-mingw32-g++")
open(f"{obj}/Makefile", "w").write("\n".join(out) + "\n")
EOF

  (cd "$OBJ" && "$TOOLS/tools/makedep")

  log "Building $name"
  make -C "$OBJ" -j"$JOBS"

  log "Installing $name into $DIST_DIR"
  local f arch
  # makedep places outputs under dlls/src-<name>/ or programs/src-<name>/ depending on the module type.
  for arch in i386 x86_64; do
    while IFS= read -r -d '' f; do
      install -m 644 "$f" "$DIST_DIR/lib/wine/$arch-windows/$(basename "$f")"
    done < <(find "$OBJ" -path "*/src-$name/$arch-windows/*" \( -name '*.dll' -o -name '*.exe' \) -print0)
  done
  while IFS= read -r -d '' f; do
    install -m 755 "$f" "$DIST_DIR/lib/wine/x86_64-unix/$(basename "$f")"
  done < <(find "$OBJ" -path "*/src-$name/*" -maxdepth 4 -name '*.so' -print0)
}

modules=("$@")
[[ ${#modules[@]} -gt 0 ]] || modules=(lsteamclient steamexe)
for m in "${modules[@]}"; do
  case "$m" in
    lsteamclient) build_module lsteamclient lsteamclient ;;
    steamexe)     build_module steamexe steam_helper ;;
    *) echo "unknown module: $m" >&2; exit 2 ;;
  esac
done
log "Done"
