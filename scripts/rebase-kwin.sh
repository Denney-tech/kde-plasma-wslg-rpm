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

log "checking kwin.spec.patch still applies"
# The overlay no longer touches the Release: line or %changelog (rendered_spec() applies
# those by anchor instead, see lib.sh) — the three remaining hunks are anchored on spec
# text that upstream essentially never moves, so this should apply with zero fuzz. If it
# needs fuzz at all, that's the overlay's anchors having drifted and worth tightening by
# hand even though it technically still applied.
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
cp "$DISTGIT/kwin.spec" "$tmp/kwin.spec"
if patch -p1 -d "$tmp" --fuzz=0 < packaging/kwin/kwin.spec.patch > "$tmp/patchlog" 2>&1; then
    log "kwin.spec.patch applies cleanly, no changes needed"
elif patch -p1 -d "$tmp" --fuzz=3 < packaging/kwin/kwin.spec.patch > "$tmp/patchlog" 2>&1; then
    cat "$tmp/patchlog" >&2
    log "WARNING: kwin.spec.patch only applied with fuzz — consider tightening its anchors by hand"
else
    cat "$tmp/patchlog" >&2
    die "kwin.spec.patch does not apply to the new dist-git spec — edit it by hand, then re-run"
fi

log "regenerating wslg-kwin-rail.patch against kwin $newver"
before_patch_hash="$(sha256sum packaging/kwin/wslg-kwin-rail.patch 2> /dev/null | awk '{print $1}')"
scripts/gen-patch.sh
after_patch_hash="$(sha256sum packaging/kwin/wslg-kwin-rail.patch | awk '{print $1}')"

cat >&2 << EOF

Next:
  1. scripts/build-rpms.sh kwin   (in an el10 container) to prove it still builds.
  2. git add packaging/kwin/dist-git packaging/kwin/wslg-kwin-rail.patch .gitmodules
  3. commit as  fix: rebase kwin onto $newver
EOF
if [ "$before_patch_hash" != "$after_patch_hash" ]; then
    cat >&2 << 'EOF'

wslg-kwin-rail.patch content changed (not just re-generated identically) — the C++ patch
needed adjusting for this upstream version. Also bump packaging/kwin/wslg-release and add
a dated entry to packaging/kwin/wslg-changelog-entry.txt describing what changed, so the
built package's Release/changelog reflect it.
EOF
fi
