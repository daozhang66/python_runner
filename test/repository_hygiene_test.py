import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


CHECKER = Path(__file__).resolve().parents[1] / 'scripts/check_repo_hygiene.py'


class RepositoryHygieneTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.env = os.environ.copy()
        # Tests always own a fresh index, even when invoked while preparing a
        # release through an alternate index in the parent repository.
        self.env.pop('GIT_INDEX_FILE', None)
        self.git('init', '--quiet')
        self.git('config', 'core.autocrlf', 'false')

    def git(self, *args):
        return subprocess.check_output(['git', *args], cwd=self.root, env=self.env)

    def stage(self, name, data):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
        self.git('add', '--', name)

    def check(self, *args):
        return subprocess.run([sys.executable, str(CHECKER), *args], cwd=self.root,
                              env=self.env, capture_output=True, text=True)

    def test_failed_download_rejected_even_when_working_copy_is_fixed(self):
        self.stage('assets/font.ttf', b'404: Not Found')
        (self.root / 'assets/font.ttf').write_bytes(b'\0\1\0\0working-copy')
        result = self.check()
        self.assertEqual(1, result.returncode)
        self.assertIn('download error response', result.stderr)
        self.assertIn('assets/font.ttf', result.stderr)

    def test_staged_deletion_removes_bad_blob(self):
        self.stage('assets/font.ttf', b'404: Not Found')
        self.git('rm', '-f', '--', 'assets/font.ttf')
        self.assertEqual(0, self.check().returncode)

    def test_generated_directories_and_build_outputs_rejected(self):
        for path in ['assets/__pycache__/hook.pyc', '.vscode/settings.json',
                     '.pytest_cache/index', 'build/result.bin', 'release/app.apk']:
            self.stage(path, b'generated')
        result = self.check()
        self.assertEqual(1, result.returncode)
        for path in ['hook.pyc', 'settings.json', 'result.bin', 'app.apk']:
            self.assertIn(path, result.stderr)

    def test_required_native_assets_and_test_fixtures_are_allowed(self):
        for path, data in {
            'assets/font.ttf': b'\0\1\0\0font',
            'android/app/src/main/jniLibs/arm64-v8a/libproot.so': b'\x7fELFbinary',
            'test/goldens/view.png': b'\x89PNG\r\n\x1a\nimage',
            'test/fixtures/input.zip': b'PKfixture',
            'test/fixtures/localhost-key.pem': b'public test fixture',
            'LICENSE': b'license text',
        }.items():
            self.stage(path, data)
        self.assertEqual(0, self.check().returncode)

    def test_untracked_local_files_are_not_source(self):
        (self.root / 'local.apk').write_bytes(b'generated')
        self.assertEqual(0, self.check().returncode)

    def test_commit_tree_is_checked_independently_of_staged_cleanup(self):
        self.stage('bad.png', b'<html>404</html>')
        tree = self.git('write-tree').decode().strip()
        self.git('rm', '-f', '--', 'bad.png')
        self.assertEqual(0, self.check().returncode)
        self.assertEqual(1, self.check('--ref', tree).returncode)


if __name__ == '__main__':
    unittest.main()
