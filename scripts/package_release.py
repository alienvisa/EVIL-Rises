"""Build and validate the WoW Forever ZIP using the unmodified BigWigs packager."""

from dataclasses import dataclass
import hashlib
import os
from pathlib import Path
import re
import subprocess
import tempfile
from urllib.request import urlopen
from zipfile import ZipFile


PACKAGER_URL = (
    "https://raw.githubusercontent.com/BigWigsMods/packager/"
    "01e8631a69c69d7654c788d152630d5fed9e3812/release.sh"
)
TOC = Path("EVILRises/EVILRises.toc")


@dataclass(frozen=True)
class Package:
    archive: Path
    interface: int
    changelog: str
    sha256: str

    def metadata(self, tag):
        return {"releases": [{
            "name": "EVILRises",
            "version": tag,
            "filename": self.archive.name,
            "nolib": False,
            "metadata": [{"flavor": "forever", "interface": self.interface}],
        }]}


def validate_archive(archive, tag):
    with ZipFile(archive) as package:
        names = set(package.namelist())
        if package.testzip() or any(
            not name.startswith("EVILRises/") or ".." in name.split("/") for name in names
        ):
            raise ValueError("The ZIP must contain one intact EVILRises addon folder")
        manifest = package.read(TOC.as_posix()).decode("utf-8").splitlines()
        manifest_text = "\n".join(manifest)
        if re.findall(r"^## Version: (.+)$", manifest_text, re.MULTILINE) != [tag[1:]]:
            raise ValueError(f"The packaged manifest must have version {tag[1:]}")
        interfaces = re.findall(r"^## Interface: (16[0-9]{3})$", manifest_text, re.MULTILINE)
        if len(interfaces) != 1:
            raise ValueError("The packaged manifest must declare one WoW Forever interface")
        for line in manifest:
            entry = line.strip().replace("\\", "/")
            if entry and not entry.startswith("#") and f"EVILRises/{entry}" not in names:
                raise ValueError(f"Missing packaged file referenced by the manifest: {entry}")
        changelogs = [name for name in names if name.startswith("EVILRises/CHANGELOG")]
        if len(changelogs) != 1:
            raise ValueError("Expected one release changelog in the ZIP")
        changelog = package.read(changelogs[0]).decode("utf-8")
    with archive.open("rb") as stream:
        checksum = hashlib.file_digest(stream, "sha256").hexdigest()
    return Package(archive, int(interfaces[0]), changelog, checksum)


def stamp_toc(original, tag):
    stamped, replacements = re.subn(
        rb"(?m)^## Version: [0-9]+\.[0-9]+\.[0-9]+(?=\r?$)",
        f"## Version: {tag[1:]}".encode("ascii"),
        original,
    )
    if replacements != 1:
        raise ValueError("Expected one numeric version in EVILRises.toc")
    return stamped


def build_archive(root, tag, directory):
    toc = root / TOC
    original = toc.read_bytes()
    stamped = stamp_toc(original, tag)
    directory = directory.resolve()
    directory.mkdir(parents=True, exist_ok=True)
    archive = directory / f"EVILRises-{tag}.zip"
    with tempfile.TemporaryDirectory() as temp:
        packager = Path(temp) / "release.sh"
        with urlopen(PACKAGER_URL, timeout=30) as response:
            packager.write_bytes(response.read())
        environment = {key: os.environ[key] for key in ("PATH", "HOME") if key in os.environ}
        try:
            toc.write_bytes(stamped)
            result = subprocess.run(
                ["bash", str(packager), "-d", "-g", "forever", "-r", str(directory),
                 "-n", "EVILRises-{project-version}"],
                cwd=root, env=environment, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                text=True, encoding="utf-8", errors="replace", timeout=120,
            )
            if result.returncode:
                raise ValueError(f"BigWigs packaging failed ({result.returncode})\n{result.stdout[-4000:]}")
        finally:
            toc.write_bytes(original)
    return validate_archive(archive, tag)
