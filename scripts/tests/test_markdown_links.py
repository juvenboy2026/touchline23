"""Controls for path/anchor checks used in local publication review."""
from pathlib import Path
import subprocess
import tempfile
import unittest
from scripts import check_markdown_links as links


class MarkdownLinks(unittest.TestCase):
    def test_github_heading_duplicates_and_explicit_anchors(self):
        self.assertEqual(links.anchors('# Hello, `world`!\n## Hello, world!\n<a id="manual"></a>'),
                         {'hello-world', 'hello-world-1', 'manual'})

    def test_code_examples_do_not_create_links_or_anchors(self):
        text = '# Real\n```md\n# Fake\n[x](missing.md)\n```\n[x](real.md#real)'
        self.assertEqual(links.anchors(text), {'real'})
        self.assertEqual(links.destinations(text), [(6, 'real.md#real')])

    def test_encoded_paths_and_reference_links(self):
        self.assertEqual(links.destinations('[one](my%20file.md#anchor)\n[two]: other.md'),
                         [(1, 'my%20file.md#anchor'), (2, 'other.md')])

    def test_missing_targets_and_anchors_are_reported(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            subprocess.run(['git', 'init', '-q', str(root)], check=True)
            (root / 'README.md').write_text('[ok](guide.md#works)\n[bad](guide.md#absent)\n[x](gone.md)')
            (root / 'guide.md').write_text('# Works\n')
            result = links.check(root)
            self.assertEqual(result['markdown_files'], 2)
            self.assertEqual([row['error'] for row in result['errors']], ['missing anchor', 'missing path'])


if __name__ == '__main__':
    unittest.main()
