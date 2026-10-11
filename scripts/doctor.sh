#!/usr/bin/env bash
# doctor.sh — checks the host environment for building and running Proton-macOS.
# Exit code: 0 if every critical check passes, 1 otherwise. Warnings never fail.
# --ci: only system checks are critical (CI runners have no Steam, toolchains or GPTK).
set -uo pipefail

CI_MODE=0
[[ "${1:-}" == "--ci" ]] && CI_MODE=1

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  G=$'\e[32m'; Y=$'\e[33m'; R=$'\e[31m'; B=$'\e[1m'; N=$'\e[0m'
else
  G=; Y=; R=; B=; N=
fi

FAIL=0
ok()   { printf '%s[ OK ]%s %s\n' "$G" "$N" "$*"; }
warn() { printf '%s[WARN]%s %s\n' "$Y" "$N" "$*"; }
bad()  { printf '%s[FAIL]%s %s\n' "$R" "$N" "$*"; FAIL=1; }
# Critical on a developer machine, informational in CI.
need() { if [[ $CI_MODE -eq 1 ]]; then warn "$*"; else bad "$*"; fi; }
hdr()  { printf '\n%s== %s ==%s\n' "$B" "$*" "$N"; }

STEAM_SUPPORT="$HOME/Library/Application Support/Steam"
STEAM_CLIENT="$STEAM_SUPPORT/Steam.AppBundle/Steam/Contents/MacOS"
LLVM_MINGW="${LLVM_MINGW:-$HOME/.local/opt/llvm-mingw}"

archs() { lipo -archs "$1" 2>/dev/null; }

hdr "System"
os_ver=$(sw_vers -productVersion)
chip=$(sysctl -n machdep.cpu.brand_string 2>/dev/null)
if [[ $(uname -m) == arm64 ]]; then
  ok "macOS $os_ver on $chip (arm64)"
else
  bad "macOS $os_ver on $(uname -m): Apple Silicon required"
fi

if arch -x86_64 /usr/bin/true 2>/dev/null; then
  ok "Rosetta 2 installed"
else
  bad "Rosetta 2 missing: softwareupdate --install-rosetta --agree-to-license"
fi

hdr "Toolchain"
if clt=$(xcode-select -p 2>/dev/null); then
  ok "Xcode Command Line Tools: $clt"
else
  bad "Xcode Command Line Tools missing: xcode-select --install"
fi

if [[ -x /opt/homebrew/bin/brew ]]; then
  ok "Homebrew arm64: $(/opt/homebrew/bin/brew --version | head -1)"
else
  bad "Homebrew arm64 missing (/opt/homebrew)"
fi

# Homebrew no longer supports x86_64 on macOS, so Wine's unix-side deps (freetype, gnutls,
# MoltenVK, SDL2...) are built from source into a user prefix by scripts/build-deps.sh.
DEPS_X86_64="${DEPS_X86_64:-$HOME/.local/opt/proton-macos-deps/x86_64}"
if [[ -f "$DEPS_X86_64/lib/libfreetype.dylib" ]]; then
  ok "x86_64 build deps: $DEPS_X86_64"
else
  warn "x86_64 build deps missing at $DEPS_X86_64: run scripts/build-deps.sh (milestone 2)"
fi

if [[ -x "$LLVM_MINGW/bin/x86_64-w64-mingw32-clang" ]]; then
  ok "llvm-mingw: $("$LLVM_MINGW/bin/x86_64-w64-mingw32-clang" --version | head -1) ($LLVM_MINGW)"
else
  need "llvm-mingw missing at $LLVM_MINGW (https://github.com/mstorsjo/llvm-mingw/releases)"
fi

hdr "Graphics (GPTK / D3DMetal)"
# Never copied or redistributed: we only detect the user's own install.
gptk_candidates=(
  "${PROTON_MAC_GPTK:-}"
  "/usr/local/opt/game-porting-toolkit/lib/external"
  "/Applications/Game Porting Toolkit.app/Contents/Resources/wine/lib/external"
  "/Library/Apple/usr/lib/external"
)
for v in /Volumes/*Game\ Porting\ Toolkit*/redist/lib/external; do gptk_candidates+=("$v"); done
gptk=""
for c in "${gptk_candidates[@]}"; do
  [[ -n "$c" && -d "$c/D3DMetal.framework" ]] && { gptk="$c"; break; }
done
if [[ -n "$gptk" ]]; then
  ok "D3DMetal.framework: $gptk"
else
  warn "GPTK/D3DMetal not found (set PROTON_MAC_GPTK=<dir containing D3DMetal.framework>). DXVK fallback only."
fi

hdr "Steam"
if [[ -d /Applications/Steam.app ]]; then
  ok "Steam.app bootstrapper present"
else
  need "Steam.app missing (/Applications)"
fi
if [[ -f "$STEAM_CLIENT/steamclient.dylib" ]]; then
  ver=$(plutil -extract CFBundleVersion raw "$STEAM_CLIENT/../Info.plist" 2>/dev/null)
  build=$(awk -F'"' '/"version"/ {print $4; exit}' "$STEAM_CLIENT/package/steam_client_osx.manifest" 2>/dev/null)
  ok "Steam client bundle: CFBundleVersion ${ver:-?}, build ${build:-?}"
  for lib in steamclient.dylib libtier0_s.dylib libvstdlib_s.dylib; do
    a=$(archs "$STEAM_CLIENT/$lib")
    if [[ $a == *x86_64* ]]; then
      ok "$lib: $a"
    else
      need "$lib: ${a:-missing} (no x86_64 slice: lsteamclient will need an arm64 helper + IPC)"
    fi
  done
else
  need "steamclient.dylib not found: launch Steam once so it bootstraps $STEAM_CLIENT"
fi

echo
if [[ $FAIL -eq 0 ]]; then
  printf '%sAll critical checks passed.%s\n' "$G" "$N"
else
  printf '%sSome critical checks failed.%s\n' "$R" "$N"
fi
exit $FAIL
