#!/bin/bash
# Verify every package spec parses: the kwin dist-git spec with our overlay applied,
# and the noarch specs as-is. Used by pre-commit and CI. Needs `rpmspec` (rpm-build).
set -euo pipefail
# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/lib.sh"

command -v rpmspec > /dev/null || die "rpmspec not found (install rpm-build / rpmdevtools)"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
rc=0

for pkg in kwin kde-plasma-wslg kde-plasma-wslg-repo; do
    rendered_spec "$pkg" "$tmp/$pkg"
    # placeholder Source/Patch files so %prep-time references resolve
    : > "$tmp/$pkg/wslg-kwin-rail.patch"
    for s in kwin_wayland_wrapper.shim plasma-wslg plasma-wslg-launch plasma-wslg.service \
        kde-plasma-wslg.tmpfiles.conf kscreenlockerrc README.md LICENSE \
        kde-plasma-wslg-rpm.repo RPM-GPG-KEY-kde-plasma-wslg "kwin-$(kwin_version).tar.xz" \
        "kwin-$(kwin_version).tar.xz.sig"; do
        : > "$tmp/$pkg/$s"
    done
    if rpmspec --define "_sourcedir $tmp/$pkg" -P "$tmp/$pkg/$pkg.spec" > /dev/null 2> "$tmp/$pkg.err"; then
        log "$pkg.spec parses"
    else
        printf '\033[1;31m%s.spec failed to parse:\033[0m\n' "$pkg" >&2
        cat "$tmp/$pkg.err" >&2
        rc=1
    fi
done
exit $rc
