#!/usr/bin/env bash
# build-deps.sh — builds Wine's unix-side dependencies for x86_64 (Rosetta) from source.
#
# Homebrew no longer supports x86_64 on macOS, so we build the few libraries Wine links on the
# unix side into a private prefix. Everything Wine can build as PE (zlib, png, jpeg, xml2, ...)
# is left to Wine's bundled copies.
#
# We cross-compile from the arm64 host (clang -arch x86_64) instead of running under
# `arch -x86_64`: on macOS 27 the Command Line Tools (clang, make, ld, libxcrun) are arm64-only,
# so the /usr/bin shims fail inside an x86_64 process.
#
# Usage: scripts/build-deps.sh [package...]     (default: all)
# Env:   DEPS_X86_64  install prefix (default ~/.local/opt/proton-macos-deps/x86_64)
#        DEPS_CACHE   download cache (default ~/Library/Caches/proton-macos/deps)
set -euo pipefail

PREFIX="${DEPS_X86_64:-$HOME/.local/opt/proton-macos-deps/x86_64}"
CACHE="${DEPS_CACHE:-$HOME/Library/Caches/proton-macos/deps}"
BUILD="${TMPDIR:-/tmp}/proton-macos-deps-build"
JOBS="$(sysctl -n hw.ncpu)"

# Matches steamclient.dylib (LC_BUILD_VERSION minos 11.0).
export MACOSX_DEPLOYMENT_TARGET=11.0
export CC="clang -arch x86_64"
export CXX="clang++ -arch x86_64"
export CFLAGS="-O2"
export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig"
export PKG_CONFIG_LIBDIR="$PREFIX/lib/pkgconfig"

# name | version | url | sha256 | extra configure flags
PACKAGES=(
  "freetype|2.14.3|https://download.savannah.gnu.org/releases/freetype/freetype-2.14.3.tar.xz|36bc4f1cc413335368ee656c42afca65c5a3987e8768cc28cf11ba775e785a5f|--with-zlib=no --with-bzip2=no --with-png=no --with-harfbuzz=no --with-brotli=no"
)

log() { printf '\033[1m==> %s\033[0m\n' "$*" >&2; }

fetch() {
  local url=$1 sha=$2 file
  file="$CACHE/$(basename "$url")"
  mkdir -p "$CACHE"
  if [[ ! -f "$file" ]]; then
    log "Downloading $(basename "$url")"
    curl -fsSL -o "$file.part" "$url"
    mv "$file.part" "$file"
  fi
  if [[ "$(shasum -a 256 "$file" | cut -d' ' -f1)" != "$sha" ]]; then
    echo "sha256 mismatch for $file" >&2
    rm -f "$file"
    exit 1
  fi
  echo "$file"
}

build_autotools() {
  local name=$1 version=$2 url=$3 sha=$4 flags=$5 tarball src
  if [[ -f "$PREFIX/.built-$name-$version" ]]; then
    log "$name $version already built"
    return
  fi
  tarball=$(fetch "$url" "$sha")
  src="$BUILD/$name-$version"
  rm -rf "$src" && mkdir -p "$BUILD"
  tar -xf "$tarball" -C "$BUILD"
  log "Building $name $version (x86_64)"
  (
    cd "$src"
    # shellcheck disable=SC2086  # flags is intentionally word-split
    ./configure --prefix="$PREFIX" --build=aarch64-apple-darwin --host=x86_64-apple-darwin \
      --enable-shared --disable-static $flags
    make -j"$JOBS"
    make install
  )
  touch "$PREFIX/.built-$name-$version"
}

wanted=("$@")
for entry in "${PACKAGES[@]}"; do
  IFS='|' read -r name version url sha flags <<<"$entry"
  if [[ ${#wanted[@]} -gt 0 && ! " ${wanted[*]} " =~ \ $name\  ]]; then
    continue
  fi
  build_autotools "$name" "$version" "$url" "$sha" "$flags"
done

log "Done. Prefix: $PREFIX"
