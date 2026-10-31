"""Offline UI names: exact coverage/provenance, separate from build identity."""
import json
from pathlib import Path
import unittest

from tools.packaging_gui import registry

ROOT = Path(__file__).resolve().parents[2]
DATA = ROOT / 'tools/packaging_gui/data/game_names.zh-Hans.json'


class DisplayNameDataTests(unittest.TestCase):
    def setUp(self):
        self.data = json.loads(DATA.read_text())

    def test_every_current_supported_title_was_reviewed_by_exact_id(self):
        supported = {row['id']: row for row in registry.catalog()['games']
                     if any(t['supported'] for t in row['capability']['targets'])}
        self.assertEqual(set(self.data['names']), set(supported))
        for tid, entry in self.data['names'].items():
            self.assertRegex(tid, r'^[0-9A-F]{16}$')
            self.assertEqual(entry['english'], supported[tid]['name'])
            self.assertIn(entry['status'], ('verified', 'missing', 'ambiguous'))
            self.assertTrue(entry['note'])
            for source in entry['source_ids']:
                self.assertIn(source, self.data['sources'])
            if entry['status'] == 'verified':
                self.assertRegex(entry['zh_hans'], r'[\u4e00-\u9fff]')
                self.assertRegex(entry['nsuid'], r'^\d{14}$')
                self.assertNotIn('Nintendo Switch 2', entry['zh_hans'])
            else:
                self.assertIsNone(entry['zh_hans'])

    def test_regional_conflicts_are_withheld_not_guessed(self):
        for tid, entry in self.data['names'].items():
            if entry['status'] == 'ambiguous':
                self.assertNotEqual(entry['regional_candidate']['title_id'], tid)
                self.assertIsNone(entry['zh_hans'])

    def test_the_registered_title_keeps_its_source_link(self):
        entry = self.data['names']['01001C8016B4E000']
        self.assertEqual(entry['status'], 'verified')
        self.assertEqual(entry['source_ids'], ['titledb-hk'])
        self.assertTrue((DATA.parent / 'titledb-LICENSE.md').is_file())
        self.assertEqual(self.data['sources']['titledb-hk']['revision'],
                         '49db6611a8cb0278082cc2544e304fe4ae51e552')

    def test_names_are_shipped_by_the_existing_bundle_manifest(self):
        from tools.packaging_gui.distribution import source_files
        self.assertIn(DATA.relative_to(ROOT).as_posix(), set(source_files(ROOT)))
        controller = (ROOT / 'gui/Sources/NXPackagingGUI/TaskController.swift').read_text()
        self.assertIn('found.withLocalizedNames(names)', controller)
        model = (ROOT / 'gui/Sources/PackagingModel/LocalizedGameNames.swift').read_text()
        self.assertNotIn('URLSession', model)
        self.assertNotIn('http', model)


if __name__ == '__main__':
    unittest.main()
