"""Exercise the real BigWigs build in a temporary checkout."""

from contextlib import chdir
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from zipfile import ZipFile

from scripts.release import build_at_tag


ROOT = Path(__file__).resolve().parents[1]


class PackageTests(unittest.TestCase):
    def test_stable_install_zip_preserves_source(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            for directory in ("EVILRises", "scripts", ".github", "tests"):
                shutil.copytree(ROOT / directory, root / directory)
            for name in (".pkgmeta", ".gitignore", "README.md"):
                shutil.copy2(ROOT / name, root)
            self.git(root, "init", "-q", "-b", "main")
            self.git(root, "remote", "add", "origin", "https://github.com/alienvisa/EVIL-Rises.git")
            self.git(root, "add", ".")
            self.git(root, "-c", "user.name=Package test", "-c", "user.email=test@example.invalid",
                     "commit", "-qm", "fix: package fixture")
            self.git(root, "tag", "v0.4.5")

            (root / "EVILRises/Future.lua").write_text("-- A later commit\n", encoding="utf-8")
            self.git(root, "add", ".")
            self.git(root, "-c", "user.name=Package test", "-c", "user.email=test@example.invalid",
                     "commit", "-qm", "feat: later commit")
            toc = root / "EVILRises/EVILRises.toc"
            original = toc.read_bytes()
            with chdir(root):
                package = build_at_tag("v0.4.5", root / ".release")
            self.assertEqual(package.archive.name, "EVILRises-v0.4.5.zip")
            self.assertEqual(package.interface, 16001)
            self.assertEqual(toc.read_bytes(), original)
            with ZipFile(package.archive) as archive:
                self.assertIn(b"## Version: 0.4.5", archive.read("EVILRises/EVILRises.toc"))
                self.assertNotIn("EVILRises/Future.lua", archive.namelist())
                for name in archive.namelist():
                    self.assertFalse(
                        {".github", "scripts", "tests", "README.md", "AGENTS.md"} & set(name.split("/")),
                        name,
                    )

    def git(self, root, *args):
        subprocess.run(["git", *args], cwd=root, check=True)


if __name__ == "__main__":
    unittest.main()
