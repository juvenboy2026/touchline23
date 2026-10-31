"""Offline publication contracts for the retained, locked translator distribution."""
import csv
import hashlib
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
RUNTIME = ROOT / 'dm/gfx/tools/dmsh_xlate_bin'
EVIDENCE = ROOT / 'dm/third_party/translator-runtime'


def digest(data):
    return hashlib.sha256(data).hexdigest()


class TranslatorProvenance(unittest.TestCase):
    def test_every_distributed_runtime_binary_has_exact_provenance(self):
        manifest = json.loads((EVIDENCE / 'binary-provenance.json').read_text())
        records = {row['file']: row for row in manifest['files']}
        actual = {p.relative_to(RUNTIME).as_posix() for p in RUNTIME.rglob('*')
                  if p.is_file() and (p.suffix == '.dll' or p.name == 'dmsh_xlate')}
        self.assertEqual(actual, set(records))
        self.assertEqual(len(records), 61)
        self.assertEqual(sum('member' in row for row in records.values()), 56)
        for name, row in records.items():
            with self.subTest(file=name):
                self.assertEqual(digest((RUNTIME / name).read_bytes()), row['sha256'])
                self.assertEqual(row['sha256'], row['touchline27_sha256'])
                self.assertTrue(row['status'].startswith('resolved-'))
                self.assertIn('package_sha256' if 'member' in row else 'producer_commit', row)
        with (EVIDENCE / 'binaries.tsv').open() as stream:
            inventory = list(csv.DictReader(stream, delimiter='\t'))
        self.assertEqual(len(inventory), len(records))
        for row in inventory:
            self.assertEqual(digest((ROOT / row['path']).read_bytes()), row['sha256'])

    def test_source_and_license_hashes_retain_the_reviewed_snapshot(self):
        with (EVIDENCE / 'source-provenance.tsv').open() as stream:
            sources = list(csv.DictReader(stream, delimiter='\t'))
        self.assertEqual(len(sources), 364)
        for row in sources:
            data = (ROOT / row['path']).read_bytes()
            self.assertEqual(digest(data), row['sha256'], row['path'])
            blob = hashlib.sha1(b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest()
            self.assertEqual(blob, row['git_blob'], row['path'])
        manifest = json.loads((EVIDENCE / 'binary-provenance.json').read_text())
        self.assertEqual(len(manifest['license_materials']), 8)
        for row in manifest['license_materials']:
            self.assertEqual(digest((EVIDENCE / row['file']).read_bytes()), row['sha256'])
        self.assertIn('Apache License', (EVIDENCE / 'licenses/MsgPack-Apache-2.0.txt').read_text())
        humanizer = (EVIDENCE / 'licenses/Humanizer-MIT.txt').read_text()
        for name in ('Scott Kirkland', 'Omar Khudeira', '.NET Foundation'):
            self.assertIn(name, humanizer)

    def test_lock_still_names_the_reviewed_binaries(self):
        lock = dict(line.split('\t', 1) for line in
                    (ROOT / 'dm/gfx/tools/dmsh_chain.lock').read_text().splitlines()
                    if '\t' in line and not line.startswith('#'))
        for name in ('dmsh_xlate.dll', 'Ryujinx.Common.dll', 'Ryujinx.Graphics.Shader.dll'):
            self.assertEqual(digest((RUNTIME / name).read_bytes())[:16], lock[name])
        self.assertTrue((ROOT / 'dm/third_party/deko3d/LICENSE').is_file())
        self.assertTrue((ROOT / 'dm/third_party/vulkan-headers/LICENSES/MIT.txt').is_file())


if __name__ == '__main__':
    unittest.main()
