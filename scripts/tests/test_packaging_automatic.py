"""Automatic preparation safety and orchestration, without retail compilation."""
from contextlib import contextmanager
from dataclasses import replace
import json
from pathlib import Path
import shutil
import tempfile
import unittest
from unittest.mock import patch

from tools.packaging_gui import automatic, cache, distribution, engine, registry, shader_build, workflow
from scripts.tests.test_packaging_gui import build_cache, write_program, FIFA


class AutomaticTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.cache = self.root / 'custom SSD cache'
        self.managed = cache.namespace(self.cache)
        self.repo = self.root / 'payload'
        (self.repo / 'bin/nx_extract').mkdir(parents=True)
        (self.repo / 'bin/nx_extract/nx_extract.dll').write_bytes(b'extractor fixture')
        self.request = engine.Request(automatic='1', cache_root=str(self.cache),
            base=str(self.root / 'base.xci'), update=str(self.root / 'update.nsp'),
            keys=str(self.root / 'prod.keys'), output=str(self.root))
        for name in ('base.xci', 'update.nsp', 'prod.keys'):
            (self.root / name).write_bytes(b'private fixture')

    def test_all_registered_program_versions_are_detected(self):
        profile = registry.by_key(FIFA)
        for version, _, ids in profile.versions:
            class FS:
                def check_build(self, module, build):
                    if ids[module] != build:
                        raise OSError('mismatch')
            self.assertEqual(automatic.mounted_version(FS(), profile), version)

    def test_unknown_module_build_never_falls_back_to_base(self):
        class FS:
            def check_build(self, *args):
                raise OSError('mismatch')
        with self.assertRaisesRegex(ValueError, 'no registered program version'):
            automatic.mounted_version(FS(), registry.by_key(FIFA))

    def test_extraction_is_program_only_and_reuses_verified_bytes(self):
        for version in ('v196608', 'v0'):
            profile = registry.by_key(FIFA)
            def extract(argv, **kwargs):
                self.assertEqual(argv[-1], '--program-only')
                self.assertIn(self.request.update, argv)
                write_program(Path(argv[-2]) / 'ExeFS', profile, version)
                nacp = bytearray(0x4000)
                display = profile.display_of(version).encode()
                nacp[0x3060:0x3060 + len(display)] = display
                (Path(argv[-2]) / 'control.nacp').write_bytes(nacp)
            with patch.object(engine, 'REPO', self.repo), \
                 patch.object(automatic, 'extractor_command', return_value=['dotnet', 'extractor']), \
                 patch.object(automatic.subprocess, 'run', side_effect=extract) as run:
                first = automatic.program(self.request, self.managed, profile, version)
                self.assertFalse((first / 'RomFS').exists())
                self.assertEqual(engine.detect_program(profile, first / 'ExeFS')[0], version)
                self.assertEqual(automatic.program(self.request, self.managed, profile, version), first)
                self.assertEqual(run.call_count, 1)
                # Preserve corruption for inspection; create and subsequently reuse
                # a new entry instead of repairing bytes under an old identity.
                (first / 'ExeFS/main').write_bytes(b'bad')
                second = automatic.program(self.request, self.managed, profile, version)
                self.assertNotEqual(first, second)
                self.assertEqual(automatic.program(self.request, self.managed, profile, version), second)
                self.assertEqual((first / 'ExeFS/main').read_bytes(), b'bad')
                self.assertEqual(run.call_count, 2)

    def test_same_program_build_does_not_substitute_a_different_package_version(self):
        profile = registry.by_key(FIFA)
        folder = self.root / 'program'; folder.mkdir()
        nacp = bytearray(0x4000); nacp[0x3060:0x3065] = b'1.2.0'
        (folder / 'control.nacp').write_bytes(nacp)
        with self.assertRaisesRegex(ValueError, 'not registered'):
            automatic.control_version(folder, profile, 'v196608')

    def test_failed_extraction_removes_only_its_new_partial_program(self):
        sentinel = self.root / 'keep.xci'; sentinel.write_bytes(b'keep')
        with patch.object(engine, 'REPO', self.repo), \
             patch.object(automatic, 'extractor_command', side_effect=ValueError('missing dotnet')):
            with self.assertRaisesRegex(ValueError, 'missing dotnet'):
                automatic.program(self.request, self.managed, registry.by_key(FIFA), 'v0')
        self.assertEqual(list((self.managed / 'programs').iterdir()), [])
        self.assertEqual(sentinel.read_bytes(), b'keep')

    def test_cold_cache_plans_real_generation_and_output_does_not_change_identity(self):
        profile = registry.by_key(FIFA)
        first = automatic.shader_slot(self.request, self.managed, profile)
        second = automatic.shader_slot(replace(self.request, output='/different/output'), self.managed, profile)
        self.assertEqual(first.cache, second.cache)
        self.assertEqual(first.shader_action, 'generate')
        exefs = write_program(self.root / 'program/ExeFS', profile, 'v196608')
        recipe = engine.plan(replace(first, game=FIFA, exefs=str(exefs)), self.root / 'task')
        self.assertEqual(recipe['commands'][0]['stage'], 'generate-shaders')
        self.assertIn(str(engine.REPO / 'scripts/packaging_shaders.py'), recipe['commands'][0]['argv'])
        self.assertIsNone(workflow.disabled_reason(replace(first, game=FIFA)))

    def test_valid_legacy_cache_is_read_only_and_stale_cache_is_preserved(self):
        profile = registry.by_key(FIFA)
        build_cache(self.cache, profile)
        selected = automatic.shader_slot(self.request, self.managed, profile)
        self.assertEqual(selected.shader_action, 'reuse')
        lib = next((self.cache / 'shaders').rglob('*.metallib'))
        lib.unlink()
        regenerated = automatic.shader_slot(self.request, self.managed, profile)
        self.assertEqual(regenerated.shader_action, 'generate')
        self.assertTrue((self.cache / 'profile').is_dir())
        self.assertNotEqual(regenerated.cache, selected.cache)

    def test_gui_only_profile_metadata_does_not_change_shader_cache_identity(self):
        profile = registry.by_key(FIFA)
        folder, _, _, _ = build_cache(self.cache, profile)
        with (folder / 'game.tsv').open('a') as out:
            out.write('\napp_name\tA different GUI label\n')
        engine.validate_cache(replace(self.request, game=FIFA, cache=str(self.cache)))
        with (folder / 'game.tsv').open('a') as out:
            out.write('\nfps_target\t999\n')
        with self.assertRaisesRegex(ValueError, 'Profile differs'):
            engine.validate_cache(replace(self.request, game=FIFA, cache=str(self.cache)))

    def test_shader_source_version_is_independent_of_selected_update(self):
        profile = registry.by_key(FIFA)
        opened = []
        class FS:
            def __init__(self, library, **kwargs): opened.append(kwargs)
            def check_build(self, module, build):
                if profile.build_ids('v0')[module] != build: raise OSError('wrong version')
            def close(self): pass
        with patch.object(shader_build, 'ResourceFS', FS):
            shader_build.source_mount(self.request, profile, 'v0')
        self.assertIsNone(opened[0]['update'])

    def test_bundled_source_inventory_excludes_tests_keys_and_git(self):
        names = set(distribution.source_files(engine.REPO))
        self.assertIn('dm/gfx/tools/dmsh_xlate_bin/dmsh_xlate.dll', names)
        self.assertIn('dm/host/Makefile', names)
        self.assertIn('scripts/packaging_shaders.py', names)
        self.assertIn('tools/packaging_gui/automatic.py', names)
        self.assertFalse(any('/tests/' in n or n.startswith('.git') or n.endswith(('.keys', '.nsp', '.xci')) for n in names))

    def test_cold_generation_reaches_compiler_validates_both_targets_and_publishes(self):
        profile = registry.by_key(FIFA)
        work = self.root / 'task/work'; work.mkdir(parents=True)
        final = cache.area(self.managed, 'shaders') / 'new-cold-cache'
        request = replace(self.request, game=profile.key, cache=str(final), task_work=str(work))
        calls = []
        def prepare(r, p, output, run):
            (output / 'pkg').mkdir()
            (output / 'pkg/source.bin').write_bytes(b'synthetic shader source')
            return dict(provider='easf', versions=list(p.shader_versions), archives=['synthetic-archive'])
        def compiler(argv, **kwargs):
            calls.append([str(a) for a in argv])
            tool = Path(argv[1]).name
            output = Path(kwargs['env']['DM_ROOT'])
            if tool == 'dmsh_build.py':
                fixture = self.root / 'compiler-fixture'
                build_cache(fixture, profile)
                shutil.copytree(fixture / 'shaders', output / 'shaders')
                shutil.copytree(fixture / 'shaders', output / 'ios/dmsh_b')
                for folder in (output / 'shaders', output / 'ios/dmsh_b'):
                    for reflection in folder.rglob('*_b.json'):
                        record = json.loads(reflection.read_text())
                        record['chain_metal'] = ('iphoneos' if 'ios' in folder.parts else 'macosx') + ' fixture'
                        reflection.write_text(json.dumps(record))
                    if folder == output / 'shaders':
                        from tools.nxrom.prepared_build import shader_keys
                        for chain_dir in folder.iterdir():
                            (chain_dir / '_b_build.json').write_text(json.dumps(
                                [{'key':key,'st':'ok'} for key in shader_keys(profile.game())]))
            elif tool in ('c1_guard.py','cb_extent.py'):
                Path(argv[3]).write_text(engine.chain_tools().table_head(argv[2]) + ' fixture\n')
        from tools.packaging_gui import shader_sources
        with patch.object(shader_sources.EasfSource, 'prepare', side_effect=prepare), \
             patch.object(shader_build.subprocess, 'run', side_effect=compiler):
            shader_build.generate(request)
        self.assertTrue(final.is_dir())
        self.assertTrue(any(Path(row[1]).name == 'dmsh_build.py' for row in calls))
        self.assertEqual(list(work.iterdir()), [])
        for target in ('macos', 'ios'):
            self.assertGreater(engine.validate_cache(replace(request,target=target))['shader_count'],0)
        self.assertFalse(list((final / 'ios').rglob('_b_build.json')),
                         'The real compiler writes only one combined summary')
        # A second approved platform with this same cold plan validates/reuses
        # the complete cache; it cannot re-run the compiler.
        with patch.object(shader_build.subprocess, 'run', side_effect=AssertionError('unexpected rebuild')):
            shader_build.generate(replace(request,target='ios'))

    def test_space_containing_cache_paths_get_a_make_alias_on_the_same_disk(self):
        profile = registry.by_key(FIFA)
        exefs = write_program(self.root / 'ExeFS', profile, 'v0')
        task = self.root / 'external SSD/task'
        task.parent.mkdir()
        recipe = engine.plan(replace(self.request,game=FIFA,exefs=str(exefs),cache='/cache',shader_action='reuse'),task)
        host = next(c for c in recipe['commands'] if c['stage']=='host')
        gen = next(a[4:] for a in host['argv'] if a.startswith('GEN='))
        self.assertNotIn(' ',gen)
        self.assertTrue(gen.startswith('/private/tmp/nxpack-work-'))

    def test_clean_environment_still_supplies_the_system_username(self):
        with patch.dict(workflow.os.environ, {}, clear=True):
            self.assertTrue(workflow.tool_environment(self.root)['USER'])


class CacheSafetyTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(); self.addCleanup(self.temp.cleanup)
        self.folder = Path(self.temp.name).resolve()
        self.root = cache.namespace(self.folder)

    def owned(self, name='entry'):
        item = cache.area(self.root, 'programs') / name
        item.mkdir()
        (item / cache.OWNER).write_text(json.dumps({'owner': cache.NAMESPACE, 'schema': 1}))
        (item / 'data').write_bytes(b'cache')
        return item

    def test_clear_only_owned_entries_never_unrelated_files_or_external_links(self):
        item = self.owned()
        outside = self.folder / 'prod.keys'; outside.write_bytes(b'never delete')
        (item / 'external').symlink_to(outside)
        unknown = self.root / 'programs/user-files'; unknown.mkdir()
        (unknown / 'keep.nsp').write_bytes(b'keep')
        report = cache.status(self.folder)
        cache.clear(self.folder, report['bytes'])
        self.assertFalse(item.exists())
        self.assertEqual(outside.read_bytes(), b'never delete')
        self.assertTrue((unknown / 'keep.nsp').is_file())
        self.assertEqual(cache.status(self.folder)['bytes'], 0)

    def test_namespace_and_area_links_are_refused(self):
        target = self.folder / 'unrelated'; target.mkdir()
        (self.root / 'programs').symlink_to(target)
        with self.assertRaisesRegex(ValueError, 'symbolic link'):
            cache.clear(self.folder, 0)
        self.assertTrue(target.is_dir())

    def test_changed_cache_size_requires_a_new_confirmation(self):
        item = self.owned()
        measured = cache.status(self.folder)['bytes']
        (item / 'data').write_bytes(b'changed')
        with self.assertRaisesRegex(ValueError, 'changed'):
            cache.clear(self.folder, measured)
        self.assertTrue(item.is_dir())

    def test_clear_is_blocked_while_any_process_holds_a_build_lease(self):
        item = self.owned()
        with cache.lease(self.folder):
            with self.assertRaisesRegex(ValueError, 'in use'):
                cache.clear(self.folder, cache.status(self.folder)['bytes'])
        self.assertTrue(item.is_dir())

    def test_unmarked_existing_namespace_is_never_claimed(self):
        (self.root / cache.OWNER).unlink()
        (self.root / 'unrelated').write_bytes(b'keep')
        with self.assertRaisesRegex(ValueError, 'no ownership marker'):
            cache.namespace(self.folder)
        self.assertTrue((self.root / 'unrelated').is_file())

    def test_tool_hints_never_feed_the_build_capability_gate(self):
        with patch.object(automatic.shutil, 'which', return_value=None), \
             patch.object(automatic.subprocess, 'run', side_effect=OSError('missing')):
            self.assertFalse(any(automatic.tool_status().values()))
        self.assertIsNone(workflow.disabled_reason(engine.Request(game=FIFA, automatic='1', shader_action='generate')))


if __name__ == '__main__':
    unittest.main()
