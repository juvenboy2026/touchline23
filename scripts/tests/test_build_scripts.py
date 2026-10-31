"""What the build helpers read: a build directory without a manifest, and a tree without Git.

The launcher used to require build-manifest.json, which only one build path
writes; and the source builder used to call Git unconditionally, which a
downloaded source archive cannot answer. Both are checked here without running
a build.
"""
import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

SCRIPTS = Path(__file__).parents[1]


def load(name):
    spec = importlib.util.spec_from_file_location(name, SCRIPTS / (name + '.py'))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


builder = load('build_fifa23')
runner = load('run_fifa23')


class SourceState(unittest.TestCase):
    def test_a_checkout_records_its_revision_and_dirtiness(self):
        with patch.object(builder.subprocess, 'check_output', side_effect=['abc123\n', ' M scripts/x.py\n']):
            self.assertEqual(builder.source_state(), ('abc123', True))
        with patch.object(builder.subprocess, 'check_output', side_effect=['abc123\n', '']):
            self.assertEqual(builder.source_state(), ('abc123', False))

    def test_a_tree_without_git_records_nothing(self):
        for error in (FileNotFoundError('git'), subprocess.CalledProcessError(128, 'git')):
            with self.subTest(error=type(error).__name__):
                with patch.object(builder.subprocess, 'check_output', side_effect=error):
                    self.assertEqual(builder.source_state(), (None, None))


class RunInputs(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.build = Path(self.temp.name)

    def tearDown(self):
        self.temp.cleanup()

    def write(self, name, text=''):
        path = self.build / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
        return path

    def test_rewritten_modules_are_read_from_the_patched_directory(self):
        self.assertEqual(runner.missing_modules(self.build), ['main', 'sdk'])
        for name in ('main', 'sdk'):
            self.write(f'patched/{name}.patched.bin')
            self.write(f'patched/{name}.fixups.tsv')
        self.assertEqual(runner.missing_modules(self.build), [])
        (self.build / 'patched/sdk.fixups.tsv').unlink()
        self.assertEqual(runner.missing_modules(self.build), ['sdk'])

    def test_chain_comes_from_the_library_when_there_is_no_manifest(self):
        self.assertIsNone(runner.shader_chain(self.build))
        (self.build / 'shaders' / 'b-abc123').mkdir(parents=True)
        self.assertEqual(runner.shader_chain(self.build), 'abc123')

    def test_chain_is_unknown_when_several_libraries_could_be_meant(self):
        (self.build / 'shaders' / 'b-abc123').mkdir(parents=True)
        (self.build / 'shaders' / 'b-def456').mkdir()
        self.assertIsNone(runner.shader_chain(self.build))
        self.write('build-manifest.json', '{"chain": "def456"}')
        self.assertEqual(runner.shader_chain(self.build), 'def456')

    def test_a_damaged_manifest_still_leaves_the_library(self):
        self.write('build-manifest.json', 'not json')
        (self.build / 'shaders' / 'b-abc123').mkdir(parents=True)
        self.assertEqual(runner.shader_chain(self.build), 'abc123')


if __name__ == '__main__':
    unittest.main()
