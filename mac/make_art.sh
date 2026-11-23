#!/bin/bash
# The launcher's art, made from the player's own copy of the game: nothing from the
# game is in this repository. Runs the built game once, unseen and muted, down the
# scripted path to Siberia (xboxrecomp docs/technical/ts2-resource-use.md), capturing
# frames as it goes; then
#   logo.png, glow.png   the title screen's own logo textures (mac/tools/captex.py)
#   backdrop.jpg         the Oblask Dam establishing shot, replayed at 4x
#   card_metal.jpg       the time portal hub, 4x
#   card_vulkan.jpg      Siberia's base, 4x
# into <data>/art. Takes about three minutes. The captures and the copy of the game
# it ran from are deleted afterwards (both are game content).
#
#   mac/make_art.sh [data dir]          default ~/Games/TimeSplitters2Native
set -euo pipefail
HERE=$(cd "$(dirname "$0")/.." && pwd)
DATA=${1:-$HOME/Games/TimeSplitters2Native}
GAME=$DATA/game
BIN=$HERE/build/Release/split2_recomp
REPLAY=$HERE/build/Release/xboxrecomp/src/replay/d3d8_replay
CAPTEX=$HERE/mac/tools/captex.py
die() { echo "make_art: $*" >&2; exit 1; }
[ -f "$GAME/default.xbe" ] || die "no game at $GAME"
[ -x "$BIN" ] && [ -x "$REPLAY" ] || die "build first (scripts/build.py)"
pgrep -f 'split2_recomp' >/dev/null && die "the game is running; quit it first"

WORK=$(mktemp -d "${TMPDIR:-/tmp}/ts2art.XXXXXX")
cleanup() { [ -n "${PID:-}" ] && kill -KILL "$PID" 2>/dev/null; rm -rf "${WORK:?}"; }
trap cleanup EXIT
# its own copy of the game: the game saves into its folder, and this run must not
cp -cR "$GAME" "$WORK/game" 2>/dev/null || cp -R "$GAME" "$WORK/game"
rm -rf "$WORK/game/UDATA" "$WORK/game/TDATA"
mkdir -p "$WORK/caps" "$WORK/saves" "$WORK/frames" "$WORK/art"

echo "== playing to Siberia (about 3 minutes)"
SEQ=12000:start,16000:start,20000:start,24000:start,28000:a,34000:a,40000:a,46000:a,52000:a,58000:a,64000:a,70000:a,76000:a,82000:a,88000:a,94000:a,120000:lstick_up:3000,125000:rstick_right:1200,134000:lstick_up:4000
RECOMP_D3D8_BACKEND=metal RECOMP_GAME_DIR="$WORK/game" RECOMP_SAVE_DIR="$WORK/saves" RECOMP_USER_DIR="$WORK/user" \
RECOMP_MUTE=1 RECOMP_WINDOW_BACKGROUND=1 RECOMP_INPUT_SEQ=$SEQ \
RECOMP_D3D8_CAPTURE="$WORK/caps/a.d3dcap" RECOMP_D3D8_CAPTURE_SWAP=600 RECOMP_D3D8_CAPTURE_EVERY=300 RECOMP_D3D8_CAPTURE_MAX=28 \
    "$BIN" >"$WORK/game.log" 2>&1 &
PID=$!
for _ in $(seq 1 170); do sleep 1; kill -0 "$PID" 2>/dev/null || break; done
kill -TERM "$PID" 2>/dev/null || true; sleep 2; kill -KILL "$PID" 2>/dev/null || true; PID=
n=$(ls "$WORK/caps" | wc -l | tr -d ' ')
[ "$n" -ge 20 ] || die "only $n frames were captured (see the game's log: $WORK/game.log)"

echo "== the logo"
python3 -I "$CAPTEX" logo "$WORK/caps" "$WORK/art"

echo "== choosing the pictures"
for c in "$WORK"/caps/*.d3dcap; do
    RECOMP_D3D8_BACKEND=metal "$REPLAY" "$c" --out "$WORK/frames/$(basename "$c" .d3dcap)_" --quiet >/dev/null 2>&1 || true
done
render() {   # <from swap> <to swap> <name>: the brightest frame in the range, at 4x
    local f; f=$(python3 -I "$CAPTEX" pick "$WORK/frames" "$1" "$2") || die "no frame between swaps $1 and $2"
    local cap="$WORK/caps/$(basename "$f" | sed -E 's/_000\.bmp$//').d3dcap"
    RECOMP_RES_SCALE=4 RECOMP_D3D8_BACKEND=metal "$REPLAY" "$cap" --out "$WORK/hi_$3_" --quiet >/dev/null 2>&1
    sips -s format jpeg -s formatOptions 88 "$WORK/hi_$3_000.bmp" --out "$WORK/art/$3.jpg" >/dev/null
    echo "   $3: $(basename "$cap")"
}
render 3900 5700 backdrop        # the dam: the level's opening shot, snow-bright
render 3500 3700 card_metal      # the hub, its portal open
render 6900 8400 card_vulkan     # outside, at the base

mkdir -p "$DATA/art"
cp "$WORK"/art/* "$DATA/art/"
echo "== art in $DATA/art"
ls -1 "$DATA/art"
