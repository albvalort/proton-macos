#!/usr/bin/env bash
# stress.sh — runs synctest (64- and 32-bit) in a loop under msync for a given time and reports
# failures and hangs (a run exceeding its deadline is killed and counted as a hang).
# Usage: tests/msync/stress.sh [minutes]   (needs build/synctest.exe and build/synctest32.exe)
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
MINUTES="${1:-30}"
export WINEPREFIX="$ROOT/build/prefix-msync" WINEDLLOVERRIDES="mscoree,mshtml=" WINEDEBUG=-all WINEFSYNC=1
export DYLD_FALLBACK_LIBRARY_PATH="$ROOT/dist/wine/lib:/usr/lib"
WINE="$ROOT/dist/wine/bin/wine"
end=$(( $(date +%s) + MINUTES * 60 ))
runs=0 fails=0 hangs=0
while (( $(date +%s) < end )); do
  for exe in synctest.exe synctest32.exe; do
    out=$(mktemp)
    "$WINE" "$ROOT/build/$exe" > "$out" 2>&1 &
    pid=$!
    deadline=$(( $(date +%s) + 120 ))
    while kill -0 "$pid" 2>/dev/null && (( $(date +%s) < deadline )); do sleep 1; done
    if kill -0 "$pid" 2>/dev/null; then
      hangs=$((hangs + 1)); echo "HANG in $exe (run $runs)"; tail -3 "$out"
      "$ROOT/dist/wine/bin/wineserver" -k
    elif ! grep -q "ALL PASSED" "$out"; then
      fails=$((fails + 1)); echo "FAIL in $exe (run $runs)"; grep -E "FAIL" "$out" | head -3
    fi
    runs=$((runs + 1)); rm -f "$out"
  done
done
echo "stress: $runs runs in $MINUTES min, $fails failures, $hangs hangs"
(( fails == 0 && hangs == 0 ))
