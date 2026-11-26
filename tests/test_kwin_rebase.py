"""Offline KWin rebase regression tests.

Run from the repository root: python3 -B -m unittest discover -s tests -p test_kwin_rebase.py
Requires Bash, Git, and the usual Linux build utilities (patch, tar, coreutils).
"""

import hashlib
import io
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile
import textwrap
import unittest


ROOT = Path(__file__).resolve().parents[1]
UPSTREAM_SOURCE = "src/backends/wayland"
OLD = "6.7.4"
NEW = "6.7.5"
BASE = "local=base\ncontext 1\ncontext 2\ncontext 3\nupstream=base\n"
OURS = BASE.replace("local=base", "local=wslg")
THEIRS = BASE.replace("upstream=base", "upstream=new")
MERGED = OURS.replace("upstream=base", "upstream=new")


class SandboxTest(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory(prefix="kwin-rebase-")
        self.addCleanup(tmp.cleanup)
        self.sandbox = Path(tmp.name)
        self.repo = self.sandbox / "repo"
        self.repo.mkdir()
        self.bin = self.sandbox / "bin"
        self.bin.mkdir()
        self.env = {
            "PATH": f"{self.bin}:{os.environ['PATH']}",
            "HOME": tmp.name,
            "LC_ALL": "C",
            "GIT_CONFIG_NOSYSTEM": "1",
            "GIT_CONFIG_GLOBAL": os.devnull,
            "GIT_ALLOW_PROTOCOL": "file",
            "GIT_TERMINAL_PROMPT": "0",
        }
        self.calls = self.sandbox / "calls"
        self.env["CALLS"] = str(self.calls)

    def run_cmd(self, *args, cwd=None, check=True):
        result = subprocess.run(
            args, cwd=cwd or self.repo, env=self.env, stdin=subprocess.DEVNULL,
            capture_output=True, text=True, timeout=5,
        )
        if check:
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return result

    def stub(self, path, body):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("#!/bin/bash\nset -euo pipefail\n" + textwrap.dedent(body))
        path.chmod(0o755)


class OverlayTests(SandboxTest):
    def setUp(self):
        super().setUp()
        scripts = self.repo / "scripts"
        scripts.mkdir()
        for name in ("merge-overlay.sh", "rebase-kwin.sh", "lib.sh", "gen-patch.sh"):
            shutil.copy2(ROOT / "scripts" / name, scripts / name)
        self.kwin = self.repo / "packaging/kwin"
        self.src = self.kwin / "src"
        self.src.mkdir(parents=True)
        self.distgit = self.kwin / "dist-git"
        self.git("init", "-q", "-b", "old", str(self.distgit), cwd=self.repo)
        self.tarballs = self.sandbox / "tarballs"
        self.tarballs.mkdir()
        self.env["TARBALLS"] = str(self.tarballs)
        self.stub(self.bin / "curl", """\
            printf '%s\\n' "${!#}" >> "$CALLS"
            while [[ "$1" != -o ]]; do shift; done
            url="${!#}"
            cp "$TARBALLS/${url##*/}" "$2"
        """)
        self.files = {"a.cpp": OURS, "z.h": OURS}
        for name, contents in self.files.items():
            (self.src / name).write_text(contents)
        self.old = self.upstream(OLD, dict.fromkeys(self.files, BASE))

    def git(self, *args, cwd=None):
        return self.run_cmd("git", *args, cwd=cwd or self.distgit).stdout.strip()

    def upstream(self, version, files, *, release="1"):
        name = f"kwin-{version}.tar.xz"
        archive = self.tarballs / name
        if files is not None:
            with tarfile.open(archive, "w:xz") as tar:
                for filename, contents in files.items():
                    content = contents.encode()
                    info = tarfile.TarInfo(f"kwin-{version}/{UPSTREAM_SOURCE}/{filename}")
                    info.size = len(content)
                    tar.addfile(info, io.BytesIO(content))
        checksum = hashlib.sha512(archive.read_bytes()).hexdigest()
        (self.distgit / "sources").write_text(f"SHA512 ({name}) = {checksum}\n")
        (self.distgit / "kwin.spec").write_text(
            f"Name: kwin\nVersion: {version}\nRelease: {release}\nSummary: fixture\n"
        )
        self.git("add", "kwin.spec", "sources")
        self.git("-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid",
                 "commit", "-qm", f"KWin {version}")
        return self.git("rev-parse", "HEAD")

    def target(self, files=None):
        self.git("switch", "-qc", "target")
        new = self.upstream(NEW, dict.fromkeys(self.files, THEIRS) if files is None else files)
        self.git("switch", "-q", "old")
        return new

    def overlay(self):
        return {path.name: path.read_text() for path in self.src.iterdir()}

    def merge(self, new, *, check=True):
        return self.run_cmd("scripts/merge-overlay.sh", self.old, new, check=check)

    def assert_rollback(self, result, diagnostic):
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(diagnostic, result.stderr)
        self.assertEqual(self.git("rev-parse", "HEAD"), self.old)
        self.assertEqual(self.overlay(), self.files)

    def test_preserves_local_and_upstream_changes(self):
        new = self.target()
        self.merge(new)
        self.assertEqual(self.overlay(), dict.fromkeys(self.files, MERGED))
        self.assertEqual(self.git("rev-parse", "HEAD"), new)

    def test_conflict_keeps_markers_and_installs_other_merges(self):
        theirs = THEIRS.replace("local=base", "local=upstream")
        new = self.target({"a.cpp": THEIRS, "z.h": theirs})
        result = self.merge(new, check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("conflict:", result.stderr)
        self.assertIn("z.h", result.stderr)
        self.assertIn("then run scripts/gen-patch.sh", result.stderr)
        self.assertEqual(self.git("rev-parse", "HEAD"), new)
        self.assertEqual(self.overlay()["a.cpp"], MERGED)
        marked = self.overlay()["z.h"]
        self.assertIn("<<<<<<< ours", marked)
        self.assertIn("\nlocal=wslg\n=======\nlocal=upstream\n>>>>>>> kwin-", marked)
        self.assertIn("upstream=new", marked)

    def test_same_version_advances_ref_without_merging(self):
        self.git("switch", "-qc", "target")
        new = self.upstream(OLD, None, release="2")
        self.git("switch", "-q", "old")
        self.merge(new)
        self.assertEqual(self.overlay(), self.files)
        self.assertEqual(self.git("rev-parse", "HEAD"), new)
        self.assertEqual(len(self.calls.read_text().splitlines()), 1)

    def test_missing_upstream_counterpart_cannot_partially_merge(self):
        new = self.target({"a.cpp": THEIRS})
        self.assert_rollback(self.merge(new, check=False), f"z.h missing from kwin-{NEW}")

    def test_failed_download_from_new_ref_restores_old_ref(self):
        new = self.target()
        self.git("switch", "-q", "target")  # Dependabot starts at the new ref.
        (self.tarballs / f"kwin-{NEW}.tar.xz").unlink()
        self.assert_rollback(self.merge(new, check=False), f"could not download kwin-{NEW}")

    def test_fatal_merge_error_leaves_earlier_files_untouched(self):
        new = self.target()
        self.env["REAL_GIT"] = shutil.which("git")
        self.stub(self.bin / "git", """\
            if [[ "$1" == merge-file && "${!#}" == */z.h ]]; then
                exit 255
            fi
            exec "$REAL_GIT" "$@"
        """)
        self.assert_rollback(self.merge(new, check=False), "status 255")

    def test_partial_install_restores_originals_and_allows_retry(self):
        new = self.target()
        self.env["REAL_CP"] = shutil.which("cp")
        self.stub(self.bin / "cp", """\
            if [[ "$1" == */merged/* && "${!#}" == */kwin/src/ ]]; then
                "$REAL_CP" "$1" "${!#}"
                exit 1
            fi
            exec "$REAL_CP" "$@"
        """)
        original = self.src / "a.cpp"
        original.chmod(0o640)
        original_stat = original.stat()
        self.assert_rollback(self.merge(new, check=False), "originals restored")
        self.assertEqual(original.stat().st_mode, original_stat.st_mode)
        self.assertEqual(original.stat().st_mtime_ns, original_stat.st_mtime_ns)
        (self.bin / "cp").unlink()
        self.merge(new)
        self.assertEqual(self.overlay(), dict.fromkeys(self.files, MERGED))
        self.assertEqual(self.git("rev-parse", "HEAD"), new)

    def prepare_rebase(self):
        self.git("remote", "add", "origin", ".")
        self.git("config", "-f", str(self.repo / ".gitmodules"),
                 "submodule.packaging/kwin/dist-git.branch", "target")
        (self.kwin / "kwin.spec.patch").write_text(
            "--- a/kwin.spec\n+++ b/kwin.spec\n@@ -4 +4 @@\n-Summary: fixture\n+Summary: overlay\n"
        )
        self.patch = self.kwin / "wslg-kwin-rail.patch"
        self.patch.write_text("original patch\n")

    def test_tracked_branch_rebase_generates_patch_from_merged_sources(self):
        new = self.target()
        self.prepare_rebase()
        self.run_cmd("scripts/rebase-kwin.sh")
        self.assertEqual(self.git("rev-parse", "HEAD"), new)
        self.assertEqual(self.overlay(), dict.fromkeys(self.files, MERGED))
        changes = [
            line for line in self.patch.read_text().splitlines()
            if line.startswith(("+", "-")) and not line.startswith(("+++", "---"))
        ]
        self.assertEqual(changes, ["-local=base", "+local=wslg"] * len(self.files))

    def test_explicit_sha_rebase_does_not_generate_patch_on_conflict(self):
        new = self.target({"a.cpp": BASE.replace("local=base", "local=upstream"), "z.h": THEIRS})
        self.prepare_rebase()
        result = self.run_cmd("scripts/rebase-kwin.sh", new, check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("conflict:", result.stderr)
        self.assertEqual(self.git("rev-parse", "HEAD"), new)
        self.assertEqual(self.patch.read_text(), "original patch\n")
        self.assertEqual(self.overlay()["z.h"], MERGED)


class WorkflowTests(SandboxTest):
    def workflow_step(self, workflow, step):
        # These steps use literal run blocks. Read the checked-in shell rather
        # than copying its logic or requiring a YAML dependency for this suite.
        lines = iter((ROOT / ".github/workflows" / f"{workflow}.yml").read_text().splitlines())
        marker = f"      - name: {step}"
        for line in lines:
            if line == marker:
                break
        else:
            self.fail(f"Step not found: {marker}")
        for line in lines:
            if line == "        run: |":
                break
            self.assertFalse(line.startswith("      - name:"), f"No run block: {marker}")
        else:
            self.fail(f"No run block: {marker}")
        script = []
        for line in lines:
            if line and not line.startswith("          "):
                break
            script.append(line[10:])
        self.assertTrue(script, f"Empty run block: {marker}")
        return self.run_cmd("bash", "-e", "-c", "\n".join(script))

    def test_dependabot_merges_from_base_gitlink_to_head_gitlink(self):
        self.env.update(BASE_SHA="pr-base", HEAD_SHA="pr-head")
        self.stub(self.bin / "git", """\
            case "$*" in
                'config --global --add safe.directory *') ;;
                'fetch --depth=1 origin pr-base') echo fetch-base >> "$CALLS" ;;
                'rev-parse pr-base:packaging/kwin/dist-git') echo old-distgit ;;
                'rev-parse pr-head:packaging/kwin/dist-git') echo new-distgit ;;
                '-C packaging/kwin/dist-git fetch --unshallow --tags origin '*) exit 1 ;;
                '-C packaging/kwin/dist-git fetch --tags origin '*) echo fetch-submodule >> "$CALLS" ;;
                *) exit 99 ;;
            esac
        """)
        self.stub(self.repo / "scripts/merge-overlay.sh", 'echo "merge $*" >> "$CALLS"\n')
        self.workflow_step(
            "kwin-dependabot-rebase", "3-way merge the overlay sources onto the new kwin tarball",
        )
        self.assertEqual(
            self.calls.read_text().splitlines(),
            ["fetch-base", "fetch-submodule", "merge old-distgit new-distgit"],
        )

    def test_dependabot_regenerates_if_patch_or_overlay_sources_changed(self):
        output = self.sandbox / "github-output"
        self.env["GITHUB_OUTPUT"] = str(output)
        self.stub(self.bin / "git", """\
            [[ "$*" == "status --porcelain -- packaging/kwin/src" ]]
            printf '%s' "$OVERLAY_STATUS"
        """)
        self.stub(self.repo / "scripts/gen-patch.sh", """\
            if [[ "${1:-}" == --check ]]; then
                exit "$PATCH_STALE"
            fi
            echo regenerate >> "$CALLS"
        """)
        self.stub(self.repo / "scripts/check-specs.sh", 'echo check-specs >> "$CALLS"\n')
        for stale, status, changed in (
            ("0", "", False),
            ("0", " M packaging/kwin/src/a.cpp", True),
            ("1", "", True),
        ):
            with self.subTest(stale=stale, status=status):
                self.env.update(PATCH_STALE=stale, OVERLAY_STATUS=status)
                self.calls.write_text("")
                output.write_text("")
                self.workflow_step(
                    "kwin-dependabot-rebase", "Regenerate wslg-kwin-rail.patch and verify the spec overlay",
                )
                expected = "true" if changed else "false"
                self.assertEqual(output.read_text(), f"changed={expected}\n")
                self.assertEqual(
                    self.calls.read_text().splitlines(),
                    ["regenerate", "check-specs"] if changed else ["check-specs"],
                )

    def test_rhel_watch_resumes_existing_branch_or_creates_a_new_one(self):
        self.env.update(NEW_BRANCH="epel10.3", NEW_MINOR="3")
        self.stub(self.bin / "git", """\
            case "$1" in
                config) ;;
                ls-remote) exit "$BRANCH_STATUS" ;;
                commit) echo commit >> "$CALLS" ;;
                switch|add|push) echo "$*" >> "$CALLS" ;;
                *) exit 99 ;;
            esac
        """)
        self.stub(self.bin / "gh", """\
            case "$1 $2" in
                'pr list') printf '%s' "$OPEN_PR" ;;
                'pr create') echo "$*" >> "$CALLS" ;;
                'issue list') ;;
                *) exit 99 ;;
            esac
        """)
        self.stub(self.repo / "scripts/rebase-kwin.sh", 'echo "rebase $*" >> "$CALLS"\n')
        for branch_status, open_pr in (("0", "8"), ("0", ""), ("2", "")):
            with self.subTest(branch_status=branch_status, open_pr=open_pr):
                self.env.update(BRANCH_STATUS=branch_status, OPEN_PR=open_pr)
                self.calls.write_text("")
                self.workflow_step(
                    "kwin-rhel-minor-watch", "EPEL has branched — move the submodule and open a PR",
                )
                calls = self.calls.read_text().splitlines()
                if open_pr:
                    self.assertEqual(calls, [])
                    continue
                self.assertTrue(calls[-1].startswith("pr create --base main --head rhel-10-3 "))
                if branch_status == "0":
                    self.assertEqual(len(calls), 1)
                else:
                    self.assertEqual(calls[:2], ["switch -c rhel-10-3", "rebase epel10.3"])
                    self.assertEqual(
                        calls[2].split(),
                        ["add", ".gitmodules", "packaging/kwin/dist-git",
                         "packaging/kwin/src", "packaging/kwin/wslg-kwin-rail.patch"],
                    )
                    self.assertEqual(calls[3:-1], ["commit", "push origin rhel-10-3"])


if __name__ == "__main__":
    unittest.main()
