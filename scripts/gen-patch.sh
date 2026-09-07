#!/bin/bash
# Regenerate packaging/kwin/wslg-kwin-rail.patch from packaging/kwin/src/ against the
# upstream kwin tarball named by the dist-git submodule.
#
#   scripts/gen-patch.sh           # write the patch
#   scripts/gen-patch.sh --check   # exit 1 if the committed patch is stale (used by pre-commit/CI)
set -euo pipefail
# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/lib.sh"

check=0
[ "${1:-}" = "--check" ] && check=1

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
ver="$(kwin_version)"
tar="$(fetch_kwin_tarball "$tmp")"

tar -C "$tmp" -xf "$tar"
cp -r "$tmp/kwin-$ver" "$tmp/kwin-$ver.orig"
for f in "$PKG_DIR"/kwin/src/*; do
    dst="$tmp/kwin-$ver/src/backends/wayland/$(basename "$f")"
    [ -f "$dst" ] || die "src/$(basename "$f") has no counterpart at src/backends/wayland/ in kwin-$ver — the tree moved"
    cp "$f" "$dst"
done

out="$tmp/wslg-kwin-rail.patch"
# Strip the volatile mtime from the ---/+++ header lines so the patch is reproducible.
(cd "$tmp" && diff -Nurp "kwin-$ver.orig" "kwin-$ver" || true) |
    sed -E -e "s|kwin-$ver\.orig/|a/|g" -e "s|kwin-$ver/|b/|g" \
        -e 's|^(--- a/[^\t]+)\t.*|\1|' -e 's|^(\+\+\+ b/[^\t]+)\t.*|\1|' > "$out"

grep -q '^--- a/' "$out" || die "generated patch is empty — src/ matches upstream?"

dest="$PKG_DIR/kwin/wslg-kwin-rail.patch"
if [ "$check" = 1 ]; then
    if ! diff -q "$out" "$dest" > /dev/null 2>&1; then
        echo "wslg-kwin-rail.patch is out of date; run scripts/gen-patch.sh" >&2
        diff -u "$dest" "$out" | head -40 >&2 || true
        exit 1
    fi
    log "wslg-kwin-rail.patch is current"
else
    cp "$out" "$dest"
    log "wrote $dest ($(wc -l < "$dest") lines, against kwin $ver)"
fi
