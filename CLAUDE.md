# CLAUDE.md

Instructions for Claude Code (or any AI coding agent) working in this repository.

## Git workflow — never commit directly to `main`

`main` is protected and `v1.0.0` has shipped. **Do not commit or push directly to `main`.**
There is no standing exception — a change only skips this if the user explicitly says so
for that specific change, in that moment; a past exception doesn't carry forward.

For every change, however small (including docs, CI config, one-line fixes):

1. Branch off `main`: `git switch -c <descriptive-name> origin/main`.
2. Commit there, following the Conventional Commits format described in `CONTRIBUTING.md`.
3. Push the branch and open a PR into `main`. Let the `Lint` and `Build` checks actually
   run against it — that's the point of the branch — and fix anything they catch before
   it merges.
4. If `main` gains commits while the branch is still open, **rebase onto `main`**
   (`git fetch origin && git rebase origin/main`) rather than merging `main` into the
   branch, so history stays linear and conflicts get resolved once, early, instead of
   compounding in a merge commit later.

This holds regardless of how the work was requested — "commit this," "push it," "fix the
CI failure" all mean "on a branch, via a PR," not "on `main`."
