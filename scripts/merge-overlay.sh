#!/bin/bash
# 3-way merge packaging/kwin/src/ (whole-file copies of our modified upstream sources)
# from the kwin version at dist-git <old-ref> onto the version at <new-ref>:
# base = old upstream tarball, ours = src/, theirs = new upstream tarball.
#
#   scripts/merge-overlay.sh <old-dist-git-ref> <new-dist-git-ref>
#
# gen-patch.sh copies src/ over the new tarball, so without this step every upstream
# change to those files would be silently reverted by the regenerated patch.
#
# On success, or on a merge conflict (markers left in src/ for hand resolution, then run
# scripts/gen-patch.sh), dist-git is left at <new-ref>. On any failure *before* the
# merge (e.g. a tarball download), dist-git is put back at <old-ref>, so a re-run of
# scripts/rebase-kwin.sh still sees the old version as the merge base instead of
# skipping the merge.
set -euo pipefail
# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/lib.sh"

[ $# -eq 2 ] || die "usage: $0 <old-dist-git-ref> <new-dist-git-ref>"
old_ref="$1"
new_ref="$2"

# Install the rollback trap before anything (even mktemp) can fail.
tmp=""
restore=1
cleanup() {
    if [ "$restore" = 1 ]; then
        git -C "$DISTGIT" checkout -q "$old_ref" || true
    fi
    if [ -n "$tmp" ]; then rm -rf "$tmp"; fi
}
trap cleanup EXIT
tmp="$(mktemp -d)"

# fetch_kwin_tarball reads the version + checksum from the dist-git checkout.
git -C "$DISTGIT" checkout -q "$old_ref"
oldver="$(kwin_version)"
oldtar="$(fetch_kwin_tarball "$tmp/old")"
git -C "$DISTGIT" checkout -q "$new_ref"
newver="$(kwin_version)"
if [ "$oldver" = "$newver" ]; then
    restore=0
    log "kwin $newver unchanged — no overlay merge needed"
    exit 0
fi
newtar="$(fetch_kwin_tarball "$tmp/new")"
tar -C "$tmp/old" -xf "$oldtar"
tar -C "$tmp/new" -xf "$newtar"

log "3-way merging packaging/kwin/src/ from kwin $oldver onto $newver"
for f in "$PKG_DIR"/kwin/src/*; do
    rel="src/backends/wayland/$(basename "$f")"
    [ -f "$tmp/old/kwin-$oldver/$rel" ] || die "$rel missing from kwin-$oldver — can't use it as the merge base"
    [ -f "$tmp/new/kwin-$newver/$rel" ] || die "$rel missing from kwin-$newver — the tree moved, port src/$(basename "$f") by hand"
done
# Merge into scratch copies and only move them into src/ once every file merged (cleanly
# or with conflict markers): a fatal git error part-way through then leaves src/
# untouched and dist-git restored to <old-ref>, so a re-run redoes the whole merge.
mkdir "$tmp/merged"
conflicts=()
for f in "$PKG_DIR"/kwin/src/*; do
    rel="src/backends/wayland/$(basename "$f")"
    out="$tmp/merged/$(basename "$f")"
    cp "$f" "$out" && chmod u+w "$out"
    # exit status = number of conflicts (capped at 127); git's -1 error status is 255
    rc=0
    git merge-file -L "ours (packaging/kwin/src)" -L "kwin-$oldver" -L "kwin-$newver" \
        "$out" "$tmp/old/kwin-$oldver/$rel" "$tmp/new/kwin-$newver/$rel" || rc=$?
    [ "$rc" -le 127 ] || die "git merge-file failed on $f (status $rc) — not a conflict; src/ left untouched"
    [ "$rc" -eq 0 ] || conflicts+=("$f")
done
# Install the merged files; if that copy fails part-way (e.g. disk full), put the
# originals back and die with restore still set, so the trap restores <old-ref> too.
mkdir "$tmp/orig"
cp -p "$PKG_DIR"/kwin/src/* "$tmp/orig/"
if ! cp "$tmp/merged"/* "$PKG_DIR/kwin/src/"; then
    cp -p "$tmp/orig"/* "$PKG_DIR/kwin/src/" ||
        die "installing merged files failed AND restoring the originals failed — restore packaging/kwin/src/ with git checkout"
    die "installing the merged files into packaging/kwin/src/ failed — originals restored, nothing merged"
fi
restore=0
if [ "${#conflicts[@]}" -gt 0 ]; then
    printf '  conflict: %s\n' "${conflicts[@]}" >&2
    die "upstream kwin $newver changed code our overlay also touches — resolve the conflict markers by hand, then run scripts/gen-patch.sh"
fi
log "overlay merged cleanly onto kwin $newver"
