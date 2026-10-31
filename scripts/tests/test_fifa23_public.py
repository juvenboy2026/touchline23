"""Exercise the audit with synthetic data, including a removed historical secret."""
import contextlib
import io
from unittest.mock import patch
import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('audit', Path(__file__).parents[1] / 'check_fifa23_public.py')
audit = importlib.util.module_from_spec(spec)
spec.loader.exec_module(audit)


class PublicAudit(unittest.TestCase):
    def test_localized_text_scope_keeps_credential_and_path_checks(self):
        chinese = '\u4e2d\u6587'
        for name in ('README.zh-CN.md', 'README.md', 'docs/UPSTREAM-DIFFERENCES.zh-CN.md',
                     'gui/Sources/PackagingModel/Localization.swift', 'gui/Tests/PackagingModelTests/LocalizationTests.swift'):
            with self.subTest(path=name):
                self.assertEqual(audit.inspect(name, chinese.encode()), [])
                secret = 'gh' + 'p_' + 'a' * 25
                self.assertTrue(any('authentication token' in item for item in audit.inspect(name, (chinese + ' ' + secret).encode())))
                self.assertTrue(any('personal absolute path' in item for item in audit.inspect(name, b'/Users' + b'/example/private')))
        self.assertTrue(any('non-English source text' in item for item in audit.inspect('dm/host/example.c', chinese.encode())))
        self.assertTrue(any('non-English source text' in item for item in audit.inspect('scripts/example.py', chinese.encode())))

    def test_task_build_path_is_not_an_authentication_token(self):
        value = 'gui-task-build-35ADE980-0C34-402D-9E0D-D5630CC650D2/task.log'
        self.assertEqual(audit.inspect('docs/example.md', value.encode()), [])
        for secret in ('s' + 'k-' + 'a' * 25, 'github_' + 'pat_' + 'a' * 25):
            self.assertTrue(any('authentication token' in item for item in audit.inspect('example.py', secret.encode())))

    def test_sensitive_values_are_never_echoed(self):
        value = 'gh' + 'p_' + 'a' * 25
        findings = audit.inspect('example.py', ('token = ' + repr(value)).encode())
        self.assertTrue(findings)
        self.assertNotIn(value, '\n'.join(findings))
        self.assertTrue(audit.inspect('input.nso', b'NSO0'))
        self.assertTrue(audit.inspect('example.py', b'\xff'))

    def test_first_commit_staged_scan_reads_index_not_working_copy(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            subprocess.run(['git', 'init', '-q', directory], check=True)
            candidate = root / 'example.py'
            candidate.write_text('token = ' + repr('gh' + 'p_' + 'a' * 25))
            subprocess.run(['git', '-C', directory, 'add', 'example.py'], check=True)
            candidate.write_text('Safe working copy')
            output = io.StringIO()
            with patch.object(audit, 'REPO', root), patch('sys.argv', ['audit', '--staged']), contextlib.redirect_stdout(output):
                self.assertTrue(audit.main())
            self.assertIn('authentication token', output.getvalue())

    def test_candidates_exclude_ignored_builds_and_keep_source(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            subprocess.run(['git', 'init', '-q', directory], check=True)
            (root / '.gitignore').write_text('*.ipa\n*.app/\n')
            (root / 'game.ipa').write_bytes(b'private build')
            (root / 'game.app').mkdir()
            (root / 'game.app/payload').write_bytes(b'private build')
            (root / 'source.py').write_text('print(1)')
            with patch.object(audit, 'REPO', root):
                self.assertEqual(audit.working_tree(), ['.gitignore', 'source.py'])

    def test_removed_file_is_scanned_in_its_original_commit(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            def git(*args):
                return subprocess.check_output(['git', '-C', directory, *args], stderr=subprocess.DEVNULL)
            def commit(message):
                git('-c', 'user.name=Audit Test', '-c', 'user.email=audit@example.invalid', 'commit', '-qm', message)
            git('init', '-q')
            (root / 'README.md').write_text('Synthetic repository\n')
            git('add', '.')
            commit('base')
            base = git('rev-parse', 'HEAD').decode().strip()
            (root / 'removed.py').write_text('token = ' + repr('gh' + 'p_' + 'a' * 25) + '\n')
            git('add', '.')
            commit('synthetic secret')
            git('rm', '-q', 'removed.py')
            commit('remove file')
            previous = audit.REPO
            try:
                audit.REPO = root
                commits, names, versions, findings = audit.history(base)
            finally:
                audit.REPO = previous
            self.assertEqual(len(commits), 2)
            self.assertIn('removed.py', names)
            self.assertEqual(len(versions), 1)
            self.assertEqual(len(findings), 1)
            self.assertIn('authentication token', findings[0])


if __name__ == '__main__':
    unittest.main()
