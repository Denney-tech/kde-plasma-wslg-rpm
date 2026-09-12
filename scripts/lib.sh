#!/bin/bash
# Shared helpers for the kde-plasma-wslg-rpm build scripts. Source, don't execute.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PKG_DIR="$REPO_ROOT/packaging"
DISTGIT="$PKG_DIR/kwin/dist-git"

log() { printf '\033[1;34m==>\033[0m %s\n' "$*" >&2; }
die() {
    printf '\033[1;31merror:\033[0m %s\n' "$*" >&2
    exit 1
}

# spec_field <spec> <Field:>  -> value of the first matching tag
spec_field() { awk -v k="$2" 'tolower($1)==tolower(k){print $2; exit}' "$1"; }

# kwin_version -> upstream version from the (pristine) dist-git spec
kwin_version() { spec_field "$DISTGIT/kwin.spec" "Version:"; }

# fetch_kwin_tarball <destdir>  -> downloads + SHA512-verifies kwin-<ver>.tar.xz,
# echoes its path. Tries the KDE mirror first, then the Fedora lookaside.
fetch_kwin_tarball() {
    local dest="$1" ver tar want got
    ver="$(kwin_version)"
    tar="$dest/kwin-${ver}.tar.xz"
    want="$(awk -v f="kwin-${ver}.tar.xz" '$0 ~ "\\("f"\\)"{print $NF}' "$DISTGIT/sources")"
    [ -n "$want" ] || die "no SHA512 for kwin-${ver}.tar.xz in $DISTGIT/sources"
    if [ ! -f "$tar" ]; then
        mkdir -p "$dest"
        local urls=(
            "https://download.kde.org/stable/plasma/${ver}/kwin-${ver}.tar.xz"
            "https://src.fedoraproject.org/lookaside/pkgs/rpms/kwin/kwin-${ver}.tar.xz/sha512/${want}/kwin-${ver}.tar.xz"
        )
        local u
        for u in "${urls[@]}"; do
            log "fetching $u"
            if curl -fsSL --retry 3 -o "$tar.part" "$u"; then
                mv "$tar.part" "$tar"
                break
            fi
        done
        [ -f "$tar" ] || die "could not download kwin-${ver}.tar.xz"
    fi
    got="$(sha512sum "$tar" | awk '{print $1}')"
    [ "$got" = "$want" ] || die "SHA512 mismatch for $tar (want $want, got $got)"
    echo "$tar"
}

# rendered_spec <pkg> <outdir>  -> writes the build-ready spec to <outdir>/<pkg>.spec
#   kwin: dist-git spec + kwin.spec.patch overlay + the .wslgN release suffix and our
#         %changelog entry, both applied by anchor (not diff context) so a routine
#         upstream Release/changelog bump can never conflict with them — see
#         MAINTAINING.md "Why the Release suffix and changelog aren't in the diff".
#   others: the spec as-is under packaging/<pkg>/
rendered_spec() {
    local pkg="$1" out="$2" spec
    mkdir -p "$out"
    case "$pkg" in
        kwin)
            cp "$DISTGIT/kwin.spec" "$out/kwin.spec"
            patch -s -p1 -d "$out" < "$PKG_DIR/kwin/kwin.spec.patch" ||
                die "kwin.spec.patch no longer applies to the dist-git spec — run scripts/rebase-kwin.sh"

            local wslgn=""
            wslgn="$(tr -d '[:space:]' < "$PKG_DIR/kwin/wslg-release")"
            [ -n "$wslgn" ] || die "packaging/kwin/wslg-release is empty"
            sed -i -E "s/^(Release:[[:space:]]*[^[:space:]]+)\$/\1.wslg${wslgn}/" "$out/kwin.spec"
            grep -qE "^Release:.*\.wslg${wslgn}\$" "$out/kwin.spec" ||
                die "couldn't find/suffix the Release: line in kwin.spec — dist-git spec format changed?"

            grep -qx '%changelog' "$out/kwin.spec" || die "no %changelog line in kwin.spec"
            sed -i "/^%changelog\$/r $PKG_DIR/kwin/wslg-changelog-entry.txt" "$out/kwin.spec"
            ;;
        *)
            spec="$PKG_DIR/$pkg/$pkg.spec"
            [ -f "$spec" ] || die "no spec for '$pkg'"
            cp "$spec" "$out/$pkg.spec"
            ;;
    esac
}
