"""Synthetic evidence for the Touchline 23 packaging engine; no retail Shaders.

The one registered profile goes through one plan, one preflight and one cache
validation. Fixtures are synthetic NSO headers and empty metallibs.
"""
from dataclasses import replace
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO))
from tools.packaging_gui import capabilities, engine, registry, shader_sources

FIFA = '01001C8016B4E000'
OTHER = '0100FFFFFFFFE000'


def write_program(exefs, profile, version):
    """Synthetic NSO headers carrying that version's build IDs, plus control.nacp."""
    exefs = Path(exefs)
    exefs.mkdir(parents=True, exist_ok=True)
    ids = profile.build_ids(version)
    for module in profile.modules:
        data = bytearray(0x60)
        data[:4] = b'NSO0'
        data[0x40:0x50] = bytes.fromhex(ids[module])
        (exefs / module).write_bytes(data)
    (exefs.parent / 'control.nacp').write_bytes(b'synthetic metadata')
    return exefs


def build_cache(root, profile, target='macos'):
    """A completed Shader build: profile copy, stamp, generated tables, libraries."""
    from tools.nxrom.prepared_build import shader_keys
    profile_dir = Path(root) / 'profile' / profile.key
    profile_dir.mkdir(parents=True)
    source = profile.table('game.tsv').parent
    for item in source.glob('*.tsv'):
        shutil.copyfile(item, profile_dir / item.name)
    chain = engine.chain_tools()
    version = chain.version()
    cache = Path(root) / ('shaders' if target == 'macos' else 'ios/dmsh_b') / ('b-' + version)
    cache.mkdir(parents=True)
    chain.write_stamp(str(cache), profile.key,
                      chain.inputs(registry.game_profiles.Game(profile_dir)))
    for name in ('c1_full.tsv', 'cb_extent.tsv'):
        (profile_dir / name).write_text(chain.table_head(str(cache)) + ' synthetic\n')
    for key in shader_keys(registry.game_profiles.Game(profile_dir)):
        (cache / (key + '_b.json')).write_text(json.dumps(
            dict(chain=version, key=key + '_b', chain_metal='macosx fixture')))
        (cache / (key + '_b.metallib')).write_bytes(b'MTLB' + bytes(28))
    # An EASF profile's reuse also needs the prepared archive package and the
    # build manifest a completed source build leaves beside the libraries.
    if profile.archive_format == 'easf':
        from tools.nxrom.shader_package import digest
        pkg = Path(root) / 'pkg'
        pkg.mkdir(exist_ok=True)
        (pkg / 'synthetic.bin').write_bytes(b'synthetic package')
        (Path(root) / 'build-manifest.json').write_text(json.dumps(dict(
            chain=version, host_from_source=True,
            packages={p.name: digest(p) for p in pkg.glob('*.bin')})))
    return profile_dir, cache, chain, version


class RecipeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.fifa = registry.by_title(FIFA)
        self.exefs = write_program(self.root / 'program/ExeFS', self.fifa, 'v0')
        self.r = engine.Request(game=FIFA, base=str(self.root / 'base.xci'), keys=str(self.root / 'prod.keys'),
                                output=str(self.root), exefs=str(self.exefs),
                                cache=str(self.root / 'source'), romfs=str(self.root / 'program/RomFS'))

    def plan(self, request=None, task=None):
        return engine.plan(request or self.r, task or self.root / 'new-task')

    def test_automatic_dlc_stage_and_platform_packagers_are_connected(self):
        for target in ('macos', 'ios'):
            request = replace(self.r, target=target, mode='directory', automatic='1',
                aoc=str(self.root/'future-aoc'), dlcs=({'index':1},))
            recipe = self.plan(request)
            stages = [c['stage'] for c in recipe['commands']]
            self.assertLess(stages.index('prepare-dlc'), stages.index('rewrite-main'))
            package = recipe['commands'][-1]
            if target == 'macos':
                self.assertIn('--aoc',package['argv'])
                self.assertIn(request.aoc,package['argv'])
            else:
                self.assertEqual(package['environment']['AOC'],request.aoc)

    def test_all_four_recipes_use_real_packagers_and_remain_disabled(self):
        for target in ('macos', 'ios'):
            for mode in ('directory', 'nsp'):
                with self.subTest(target=target, mode=mode):
                    result = self.plan(replace(self.r, target=target, mode=mode))
                    package = result['commands'][-1]
                    self.assertFalse(result['execution_enabled'])
                    self.assertEqual(result['program_version'], 'v0')
                    self.assertEqual(result['shader_source_versions'], ['v0'])
                    self.assertFalse(any('build_external_nsp.py' in arg for c in result['commands'] for arg in c['argv']))
                    self.assertFalse(any('ready.json' in arg for c in result['commands'] for arg in c['argv']))
                    if target == 'macos':
                        self.assertIn(str(REPO / 'scripts/build_mac_app.py'), package['argv'])
                        self.assertEqual('--romfs' in package['argv'], mode == 'directory')
                    else:
                        self.assertIn(str(REPO / 'dm/ios/tools/build_ipa.sh'), package['argv'])
                        self.assertEqual(package['environment']['DM_RESOURCE_BACKEND'], mode)
                        for name in ('DM_IOS_BUILD_DIR', 'DM_XCODE_DERIVED_DATA', 'W'):
                            self.assertTrue(Path(package['environment'][name]).is_relative_to(self.root / 'new-task'))
        self.assertFalse((self.root / 'new-task').exists())

    def test_program_version_comes_from_the_exefs_not_from_an_update(self):
        """A selected update never decides the version: the module build IDs do."""
        base_only = self.plan()
        updated = self.plan(replace(self.r, update=str(self.root / 'update.nsp'), exefs=str(
            write_program(self.root / 'program-1.0.3/ExeFS', self.fifa, 'v196608'))))
        self.assertEqual(base_only['program_version'], 'v0')
        self.assertEqual(updated['program_version'], 'v196608')
        self.assertEqual(updated['program_display'], '1.0.3')
        # The Shader tables cover the base game; an update does not change that.
        self.assertEqual(updated['shader_source_versions'], ['v0'])

    def test_an_exefs_of_no_registered_version_is_refused(self):
        foreign = self.root / 'program-foreign/ExeFS'
        foreign.mkdir(parents=True)
        for module in self.fifa.modules:
            data = bytearray(0x60); data[:4] = b'NSO0'; data[0x40:0x50] = bytes(16)
            (foreign / module).write_bytes(data)
        (foreign.parent / 'control.nacp').write_bytes(b'metadata')
        with self.assertRaisesRegex(ValueError, 'no program version'):
            self.plan(replace(self.r, exefs=str(foreign)))

    def test_generation_uses_the_archive_format_provider_only(self):
        r = replace(self.r, target='ios', shader_action='generate',
                    update=str(self.root / 'update.nsp'), easf_key_file=str(self.root / 'private.json'))
        command = self.plan(r)['commands'][0]
        self.assertIn(str(REPO / 'scripts/build_fifa23.py'), command['argv'])
        self.assertIn('--key-file', command['argv'])
        self.assertNotIn('--no-key-discovery', command['argv'])
        self.assertIn('--exefs', command['argv'])
        self.assertIn('IOSOUT', command['environment'])
        self.assertTrue(Path(command['argv'][command['argv'].index('--out') + 1]).is_relative_to(self.root / 'new-task'))
        # The archive location comes from the profile, not from the script defaults.
        self.assertEqual(command['argv'][command['argv'].index('--datax') + 1], 'datax.big')
        members = [command['argv'][i + 1] for i, arg in enumerate(command['argv']) if arg == '--member']
        self.assertEqual(members, list(self.fifa.archive_members))

    def test_reuse_never_invokes_shader_compilation(self):
        stages = [c['stage'] for c in self.plan()['commands']]
        self.assertNotIn('generate-shaders', stages)

    def test_shell_characters_stay_in_a_single_argument(self):
        name = str(self.root / 'base ; $(touch nope).xci')
        result = self.plan(replace(self.r, base=name, shader_action='generate'))
        args = result['commands'][0]['argv']
        self.assertEqual(args[args.index('--base') + 1], name)
        self.assertNotIn('-c', args)

    def test_existing_task_is_never_overwritten(self):
        (self.root / 'new-task').mkdir()
        with self.assertRaisesRegex(ValueError, 'new directory'):
            self.plan()

    def test_task_parent_must_already_exist(self):
        with self.assertRaisesRegex(ValueError, 'parent folder'):
            engine.plan(self.r, self.root / 'missing-run' / 'work')

    def test_invalid_enum_and_worker_count_fail(self):
        for change in ({'target': 'android'}, {'mode': 'cloud'}, {'jobs': 0}, {'shader_action': 'ignore'}):
            with self.assertRaises(ValueError):
                self.plan(replace(self.r, **change))

    def test_an_unknown_game_is_refused_before_any_command(self):
        with self.assertRaisesRegex(ValueError, 'No registered game profile'):
            self.plan(replace(self.r, game='0100FFFFFFFFE000'))
        with self.assertRaisesRegex(ValueError, 'No registered game profile'):
            self.plan(replace(self.r, game=''))

    def test_inspection_fails_closed_without_inputs_and_never_runs_commands(self):
        with patch.object(subprocess, 'run', side_effect=AssertionError('No subprocess allowed')):
            result = engine.inspect(self.r)
        self.assertFalse(result['input_checks_passed'])
        self.assertFalse(result['execution_enabled'])
        self.assertIn('container-identity', result['issues'])
        self.assertIn('shader-cache', result['issues'])
        self.assertFalse((self.root / 'new-task').exists())

    def test_python_dependency_set_excludes_unused_cryptography(self):
        # The executable chain imports only these three modules. EASF decoding is
        # the sole importer of Crypto, and only the disabled generate path can
        # reach it, where it raises its own error for an EASF input. A preflight
        # requirement here would reject a valid environment for no benefit.
        self.assertEqual(engine.PYTHON_DEPENDENCIES, ('capstone', 'lz4.block', 'fontTools'))
        for action in ('reuse', 'generate'):
            with self.subTest(action=action):
                names = [c['name'] for c in engine.inspect(replace(self.r, shader_action=action))['checks']]
                self.assertEqual([n for n in names if n.startswith('python-')],
                                 ['python-capstone', 'python-lz4.block', 'python-fontTools'])
                self.assertFalse(any('Crypto' in n for n in names))

    def test_compressed_input_rejected_before_mount(self):
        base = self.root / 'base.xcz'; base.write_bytes(b'compressed')
        result = engine.inspect(replace(self.r, base=str(base)))
        self.assertIn('base', result['issues'])

    def test_program_version_checked_from_nso_header(self):
        result = engine.inspect(self.r)
        detail = next(c['detail'] for c in result['checks'] if c['name'] == 'program-identity')
        self.assertEqual(detail['version'], 'v0')
        self.assertEqual(detail['modules'], ('main', 'sdk'))
        self.assertNotIn('program-identity', result['issues'])
        # A missing module, a non-NSO file and an unregistered build ID all fail.
        (self.exefs / 'sdk').unlink()
        self.assertIn('program-identity', engine.inspect(self.r)['issues'])
        write_program(self.exefs, self.fifa, 'v0')
        (self.exefs / 'main').write_bytes(b'NOPE' + bytes(0x5C))
        self.assertIn('program-identity', engine.inspect(self.r)['issues'])

    def test_low_disk_space_blocks_validation(self):
        with patch.object(shutil, 'disk_usage', return_value=shutil._ntuple_diskusage(100, 99, 1)):
            result = engine.inspect(replace(self.r, mode='nsp'))
        space = next(c for c in result['checks'] if c['name'] == 'output-space')
        self.assertFalse(space['ok'])
        self.assertIn('Insufficient space', space['detail'])

    def test_directory_space_includes_work_and_publication_copies(self):
        romfs = self.root / 'RomFS'; romfs.mkdir()
        (romfs / 'data3.big').write_bytes(b'game data')
        request = replace(self.r, mode='directory', romfs=str(romfs))
        required = 8 * 2**30 + 2 * len(b'game data')
        with patch.object(shutil, 'disk_usage', return_value=shutil._ntuple_diskusage(required, 0, required)):
            check = next(c for c in engine.inspect(request)['checks'] if c['name'] == 'output-space')
        self.assertTrue(check['ok'])
        self.assertEqual(check['detail']['estimated_bytes'], required)
        with patch.object(shutil, 'disk_usage', return_value=shutil._ntuple_diskusage(required, 1, required - 1)):
            check = next(c for c in engine.inspect(request)['checks'] if c['name'] == 'output-space')
        self.assertFalse(check['ok'])

    def test_redaction_hides_paths_and_raw_key_shapes(self):
        secret = '0123456789abcdef0123456789abcdef'
        result = engine.redact({'error': self.r.keys + ' ' + self.r.base + ' ' + secret}, self.r)
        self.assertNotIn(self.r.keys, result['error'])
        self.assertNotIn(self.r.base, result['error'])
        self.assertNotIn(secret, result['error'])

    def test_container_identity_uses_native_title_and_module_checks(self):
        library = self.root / 'reader.dylib'
        for item in (Path(self.r.base), Path(self.r.keys), library):
            item.write_bytes(b'synthetic')
        from tools.nxrom import resourcefs
        with patch.object(resourcefs, 'ResourceFS') as reader:
            opened = reader.return_value.__enter__.return_value
            opened.title = int(FIFA, 16)
            result = engine.inspect(replace(self.r, library=str(library)))
            self.assertNotIn('container-identity', result['issues'])
            # The resource decides the game: no expected Title ID is imposed.
            self.assertEqual(reader.call_args.kwargs['title'], 0)
            self.assertEqual(opened.check_build.call_count, 2)
            detail = next(c['detail'] for c in result['checks'] if c['name'] == 'container-identity')
            self.assertEqual(detail['title_id'], FIFA)
            self.assertEqual(detail['game'], FIFA)
            self.assertEqual(detail['name'], 'FIFA 23 Legacy Edition')

    def test_a_different_game_is_rejected_before_any_command_is_planned(self):
        library = self.root / 'reader.dylib'
        for item in (Path(self.r.base), Path(self.r.keys), library):
            item.write_bytes(b'synthetic')
        from tools.nxrom import resourcefs
        with patch.object(resourcefs, 'ResourceFS') as reader:
            reader.return_value.__enter__.return_value.title = 0x0100FFFFFFFFE000
            result = engine.inspect(replace(self.r, library=str(library)))
        self.assertIn('container-identity', result['issues'])
        detail = next(c['detail'] for c in result['checks'] if c['name'] == 'container-identity')
        self.assertIn('无法识别的游戏', detail)
        self.assertFalse(result['input_checks_passed'])

    def test_incompatible_update_from_native_reader_blocks_inspection(self):
        library = self.root / 'reader.dylib'; update = self.root / 'update.nsp'
        for item in (Path(self.r.base), Path(self.r.keys), library, update):
            item.write_bytes(b'synthetic')
        from tools.nxrom import resourcefs
        with patch.object(resourcefs, 'ResourceFS', side_effect=OSError('wrong title/update')):
            result = engine.inspect(replace(self.r, library=str(library), update=str(update)))
        self.assertIn('container-identity', result['issues'])
        self.assertFalse(result['input_checks_passed'])

    def test_compressed_update_is_named_before_the_mount(self):
        update = self.root / 'update.nsz'; update.write_bytes(b'compressed')
        result = engine.inspect(replace(self.r, update=str(update)))
        detail = next(c['detail'] for c in result['checks'] if c['name'] == 'update')
        self.assertFalse(next(c['ok'] for c in result['checks'] if c['name'] == 'update'))
        self.assertIn('nsz -D', detail)
        self.assertIn('update', result['issues'])

    def test_add_on_content_requires_a_verified_manifest(self):
        aoc = self.root / 'aoc'; aoc.mkdir()
        (aoc / '2').mkdir(); (aoc / '2/data3.big').write_bytes(b'add-on')
        result = engine.inspect(replace(self.r, target='ios', mode='directory', aoc=str(aoc)))
        self.assertIn('aoc', result['issues'])
        from tools.packaging_gui import dlc
        manifest = dict(schema=1, dlcs=[dict(index=2, application=int(FIFA,16),
                         title=int(FIFA,16)+0x1002)], files=dlc.tree_inventory(aoc))
        (aoc / 'manifest.json').write_text(json.dumps(manifest))
        self.assertNotIn('aoc', engine.inspect(replace(self.r, target='ios', mode='directory',
                                                       aoc=str(aoc)))['issues'])

    def test_ios_build_needs_control_data_next_to_the_metadata_folder(self):
        result = engine.inspect(replace(self.r, target='ios'))
        self.assertNotIn('control-nacp', result['issues'])
        (self.exefs.parent / 'control.nacp').unlink()
        self.assertIn('control-nacp', engine.inspect(replace(self.r, target='ios'))['issues'])

    def test_an_unauditable_backend_is_refused_with_its_reason(self):
        request = engine.Request(game=FIFA, target='macos')
        unsupported = replace(registry.by_title(FIFA), graphics_api='vulkan')
        with patch.object(registry, 'by_title', return_value=unsupported):
            result = engine.inspect(request)
        self.assertIn('graphics-api', result['issues'])
        detail = next(c['detail'] for c in result['checks'] if c['name'] == 'graphics-api')
        self.assertIn('audit', detail)


class CacheTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        parts = build_cache(self.root, registry.by_title(FIFA))
        self.profile, self.cache, self.chain, self.version = parts
        from tools.nxrom.shader_package import digest
        (self.root / 'pkg').mkdir(exist_ok=True)
        (self.root / 'pkg/synthetic.bin').write_bytes(b'synthetic package')
        (self.root / 'build-manifest.json').write_text(json.dumps(dict(
            chain=self.version, host_from_source=True,
            libraries={lib.name: digest(lib) for lib in self.cache.glob('*.metallib')})))
        self.r = engine.Request(game=FIFA, cache=str(self.root))

    def test_valid_stamp_and_platform_pass(self):
        result = engine.validate_cache(self.r)
        self.assertEqual(result['chain'], self.version)
        self.assertGreater(result['shader_count'], 0)

    def test_existing_files_do_not_override_bad_stamp(self):
        (self.cache / 'inputs.tsv').write_text('game\twrong\ninputs\twrong\n')
        with self.assertRaisesRegex(ValueError, 'inputs.tsv'):
            engine.validate_cache(self.r)

    def test_mac_libraries_are_not_accepted_for_ios(self):
        ios = self.root / 'ios/dmsh_b'; ios.mkdir(parents=True)
        shutil.copytree(self.cache, ios / self.cache.name)
        with self.assertRaisesRegex(ValueError, 'platform'):
            engine.validate_cache(replace(self.r, target='ios'))

    def test_missing_library_is_not_a_valid_cache(self):
        next(self.cache.glob('*.metallib')).unlink()
        with self.assertRaisesRegex(ValueError, 'Missing base'):
            engine.validate_cache(self.r)

    def test_stale_profile_table_is_rejected(self):
        (self.profile / 'c1_full.tsv').write_text('# wrong chain and inputs\n')
        with self.assertRaisesRegex(ValueError, 'Stale generated'):
            engine.validate_cache(self.r)

    def test_changed_library_bytes_are_rejected(self):
        lib = next(self.cache.glob('*.metallib'))
        lib.write_bytes(b'MTLB' + bytes(27) + b'x')
        with self.assertRaisesRegex(ValueError, 'bytes differ'):
            engine.validate_cache(self.r)

    def test_package_only_build_cannot_certify_compiled_cache(self):
        (self.root / 'build-manifest.json').unlink()
        with self.assertRaisesRegex(ValueError, 'matching chain manifest'):
            engine.validate_cache(self.r)

    def test_an_easf_cache_needs_its_source_build_package(self):
        shutil.rmtree(self.root / 'pkg')
        with self.assertRaisesRegex(ValueError, 'Shader Package'):
            engine.validate_cache(self.r)


class SourceProviderTests(unittest.TestCase):
    def test_the_provider_is_chosen_by_the_profile(self):
        provider = shader_sources.for_profile(registry.by_title(FIFA))
        self.assertEqual(provider.key, 'easf')
        self.assertTrue(provider.can_generate)

    def test_an_unknown_format_is_refused(self):
        with self.assertRaisesRegex(ValueError, 'Unknown archive_format'):
            shader_sources.for_profile(replace(registry.by_title(FIFA), archive_format='zip'))


if __name__ == '__main__':
    unittest.main()
