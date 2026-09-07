#!/bin/bash
# Build the .src.rpm for one package into build/ (default) or $2.
#
#   scripts/build-srpm.sh kwin
#   scripts/build-srpm.sh kde-plasma-wslg
#   scripts/build-srpm.sh kde-plasma-wslg-repo
set -euo pipefail
# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/lib.sh"

pkg="${1:?usage: build-srpm.sh <pkg> [outdir]}"
outdir="${2:-$REPO_ROOT/build}"
top="$outdir/rpmbuild"
mkdir -p "$top"/{SPECS,SOURCES,SRPMS,RPMS,BUILD,BUILDROOT}

rendered_spec "$pkg" "$top/SPECS"

case "$pkg" in
    kwin)
        fetch_kwin_tarball "$top/SOURCES" > /dev/null
        ver="$(kwin_version)"
        # the .sig is a declared Source; provide a (possibly empty) placeholder if the
        # mirror doesn't carry it -- the spec only %autosetup's the tarball.
        curl -fsSL --retry 2 -o "$top/SOURCES/kwin-${ver}.tar.xz.sig" \
            "https://download.kde.org/stable/plasma/${ver}/kwin-${ver}.tar.xz.sig" ||
            : > "$top/SOURCES/kwin-${ver}.tar.xz.sig"
        cp "$PKG_DIR/kwin/wslg-kwin-rail.patch" "$top/SOURCES/"
        cp "$PKG_DIR/kwin/kwin_wayland_wrapper.shim" "$top/SOURCES/"
        ;;
    kde-plasma-wslg)
        cp "$PKG_DIR/kde-plasma-wslg/"{plasma-wslg,plasma-wslg-launch,plasma-wslg.service,kde-plasma-wslg.tmpfiles.conf,kscreenlockerrc,README.md} "$top/SOURCES/"
        cp "$REPO_ROOT/LICENSE" "$top/SOURCES/"
        ;;
    kde-plasma-wslg-repo)
        cp "$PKG_DIR/kde-plasma-wslg-repo/"{kde-plasma-wslg-rpm.repo,RPM-GPG-KEY-kde-plasma-wslg} "$top/SOURCES/"
        cp "$REPO_ROOT/LICENSE" "$top/SOURCES/"
        ;;
    *) die "unknown package '$pkg'" ;;
esac

rpmbuild --define "_topdir $top" --undefine=_disable_source_fetch -bs "$top/SPECS/$pkg.spec"
# shellcheck disable=SC2012  # SRPM names are rpmbuild-generated, no odd chars
srpm="$(ls -t "$top"/SRPMS/"$pkg"-*.src.rpm | head -1)"
log "built $srpm"
echo "$srpm"
