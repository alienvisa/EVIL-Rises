"""Stage and publish a single release across GitHub and CurseForge."""

import json
import os
from pathlib import Path
import subprocess
import tempfile
from urllib.parse import urlencode
from urllib.request import Request, urlopen


ATTEMPT = "curseforge-attempt.json"
RECEIPT = "curseforge-upload.json"
METADATA = "release.json"
CURSEFORGE_URL = "https://wow.curseforge.com"
FOREVER_VERSION_TYPE = 88568


def write_json(path, value):
    temporary = path.with_suffix(".tmp")
    temporary.write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")
    temporary.replace(path)
    return path


def read_json(path):
    return json.loads(path.read_text(encoding="utf-8"))


class GitHub:
    def __init__(self, repository):
        self.repository = repository

    def command(self, *args, binary=False, payload=None):
        result = subprocess.run(
            ["gh", *args], check=True, stdout=subprocess.PIPE,
            input=json.dumps(payload).encode("utf-8") if payload is not None else None,
            timeout=120,
        )
        return result.stdout if binary else result.stdout.decode("utf-8")

    def releases(self):
        pages = json.loads(self.command(
            "api", f"repos/{self.repository}/releases", "--paginate", "--slurp",
        ))
        return {entry["tag_name"]: entry for page in pages for entry in page}

    def reserve(self, tag, sha):
        self.command(
            "api", f"repos/{self.repository}/git/refs",
            "-f", f"ref=refs/tags/{tag}", "-f", f"sha={sha}",
        )

    def create_draft(self, tag, source, changelog):
        return json.loads(self.command(
            "api", f"repos/{self.repository}/releases", "--method", "POST", "--input", "-",
            payload={
                "tag_name": tag,
                "target_commitish": source,
                "name": f"EVIL Rises {tag}",
                "body": changelog,
                "draft": True,
            },
        ))

    def release(self, release_id):
        return GitHubRelease(self, json.loads(self.command(
            "api", f"repos/{self.repository}/releases/{release_id}",
        )))


class GitHubRelease:
    def __init__(self, github, entry):
        if entry["prerelease"]:
            raise ValueError(f"{entry['tag_name']} is a prerelease")
        self.github = github
        self.id = entry["id"]
        self.tag = entry["tag_name"]
        self.is_draft = entry["draft"]
        self.assets = {asset["name"]: asset for asset in entry["assets"]}

    def download(self, name, directory):
        asset = self.assets.get(name)
        if not asset or asset["state"] != "uploaded":
            return None
        path = directory / name
        path.write_bytes(self.github.command(
            "api", f"repos/{self.github.repository}/releases/assets/{asset['id']}",
            "--header", "Accept: application/octet-stream", binary=True,
        ))
        return path

    def upload(self, path):
        if not self.is_draft:
            raise ValueError(f"Cannot add assets to the published release {self.tag}")
        asset = self.assets.get(path.name)
        if asset and asset["state"] == "starter":
            self.delete_asset(asset)
        endpoint = f"https://uploads.github.com/repos/{self.github.repository}/releases/{self.id}/assets"
        self.assets[path.name] = json.loads(self.github.command(
            "api", f"{endpoint}?{urlencode({'name': path.name})}",
            "--method", "POST", "--header", "Content-Type: application/octet-stream",
            "--input", str(path),
        ))

    def delete_asset(self, asset):
        self.github.command(
            "api", "--method", "DELETE",
            f"repos/{self.github.repository}/releases/assets/{asset['id']}",
        )

    def publish(self):
        if self.is_draft:
            if ATTEMPT in self.assets:
                self.delete_asset(self.assets[ATTEMPT])
            self.github.command(
                "api", f"repos/{self.github.repository}/releases/{self.id}",
                "--method", "PATCH", "-F", "draft=false",
            )


class CurseForge:
    def __init__(self, project_id, interface, token, base_url=CURSEFORGE_URL):
        self.project_id = project_id
        self.interface = interface
        self.token = token
        self.base_url = base_url

    def metadata(self, archive, changelog):
        if not self.token:
            raise ValueError("Set CF_API_TOKEN before publishing to CurseForge")
        major, remainder = divmod(self.interface, 10000)
        minor, patch = divmod(remainder, 100)
        version = f"{major}.{minor}.{patch}"
        request = Request(
            f"{self.base_url}/api/game/wow/versions", headers={"x-api-token": self.token},
        )
        with urlopen(request, timeout=30) as response:
            versions = json.load(response)
        if not isinstance(versions, list):
            raise ValueError("Unexpected response from the CurseForge game versions API")
        matches = [
            entry["id"] for entry in versions
            if entry["name"] == version and entry["gameVersionTypeID"] == FOREVER_VERSION_TYPE
        ]
        if len(matches) != 1 or type(matches[0]) is not int or matches[0] < 1:
            raise ValueError(f"CurseForge must list exactly one WoW Forever version for {version}")
        return {
            "displayName": archive.stem,
            "gameVersions": matches,
            "releaseType": "release",
            "changelog": changelog,
            "changelogType": "markdown",
        }

    def upload(self, archive, metadata):
        with tempfile.TemporaryDirectory() as temp:
            payload = write_json(Path(temp) / "metadata.json", metadata)
            response = subprocess.run(
                ["curl", "--disable", "--fail", "--silent", "--show-error",
                 "--connect-timeout", "15", "--max-time", "120", "--header", "@-",
                 "--form", f"metadata=<{payload}", "--form", f"file=@{archive}",
                 f"{self.base_url}/api/projects/{self.project_id}/upload-file"],
                input=f"x-api-token: {self.token}\n", capture_output=True,
                text=True, encoding="utf-8", timeout=125,
                env={key: os.environ[key] for key in ("PATH", "HOME", "SystemRoot") if key in os.environ},
            )
        if response.returncode:
            raise ValueError(
                f"CurseForge upload did not confirm success (curl exit {response.returncode}). "
                "Check the upload history."
            )
        result = json.loads(response.stdout)
        file_id = result.get("id") if isinstance(result, dict) else None
        if type(file_id) is not int or file_id < 1:
            raise ValueError("CurseForge response had no file ID. Check the upload history.")
        return file_id


def verify_receipt(path, identity):
    receipt = read_json(path)
    file_id = receipt.get("id") if isinstance(receipt, dict) else None
    if type(file_id) is not int or file_id < 1 or receipt != {**identity, "id": file_id}:
        raise ValueError("The CurseForge receipt does not match the staged release")
    return receipt


def publish_curseforge(release, curseforge, archive, identity, changelog):
    directory = archive.parent
    receipt = release.download(RECEIPT, directory)
    if receipt:
        return verify_receipt(receipt, identity)
    if not release.is_draft:
        raise ValueError("A published GitHub release is missing the CurseForge receipt")
    if release.download(ATTEMPT, directory):
        raise ValueError("An earlier CurseForge upload is unconfirmed. Check the upload history.")
    metadata = curseforge.metadata(archive, changelog)
    release.upload(write_json(directory / ATTEMPT, identity))
    file_id = curseforge.upload(archive, metadata)
    receipt = {**identity, "id": file_id}
    release.upload(write_json(directory / RECEIPT, receipt))
    return receipt


def publish_github(release, archive, identity):
    receipt = release.download(RECEIPT, archive.parent)
    if not receipt:
        raise ValueError("The CurseForge receipt is required before publishing to GitHub")
    verified = verify_receipt(receipt, identity)
    release.publish()
    return verified
