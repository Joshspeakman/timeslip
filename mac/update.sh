#!/bin/bash
# The app's updater (installed as Contents/MacOS/update, which runs this file from the checkout the app was built
# from). The launcher's Updates tile calls it.
#   update.sh --check     the newest commit of the branch on GitHub (no changes made)
#   update.sh             fast-forward, lift and build again, reinstall the app
# The "== " lines are the phases the launcher shows while it runs.
set -euo pipefail
HERE=$(cd "$(dirname "$0")/.." && pwd)
BRANCH=${TS2_BRANCH:-$(git -C "$HERE" rev-parse --abbrev-ref HEAD)}
if [ "${1:-}" = "--check" ]; then
    git -C "$HERE" ls-remote origin "refs/heads/$BRANCH" | cut -f1
    exit 0
fi
cd "$HERE"
if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
    echo "update: $HERE has local changes; not updating over them" >&2
    exit 1
fi
echo "== fetching"
git fetch -q origin "$BRANCH"
git checkout -q "$BRANCH"
git merge -q --ff-only "origin/$BRANCH"
echo "== $BRANCH: $(git log -1 --format='%h %s')"
git submodule update --init xboxrecomp
echo "== recompiling"
PY=python3; [ -x "$HOME/.venvs/recomp/bin/python" ] && PY=$HOME/.venvs/recomp/bin/python
VULKAN_SDK=${VULKAN_SDK:-$HOME/VulkanSDK/1.4.357.1/macOS} "$PY" scripts/build.py --relift
echo "== building"
exec "$HERE/mac/install.sh"
