"""Validate commit titles and release EVIL Rises for WoW Forever."""

import argparse
from contextlib import suppress
import os
from pathlib import Path
import re
import subprocess
import tempfile
from zipfile import BadZipFile

from scripts.package_release import TOC, build_archive, stamp_toc, validate_archive
from scripts.publish_release import (
    METADATA, RECEIPT, CurseForge, GitHub, GitHubRelease, publish_curseforge, publish_github,
    read_json, write_json,
)


TITLE = re.compile(
    r"(feat|fix|chore|ci|docs|style|refactor|perf|test|build|revert)"
    r"(?:\([^()\r\n]+\))?(!)?: \S[^\r\n]*"
)
GITHUB_MERGE_SUBJECT = re.compile(r"Merge pull request #[1-9][0-9]* from \S+/\S+")
TAG = re.compile(r"v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)")
TOC_SYNC_TITLE = re.compile(r"chore\(release\): sync TOC to (v\S+)(?: \(#[1-9][0-9]*\))?")
LEVELS = ("patch", "minor", "major")
LEGACY_RELEASE = "v0.4.4"
RELEASE_DIRECTORY = Path(".release").resolve()


def release_level(title, body=""):
    match = TITLE.fullmatch(title)
    if not match:
        raise ValueError(f"Expected a Conventional Commit title, got {title!r}")
    if match[2] or re.search(r"^BREAKING[ -]CHANGE: \S", body, re.MULTILINE):
        return "major"
    return "minor" if match[1] == "feat" else "patch"


def bump(tag, level):
    version = list(map(int, TAG.fullmatch(tag).groups()))
    index = 2 - LEVELS.index(level)
    version[index] += 1
    version[index + 1:] = [0] * (2 - index)
    return "v" + ".".join(map(str, version))


def git(*args):
    return subprocess.check_output(["git", *args], text=True, encoding="utf-8").strip()


def stable_tags():
    return [
        tag for tag in git("tag", "--list", "--sort=-version:refname").splitlines()
        if TAG.fullmatch(tag)
    ]


def release_source(tag):
    source = git("rev-parse", f"refs/tags/{tag}^{{commit}}")
    if source not in git("rev-list", "--first-parent", "HEAD").splitlines():
        raise ValueError(f"{tag} is outside HEAD's first-parent history")
    return source


def is_toc_sync(sha, subject, tags):
    match = TOC_SYNC_TITLE.fullmatch(subject)
    if not match or match[1] not in tags:
        return False
    changed = git("diff", "--no-renames", "--name-status", f"{sha}^", sha)
    if changed != f"M\t{TOC.as_posix()}":
        return False
    before = subprocess.check_output(["git", "show", f"{sha}^:{TOC.as_posix()}"])
    after = subprocess.check_output(["git", "show", f"{sha}:{TOC.as_posix()}"])
    with suppress(ValueError):
        return before != after and stamp_toc(before, match[1]) == after
    return False


def next_tag(tags):
    if not tags:
        raise ValueError("Expected an existing stable tag to seed versioning")
    existing = set(tags).intersection(git("tag", "--points-at", "HEAD").splitlines())
    if len(existing) > 1:
        raise ValueError("Multiple stable tags point to HEAD")
    if existing:
        return existing.pop()

    latest = tags[0]
    release_source(latest)
    levels = []
    for sha in git("rev-list", "--first-parent", f"{latest}..HEAD").splitlines():
        parents, subject, body = git("show", "-s", "--format=%P%x00%s%x00%b", sha).split("\0", 2)
        parent_count = len(parents.split())
        if parent_count == 2 and GITHUB_MERGE_SUBJECT.fullmatch(subject):
            # GitHub puts the PR title on the first line of the default merge body.
            subject = body.lstrip().partition("\n")[0]
        elif parent_count != 1:
            raise ValueError(f"{sha[:12]} is not a standard GitHub PR merge. Use squash merging.")
        if is_toc_sync(sha, subject, tags):
            continue
        try:
            levels.append(release_level(subject, body))
        except ValueError as error:
            raise ValueError(
                f"{sha[:12]}: {error}. Preserve the PR title when merging."
            ) from error
    return bump(latest, max(levels, key=LEVELS.index)) if levels else None


def build_at_tag(tag, directory):
    with tempfile.TemporaryDirectory(prefix="evil-rises-release-") as temp:
        checkout = Path(temp) / "source"
        # BigWigs recognizes a standalone .git directory in the packaging checkout.
        git("clone", "--quiet", "--no-checkout", ".", str(checkout))
        git("-C", str(checkout), "remote", "set-url", "origin", git("remote", "get-url", "origin"))
        git("-C", str(checkout), "checkout", "--quiet", "--detach", f"refs/tags/{tag}")
        return build_archive(checkout, tag, directory)


def prepare(github, directory):
    tags = stable_tags()
    if not tags:
        raise ValueError("Expected an existing stable tag to seed versioning")
    latest = tags[0]
    release_source(latest)
    releases = github.releases()
    previous = releases.get(latest)
    if latest == LEGACY_RELEASE and (not previous or previous["draft"]):
        raise ValueError(f"Expected the published baseline release {LEGACY_RELEASE}")
    if previous and previous["prerelease"]:
        raise ValueError(f"{latest} is a prerelease")
    if previous and not previous["draft"] and latest != LEGACY_RELEASE:
        previous_assets = {
            asset["name"] for asset in previous["assets"] if asset["state"] == "uploaded"
        }
        if not {f"EVILRises-{latest}.zip", METADATA, RECEIPT} <= previous_assets:
            raise ValueError(f"Release {latest} is missing published assets")

    tag = latest if not previous or previous["draft"] else next_tag(tags)
    if tag is None:
        return None
    directory.mkdir(parents=True, exist_ok=True)
    entry = releases.get(tag)
    release = GitHubRelease(github, entry) if entry else None
    filename = f"EVILRises-{tag}.zip"
    archive = release.download(filename, directory) if release else None
    if archive:
        package = validate_archive(archive, tag)
    else:
        if release and not release.is_draft:
            raise ValueError(f"The published release {tag} is missing {filename}")
        if release and any(name != filename for name in release.assets):
            raise ValueError(f"The draft {tag} has assets but is missing {filename}")
        if tag not in tags:
            git("tag", tag)
        package = build_at_tag(tag, directory)
        if not release:
            source = release_source(tag)
            if tag not in tags:
                github.reserve(tag, source)
            release = GitHubRelease(github, github.create_draft(tag, source, package.changelog))
        release.upload(package.archive)

    metadata = release.download(METADATA, directory)
    expected = package.metadata(tag)
    if metadata is None:
        release.upload(write_json(directory / METADATA, expected))
    elif read_json(metadata) != expected:
        raise ValueError("release.json does not match the staged ZIP")
    return release


def curseforge_project_id():
    project_id = os.environ.get("CF_PROJECT_ID", "")
    if not re.fullmatch(r"[1-9][0-9]*", project_id):
        raise ValueError("Set CF_PROJECT_ID to the numeric CurseForge project ID")
    return int(project_id)


def publish(github, tag, release_id, directory, target):
    if not TAG.fullmatch(tag) or not re.fullmatch(r"[1-9][0-9]*", release_id):
        raise ValueError("Expected a stable tag and numeric GitHub release ID")
    source = release_source(tag)
    project_id = curseforge_project_id()
    release = github.release(release_id)
    if release.tag != tag:
        raise ValueError(f"GitHub release {release_id} belongs to {release.tag}, expected {tag}")
    archive = release.download(f"EVILRises-{tag}.zip", directory)
    metadata = release.download(METADATA, directory)
    if not archive or not metadata:
        raise ValueError("The draft must have the staged ZIP and release.json")
    package = validate_archive(archive, tag)
    if read_json(metadata) != package.metadata(tag):
        raise ValueError("release.json does not match the staged ZIP")
    identity = {
        "version": tag,
        "sourceCommit": source,
        "filename": archive.name,
        "sha256": package.sha256,
        "releaseType": "release",
        "projectId": project_id,
    }
    if target == "publish-curseforge":
        curseforge = CurseForge(project_id, package.interface, os.environ.get("CF_API_TOKEN"))
        publish_curseforge(release, curseforge, archive, identity, package.changelog)
    else:
        receipt = publish_github(release, archive, identity)
        summary = os.environ.get("GITHUB_STEP_SUMMARY")
        if summary:
            with Path(summary).open("a", encoding="utf-8") as stream:
                stream.write(
                    f"Published [EVIL Rises {tag}](https://github.com/{github.repository}/releases/tag/{tag})"
                    f" and recorded CurseForge file {receipt['id']}.\n"
                    f"ZIP SHA-256: `{package.sha256}`\n"
                )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--title", help="Validate a PR title instead of calculating a tag")
    parser.add_argument("--sync-toc", metavar="TAG", help="Write a published version to the source TOC")
    parser.add_argument("command", nargs="?", choices=("package", "publish-curseforge", "publish-github"))
    args = parser.parse_args()
    try:
        if args.title is not None:
            print(release_level(args.title))
        elif args.sync_toc is not None:
            if not TAG.fullmatch(args.sync_toc):
                raise ValueError("Expected a stable release tag")
            TOC.write_bytes(stamp_toc(TOC.read_bytes(), args.sync_toc))
        elif not args.command:
            tag = next_tag(stable_tags())
            if tag is not None:
                print(tag)
        else:
            github = GitHub(os.environ["GITHUB_REPOSITORY"])
            if args.command == "package":
                curseforge_project_id()
                release = prepare(github, RELEASE_DIRECTORY)
                if release is None:
                    print("No release needed after the TOC version sync.")
                    return
                with Path(os.environ["GITHUB_OUTPUT"]).open("a", encoding="utf-8") as stream:
                    stream.write(f"tag={release.tag}\nrelease_id={release.id}\n")
            else:
                publish(
                    github, os.environ["RELEASE_TAG"], os.environ["RELEASE_ID"],
                    RELEASE_DIRECTORY, args.command,
                )
    except (ValueError, OSError, KeyError, BadZipFile, subprocess.SubprocessError) as error:
        parser.exit(1, f"{error}\n")


if __name__ == "__main__":
    main()
