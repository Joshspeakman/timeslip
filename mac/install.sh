#!/bin/bash
# Builds the Timeslip collection as one app from this checkout's builds and installs it: "Timeslip.app", which has
# TimeSplitters 2 (scripts/build.py first) and TimeSplitters: Future Perfect (fp/scripts/build.py first). --title ts2 or
# fp builds one game alone, as "TimeSplitters 2.app" or "TimeSplitters Future Perfect.app" (the launcher then shows
# the other as not installed).
#
#   mac/install.sh [--title all|ts2|fp] [--app <path.app>] [--data <dir>] [--data-ts2 <dir>] [--data-fp <dir>]
#     --title     which games (default all)
#     --app       where the app goes (default /Applications/<its name>.app)
#     --data-ts2, --data-fp, or --data with one game: a game's folder: <data>/game holds the disc's files, <data>/art
#                 the launcher's art (default ~/Games/TimeSplitters2Native and ~/Games/TimeSplittersFPNative;
#                 mac/make_art.sh makes TimeSplitters 2's art)
#
# The app: Contents/MacOS/<its name> ("Timeslip Launcher" for the collection) is the launcher (mac/ts2_launcher.m): a card for each game, then the one picked
# starts in the same process (Contents/MacOS/timeslip, timeslip_fp, bundled by recompose/scripts/make_macos_app.py:
# DXC, which the Metal renderer compiles its shaders with, and the Vulkan loader and MoltenVK for the renderer kept
# under Advanced). Contents/MacOS/update runs mac/update.sh from this checkout. It contains the games' recompiled code:
# for this Mac only, never distribute it.
set -euo pipefail
HERE=$(cd "$(dirname "$0")/.." && pwd)
TITLE=all APP="" DATA="" DATA_TS2="" DATA_FP="" LAUNCHER=""
while [ $# -gt 0 ]; do
    case "$1" in
    --title) TITLE=$2; shift 2 ;;
    --app) APP=$2; shift 2 ;;
    --data) DATA=$2; shift 2 ;;
    --data-ts2) DATA_TS2=$2; shift 2 ;;
    --data-fp) DATA_FP=$2; shift 2 ;;
    *) echo "usage: mac/install.sh [--title all|ts2|fp] [--app <path.app>] [--data <dir>] [--data-ts2 <dir>] [--data-fp <dir>]" >&2; exit 2 ;;
    esac
done
die() { echo "install: $*" >&2; exit 1; }
# each game: its executable, build and data folder
BIN_ts2=$HERE/build/Release/timeslip;        BUILD_ts2=scripts/build.py
BIN_fp=$HERE/fp/build/Release/timeslip_fp;   BUILD_fp=fp/scripts/build.py
case "$TITLE" in
all) NAME="Timeslip"; BUNDLE_ID=io.github.joshspeakman.timeslip; GAMES="ts2 fp"; LAUNCHER="Timeslip Launcher"
     [ -z "$DATA" ] || die "--data is for one game; use --data-ts2 and --data-fp" ;;
ts2) NAME="TimeSplitters 2"; BUNDLE_ID=io.github.joshspeakman.timesplitters2; GAMES=ts2; EXE=timeslip; DATA_TS2=${DATA:-$DATA_TS2} ;;
fp)  NAME="TimeSplitters Future Perfect"; BUNDLE_ID=io.github.joshspeakman.timesplitters-fp; GAMES=fp; EXE=timeslip_fp; DATA_FP=${DATA:-$DATA_FP} ;;
*)   die "--title is all, ts2 or fp, not $TITLE" ;;
esac
# the launcher's file in Contents/MacOS: not "Timeslip", which a Mac's disk (case-insensitive) takes for the game's "timeslip"
LAUNCHER=${LAUNCHER:-$NAME}
DATA_ts2=${DATA_TS2:-$HOME/Games/TimeSplitters2Native}
DATA_fp=${DATA_FP:-$HOME/Games/TimeSplittersFPNative}
APP=${APP:-/Applications/$NAME.app}
SDK=${VULKAN_SDK:-$HOME/VulkanSDK/1.4.357.1/macOS}

for g in $GAMES; do
    bin=BIN_$g build=BUILD_$g data=DATA_$g
    [ -x "${!bin}" ] || die "no build of $g: run ${!build} first"
    [ -f "${!data}/game/default.xbe" ] || echo "install: note: no game in ${!data}/game yet; the launcher will say so" >&2
done
pgrep -f "$APP/Contents/MacOS/" >/dev/null && die "$APP is running; quit it first"
if [ -e "$APP" ]; then   # replace only this app, never something else at that path
    old=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist" 2>/dev/null || true)
    case "$old" in
    "$BUNDLE_ID") ;;
    org.xboxrecomp.split2_recomp) [ "$TITLE" = ts2 ] || die "$APP is TimeSplitters 2's; not replacing it" ;;
    *) die "$APP exists and is not this app (bundle id '${old:-none}'); not replacing it" ;;
    esac
fi

STAGE=$(mktemp -d "${TMPDIR:-/tmp}/ts2app.XXXXXX")
trap 'rm -rf "${STAGE:?}"' EXIT
A="$STAGE/$NAME.app"
PY=python3; [ -x "$HOME/.venvs/recomp/bin/python" ] && PY=$HOME/.venvs/recomp/bin/python

echo "== the games"
# The first game makes the bundle (its rpath, the shader compiler, the Vulkan loader and MoltenVK); any other is
# bundled the same way beside it and its executable moved in, the libraries being the same.
first=""
for g in $GAMES; do
    bin=BIN_$g
    if [ -z "$first" ]; then
        VULKAN_SDK=$SDK "$PY" "$HERE/recompose/scripts/make_macos_app.py" "${!bin}" --name "$NAME" --out "$STAGE" \
            --bundle-id "$BUNDLE_ID" --no-sign >/dev/null
        first=$g
    else
        mkdir -p "$STAGE/$g"
        VULKAN_SDK=$SDK "$PY" "$HERE/recompose/scripts/make_macos_app.py" "${!bin}" --name "$g" --out "$STAGE/$g" \
            --bundle-id "$BUNDLE_ID.$g" --no-sign >/dev/null
        mv "$STAGE/$g/$g.app/Contents/MacOS/$(basename "${!bin}")" "$A/Contents/MacOS/"
        rm -rf "${STAGE:?}/$g"
    fi
    echo "   $(basename "${!bin}")"
done

echo "== the launcher"
clang -O2 -fobjc-arc -Wall -Wno-unused-parameter -framework Cocoa -o "$A/Contents/MacOS/$LAUNCHER" "$HERE/mac/ts2_launcher.m"
# the updater rebuilds this game, from this data folder (mac/update.sh)
printf '#!/bin/bash\nTIMESLIP_TITLE=%q TIMESLIP_DATA_TS2=%q TIMESLIP_DATA_FP=%q exec /bin/bash %q "$@"\n' \
    "$TITLE" "$DATA_ts2" "$DATA_fp" "$HERE/mac/update.sh" > "$A/Contents/MacOS/update"
chmod +x "$A/Contents/MacOS/update"

echo "== the icon"
# The game's own, made here from the player's disc (tools/make_icon.py; nothing of the game is in the repository): the
# title screen's logo on the front end's blue for 128 px and up, and the Xbox dashboard's emblem, which stays sharp
# small, for 16-64. For the collection (both games), or without the launcher's art (mac/make_art.sh) or Pillow,
# Timeslip's own icon (art/icon/png/1024.png, tools/art/make_art.py). Either is fitted to macOS's icon grid (824 of 1024 px).
swiftc -O -o "$STAGE/icongrid" "$HERE/mac/tools/icongrid.swift" 2>/dev/null
IS="$STAGE/AppIcon.iconset"; mkdir -p "$IS"
small="$STAGE/icon1024.png"
DATA=""; [ "$TITLE" = all ] || { d=DATA_$TITLE; DATA=${!d}; }
if [ -n "$DATA" ] && [ -f "$DATA/game/default.xbe" ] && [ -f "$DATA/art/logo.png" ] && [ -f "$DATA/art/glow.png" ] &&
   "$PY" "$HERE/tools/make_icon.py" --game "$DATA/game" --art "$DATA/art" --png "$STAGE/game1024.png" --size 1024 >/dev/null &&
   "$PY" "$HERE/tools/make_icon.py" --game "$DATA/game" --png "$STAGE/emblem.png" --out "$STAGE/emblem.ico" >/dev/null; then
    "$STAGE/icongrid" "$STAGE/game1024.png" "$STAGE/icon1024.png" 0
    "$STAGE/icongrid" "$STAGE/emblem.png" "$STAGE/emblem1024.png" 0
    small="$STAGE/emblem1024.png"
    echo "   the game's (the title logo; the dashboard emblem when small)"
else
    [ -s "$HERE/art/icon/png/1024.png" ] || die "no art/icon/png/1024.png (tools/art/make_art.py makes it)"
    "$STAGE/icongrid" "$HERE/art/icon/png/1024.png" "$STAGE/icon1024.png"
    echo "   Timeslip's own"
fi
for s in 16 32 128 256 512; do
    src="$STAGE/icon1024.png"; [ $s -le 32 ] && src=$small                  # 16, 32 and their @2x (64)
    sips -z $s $s "$src" --out "$IS/icon_${s}x${s}.png" >/dev/null
    sips -z $((s * 2)) $((s * 2)) "$src" --out "$IS/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$IS" -o "$A/Contents/Resources/AppIcon.icns"

echo "== the art"
# each game's launcher art (its backdrop, logo and card), a copy beside its data folder's: Resources/art_<game>
PB=/usr/libexec/PlistBuddy; P="$A/Contents/Info.plist"
plist() { $PB -c "Add :$1 string $2" "$P" 2>/dev/null || $PB -c "Set :$1 $2" "$P"; }
for g in $GAMES; do
    d=DATA_$g; mkdir -p "$A/Contents/Resources/art_$g"
    if [ -d "${!d}/art" ]; then cp "${!d}"/art/* "$A/Contents/Resources/art_$g/"; else echo "install: note: no art for $g yet (mac/make_art.sh)" >&2; fi
    plist "Timeslip$(echo "$g" | tr '[:lower:]' '[:upper:]')Data" "${!d}"       # where the launcher finds the game
done
$PB -c "Set :CFBundleExecutable $LAUNCHER" "$P"
$PB -c "Add :CFBundleIconFile string AppIcon" "$P" 2>/dev/null || $PB -c "Set :CFBundleIconFile AppIcon" "$P"
plist CFBundleName "$NAME"; plist TS2DisplayName "$NAME"
[ "$TITLE" = all ] || plist TS2Exe "$EXE"                                     # a one-game app: which it is
plist TS2Branch "$(git -C "$HERE" rev-parse --abbrev-ref HEAD)"; plist TS2Built "$(git -C "$HERE" rev-parse HEAD)"

echo "== signing"
# A stable identity when this Mac has one (~/Games/TimeSplitters2Native/make-signing-identity.sh makes
# "Josh Local Code Signing"): the firewall's Allow and the Local Network permission follow the signing
# identity, so with it they survive rebuilds; ad hoc, every build is new to macOS and it asks again.
ID=${TS2_SIGN_ID:-Josh Local Code Signing}
SIGN_WAIT=${TS2_SIGN_WAIT:-60}
if security find-identity -v -p codesigning 2>/dev/null | grep -q "\"$ID\""; then
    # Until the key's partition list allows codesign (`security set-key-partition-list`, which needs the
    # login password), codesign either fails at once (errSecInternalComponent) or waits on a keychain
    # prompt that may never be answered. So it gets $SIGN_WAIT seconds, then the build is signed ad hoc.
    codesign --force --deep --sign "$ID" "$A" 2>"$STAGE/sign.log" & SIGN_PID=$!
    waited=0
    while kill -0 "$SIGN_PID" 2>/dev/null && [ "$waited" -lt "$SIGN_WAIT" ]; do sleep 1; waited=$((waited + 1)); done
    if kill -0 "$SIGN_PID" 2>/dev/null; then
        kill "$SIGN_PID" 2>/dev/null; wait "$SIGN_PID" 2>/dev/null || true
        # a codesign stopped part way leaves <binary>.cstemp files, which the next seal would count as content
        find "$A" -name '*.cstemp' -delete
        echo "   signing as $ID waited ${SIGN_WAIT}s (a keychain prompt?); signing ad hoc" >&2
        codesign --force --deep --sign - "$A" 2>/dev/null
    elif wait "$SIGN_PID"; then
        echo "   signed as $ID"
    else
        echo "   could not sign as $ID ($(tail -1 "$STAGE/sign.log")); signing ad hoc" >&2
        codesign --force --deep --sign - "$A" 2>/dev/null
    fi
else
    codesign --force --deep --sign - "$A" 2>/dev/null
    echo "   signed ad hoc (no \"$ID\" identity: the firewall will ask again after each rebuild)"
fi
codesign --verify --strict "$A"

echo "== installing"
rm -rf "$APP"
ditto "$A" "$APP"
echo "installed $APP ($(git -C "$HERE" rev-parse --short HEAD))"
