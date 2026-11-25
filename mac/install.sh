#!/bin/bash
# Builds a game of the Timeslip collection as an app from this checkout's build and installs it:
# "TimeSplitters 2.app" (scripts/build.py first), or with --title fp "TimeSplitters Future Perfect.app"
# (fp/scripts/build.py first).
#
#   mac/install.sh [--title ts2|fp] [--app <path.app>] [--data <dir>]
#     --title which game (default ts2)
#     --app   where the app goes (default /Applications/<the game's name>.app)
#     --data  the game's folder: <data>/game holds the disc's files, <data>/art the launcher's art
#             (default ~/Games/TimeSplitters2Native, or ~/Games/TimeSplittersFPNative; mac/make_art.sh makes
#             TimeSplitters 2's art)
#
# The app: Contents/MacOS/"TimeSplitters 2" is the launcher (mac/ts2_launcher.m), which starts the recompiled game
# (Contents/MacOS/timeslip, bundled by recompose/scripts/make_macos_app.py --metal-only: DXC, which the Metal renderer
# compiles its shaders with; the Mac draws with Metal only, so no Vulkan loader or MoltenVK) in the same process. Contents/MacOS/update runs
# mac/update.sh from this checkout. It contains the game's recompiled code: for this Mac only, never distribute it.
set -euo pipefail
HERE=$(cd "$(dirname "$0")/.." && pwd)
TITLE=ts2 APP="" DATA=""
while [ $# -gt 0 ]; do
    case "$1" in
    --title) TITLE=$2; shift 2 ;;
    --app) APP=$2; shift 2 ;;
    --data) DATA=$2; shift 2 ;;
    *) echo "usage: mac/install.sh [--title ts2|fp] [--app <path.app>] [--data <dir>]" >&2; exit 2 ;;
    esac
done
die() { echo "install: $*" >&2; exit 1; }
case "$TITLE" in
ts2) NAME="TimeSplitters 2"; BUNDLE_ID=io.github.joshspeakman.timesplitters2; EXE=timeslip; TITLE_ID=4553000A
     BIN=$HERE/build/Release/timeslip; BUILD_CMD=scripts/build.py; DEF_DATA="$HOME/Games/TimeSplitters2Native" ;;
fp)  NAME="TimeSplitters Future Perfect"; BUNDLE_ID=io.github.joshspeakman.timesplitters-fp; EXE=timeslip_fp; TITLE_ID=45410066
     BIN=$HERE/fp/build/Release/timeslip_fp; BUILD_CMD=fp/scripts/build.py; DEF_DATA="$HOME/Games/TimeSplittersFPNative" ;;
*)   die "--title is ts2 or fp, not $TITLE" ;;
esac
APP=${APP:-/Applications/$NAME.app}
DATA=${DATA:-$DEF_DATA}
SDK=${VULKAN_SDK:-$HOME/VulkanSDK/1.4.357.1/macOS}

[ -x "$BIN" ] || die "no build: run $BUILD_CMD first"
[ -f "$DATA/game/default.xbe" ] || echo "install: note: no game in $DATA/game yet; the launcher will say so" >&2
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

echo "== the game"
VULKAN_SDK=$SDK "$PY" "$HERE/recompose/scripts/make_macos_app.py" "$BIN" --name "$NAME" --out "$STAGE" \
    --bundle-id "$BUNDLE_ID" --metal-only --no-sign >/dev/null

echo "== the launcher"
clang -O2 -fobjc-arc -Wall -Wno-unused-parameter -framework Cocoa -o "$A/Contents/MacOS/$NAME" "$HERE/mac/ts2_launcher.m"
# the updater rebuilds this game, from this data folder (mac/update.sh)
printf '#!/bin/bash\nTIMESLIP_TITLE=%q TIMESLIP_DATA=%q exec /bin/bash %q "$@"\n' "$TITLE" "$DATA" "$HERE/mac/update.sh" \
    > "$A/Contents/MacOS/update"
chmod +x "$A/Contents/MacOS/update"

echo "== the icon"
# The game's own, made here from the player's disc (tools/make_icon.py; nothing of the game is in the repository): the
# title screen's logo on the front end's blue for 128 px and up, and the Xbox dashboard's emblem, which stays sharp
# small, for 16-64. Without the launcher's art (mac/make_art.sh) or Pillow, Timeslip's own icon
# (art/icon/png/1024.png, tools/art/make_art.py). Either is fitted to macOS's icon grid (824 of 1024 px).
swiftc -O -o "$STAGE/icongrid" "$HERE/mac/tools/icongrid.swift" 2>/dev/null
IS="$STAGE/AppIcon.iconset"; mkdir -p "$IS"
small="$STAGE/icon1024.png"
if [ -f "$DATA/game/default.xbe" ] && [ -f "$DATA/art/logo.png" ] && [ -f "$DATA/art/glow.png" ] &&
   "$PY" "$HERE/tools/make_icon.py" --game "$DATA/game" --art "$DATA/art" --png "$STAGE/game1024.png" --size 1024 >/dev/null &&
   "$PY" "$HERE/tools/make_icon.py" --game "$DATA/game" --png "$STAGE/emblem.png" --out "$STAGE/emblem.ico" >/dev/null; then
    "$STAGE/icongrid" "$STAGE/game1024.png" "$STAGE/icon1024.png" 0
    "$STAGE/icongrid" "$STAGE/emblem.png" "$STAGE/emblem1024.png" 0
    small="$STAGE/emblem1024.png"
    echo "   the game's (the title logo; the dashboard emblem when small)"
else
    [ -s "$HERE/art/icon/png/1024.png" ] || die "no art/icon/png/1024.png (tools/art/make_art.py makes it)"
    "$STAGE/icongrid" "$HERE/art/icon/png/1024.png" "$STAGE/icon1024.png"
    echo "   Timeslip's own (no art from the disc yet: mac/make_art.sh)"
fi
for s in 16 32 128 256 512; do
    src="$STAGE/icon1024.png"; [ $s -le 32 ] && src=$small                  # 16, 32 and their @2x (64)
    sips -z $s $s "$src" --out "$IS/icon_${s}x${s}.png" >/dev/null
    sips -z $((s * 2)) $((s * 2)) "$src" --out "$IS/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$IS" -o "$A/Contents/Resources/AppIcon.icns"

echo "== the art"
mkdir -p "$A/Contents/Resources/art"
if [ -d "$DATA/art" ]; then cp "$DATA"/art/* "$A/Contents/Resources/art/"; else echo "install: note: no art yet (mac/make_art.sh)" >&2; fi
PB=/usr/libexec/PlistBuddy; P="$A/Contents/Info.plist"
$PB -c "Set :CFBundleExecutable $NAME" "$P"
$PB -c "Add :CFBundleIconFile string AppIcon" "$P" 2>/dev/null || $PB -c "Set :CFBundleIconFile AppIcon" "$P"
for kv in "TS2DataPath:$DATA" "TS2DisplayName:$NAME" "TS2Exe:$EXE" "TS2TitleID:$TITLE_ID" "TS2Branch:$(git -C "$HERE" rev-parse --abbrev-ref HEAD)" "TS2Built:$(git -C "$HERE" rev-parse HEAD)"; do
    $PB -c "Add :${kv%%:*} string ${kv#*:}" "$P" 2>/dev/null || $PB -c "Set :${kv%%:*} ${kv#*:}" "$P"
done

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
