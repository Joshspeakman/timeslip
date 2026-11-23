#!/bin/bash
# Builds "TimeSplitters 2.app" from this checkout's build (scripts/build.py first) and installs it.
#
#   mac/install.sh [--app <path.app>] [--data <dir>]
#     --app   where the app goes (default /Applications/TimeSplitters 2.app)
#     --data  the game's folder: <data>/game holds the disc's files, <data>/art the launcher's art
#             (default ~/Games/TimeSplitters2Native; mac/make_art.sh makes the art)
#
# The app: Contents/MacOS/"TimeSplitters 2" is the launcher (mac/ts2_launcher.m), which starts the recompiled game
# (Contents/MacOS/split2_recomp, bundled by xboxrecomp/scripts/make_macos_app.py with its Vulkan loader, MoltenVK and
# DXC for the Vulkan renderer; the Metal renderer needs none of them) in the same process. Contents/MacOS/update runs
# mac/update.sh from this checkout. It contains the game's recompiled code: for this Mac only, never distribute it.
set -euo pipefail
HERE=$(cd "$(dirname "$0")/.." && pwd)
APP="/Applications/TimeSplitters 2.app"
DATA="$HOME/Games/TimeSplitters2Native"
while [ $# -gt 0 ]; do
    case "$1" in
    --app) APP=$2; shift 2 ;;
    --data) DATA=$2; shift 2 ;;
    *) echo "usage: mac/install.sh [--app <path.app>] [--data <dir>]" >&2; exit 2 ;;
    esac
done
BUNDLE_ID=io.github.joshspeakman.timesplitters2
SDK=${VULKAN_SDK:-$HOME/VulkanSDK/1.4.357.1/macOS}
BIN=$HERE/build/Release/split2_recomp
die() { echo "install: $*" >&2; exit 1; }

[ -x "$BIN" ] || die "no build: run scripts/build.py first"
[ -f "$DATA/game/default.xbe" ] || echo "install: note: no game in $DATA/game yet; the launcher will say so" >&2
pgrep -f "$APP/Contents/MacOS/" >/dev/null && die "$APP is running; quit it first"
if [ -e "$APP" ]; then   # replace only this app, never something else at that path
    old=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist" 2>/dev/null || true)
    case "$old" in
    "$BUNDLE_ID"|org.xboxrecomp.split2_recomp) ;;
    *) die "$APP exists and is not this app (bundle id '${old:-none}'); not replacing it" ;;
    esac
fi

STAGE=$(mktemp -d "${TMPDIR:-/tmp}/ts2app.XXXXXX")
trap 'rm -rf "${STAGE:?}"' EXIT
A="$STAGE/TimeSplitters 2.app"
PY=python3; [ -x "$HOME/.venvs/recomp/bin/python" ] && PY=$HOME/.venvs/recomp/bin/python

echo "== the game"
VULKAN_SDK=$SDK "$PY" "$HERE/xboxrecomp/scripts/make_macos_app.py" "$BIN" --name "TimeSplitters 2" --out "$STAGE" \
    --bundle-id "$BUNDLE_ID" --no-sign >/dev/null

echo "== the launcher"
clang -O2 -fobjc-arc -Wall -Wno-unused-parameter -framework Cocoa -o "$A/Contents/MacOS/TimeSplitters 2" "$HERE/mac/ts2_launcher.m"
printf '#!/bin/bash\nexec /bin/bash %q "$@"\n' "$HERE/mac/update.sh" > "$A/Contents/MacOS/update"
chmod +x "$A/Contents/MacOS/update"

echo "== the icon"
# upstream's own icon (release/android/icon.html: drawn in the logo's style, no game artwork), dark tile, on
# macOS's icon grid
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
if [ -x "$CHROME" ]; then
    "$CHROME" --headless=new --disable-gpu --allow-file-access-from-files --default-background-color=00000000 \
        --hide-scrollbars --force-device-scale-factor=2 --window-size=512,512 --virtual-time-budget=2000 \
        --screenshot="$STAGE/icon_raw.png" "file://$HERE/release/android/icon.html?bg=dark" >/dev/null 2>&1 || true
fi
[ -s "$STAGE/icon_raw.png" ] || cp "$HERE/release/android/icon.png" "$STAGE/icon_raw.png"
swiftc -O -o "$STAGE/icongrid" "$HERE/mac/tools/icongrid.swift" 2>/dev/null
"$STAGE/icongrid" "$STAGE/icon_raw.png" "$STAGE/icon1024.png"
IS="$STAGE/AppIcon.iconset"; mkdir -p "$IS"
for s in 16 32 128 256 512; do
    sips -z $s $s "$STAGE/icon1024.png" --out "$IS/icon_${s}x${s}.png" >/dev/null
    sips -z $((s * 2)) $((s * 2)) "$STAGE/icon1024.png" --out "$IS/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$IS" -o "$A/Contents/Resources/AppIcon.icns"

echo "== the art"
mkdir -p "$A/Contents/Resources/art"
if [ -d "$DATA/art" ]; then cp "$DATA"/art/* "$A/Contents/Resources/art/"; else echo "install: note: no art yet (mac/make_art.sh)" >&2; fi

PB=/usr/libexec/PlistBuddy; P="$A/Contents/Info.plist"
$PB -c "Set :CFBundleExecutable TimeSplitters 2" "$P"
$PB -c "Add :CFBundleIconFile string AppIcon" "$P" 2>/dev/null || $PB -c "Set :CFBundleIconFile AppIcon" "$P"
for kv in "TS2DataPath:$DATA" "TS2Branch:$(git -C "$HERE" rev-parse --abbrev-ref HEAD)" "TS2Built:$(git -C "$HERE" rev-parse HEAD)"; do
    $PB -c "Add :${kv%%:*} string ${kv#*:}" "$P" 2>/dev/null || $PB -c "Set :${kv%%:*} ${kv#*:}" "$P"
done

echo "== signing"
codesign --force --deep --sign - "$A" 2>/dev/null
codesign --verify --strict "$A"

echo "== installing"
rm -rf "$APP"
ditto "$A" "$APP"
echo "installed $APP ($(git -C "$HERE" rev-parse --short HEAD))"
