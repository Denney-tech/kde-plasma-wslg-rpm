#!/bin/bash
# Move the kwin dist-git submodule to a newer EPEL branch/ref, then re-apply and
# refresh our overlay. Prints what changed and what (if anything) needs a hand.
#
#   scripts/rebase-kwin.sh              # pull the tip of the branch in .gitmodules
#   scripts/rebase-kwin.sh epel10.3     # switch to a different EPEL branch
#   scripts/rebase-kwin.sh <sha>        # pin to a specific commit
set -euo pipefail
# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/lib.sh"

ref="${1:-}"
cd "$DISTGIT"
git fetch --tags origin
if [ -n "$ref" ]; then
    git checkout -q "origin/$ref" 2> /dev/null || git checkout -q "$ref"
    git -C "$REPO_ROOT" config -f "$REPO_ROOT/.gitmodules" \
        submodule.packaging/kwin/dist-git.branch "$ref" 2> /dev/null || true
else
    br="$(git -C "$REPO_ROOT" config -f "$REPO_ROOT/.gitmodules" submodule.packaging/kwin/dist-git.branch)"
    git checkout -q "origin/$br"
fi
newver="$(spec_field kwin.spec Version:)"
newrel="$(spec_field kwin.spec Release:)"
log "dist-git now at $(git rev-parse --short HEAD) — kwin $newver-$newrel"
cd "$REPO_ROOT"

log "re-applying kwin.spec.patch"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
cp "$DISTGIT/kwin.spec" "$tmp/kwin.spec"
if patch -p1 -d "$tmp" --fuzz=3 < packaging/kwin/kwin.spec.patch > "$tmp/patchlog" 2>&1; then
    if grep -q 'FAILED\|fuzz' "$tmp/patchlog"; then
        cat "$tmp/patchlog" >&2
        die "overlay applied with fuzz/rejects — edit packaging/kwin/kwin.spec.patch by hand, then re-run"
    fi
    # regenerate the overlay from the cleanly-patched result so line offsets stay tight
    diff -u "$DISTGIT/kwin.spec" "$tmp/kwin.spec" |
        sed -E -e '1s|.*|--- a/kwin.spec|' -e '2s|.*|+++ b/kwin.spec|' > packaging/kwin/kwin.spec.patch
    log "refreshed packaging/kwin/kwin.spec.patch"
else
    cat "$tmp/patchlog" >&2
    die "overlay does not apply — edit packaging/kwin/kwin.spec.patch by hand, then re-run"
fi

log "regenerating wslg-kwin-rail.patch against kwin $newver"
scripts/gen-patch.sh

cat >&2 << EOF

Next:
  1. bump the .wslgM suffix + add a %changelog entry in packaging/kwin/kwin.spec.patch
     if the C++ patch or spec overlay changed meaningfully.
  2. git add packaging/kwin/dist-git packaging/kwin/kwin.spec.patch \\
            packaging/kwin/wslg-kwin-rail.patch .gitmodules
  3. scripts/build-rpms.sh kwin   (in an el10 container) to prove it still builds.
  4. commit as  fix: rebase kwin onto $newver
EOF
