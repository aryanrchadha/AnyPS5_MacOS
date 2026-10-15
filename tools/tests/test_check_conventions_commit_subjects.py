import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

CHECKER = Path(__file__).resolve().parents[1] / "check_conventions.py"


class CommitSubjectTests(unittest.TestCase):
    def check(self, subject):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)

            def git(*args):
                return subprocess.run(
                    ["git", "-c", f"safe.directory={root}", "-c", "user.name=Conventions Test",
                     "-c", "user.email=test@example.com", "-c", "commit.gpgsign=false", *args],
                    cwd=root, capture_output=True, text=True, check=True,
                )

            git("init", "-q")
            (root / "README.md").write_text("readme\n", encoding="utf-8")
            git("add", ".")
            git("commit", "-qm", "docs: add readme")
            (root / "README.md").write_text("readme\nmore\n", encoding="utf-8")
            git("commit", "-qam", subject)
            env = {key: value for key, value in os.environ.items()
                   if key not in ("GITHUB_EVENT_PATH", "GITHUB_STEP_SUMMARY", "GITHUB_ACTIONS")}
            env.update(GIT_CONFIG_COUNT="1", GIT_CONFIG_KEY_0="safe.directory", GIT_CONFIG_VALUE_0=str(root))
            return subprocess.run(
                [sys.executable, "-I", str(CHECKER), "--base", "HEAD~1", "--head", "HEAD"],
                cwd=root, capture_output=True, text=True, env=env, timeout=20,
            )

    def assertAccepted(self, subject):
        result = self.check(subject)
        self.assertNotIn("commit-subject", result.stdout, result.stdout + result.stderr)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def assertRejected(self, subject):
        result = self.check(subject)
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("[commit-subject]", result.stdout)

    def test_conventional_subject_passes(self):
        self.assertAccepted("fix(libc): keep errno across calls")

    def test_git_revert_of_conventional_subject_passes(self):
        self.assertAccepted('Revert "fix(libSceVideoOut): export unknown Onimusha import NID"')

    def test_git_revert_with_pull_request_number_passes(self):
        self.assertAccepted('Revert "test(libSceUserService): cover user event polling" (#3507)')

    def test_git_revert_of_merge_subject_passes(self):
        self.assertAccepted('Revert "Merge pull request #5211 from veosett/codex/recorder-coverage"')

    def test_plain_subject_fails(self):
        self.assertRejected("Fix the build")

    def test_revert_without_quotes_fails(self):
        self.assertRejected("Revert the shader cache change")

    def test_empty_revert_fails(self):
        self.assertRejected('Revert ""')


if __name__ == "__main__":
    unittest.main()
