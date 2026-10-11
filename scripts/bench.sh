#!/usr/bin/env bash
# bench.sh — measures a game's frame rate through our Proton, per graphics backend.
#
# The game runs through dist/proton-macos with Apple's Metal Performance HUD logging enabled
# (MTL_HUD_ENABLED=1 MTL_HUD_LOG_ENABLED=1). The HUD writes one "metal-HUD: <frame>,..." line per
# second to the unified log; frames per interval give the frame rate without touching the game.
# Wine's own fps trace (WINEDEBUG=+fps, "@ approx N fps" about once a second) is recorded too:
# it covers OpenGL (wined3d), which the Metal HUD does not see, and games that recreate their
# swapchain (the HUD can stop logging then). The source with more samples wins.
#
# Usage: scripts/bench.sh <appid> <path to .exe> <dxvk|wined3d|d3dmetal> [seconds=30] [warmup=20]
# Output: a summary line, appended to docs/bench/results.csv
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APPID=$1 EXE=$2 GFX=$3 SECONDS_RUN=${4:-30} WARMUP=${5:-20}
TOOL="$ROOT/dist/proton-macos"
COMPAT="$ROOT/build/compatdata-$APPID"
STEAM_CLIENT="$HOME/Library/Application Support/Steam/Steam.AppBundle/Steam/Contents/MacOS"
RESULTS="$ROOT/docs/bench/results.csv"
WINE_OUT="$ROOT/build/logs/bench-$APPID-$GFX.out"

[[ -f "$EXE" ]] || { echo "no such exe: $EXE" >&2; exit 1; }
mkdir -p "$COMPAT"

(cd "$(dirname "$EXE")" && env -i HOME="$HOME" PATH=/usr/bin:/bin USER="$USER" \
    STEAM_COMPAT_DATA_PATH="$COMPAT" STEAM_COMPAT_CLIENT_INSTALL_PATH="$STEAM_CLIENT" \
    STEAM_COMPAT_INSTALL_PATH="$(dirname "$EXE")" SteamAppId="$APPID" SteamGameId="$APPID" \
    PROTON_MAC_GFX="$GFX" MTL_HUD_ENABLED=1 MTL_HUD_LOG_ENABLED=1 WINEDEBUG="-all,+fps" \
    "$TOOL/proton" waitforexitandrun "$EXE" > "$WINE_OUT" 2>&1 &)

sleep "$WARMUP"
start=$(date '+%Y-%m-%d %H:%M:%S')
sleep "$SECONDS_RUN"
end=$(date '+%Y-%m-%d %H:%M:%S')

# Stop the game (the .exe name as Wine shows it in the process list) and its wineserver.
pkill -f "$(basename "$EXE")" || true
WINEPREFIX="$COMPAT/pfx" "$TOOL/files/bin/wineserver" -k 2>/dev/null || true

/usr/bin/log show --style compact --start "$start" --end "$end" \
    --predicate 'subsystem == "com.apple.metal.hud" AND process == "wine"' 2>/dev/null |
  APPID="$APPID" GFX="$GFX" RESULTS="$RESULTS" EXE="$EXE" WINE_OUT="$WINE_OUT" WARMUP="$WARMUP" python3 -c '
import os, re, sys, datetime
appid, gfx, results = os.environ["APPID"], os.environ["GFX"], os.environ["RESULTS"]
samples = []
for line in sys.stdin:
    m = re.match(r"(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d\.\d+) .*metal-HUD: (\d+),", line)
    if m:
        t = datetime.datetime.strptime(m.group(1), "%Y-%m-%d %H:%M:%S.%f").timestamp()
        samples.append((t, int(m.group(2))))
# one process can have several Metal layers; keep the busiest frame counter sequence
samples.sort()
fps = [(f2 - f1) / (t2 - t1) for (t1, f1), (t2, f2) in zip(samples, samples[1:]) if t2 > t1 and f2 >= f1]
source = "metal-hud"
# Wine fps trace: "...:fps:...present @ approx 59.94fps, total 60.02fps"; skip the warmup share
wine_fps = [float(x) for x in re.findall(r"@ approx ([\d.]+)fps", open(os.environ["WINE_OUT"], errors="replace").read())]
wine_fps = wine_fps[int(os.environ["WARMUP"]):]
if len(wine_fps) > len(fps):
    fps, source = wine_fps, "wine-fps"
name = os.path.basename(os.environ["EXE"])
if len(fps) < 3:
    print(f"{name} {gfx}: no frame rate samples (neither Metal HUD nor Wine fps trace)")
    sys.exit(1)
avg = sum(fps) / len(fps)
low = sorted(fps)[max(0, len(fps) // 100)]
print(f"{name} [{gfx}] avg {avg:.1f} fps, min {min(fps):.1f}, 1%-low(1s) {low:.1f}, {len(fps)} samples ({source})")
new = not os.path.exists(results)
with open(results, "a") as f:
    if new:
        f.write("date,appid,exe,backend,avg_fps,min_fps,low1_fps,samples,source\n")
    f.write(f"{datetime.date.today()},{appid},{name},{gfx},{avg:.1f},{min(fps):.1f},{low:.1f},{len(fps)},{source}\n")
'
