#!/bin/bash
# The corridor sweep on macOS or Linux: one run of the game, scripted and recorded, its
# frames dumped and checked. See README.md beside this; run_corridor.ps1 is the Windows one.
#
#   tests/sweep/run_corridor.sh --out <folder> --game <game copy> [--settings <conf>]
#                               [--exe <timeslip>] [--replay <trace>] [--python <python>]
#
# --game: a copy of the game folder (macOS: `cp -c` clones it for nothing) with no UDATA,
#         or an empty one: the run starts from a fresh profile, and the folder is used as it is.
# --settings: a settings file to play with (a copy of your own; the run never touches your
#         real one). Anything else, renderer and frame interpolation included, can be given
#         the usual way, as RECOMP_* variables in the environment.
# --replay: replay a recording made by an earlier run (<out>/corridor.trace) instead of
#         recording a new one, to compare settings that only change the picture.
# --python: one with numpy and Pillow, for analyze.py and odd.py (default python3).
# SWEEP_SEQ=<file> in the environment plays another controller script than corridor.seq.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../.." && pwd)
OUT="" GAME="" SETTINGS="" EXE="$REPO/build/Release/timeslip" REPLAY="" PY=python3
while [ $# -gt 0 ]; do
    case "$1" in
    --out) OUT=$2; shift 2 ;;
    --game) GAME=$2; shift 2 ;;
    --settings) SETTINGS=$2; shift 2 ;;
    --exe) EXE=$2; shift 2 ;;
    --replay) REPLAY=$2; shift 2 ;;
    --python) PY=$2; shift 2 ;;
    *) echo "usage: run_corridor.sh --out <folder> --game <game copy> [--settings <conf>] [--exe <timeslip>] [--replay <trace>] [--python <python>]" >&2; exit 2 ;;
    esac
done
die() { echo "run_corridor: $*" >&2; exit 1; }
[ -n "$OUT" ] && [ -n "$GAME" ] || die "--out and --game are needed"
[ -f "$GAME/default.xbe" ] || die "no default.xbe in $GAME"
[ -z "$(ls -A "$GAME/UDATA" 2>/dev/null)" ] || die "$GAME/UDATA has saves in it: use a copy without them"
[ -x "$EXE" ] || die "no $EXE"
[ -z "$REPLAY" ] || [ -f "$REPLAY" ] || die "no $REPLAY"
OUT=$(mkdir -p "$OUT" && cd "$OUT" && pwd)
[ -z "$(ls -A "$OUT")" ] || die "$OUT is not empty"
mkdir -p "$OUT/saves"
{ grep -v '^[[:space:]]*#' "$HERE/corridor.sweep"; echo "log $OUT/sweep.csv"; } > "$OUT/corridor.sweep"

# Whatever an earlier run left exported would steer this one (a replay left in
# RECOMP_LOCKSTEP_REPLAY plays that recording instead of this test). The display
# settings (RECOMP_FRAME_INTERP and the like) are kept: here they are how a run is set.
unset RECOMP_LOCKSTEP RECOMP_LOCKSTEP_REPLAY RECOMP_LOCKSTEP_TRACE RECOMP_INPUT_SEQ \
      RECOMP_INPUT_SEQ_PAD RECOMP_DISPLAY_CONFIG
export RECOMP_GAME_DIR="$GAME" RECOMP_SAVE_DIR="$OUT/saves"
# 1600x900 pixels, as on Windows: a Retina Mac's window size is in points, two pixels each,
# and a 3200x1800 dump is slow enough that the in-between frames miss their moment
WIN=1600x900; [ "$(uname)" = Darwin ] && system_profiler SPDisplaysDataType 2>/dev/null | grep -q Retina && WIN=800x450
export RECOMP_MUTE=1 RECOMP_WINDOW_BACKGROUND=1 RECOMP_WINDOW_SIZE=${RECOMP_WINDOW_SIZE:-$WIN}
[ -z "$SETTINGS" ] || export RECOMP_DISPLAY_CONFIG="$SETTINGS"
# A Mac draws with Metal only: said outright, and the run's log is checked for it below.
[ "$(uname)" = Darwin ] && export RECOMP_D3D8_BACKEND=metal
export RECOMP_TS2_SWEEP="$OUT/corridor.sweep" RECOMP_LOCKSTEP_END=7320
if [ -n "$REPLAY" ]; then
    export RECOMP_LOCKSTEP_REPLAY="$REPLAY"
    unset RECOMP_LOCKSTEP RECOMP_INPUT_SEQ
else
    export RECOMP_LOCKSTEP=1 RECOMP_LOCKSTEP_TRACE="$OUT/corridor.trace"
    RECOMP_INPUT_SEQ=$(tr -d '\r\n' < "${SWEEP_SEQ:-$HERE/corridor.seq}"); export RECOMP_INPUT_SEQ
fi
export RECOMP_PRESENT_DUMP="$OUT/p_"
RECOMP_PRESENT_DUMP_TICKS=$(tr -d '\r\n' < "$HERE/corridor.ticks"); export RECOMP_PRESENT_DUMP_TICKS
export RECOMP_PRESENT_DUMP_FRAMES=3 RECOMP_PRESENT_DUMP_MAX=6000
# stderr straight to a file: a pipe the reader falls behind on stalls the game
"$EXE" 2> "$OUT/run.log" || echo "run_corridor: the game exited with $?" >&2
grep -a '\[RHI\] renderer:' "$OUT/run.log" | head -1 || true
if [ "$(uname)" = Darwin ] && ! grep -aq '\[RHI\] renderer: metal' "$OUT/run.log"; then
    die "the run's log does not say Metal ($OUT/run.log)"
fi
grep -E 'LOCKSTEP\].*(same|differ|recorded)' "$OUT/run.log" | tail -1 || true
"$PY" "$HERE/analyze.py" "$OUT" --jpg
"$PY" "$HERE/odd.py" "$OUT"
