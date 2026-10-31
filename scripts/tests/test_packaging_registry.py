"""The profile registry, the capability model and the single-game catalog.

Everything here reads the real `dm/games` tree unless a test says otherwise, and
a test that writes profiles uses a throwaway root: the repository is never
modified by a test. Touchline 23 registers exactly one title, so the catalog and
the capability record are asserted for that title rather than for a game list.
"""
import json
from pathlib import Path
import shutil
import sys
import tempfile
import time
import unittest
from dataclasses import replace

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO))
from tools.packaging_gui import capabilities, engine, games, registry

FIFA = '01001C8016B4E000'


class RegistryTests(unittest.TestCase):
    def test_the_project_lists_its_one_profile(self):
        folders = sorted(p.name for p in (REPO / 'dm/games').iterdir()
                         if p.is_dir() and (p / 'game.tsv').is_file())
        listed = [profile.key for profile in registry.profiles()]
        self.assertEqual(sorted(listed), folders)
        self.assertEqual(listed, [FIFA])
        # The count is scanned, never a constant in the code.
        self.assertEqual(len(listed), len(registry.catalog()['games']))

    def test_profiles_carry_identity_and_registered_versions(self):
        fifa = registry.by_title(FIFA)
        self.assertEqual(fifa.key, FIFA)
        self.assertEqual(fifa.title_id, int(FIFA, 16))
        self.assertEqual(fifa.modules, ('main', 'sdk'))
        self.assertEqual([version for version, _, _ in fifa.versions], ['v196608', 'v0'])
        self.assertEqual(fifa.display_of('v0'), '1.0.0')
        self.assertEqual(fifa.shader_versions, ('v0',))
        self.assertEqual(fifa.app_name, 'Touchline 23')
        self.assertEqual(fifa.error, '')

    def test_every_readable_profile_registers_complete_build_rows(self):
        for profile in registry.profiles():
            with self.subTest(game=profile.key):
                self.assertEqual(profile.error, '')
                self.assertTrue(profile.name)
                self.assertTrue(profile.modules)
                self.assertTrue(profile.versions)
                for version, display, ids in profile.versions:
                    self.assertTrue(version.startswith('v'))
                    self.assertTrue(display)
                    for module in profile.modules:
                        self.assertRegex(ids.get(module, ''), '^[0-9a-f]{32}$')
                self.assertTrue(profile.romfs_marker or profile.modules)

    def test_optional_keys_have_documented_defaults(self):
        for profile in registry.profiles():
            with self.subTest(game=profile.key):
                self.assertIn(profile.graphics_api, registry.GRAPHICS_APIS)
                self.assertIn(profile.archive_format, registry.ARCHIVE_FORMATS)
                self.assertEqual(profile.app_name, profile.app_name or profile.name)
        self.assertEqual(registry.by_title(FIFA).graphics_api, 'nvn')
        self.assertEqual(registry.by_title(FIFA).archive_format, 'easf')

    def test_damaged_profile_is_reported_not_raised(self):
        root = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, root, True)
        good = registry.by_title(FIFA)
        broken = root / '0100FFFFFFFFFFF000'
        broken.mkdir()
        (broken / 'game.tsv').write_text('title_id\tnot-hex\n')
        empty = root / '0100FFFFFFFFFFE000'
        empty.mkdir()
        (empty / 'game.tsv').write_text('# only comments\n')
        (root / 'not-a-profile').mkdir()
        listed = registry.profiles(root)
        self.assertEqual([profile.key for profile in listed],
                         ['0100FFFFFFFFFFE000', '0100FFFFFFFFFFF000'])
        self.assertTrue(all(profile.error for profile in listed))
        self.assertTrue(all(not profile.readable for profile in listed))
        # A damaged profile is still describable: the list shows it, the engine refuses it.
        self.assertEqual(capabilities.gap(listed[0], 'macos'), 'profile is not readable')
        self.assertFalse(capabilities.of(listed[0])['plan_supported'])
        self.assertTrue(good.readable)

    def test_new_profile_is_picked_up_without_a_restart(self):
        root = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, root, True)
        source = REPO / 'dm/games' / FIFA
        first = registry.profiles(root)
        self.assertEqual(first, ())
        shutil.copytree(source, root / FIFA)
        copied = registry.profiles(root)
        self.assertEqual([profile.key for profile in copied], [FIFA])
        time.sleep(0.01)
        (root / FIFA / 'game.tsv').write_text(
            (source / 'game.tsv').read_text().replace('FIFA 23 Legacy Edition', 'FIFA 23 Renamed'))
        self.assertEqual(registry.profiles(root)[0].name, 'FIFA 23 Renamed')

    def test_catalog_carries_capability_and_separate_evidence(self):
        payload = registry.catalog()
        self.assertEqual(payload['schema'], 1)
        self.assertEqual(payload['count'], 1)
        self.assertEqual(payload['count'], len(payload['games']))
        for game in payload['games']:
            with self.subTest(game=game['id']):
                self.assertIn('capability', game)
                self.assertIn('evidence', game)
                self.assertEqual(game['title_id'], game['id'])
                self.assertIn('versions', game)
                self.assertIn(game['evidence']['build'],
                              ('none', 'upstream-release', 'fork-audited'))
                self.assertIn(game['evidence']['runtime'],
                              ('none', 'upstream-iphone', 'fork-report'))
                # A registered profile alone never becomes a verification claim.
                self.assertNotIn('verified', json.dumps(game['capability']).lower())
        fifa = payload['games'][0]
        self.assertEqual(fifa['id'], FIFA)
        self.assertEqual(fifa['evidence']['build'], 'fork-audited')
        self.assertEqual(fifa['evidence']['runtime'], 'fork-report')

    def test_evidence_is_not_invented_for_an_unknown_title(self):
        self.assertEqual(registry.evidence(0x0100FFFFFFFFE000),
                         dict(build='none', runtime='none', source='', note=''))

    def test_index_roundtrip_is_the_bundled_read_boundary(self):
        root = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, root, True)
        target = registry.write_index(root / 'games-index.json')
        loaded = registry.load_index(target)
        scanned = registry.catalog()
        self.assertEqual(loaded['count'], scanned['count'])
        strip = lambda payload: [{k: v for k, v in game.items()} for game in payload['games']]
        self.assertEqual(strip(loaded), strip(scanned))
        (root / 'bad.json').write_text('{"schema": 2, "games": []}')
        with self.assertRaisesRegex(ValueError, 'not a game catalog'):
            registry.load_index(root / 'bad.json')

    def test_title_id_helpers_are_shared_with_the_bridge(self):
        self.assertEqual(registry.title_hex(FIFA), FIFA)
        self.assertEqual(registry.parse_title(FIFA.lower()), int(FIFA, 16))
        self.assertEqual(games.title_hex(int(FIFA, 16)), FIFA)


class CapabilityTests(unittest.TestCase):
    def test_the_registered_profile_plans_both_targets_and_modes(self):
        record = capabilities.of(registry.by_title(FIFA))
        self.assertTrue(record['plan_supported'])
        self.assertEqual([entry['id'] for entry in record['targets']], ['macos', 'ios'])
        self.assertTrue(all(entry['supported'] for entry in record['targets']))
        self.assertEqual([entry['id'] for entry in record['modes']], ['nsp', 'directory'])
        self.assertTrue(record['shader_reuse'])
        self.assertEqual(record['shader_generation'], 'automatic (source verification required)')

    def test_the_easf_archive_is_reported_as_the_shader_source(self):
        record = capabilities.of(registry.by_title(FIFA))
        self.assertEqual(record['archive_format'], 'easf')
        self.assertTrue(any('EASF' in text for text in record['limitations']) or
                        record['shader_generation'].startswith('automatic'))

    def test_capability_is_derived_from_the_profile_not_a_name_list(self):
        self.assertEqual(set(capabilities.TARGETS), {'macos', 'ios'})
        self.assertEqual(set(capabilities.MODES), {'nsp', 'directory'})
        for profile in registry.profiles():
            with self.subTest(game=profile.key):
                record = capabilities.of(profile)
                self.assertEqual(record['graphics_api'], profile.graphics_api)
                if profile.graphics_api not in capabilities.AUDITED_BACKENDS:
                    self.assertFalse(any(entry['supported'] for entry in record['targets']))
                    self.assertFalse(record['plan_supported'])
                if record['plan_supported']:
                    self.assertTrue(all(entry['supported'] for entry in record['targets']))

    def test_large_guest_reservation_is_a_signing_note_not_a_refusal(self):
        profile = replace(registry.by_title(FIFA), mem_reserve=0x200000000)
        self.assertGreater(profile.mem_reserve, capabilities.IOS_ENTITLEMENT_ABOVE)
        self.assertIn('extended-virtual-addressing',
                      ' '.join(capabilities.of(profile)['limitations']))
        # The note never becomes a refusal: build_ipa.sh writes the entitlement file.
        self.assertTrue(capabilities.of(profile)['plan_supported'])
        self.assertFalse(any('extended-virtual-addressing' in text
                             for text in capabilities.of(registry.by_title(FIFA))['limitations']))

    def test_engine_refuses_a_gap_before_planning_any_command(self):
        from unittest.mock import patch
        root = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, root, True)
        # A profile whose backend the artifact audits do not cover must be
        # refused when planning, not after a command has run.
        unsupported = replace(registry.by_title(FIFA), graphics_api='vulkan')
        request = engine.Request(game=FIFA, target='ios')
        with patch.object(registry, 'by_title', return_value=unsupported):
            with self.assertRaisesRegex(ValueError, 'audit'):
                engine.plan(request, root / 'task')
        self.assertIsNotNone(engine.inspect(request)['issues'])


if __name__ == '__main__':
    unittest.main()
