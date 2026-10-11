#!/usr/bin/env bash
# build-lsteamclient.sh — builds Proton's lsteamclient (external/proton/lsteamclient) against our
# Wine build, the same way Proton's make/rules-makedep.mk does: reuse Wine's generated Makefile,
# point SUBDIRS at the lsteamclient sources and let Wine's makedep generate the rules.
#
# Produces lsteamclient.dll (i386 + x86_64 PE) and lsteamclient.so (x86_64 unix side, which
# dlopen()s the Steam client's steamclient.dylib) and installs them into $DIST_DIR/lib/wine.
#
# Requires: scripts/build-macos.sh (tools + wine) to have run.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-$ROOT/build}"
DIST_DIR="${DIST_DIR:-$ROOT/dist/wine}"
LLVM_MINGW="${LLVM_MINGW:-$HOME/.local/opt/llvm-mingw}"
JOBS="$(sysctl -n hw.ncpu)"

WINE_OBJ="$BUILD_DIR/wine-x86_64"
TOOLS="$BUILD_DIR/wine-tools"
SRC="$BUILD_DIR/src-lsteamclient"
OBJ="$BUILD_DIR/obj-lsteamclient-x86_64"

export PATH="/opt/homebrew/opt/bison/bin:/opt/homebrew/opt/flex/bin:$PATH:$LLVM_MINGW/bin"
export MACOSX_DEPLOYMENT_TARGET=11.0

log() { printf '\033[1m==> %s\033[0m\n' "$*" >&2; }

[[ -f "$WINE_OBJ/Makefile" ]] || { echo "Wine build not found in $WINE_OBJ; run build-macos.sh" >&2; exit 1; }

log "Syncing lsteamclient sources"
rsync -a --delete --exclude .git "$ROOT/external/proton/lsteamclient/" "$SRC/"
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

log "Building lsteamclient"
make -C "$OBJ" -j"$JOBS"

log "Installing into $DIST_DIR"
M="$OBJ/dlls/src-lsteamclient"
install -m 755 "$M/lsteamclient.so" "$DIST_DIR/lib/wine/x86_64-unix/lsteamclient.so"
install -m 644 "$M/x86_64-windows/lsteamclient.dll" "$DIST_DIR/lib/wine/x86_64-windows/lsteamclient.dll"
install -m 644 "$M/i386-windows/lsteamclient.dll" "$DIST_DIR/lib/wine/i386-windows/lsteamclient.dll"
log "Done"
