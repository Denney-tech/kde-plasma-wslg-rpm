# Maintaining kde-plasma-wslg-rpm

## Layout

```text
packaging/kwin/
  dist-git/                 git submodule -> src.fedoraproject.org/rpms/kwin  (EPEL, branch epel10.N)
  kwin.spec.patch           overlay onto dist-git/kwin.spec (Release suffix, Patch1000, shim, Provides)
  wslg-kwin-rail.patch      the C++ patch (Patch1000) — GENERATED from src/ by scripts/gen-patch.sh
  src/                      the 6 patched wayland-backend files — the authoritative source
  kwin_wayland_wrapper.shim  Source1000
packaging/kde-plasma-wslg/       noarch: launcher + control cmd + user unit + tmpfiles + kscreenlockerrc
packaging/kde-plasma-wslg-repo/  noarch: the .repo file + RPM-GPG-KEY
scripts/                    build-srpm, build-rpms, gen-patch, check-specs, rebase-kwin, make-repo
```

The kwin **binary** RPM version comes from EPEL (`Version:` in `dist-git/kwin.spec`); our
overlay only appends `.wslgN` to `Release:`. Bump `N` (in `kwin.spec.patch`, both the
`Release:` line and a new `%changelog` entry) whenever the C++ patch or the overlay itself
changes without an upstream version bump.

The **repo semver** (`version.txt`, the two noarch specs' `%global baseversion`, `CHANGELOG.md`)
is owned by **release-please** — never edit those by hand.

## Editing the kwin C++ patch

1. Edit the real files under `packaging/kwin/src/`.
2. `make patch` (== `scripts/gen-patch.sh`) — regenerates `wslg-kwin-rail.patch` against the
   exact upstream tarball named by the submodule's `sources` file.
3. Bump `.wslgN` + add a `%changelog` line in `packaging/kwin/kwin.spec.patch`.
4. `scripts/build-rpms.sh kwin` on an EL10 host/container to confirm it builds.
5. Commit as `fix: …` (patch RPMs) — CI rebuilds; cut a release to publish.

`make check` (CI runs it) fails if `wslg-kwin-rail.patch` is stale vs `src/`.

## Rebasing kwin onto a new EPEL release

EPEL bumps `kwin` on its `epel10` branch and, per RHEL minor, `epel10.N`. When that happens:

```bash
scripts/rebase-kwin.sh epel10.3      # or a bare sha, or no arg for the tracked branch tip
```

It moves the submodule, re-applies `kwin.spec.patch` (regenerating it from the clean result
if it applied with no fuzz), and regenerates `wslg-kwin-rail.patch` against the new tarball.
If the overlay or the C++ patch conflicts, it stops and tells you to fix
`packaging/kwin/kwin.spec.patch` / `packaging/kwin/src/*` by hand, then re-run.

Then: bump `.wslgN`, `scripts/build-rpms.sh kwin` in a container, commit as
`fix: rebase kwin onto <version>`.

The overlay's anchor points (`Release:`, `## proposed patches`, the `ln -sr … kwin` line in
`%install`, `%{_bindir}/kwin_wayland_wrapper` in `%files`, the `Requires:` block, `%changelog`)
have been stable across kwin 6.x; expect small offset fixes at most.

## Releases (automated)

- Commit with **Conventional Commits** (`feat:`, `fix:`, `chore:`, `docs:`, `feat!:`/`BREAKING
  CHANGE:` for a major). See `CONTRIBUTING.md`.
- `release-please.yml` opens/maintains a **release PR** that bumps `version.txt`, the noarch
  specs, and `CHANGELOG.md`.
- Merging that PR tags `vX.Y.Z` and creates a GitHub Release; `release-please.yml` then
  calls `release.yml` (a reusable workflow — a Release made by `GITHUB_TOKEN` can't trigger
  `on: release`): build on EL10 → GPG-sign every RPM → `createrepo_c` + sign `repomd.xml` →
  push the tree to the `gh-pages` branch (GitHub Pages serves it) → attach the RPMs + GPG
  key to the Release. To rebuild a release by hand: run the **Release** workflow via
  `workflow_dispatch` with the tag.
- The published dnf repo lives at `https://denney-tech.github.io/kde-plasma-wslg-rpm/el10/`.
  Retention: newest 5 kwin builds, all noarch (`scripts/make-repo.sh`).

## Signing

The signing keypair is RSA-4096. Public key: `packaging/kde-plasma-wslg-repo/RPM-GPG-KEY-kde-plasma-wslg`
(shipped in the `-repo` package, and as `/RPM-GPG-KEY-kde-plasma-wslg` on Pages).

Repo secrets required by `release.yml`:

| secret | value |
|---|---|
| `GPG_PRIVATE_KEY` | ASCII-armored private key block |
| `GPG_PASSPHRASE`  | its passphrase |

To rotate: generate a new RSA-4096 key, replace the public key file + the two secrets, and
cut a release (old + new keys can both be trusted during a transition by concatenating
them into the key file).

## Prerequisites (one-time, GitHub side)

1. Repo `Denney-tech/kde-plasma-wslg-rpm` exists.
2. Settings → Pages → **Deploy from a branch → `gh-pages` / `/`**.
3. Settings → Secrets → `GPG_PRIVATE_KEY`, `GPG_PASSPHRASE`.
4. Settings → Actions → Workflow permissions → **Read and write** (for release-please + gh-pages).
