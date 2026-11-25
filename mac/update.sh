#!/bin/bash
# The app's updater on the Mac (installed as Contents/MacOS/update, which runs this file from the checkout the app was
# built from). The launcher's Updates tile calls it. tools/update_windows.ps1 is the Windows one; both follow the same
# rules.
#
#   update.sh --check <installed commit>    one line on standard output:
#       available <tag> <commit>    a newer release is out
#       current <tag> <commit>      the installed build is that release, or newer
#       none                        no release has been published
#       error <why>                 GitHub or git could not be asked
#   update.sh                               to the newest release: fetch it, lift and build again from the player's own
#                                           disc, reinstall the app
#
# The release is the newest of the repository's GitHub releases (its origin's): drafts left out, pre-releases in, the
# highest version tag (v1.0.0-alpha.2 < v1.0.0-alpha.10 < v1.0.0-beta < v1.0.0 < v1.0.1). Git tags that are not
# releases do not count. "Installed" is the commit the installed app was built from (its TS2Built), not the
# checkout's. A checkout already past the release stays where it is: nothing ever moves back or detaches.
#
# The update's "== " lines are the phases the launcher shows; the other lines are its detail.
# For testing: TIMESLIP_UPDATE_RELEASES=<file> reads that JSON instead of GitHub's releases list (and the release
# tags are the checkout's own), and TIMESLIP_UPDATE_INSTALLED=<commit> stands for the installed build.
set -uo pipefail
HERE=$(cd "$(dirname "$0")/.." && pwd)
git_() { git -C "$HERE" "$@"; }

# The newest release's tag on standard output (nothing: none); exit 1 with the reason on stderr when it can't be asked.
newest_release() {
    local json
    if [ -n "${TIMESLIP_UPDATE_RELEASES:-}" ]; then
        json=$(cat "$TIMESLIP_UPDATE_RELEASES") || { echo "could not read $TIMESLIP_UPDATE_RELEASES" >&2; return 1; }
    else
        local url slug
        url=$(git_ remote get-url origin 2>/dev/null) || { echo "no origin" >&2; return 1; }
        slug=$(printf '%s' "$url" | sed -nE 's#.*github\.com[:/]+([^/]+/[^/]+)$#\1#p' | sed -E 's#\.git/?$##; s#/$##')
        [ -n "$slug" ] || { echo "origin is not on GitHub ($url)" >&2; return 1; }
        json=$(curl -fsSL --max-time 30 -H "Accept: application/vnd.github+json" -H "User-Agent: timeslip-updater" \
               "https://api.github.com/repos/$slug/releases?per_page=30") || { echo "GitHub could not be reached" >&2; return 1; }
    fi
    printf '%s' "$json" | /usr/bin/python3 -I -c '
import json, re, sys
def ver(tag):
    m = re.match(r"^v?(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z.-]+))?$", tag or "")
    if not m: return None
    pre = m.group(4).split(".") if m.group(4) else []
    # a release sorts above its pre-releases; within one, numbers below words, then by length
    return ([int(m.group(i)) for i in (1, 2, 3)], 1 if not pre else 0,
            [(0, int(p), "") if p.isdigit() else (1, 0, p) for p in pre])
try:
    rel = json.load(sys.stdin)
except ValueError:
    sys.exit("GitHub sent something that is not JSON")
if not isinstance(rel, list):
    sys.exit("GitHub did not list releases")
best = None
for r in rel:
    if r.get("draft"): continue
    v = ver(r.get("tag_name"))
    if v is not None and (best is None or v > best[0]): best = (v, r["tag_name"])
print(best[1] if best else "")
'
}

# The commit a release tag names, fetched first so it can be compared.
release_commit() {
    if [ -z "${TIMESLIP_UPDATE_RELEASES:-}" ]; then
        git_ fetch -q origin "+refs/tags/$1:refs/tags/$1" 2>/dev/null || { echo "could not fetch $1 from origin" >&2; return 1; }
    fi
    git_ rev-parse --verify --quiet "refs/tags/$1^{commit}" || { echo "$1 names no commit" >&2; return 1; }
}

is_ancestor() { git_ merge-base --is-ancestor "$1" "$2" 2>/dev/null; }

if [ "${1:-}" = "--check" ]; then
    installed=${TIMESLIP_UPDATE_INSTALLED:-${2:-}}
    err=$(mktemp); trap 'rm -f "$err"' EXIT
    tag=$(newest_release 2>"$err") || { echo "error $(tr '\n' ' ' < "$err")"; exit 0; }
    [ -n "$tag" ] || { echo "none"; exit 0; }
    rel=$(release_commit "$tag" 2>"$err") || { echo "error $(tr '\n' ' ' < "$err")"; exit 0; }
    have=""; [ -n "$installed" ] && have=$(git_ rev-parse --verify --quiet "$installed^{commit}" 2>/dev/null)
    if [ -n "$have" ] && { [ "$have" = "$rel" ] || is_ancestor "$rel" "$have"; }; then echo "current $tag $rel"
    else echo "available $tag $rel"; fi
    exit 0
fi

stop() { echo "== The update stopped: $*"; exit 1; }
cd "$HERE" || stop "no checkout at $HERE"
echo "== Asking GitHub for the newest release"
tag=$(newest_release) || stop "GitHub could not be asked"
[ -n "$tag" ] || stop "no release has been published yet"
rel=$(release_commit "$tag") || stop "could not find $tag's commit"
echo "  $tag is ${rel:0:12}"
# Local changes are left alone: an update never builds over them. A submodule's own untracked or changed files are
# not changes to this checkout.
if [ -n "$(git_ status --porcelain --untracked-files=no --ignore-submodules=dirty)" ] ||
   [ -n "$(git -C "$HERE/recompose" status --porcelain --untracked-files=no --ignore-submodules=dirty 2>/dev/null)" ]; then
    stop "the checkout at $HERE has local changes; not updating over them"
fi

echo "== Downloading $tag"
git_ fetch -q origin || stop "could not fetch from origin"
head=$(git_ rev-parse HEAD)
if [ "$head" = "$rel" ] || is_ancestor "$rel" "$head"; then
    echo "  the checkout already has $tag"
elif is_ancestor "$head" "$rel"; then
    branch=$(git_ symbolic-ref --quiet --short HEAD) || stop "the checkout is not on a branch; not moving it"
    git_ merge -q --ff-only "$rel" || stop "could not move $branch to $tag"
    echo "  $branch moved to $tag"
else
    stop "the checkout's history has gone another way from $tag; not moving it"
fi
git_ submodule update --init recompose || stop "could not update the recompose submodule"

echo "== Recompiling the game from your disc"
PY=python3; [ -x "$HOME/.venvs/recomp/bin/python" ] && PY=$HOME/.venvs/recomp/bin/python
VULKAN_SDK=${VULKAN_SDK:-$HOME/VulkanSDK/1.4.357.1/macOS} "$PY" scripts/build.py --relift || stop "the build stopped"

echo "== Installing"
"$HERE/mac/install.sh" || stop "the install stopped"
echo "== Updated to $tag"
exit 0
