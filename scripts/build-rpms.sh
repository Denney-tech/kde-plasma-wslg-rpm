#!/bin/bash
# Build binary RPMs for one package (via its .src.rpm) into build/rpmbuild/RPMS/.
# Installs BuildRequires with dnf (needs sudo or root; CI runs as root in-container).
#
#   scripts/build-rpms.sh kwin
#   scripts/build-rpms.sh kde-plasma-wslg
#   scripts/build-rpms.sh kde-plasma-wslg-repo
set -euo pipefail
# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/lib.sh"

pkg="${1:?usage: build-rpms.sh <pkg> [outdir]}"
outdir="${2:-$REPO_ROOT/build}"
top="$outdir/rpmbuild"

srpm="$("$(dirname "$0")/build-srpm.sh" "$pkg" "$outdir" | tail -1)"

SUDO=""
[ "$(id -u)" -ne 0 ] && SUDO="sudo"
log "installing build dependencies for $pkg"
$SUDO dnf -y builddep --setopt=install_weak_deps=False "$srpm"

log "building $pkg"
rpmbuild --define "_topdir $top" --undefine=_disable_source_fetch --rebuild "$srpm"

log "RPMs:"
find "$top/RPMS" -name "$pkg-*.rpm" -o -name "${pkg%%-repo}-*.rpm" | sort | sed 's/^/  /' >&2
