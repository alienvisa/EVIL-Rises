import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import Mock, patch

from scripts.release import bump, prepare, release_level


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
            git('commit', '--allow-empty', '-m', 'feat: add filters')
            self.assertEqual(version(), 'v0.5.0')
            git('tag', 'v0.5.0')
            self.assertEqual(version(), 'v0.5.0')
            git('commit', '--allow-empty', '-m', 'Edited squash title')
            with self.assertRaises(subprocess.CalledProcessError) as failure:
                subprocess.run(
                    [sys.executable, '-B', '-m', 'scripts.release'], cwd=repo, text=True,
                    env={**os.environ, 'PYTHONPATH': str(root)}, check=True, capture_output=True,
                )
            self.assertIn('Use the PR title as the squash subject', failure.exception.stderr)

    def test_pending_previous_release_blocks_the_next_tag(self):
        github = Mock()
        github.releases.return_value = {'v0.4.5': {'draft': True, 'prerelease': False}}
        with patch('scripts.release.stable_tags', return_value=['v0.4.5']):
            with patch('scripts.release.next_tag', return_value='v0.4.6'):
                with self.assertRaisesRegex(ValueError, 'Finish release v0.4.5'):
                    prepare(github, Path('unused'))
        github.reserve.assert_not_called()

    def test_published_release_without_receipt_cannot_be_the_version_baseline(self):
        github = Mock()
        github.releases.return_value = {
            'v0.4.5': {'draft': False, 'prerelease': False, 'assets': [
                {'name': 'EVILRises-v0.4.5.zip', 'state': 'uploaded'},
                {'name': 'release.json', 'state': 'uploaded'},
            ]},
        }
        with patch('scripts.release.stable_tags', return_value=['v0.4.5']):
            with patch('scripts.release.next_tag', return_value='v0.4.6'):
                with self.assertRaisesRegex(ValueError, 'Release v0.4.5 is missing published assets'):
                    prepare(github, Path('unused'))
        github.reserve.assert_not_called()
