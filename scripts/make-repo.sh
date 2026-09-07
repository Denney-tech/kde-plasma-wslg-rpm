#!/bin/bash
# Assemble / update the dnf repo tree from built RPMs and GPG-sign it.
#
#   scripts/make-repo.sh <rpm-source-dir> <repo-root> [keep-kwin-builds]
#
# <repo-root> is laid out as el10/x86_64/ and el10/noarch/ (matching the .repo baseurls).
# Needs: createrepo_c, gpg (key already imported), rpmsign; env GPG_KEY_ID must be set.
set -euo pipefail
# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/lib.sh"

src="${1:?usage: make-repo.sh <rpm-src-dir> <repo-root> [keep]}"
root="${2:?usage: make-repo.sh <rpm-src-dir> <repo-root> [keep]}"
keep="${3:-5}"
: "${GPG_KEY_ID:?set GPG_KEY_ID to the signing key id/fingerprint}"

command -v createrepo_c > /dev/null || die "createrepo_c not found"

mkdir -p "$root/el10/x86_64" "$root/el10/noarch"

log "signing + placing RPMs"
latest_repo_rpm() {
    # shellcheck disable=SC2012  # tool-generated names, newest-first by mtime
    basename "$(ls -1t "$root"/el10/noarch/kde-plasma-wslg-repo-*.rpm 2> /dev/null | head -1)" 2> /dev/null ||
        echo kde-plasma-wslg-repo.noarch.rpm
}
shopt -s nullglob
for rpm in "$src"/**/*.rpm "$src"/*.rpm; do
    case "$rpm" in *-debuginfo-* | *-debugsource-*) continue ;; esac
    rpmsign --addsign --define "_gpg_name $GPG_KEY_ID" "$rpm" > /dev/null
    case "$(rpm -qp --qf '%{ARCH}' "$rpm")" in
        noarch) cp -f "$rpm" "$root/el10/noarch/" ;;
        *) cp -f "$rpm" "$root/el10/x86_64/" ;;
    esac
done

# Retention: keep the newest <keep> builds of each kwin* subpackage, all noarch.
if [ "$keep" -gt 0 ]; then
    log "pruning old kwin builds (keep $keep)"
    for base in kwin kwin-libs kwin-common kwin-devel; do
        # shellcheck disable=SC2012  # rpm filenames are tool-generated, mtime sort is intentional
        mapfile -t old < <(ls -1t "$root"/el10/x86_64/"${base}"-[0-9]*.rpm 2> /dev/null | tail -n +$((keep + 1)))
        for f in "${old[@]:-}"; do [ -n "$f" ] && rm -f "$f" && log "  pruned $(basename "$f")"; done
    done
fi

for arch in x86_64 noarch; do
    log "createrepo_c el10/$arch"
    createrepo_c --update --general-compress-type=zstd "$root/el10/$arch"
    gpg --batch --yes --pinentry-mode loopback \
        ${GPG_PASSPHRASE:+--passphrase "$GPG_PASSPHRASE"} \
        --detach-sign --armor "$root/el10/$arch/repodata/repomd.xml"
done

cp -f "$PKG_DIR/kde-plasma-wslg-repo/RPM-GPG-KEY-kde-plasma-wslg" "$root/"
cat > "$root/index.html" << HTML
<!doctype html><meta charset=utf-8><title>kde-plasma-wslg-rpm</title>
<h1>kde-plasma-wslg-rpm</h1>
<p>dnf repository for the WSLg KDE Plasma desktop. See
<a href="https://github.com/Denney-tech/kde-plasma-wslg-rpm">the project</a>.</p>
<pre>sudo dnf install https://denney-tech.github.io/kde-plasma-wslg-rpm/el10/noarch/$(latest_repo_rpm)
sudo dnf install kde-plasma-wslg</pre>
HTML
log "repo tree ready at $root"
