"""Title ID identification against the profile registry, on synthetic gamecards only."""
import subprocess
import sys
import tempfile
from pathlib import Path
import unittest

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO))
sys.path.insert(0, str(REPO / 'dm/resource/tests'))
from tools.packaging_gui import games, registry
import fixture

FIFA = '01001C8016B4E000'
OTHER_TITLE = 0x0100FFFFFFFFE000


class GamesTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.work = tempfile.TemporaryDirectory(prefix='nxrom-games-')
        cls.root = Path(cls.work.name)
        cls.library = cls.root / 'reader.dylib'
        # The same reader source the shipping library is built from, compiled
        # once into a throwaway directory: no repository file is written.
        subprocess.run(['clang', '-dynamiclib', '-O1', '-Wall', '-Wextra', '-Werror',
                        '-Wno-deprecated-declarations', str(REPO / 'dm/resource/nxrom.c'),
                        '-o', str(cls.library)], check=True)
        fixture.write_fixture(cls.root)          # test.keys + a synthetic base.nsp
        cls.keys = str(cls.root / 'test.keys')
        cls.fifa = cls.title_of(FIFA)
        (cls.root / 'fifa.xci').write_bytes(fixture.xci({'small': b'hello'}, code=True, title=cls.fifa))
        (cls.root / 'other.xci').write_bytes(fixture.xci({'small': b'hello'}, code=True, title=OTHER_TITLE))
        # A misleading name must not decide the game.
        (cls.root / 'FIFA 23 [01001C8016B4E000].xci').write_bytes(
            fixture.xci({'small': b'hello'}, code=True, title=OTHER_TITLE))
        cls.update = cls.fifa + registry.update_delta()
        (cls.root / 'update.nsp').write_bytes(fixture.pfs([
            ('program.nca', fixture.nca(fixture.romfs({'small': b'hello'}), title=cls.update))]))

    @classmethod
    def tearDownClass(cls):
        cls.work.cleanup()

    @staticmethod
    def title_of(value):
        return int(value, 16) if isinstance(value, str) else int(value)

    def identify(self, name, keys=None):
        return games.identify(self.root / name, keys or self.keys, self.library)

    def test_registry_is_keyed_by_the_base_title_id(self):
        profile = games.by_title(FIFA)
        self.assertEqual(profile.key, FIFA)
        self.assertEqual(profile.name, 'FIFA 23 Legacy Edition')
        self.assertEqual(profile.app_name, 'Touchline 23')
        self.assertIs(games.by_key(FIFA), games.by_title(int(FIFA, 16)))
        self.assertIsNone(games.by_key('not-a-game'))
        self.assertIsNone(games.by_title(OTHER_TITLE))
        self.assertEqual(games.update_title(profile), int(FIFA, 16) + registry.update_delta())

    def test_base_game_is_identified_from_the_resource(self):
        found = self.identify('fifa.xci')
        self.assertTrue(found['ok'], found['message'])
        self.assertEqual(found['kind'], 'base')
        self.assertEqual(found['title_hex'], FIFA)
        self.assertEqual(found['game'], FIFA)
        self.assertEqual(found['name'], 'FIFA 23 Legacy Edition')

    def test_file_name_never_decides_the_game(self):
        found = self.identify('FIFA 23 [01001C8016B4E000].xci')
        self.assertFalse(found['ok'])
        self.assertEqual(found['kind'], 'unknown')
        self.assertIsNone(found['game'])
        self.assertIn(games.title_hex(OTHER_TITLE), found['message'])

    def test_update_package_is_not_reported_as_a_base_game(self):
        found = self.identify('update.nsp')
        self.assertFalse(found['ok'])
        self.assertEqual(found['kind'], 'update')
        self.assertEqual(found['title_hex'], games.title_hex(self.update))
        self.assertIn('不是游戏本体', found['message'])

    def test_unreadable_container_names_the_input_to_recheck(self):
        (self.root / 'bad.keys').write_text('not a key file\n')
        found = self.identify('fifa.xci', keys=str(self.root / 'bad.keys'))
        self.assertFalse(found['ok'])
        self.assertEqual(found['kind'], 'error')
        self.assertIn('prod.keys', found['message'])
        self.assertNotIn('not a key file', found['message'])

    def test_unregistered_title_points_at_the_profile_scheme(self):
        found = games.describe(OTHER_TITLE)
        self.assertEqual(found['kind'], 'unknown')
        self.assertIn('dm/games', found['message'])

    def test_describe_is_pure(self):
        self.assertTrue(games.describe(int(FIFA, 16))['ok'])
        self.assertEqual(games.describe(self.update)['kind'], 'update')
        self.assertEqual(games.describe(0)['kind'], 'unknown')


if __name__ == '__main__':
    unittest.main()
