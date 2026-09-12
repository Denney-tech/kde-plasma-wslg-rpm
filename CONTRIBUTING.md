# Contributing

## Commit messages — Conventional Commits

Releases and the changelog are generated from commit messages, so they must follow
[Conventional Commits](https://www.conventionalcommits.org/):

| prefix | effect | use for |
|---|---|---|
| `fix:` | patch bump | bug fixes, kwin patch tweaks, kwin rebases |
| `feat:` | minor bump | new packaged files, new options, new scripts |
| `feat!:` / `BREAKING CHANGE:` in body | major bump | anything that changes install/upgrade behaviour |
| `docs:` `chore:` `ci:` `build:` `test:` `refactor:` | no release | everything else |

Scopes are optional but nice: `fix(kwin): …`, `feat(repo): …`, `docs(gpu): …`.

The kwin **RPM** `Release` (`N%{?dist}.wslgM`) tracks EPEL's `N` automatically; the `M` is
`packaging/kwin/wslg-release`, bumped by hand only when the C++ patch itself changes — it is
*not* tied to the repo semver. release-please owns `version.txt`, the two noarch specs, and
`CHANGELOG.md`;
don't touch those in a normal PR.

## Setup

```bash
pip install pre-commit          # or: pipx install pre-commit
pre-commit install
git submodule update --init --recursive
```

`shellcheck`, `shfmt`, and `actionlint` are fetched by pre-commit automatically.
Also install `shellcheck` on your `PATH` (`dnf install ShellCheck`, `brew install
shellcheck`, …) — `actionlint` only runs its embedded shell-script checks when it can
find `shellcheck`, and CI does, so a local run without it will miss workflow-script
findings.

## Before you push

```bash
make check          # patch is in sync with src/, all specs parse
pre-commit run --all-files
```

Build the RPMs the way CI does — on EL10, or in a container:

```bash
podman run --rm -it -v "$PWD":/src -w /src quay.io/rockylinux/rockylinux:10 bash
  # inside:
  dnf -y install epel-release && dnf config-manager --set-enabled crb
  dnf -y install rpm-build rpmdevtools 'dnf-command(builddep)' createrepo_c git-core patch diffutils
  git config --global --add safe.directory /src
  make rpms
```

## Changing the kwin C++ patch

Edit `packaging/kwin/src/*` (never `wslg-kwin-rail.patch` directly), then `make patch`.
See [`MAINTAINING.md`](MAINTAINING.md) for the full rebase/patch workflow.

## PRs

CI must be green (`lint`, `build`). One logical change per PR. If you change packaged
behaviour, update `README.md` and the relevant `docs/` page in the same PR.
