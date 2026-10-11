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

# Prebuilt, redistributable binaries:
#   name | version | url | sha256 | path inside the archive | destination under $PREFIX
PREBUILT=(
  # Vulkan on Metal (universal dylib, Apache-2.0); Wine loads it as its Vulkan library.
  "moltenvk|1.4.2|https://github.com/KhronosGroup/MoltenVK/releases/download/v1.4.2/MoltenVK-macos.tar|f95765a6229cb7b915990a2890ce12ebe36a730b021545d3d52ae69ce4c4024e|MoltenVK/MoltenVK/dynamic/dylib/macOS/libMoltenVK.dylib|lib"
  # D3D10/11 on Vulkan, macOS/MoltenVK fork (PE DLLs, zlib) — see docs/adr/0004-graphics-backends.md
  "dxvk-macos|1.10.3-20230507|https://github.com/Gcenx/DXVK-macOS/releases/download/v1.10.3-20230507-repack/dxvk-macOS-async-v1.10.3-20230507-repack.tar.gz|acd1520ad105d8ef124a09c8e11a259a5dc8bdc565ad18e0e52693f9807b2477|dxvk-macOS-async-v1.10.3-20230507-repack|dxvk"
)

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

install_prebuilt() {
  local name=$1 version=$2 url=$3 sha=$4 file=$5 dest=$6 tarball src
  if [[ -f "$PREFIX/.built-$name-$version" ]]; then
    log "$name $version already installed"
    return
  fi
  tarball=$(fetch "$url" "$sha")
  src="$BUILD/$name-$version"
  rm -rf "$src" && mkdir -p "$src"
  tar -xf "$tarball" -C "$src"
  log "Installing prebuilt $name $version"
  mkdir -p "$PREFIX/$dest" "$PREFIX/share/licenses/$name"
  if [[ -d "$src/$file" ]]; then
    rsync -a --delete "$src/$file/" "$PREFIX/$dest/"
  else
    install -m 755 "$src/$file" "$PREFIX/$dest/$(basename "$file")"
  fi
  find "$src" -maxdepth 2 -name 'LICENSE*' -exec cp {} "$PREFIX/share/licenses/$name/" \;
  touch "$PREFIX/.built-$name-$version"
}

wanted=("$@")
for entry in "${PREBUILT[@]}"; do
  IFS='|' read -r name version url sha file dest <<<"$entry"
  if [[ ${#wanted[@]} -gt 0 && ! " ${wanted[*]} " =~ \ $name\  ]]; then
    continue
  fi
  install_prebuilt "$name" "$version" "$url" "$sha" "$file" "$dest"
done
for entry in "${PACKAGES[@]}"; do
  IFS='|' read -r name version url sha flags <<<"$entry"
  if [[ ${#wanted[@]} -gt 0 && ! " ${wanted[*]} " =~ \ $name\  ]]; then
    continue
  fi
  build_autotools "$name" "$version" "$url" "$sha" "$flags"
done

log "Done. Prefix: $PREFIX"
