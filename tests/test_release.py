import os
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import Mock, patch

from scripts.release import bump, prepare, publish, release_level


class ReleaseTests(unittest.TestCase):
    def test_release_levels(self):
        self.assertEqual(release_level('feat(roster): add filters'), 'minor')
        for kind in ('fix', 'chore', 'ci', 'docs'):
            self.assertEqual(release_level(f'{kind}: update addon'), 'patch')
        self.assertEqual(release_level('fix!: change format'), 'major')
        self.assertEqual(release_level('fix: change format', 'BREAKING CHANGE: saved data'), 'major')
        with self.assertRaises(ValueError):
            release_level('Update addon')

    def test_versions_reset_lower_components(self):
        self.assertEqual(bump('v0.4.4', 'patch'), 'v0.4.5')
        self.assertEqual(bump('v0.4.4', 'minor'), 'v0.5.0')
        self.assertEqual(bump('v0.4.4', 'major'), 'v1.0.0')

    def test_tag_allocation_from_main_history(self):
        root = Path(__file__).resolve().parents[1]
        with tempfile.TemporaryDirectory() as repo:
            def git(*args):
                subprocess.run(['git', *args], cwd=repo, check=True, capture_output=True)

            def version():
                return subprocess.check_output(
                    [sys.executable, '-B', '-m', 'scripts.release'], cwd=repo, text=True,
                    env={**os.environ, 'PYTHONPATH': str(root)},
                ).strip()

            git('init')
            git('config', 'user.email', 'test@example.com')
            git('config', 'user.name', 'Release Test')
            git('commit', '--allow-empty', '-m', 'Historical release')
            git('tag', 'v0.4.4')
            git('commit', '--allow-empty', '-m', 'ci: add workflows')
            self.assertEqual(version(), 'v0.4.5')
            base = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=repo, text=True).strip()
            git('switch', '-c', 'feature')
            git('commit', '--allow-empty', '-m', 'Work in progress')
            git('switch', '--detach', base)
            git('merge', '--no-ff', 'feature',
                '-m', 'Merge pull request #1 from alienvisa/CI-pipeline',
                '-m', 'feat: add CI pipeline')
            self.assertEqual(version(), 'v0.5.0')
            git('tag', 'v0.5.0')
            self.assertEqual(version(), 'v0.5.0')
            git('commit', '--allow-empty', '-m', 'Edited squash title')
            with self.assertRaises(subprocess.CalledProcessError) as failure:
                subprocess.run(
                    [sys.executable, '-B', '-m', 'scripts.release'], cwd=repo, text=True,
                    env={**os.environ, 'PYTHONPATH': str(root)}, check=True, capture_output=True,
                )
            self.assertIn('Preserve the PR title when merging', failure.exception.stderr)

    def test_successor_resumes_the_pending_draft_from_its_tag(self):
        github = Mock()
        github.releases.return_value = {'v0.4.5': {
            'id': 42, 'tag_name': 'v0.4.5', 'draft': True, 'prerelease': False, 'assets': [],
        }}
        with tempfile.TemporaryDirectory() as folder:
            directory = Path(folder)
            package = Mock(archive=directory / 'EVILRises-v0.4.5.zip')
            package.metadata.return_value = {'releases': []}
            with (
                patch('scripts.release.stable_tags', return_value=['v0.4.5']),
                patch('scripts.release.next_tag') as next_tag,
                patch('scripts.release.git', side_effect=['tagged-sha', 'head-sha\ntagged-sha']),
                patch('scripts.release.build_at_tag', return_value=package) as build,
                patch('scripts.release.GitHubRelease.upload') as upload,
            ):
                release = prepare(github, directory)
            self.assertEqual(release.tag, 'v0.4.5')
            build.assert_called_once_with('v0.4.5', directory)
            self.assertEqual(upload.call_count, 2)
            next_tag.assert_not_called()
        github.reserve.assert_not_called()
        github.create_draft.assert_not_called()

    def test_staging_uses_create_response_before_the_release_appears_in_the_list(self):
        github = Mock()
        github.releases.return_value = {
            'v0.4.4': {'draft': False, 'prerelease': False},
        }
        github.create_draft.return_value = {
            'id': 42, 'tag_name': 'v0.5.0', 'draft': True, 'prerelease': False, 'assets': [],
        }
        with tempfile.TemporaryDirectory() as folder:
            directory = Path(folder)
            package = Mock(archive=directory / 'EVILRises-v0.5.0.zip', changelog='notes')
            package.metadata.return_value = {'releases': []}
            with (
                patch('scripts.release.stable_tags', return_value=['v0.4.4']),
                patch('scripts.release.next_tag', return_value='v0.5.0'),
                patch('scripts.release.git', return_value='source-sha'),
                patch('scripts.release.build_at_tag', return_value=package),
                patch('scripts.release.GitHubRelease.upload') as upload,
            ):
                release = prepare(github, directory)
            self.assertEqual(release.id, 42)
            self.assertEqual(upload.call_count, 2)
        github.releases.assert_called_once_with()

    def test_published_release_without_receipt_cannot_be_the_version_baseline(self):
        github = Mock()
        github.releases.return_value = {
            'v0.4.5': {'draft': False, 'prerelease': False, 'assets': [
                {'name': 'EVILRises-v0.4.5.zip', 'state': 'uploaded'},
                {'name': 'release.json', 'state': 'uploaded'},
            ]},
        }
        with (
            patch('scripts.release.stable_tags', return_value=['v0.4.5']),
            patch('scripts.release.release_source', return_value='tagged-sha'),
            self.assertRaisesRegex(ValueError, 'Release v0.4.5 is missing published assets'),
        ):
            prepare(github, Path('unused'))
        github.reserve.assert_not_called()

    def test_publish_binds_the_receipt_to_the_tagged_commit(self):
        github = Mock()
        github.release.return_value.tag = 'v0.5.0'
        with tempfile.TemporaryDirectory() as folder:
            directory = Path(folder)
            metadata = directory / 'release.json'
            metadata.write_text(json.dumps({'releases': []}), encoding='utf-8')
            github.release.return_value.download.side_effect = [
                directory / 'EVILRises-v0.5.0.zip', metadata,
            ]
            package = Mock(interface=16001, sha256='b' * 64)
            package.metadata.return_value = {'releases': []}
            with (
                patch.dict(os.environ, {'CF_PROJECT_ID': '1828614'}),
                patch('scripts.release.git', side_effect=['tagged-sha', 'new-head\ntagged-sha']),
                patch('scripts.release.validate_archive', return_value=package),
                patch('scripts.release.publish_curseforge') as upload,
            ):
                publish(github, 'v0.5.0', '42', directory, 'publish-curseforge')
        github.release.assert_called_once_with('42')
        self.assertEqual(upload.call_args.args[3]['sourceCommit'], 'tagged-sha')
