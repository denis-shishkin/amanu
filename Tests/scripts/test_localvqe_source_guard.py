import hashlib
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
GUARD = ROOT / "scripts" / "verify-localvqe-source.sh"


def git(repository: Path, *arguments: str, capture: bool = False):
    return subprocess.run(
        ["git", "-C", str(repository), *arguments],
        check=True,
        capture_output=capture,
    )


def commit(repository: Path, message: str) -> None:
    git(repository, "add", ".")
    git(
        repository,
        "-c", "user.name=Audit fixture",
        "-c", "user.email=audit@example.invalid",
        "commit", "--quiet", "-m", message,
    )


def diff_hash(repository: Path, *pathspecs: str) -> str:
    result = git(
        repository, "diff", "--binary", "HEAD", "--", *pathspecs,
        capture=True,
    )
    return hashlib.sha256(result.stdout).hexdigest()


class LocalVQESourceGuardTests(unittest.TestCase):
    def test_only_exact_parent_and_nested_patches_are_accepted(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            source = Path(temporary) / "source"
            ggml = source / "ggml" / "vendor" / "ggml"
            ggml.mkdir(parents=True)

            subprocess.run(["git", "init", "--quiet", str(ggml)], check=True)
            (ggml / "approved.cpp").write_text("upstream\n")
            (ggml / "unrelated.cpp").write_text("upstream\n")
            commit(ggml, "Pinned ggml")
            ggml_revision = git(ggml, "rev-parse", "HEAD", capture=True).stdout.decode().strip()

            subprocess.run(["git", "init", "--quiet", str(source)], check=True)
            git(source, "config", "advice.addEmbeddedRepo", "false")
            (source / "ggml" / "CMakeLists.txt").write_text("upstream\n")
            (source / "LICENSE").write_text("upstream\n")
            commit(source, "Pinned LocalVQE")
            source_revision = git(source, "rev-parse", "HEAD", capture=True).stdout.decode().strip()

            (source / "ggml" / "CMakeLists.txt").write_text("approved macOS patch\n")
            (ggml / "approved.cpp").write_text("approved GRU patch\n")
            parent_hash = diff_hash(source, ".", ":(exclude)ggml/vendor/ggml")
            ggml_hash = diff_hash(ggml, ".")
            arguments = [
                "bash", str(GUARD), str(source), source_revision,
                ggml_revision, parent_hash, ggml_hash,
            ]

            accepted = subprocess.run(arguments, capture_output=True, text=True)
            self.assertEqual(accepted.returncode, 0, accepted.stderr)

            git(ggml, "restore", "approved.cpp")
            unpatched = subprocess.run(
                arguments + ["--allow-unpatched-ggml"],
                capture_output=True, text=True,
            )
            self.assertEqual(unpatched.returncode, 0, unpatched.stderr)
            requires_patch = subprocess.run(arguments, capture_output=True, text=True)
            self.assertNotEqual(requires_patch.returncode, 0)
            (ggml / "approved.cpp").write_text("approved GRU patch\n")

            (source / "LICENSE").write_text("unstaged surprise\n")
            dirty_parent = subprocess.run(arguments, capture_output=True, text=True)
            self.assertNotEqual(dirty_parent.returncode, 0)
            self.assertIn("unexpected tracked changes", dirty_parent.stderr)
            git(source, "restore", "LICENSE")

            (ggml / "unrelated.cpp").write_text("staged surprise\n")
            git(ggml, "add", "unrelated.cpp")
            dirty_nested = subprocess.run(arguments, capture_output=True, text=True)
            self.assertNotEqual(dirty_nested.returncode, 0)
            self.assertIn("unexpected tracked changes", dirty_nested.stderr)


if __name__ == "__main__":
    unittest.main()
