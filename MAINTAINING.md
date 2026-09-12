# Maintaining kde-plasma-wslg-rpm

## Layout

```text
packaging/kwin/
  dist-git/                 git submodule -> src.fedoraproject.org/rpms/kwin  (EPEL, branch epel10.N)
  kwin.spec.patch           overlay onto dist-git/kwin.spec (Patch1000/Source1000, Requires/Provides,
                            the %install+%files shim swap) — anchored on stable spec text only
  wslg-release              the "N" in ".wslgN"; bump when the C++ patch changes without an
                            upstream version bump (see "Editing the kwin C++ patch" below)
  wslg-changelog-entry.txt  our %changelog stanza, inserted by anchor (not diffed) — update its
                            text alongside wslg-release
  wslg-kwin-rail.patch      the C++ patch (Patch1000) — GENERATED from src/ by scripts/gen-patch.sh
  src/                      the 6 patched wayland-backend files — the authoritative source
  kwin_wayland_wrapper.shim  Source1000
packaging/kde-plasma-wslg/       noarch: launcher + control cmd + user unit + tmpfiles + kscreenlockerrc
packaging/kde-plasma-wslg-repo/  noarch: the .repo file + RPM-GPG-KEY
scripts/                    build-srpm, build-rpms, gen-patch, check-specs, rebase-kwin, make-repo
```

The kwin **binary** RPM version comes from EPEL (`Version:`/`Release:` in `dist-git/kwin.spec`).
`scripts/lib.sh`'s `rendered_spec()` appends `.wslgN` to whatever `Release:` EPEL currently has
and inserts `wslg-changelog-entry.txt` right after `%changelog`, both by anchoring on stable,
literal spec text (`^Release:`, `^%changelog$`) rather than diffing — so a routine upstream
Release/changelog bump (which happens on nearly every EPEL rebuild) can never conflict with
either. `kwin.spec.patch` itself only carries the three structural additions (new
`Patch1000`/`Source1000`, the `Requires:`/`Provides:` lines, the `%install`+`%files` shim swap),
each anchored on spec text that's essentially never touched by a routine EPEL update — if
*those* ever fail to apply, that's EPEL restructuring the spec and genuinely wants a look.

The **repo semver** (`version.txt`, the two noarch specs' `%global baseversion`, `CHANGELOG.md`)
is owned by **release-please** — never edit those by hand.

## Editing the kwin C++ patch

1. Edit the real files under `packaging/kwin/src/`.
2. `make patch` (== `scripts/gen-patch.sh`) — regenerates `wslg-kwin-rail.patch` against the
   exact upstream tarball named by the submodule's `sources` file.
3. Bump the number in `packaging/kwin/wslg-release` and add a dated stanza to
   `packaging/kwin/wslg-changelog-entry.txt` describing the change.
4. `scripts/build-rpms.sh kwin` on an EL10 host/container to confirm it builds.
5. Commit as `fix: …` (patch RPMs) — CI rebuilds; cut a release to publish.

`make check` (CI runs it) fails if `wslg-kwin-rail.patch` is stale vs `src/`.

## Rebasing kwin onto a new EPEL release

Mostly automated — see "Automated kwin tracking" below. By hand:

```bash
scripts/rebase-kwin.sh epel10.3      # or a bare sha, or no arg for the tracked branch tip
```

It moves the submodule, verifies `kwin.spec.patch`'s three structural hunks still apply
(`--fuzz=0`; a fuzzy-but-successful apply is a warning to tighten the anchors, not a hard
failure), and regenerates `wslg-kwin-rail.patch` against the new tarball. If the overlay
conflicts outright, it stops and tells you to fix `packaging/kwin/kwin.spec.patch` by hand.
If `wslg-kwin-rail.patch`'s *content* actually changed (not just a no-op regeneration — the
script diffs before/after), it tells you to also bump `wslg-release` +
`wslg-changelog-entry.txt`, since that means the C++ patch needed adjusting for the new
upstream code, not just a version bump.

Then: `scripts/build-rpms.sh kwin` in a container, commit as `fix: rebase kwin onto <version>`.

## Automated kwin tracking

Two independent watchers, because they answer different questions:

**"Did EPEL rebuild kwin on the branch we already track?"** — Dependabot's `gitsubmodule`
ecosystem (`.github/dependabot.yml`) checks weekly and opens a PR bumping
`packaging/kwin/dist-git` to the tracked branch's tip. It can only move the *pointer* — it
can't run our scripts — so `kwin-dependabot-rebase.yml` finishes the job: triggered by
`pull_request_target` (a plain `pull_request` trigger gets a read-only token and no repo
secrets for a Dependabot-authored PR, by GitHub design — see the comment in that workflow),
gated to `github.actor == 'dependabot[bot]'`, it checks out the PR head, regenerates
`wslg-kwin-rail.patch`, confirms the overlay still applies, builds kwin, and — only if all
of that succeeds — pushes a commit onto the PR's own branch. **If the PR's checks stay red
instead**, that's the signal something needs a human: usually `kwin.spec.patch` needs a
hand fix (see above), occasionally the C++ patch itself needs adjusting for an upstream
code change (`packaging/kwin/src/*`, same as any manual rebase). Nothing pushes back if
the build fails — the Dependabot PR is left as-is for you to finish or close.

**"Is a new RHEL 10 *minor* release out?"** — a distinct, much rarer event (per-point-release,
not per-rebuild) that Dependabot has no ecosystem for, so `kwin-rhel-minor-watch.yml` runs on
a Monday cron (+ `workflow_dispatch`). It compares the tracked `epel10.N` branch against RHEL
10's latest published minor per [endoflife.date](https://endoflife.date/api/rhel.json) — the
only open, subscription-free signal for this; there's no public RHEL-only API for it, and
`epel10.N` branches can and do appear on the kwin dist-git *before* the matching RHEL point
release is actually GA (confirmed: `epel10.3` already exists while RHEL 10's latest GA is
still 10.2). So the workflow only acts once **both** conditions hold — RHEL 10.N is the
*latest GA* minor **and** `epel10.N` exists — and always moves to that specific `epel10.N`
branch via `scripts/rebase-kwin.sh`, **never** the rolling `epel10` branch (which tracks
CentOS Stream ahead of RHEL's actual release and would risk kwin/KF6/Qt version skew against
what RHEL 10.N itself ships). If RHEL has moved but the branch doesn't exist yet, it opens
(and keeps open) a tracking issue instead of guessing; once the branch appears, the next
weekly run closes that issue and opens the real rebase PR, which still goes through the
normal `build.yml` PR check like any other change.

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
