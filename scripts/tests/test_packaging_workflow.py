"""No retail inputs or compilers: test approval boundaries and audit wiring."""
from dataclasses import replace
import hashlib
from contextlib import redirect_stdout
import importlib
import io
import json
import os
from pathlib import Path
import platform
import subprocess
import sys
import tempfile
import types
import unittest
from unittest.mock import patch

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO))
from tools.packaging_gui import engine, registry
from tools.packaging_gui import workflow as w
from tools.packaging_gui.engine import Request, plan

FIFA = '01001C8016B4E000'


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


def cached_profile(marker=''):
    """A Game-like stand-in for the profile copy a completed Shader cache carries."""
    return types.SimpleNamespace(
        get=lambda name, default='': marker if name == 'romfs_marker' else default,
        table=lambda name: Path(name), build_ids=lambda version: {})


class WorkflowTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(); self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        # A run directory lives outside the output folder, which only ever
        # receives the finished App.
        self.run = self.root / 'run'
        self.run.mkdir()
        self.task = self.run / 'task'
        write_program(self.root / 'program/ExeFS', registry.by_title(FIFA), 'v0')
        self.r = Request(game=FIFA, mode='nsp', output=str(self.root), base=str(self.root / 'base.xci'),
                         keys=str(self.root / 'prod.keys'), cache=str(self.root / 'source'),
                         exefs=str(self.root / 'program/ExeFS'))

    def identity(self, **overrides):
        """A fixed, fully installed interpreter so tests never depend on this machine."""
        dependencies = {name: dict(available=True, version='1.0.0', distribution='1.0.0')
                        for name in w.PYTHON_DEPENDENCIES}
        state = dict(executable='/fixture/venv/bin/python3', realpath='/fixture/base/bin/python3.13',
                     version='3.13.0', implementation='CPython', cache_tag='cpython-313',
                     prefix='/fixture/venv', dependencies=dependencies, missing=[])
        state.update(overrides)
        state['missing'] = [name for name, dep in state['dependencies'].items() if not dep['available']]
        return state

    def review(self, r=None, identity=None, task=None):
        request = r or self.r
        # A review reports the version the preflight read from the ExeFS, so the
        # fixture derives it from the synthetic NSO headers instead of naming one.
        profile = registry.by_key(request.game)
        try:
            version, _ = engine.detect_program(profile, request.exefs)
        except (OSError, ValueError):
            # A disabled review is still a review: without a usable ExeFS the
            # version falls back to what the profile registers.
            version = profile.package
        checked = dict(input_checks_passed=True, issues=[], checks=[
            dict(name='container-identity', ok=True,
                 detail=dict(title_id=profile.key, game=profile.key, name=profile.name)),
            dict(name='program-identity', ok=True,
                 detail=dict(version=version, display=profile.display_of(version),
                             modules=list(profile.modules))),
            dict(name='output-space', ok=True, detail=dict(estimated_bytes=8*2**30, free_bytes=20*2**30))])
        with patch.object(w, 'inspect', return_value=checked), patch.object(w, 'verify_tools'), \
             patch.object(w, 'interpreter_identity', return_value=identity or self.identity()), \
             patch.object(w, 'git_sha', return_value='a'*40):
            return w.review(request, task or self.task)

    def owner(self):
        self.task.mkdir()
        (self.task / 'result.json').write_text(json.dumps(dict(context={'kind': 'build'},
            state='running', taskDirectory=str(self.task))))

    def test_capability_matrix_covers_both_targets_and_both_backends(self):
        for target in ('macos', 'ios'):
            for mode in ('directory', 'nsp'):
                r = replace(self.r, target=target, mode=mode)
                self.assertIsNone(w.disabled_reason(r), (target, mode))
                self.assertEqual(r.artifact_name(), 'Touchline 23.ipa' if target == 'ios' else 'Touchline 23.app')
        # The one path whose prerequisites are absent from this environment.
        self.assertIsNotNone(w.disabled_reason(replace(self.r, shader_action='generate')))

    def test_artifact_name_comes_from_the_profile(self):
        self.assertEqual(replace(self.r, target='ios').artifact_name(), 'Touchline 23.ipa')
        self.assertEqual(replace(self.r, target='macos').artifact_name(), 'Touchline 23.app')

    def test_a_profile_the_engine_cannot_audit_is_disabled_with_its_reason(self):
        """Capability, not a name list: a backend with no artifact audit is refused."""
        unsupported = replace(registry.by_title(FIFA), graphics_api='vulkan')
        request = replace(self.r, target='ios')
        with patch.object(registry, 'by_title', return_value=unsupported):
            reason = w.disabled_reason(request)
            self.assertIn('audit', reason)
            self.assertIn('iOS IPA', reason)
            self.assertIn('vulkan', reason, 'the reason names the backend that has no audit')
            report = self.review(request)
            self.assertFalse(report['execution_allowed'], 'a gap is never a selectable option')
            self.assertIn('audit', report['disabled_reason'])
            with self.assertRaisesRegex(ValueError, 'audit'):
                plan(request, self.task)

    def test_add_on_content_is_limited_to_directory_builds(self):
        aoc = self.root / 'aoc'
        aoc.mkdir()
        self.assertIsNone(w.disabled_reason(replace(self.r, target='ios', mode='directory', aoc=str(aoc))))
        for change in (dict(target='ios', mode='nsp', aoc=str(aoc)),
                       dict(target='macos', mode='nsp', aoc=str(aoc))):
            with self.subTest(change=change), self.assertRaisesRegex(ValueError, 'Directory mode'):
                w.review(replace(self.r, **change), self.task)

    def test_ipa_artifact_replaces_the_app_name_and_stays_in_the_output_folder(self):
        report = self.review(replace(self.r, target='ios'))
        self.assertEqual(Path(report['artifact_path']).name, 'Touchline 23.ipa')
        self.assertEqual(Path(report['artifact_path']).parent, self.root)
        self.assertEqual(report['target'], 'ios')

    def test_review_lists_outputs_space_and_separate_versions(self):
        report = self.review()
        self.assertTrue(report['execution_allowed'])
        self.assertEqual(report['shader_source_versions'], ['v0'])
        self.assertEqual(report['program_version'], 'v0')
        self.assertEqual(Path(report['artifact_path']).name, 'Touchline 23.app')
        self.assertEqual(Path(report['artifact_path']).parent, self.root,
                         'the App is published next to the game file, not in the run directory')
        self.assertGreater(report['estimated_bytes'], 0)
        self.assertFalse(self.task.exists())

    def test_changed_selection_or_file_metadata_invalidates_confirmation(self):
        Path(self.r.base).write_bytes(b'synthetic')
        first = self.review()['fingerprint']
        Path(self.r.base).write_bytes(b'changed synthetic')
        self.assertNotEqual(first, self.review()['fingerprint'])
        self.assertNotEqual(self.review()['fingerprint'], self.review(replace(self.r, update=str(self.root / 'update.nsp')))['fingerprint'])

    def test_review_records_the_interpreter_that_would_run_the_build(self):
        interpreter = self.review()['interpreter']
        self.assertEqual(interpreter['realpath'], '/fixture/base/bin/python3.13')
        self.assertEqual(interpreter['version'], '3.13.0')
        self.assertEqual(interpreter['implementation'], 'CPython')
        self.assertEqual(sorted(interpreter['dependencies']), ['capstone', 'fontTools', 'lz4.block'])
        self.assertEqual(interpreter['dependencies']['fontTools']['version'], '1.0.0')
        self.assertEqual(interpreter['missing'], [])

    def test_changed_task_directory_invalidates_confirmation(self):
        approved = self.review()['fingerprint']
        self.assertNotEqual(approved, self.review(task=self.run / 'other')['fingerprint'])
        self.assertFalse((self.run / 'other').exists())

    def test_generator_or_auditor_change_invalidates_confirmation(self):
        approved = self.review()['fingerprint']
        original = w.digest
        for relative in ('dm/ios/tools/gen_build.py', 'tools/nxrom/prepared_build.py'):
            with self.subTest(source=relative), patch.object(w, 'digest', side_effect=lambda p:
                    'changed-source' if Path(p) == REPO / relative else original(p)):
                self.assertNotEqual(approved, self.review()['fingerprint'])

    def test_review_fingerprint_is_the_only_digest_shown(self):
        from tools.packaging_gui.engine import redact
        fingerprint = hashlib.sha256(b'approved').hexdigest()
        payload = dict(fingerprint=fingerprint, task_directory='/game/gui-task-build-x',
                       inputs={'base': 'FIFA.xci'}, shader={'files': 'a' * 64},
                       notes='digest ' + 'b' * 64)
        safe = redact(payload, self.r)
        self.assertEqual(safe['fingerprint'], fingerprint)
        self.assertEqual(safe['shader']['files'], '<redacted-digest-or-key>')
        self.assertIn('<redacted-digest-or-key>', safe['notes'])

    def test_redaction_only_restores_the_named_review_field(self):
        from tools.packaging_gui.engine import redact
        self.assertNotIn('fingerprint', redact(dict(input_checks_passed=True), self.r))
        # A non-hex value in that field is never restored.
        self.assertEqual(redact(dict(fingerprint='not a digest'), self.r)['fingerprint'], 'not a digest')

    def test_review_does_not_store_console_key_path_or_content(self):
        Path(self.r.keys).write_text('synthetic-key-content-not-for-history')
        encoded = json.dumps(self.review())
        self.assertNotIn(self.r.keys, encoded)
        self.assertNotIn('synthetic-key-content-not-for-history', encoded)

    def test_failed_preflight_disables_review(self):
        with patch.object(w, 'inspect', return_value=dict(input_checks_passed=False, issues=['container-identity'], checks=[])), \
             patch.object(w, 'interpreter_identity', return_value=self.identity()), \
             patch.object(w, 'git_sha', return_value='a'*40):
            self.assertFalse(w.review(self.r, self.task)['execution_allowed'])

    def test_tool_lock_failure_disables_review_without_updating_lock(self):
        with patch.object(w, 'inspect', return_value=dict(input_checks_passed=True, issues=[], checks=[])), \
             patch.object(w, 'interpreter_identity', return_value=self.identity()), \
             patch.object(w, 'verify_tools', side_effect=ValueError('tool lock mismatch')), \
             patch.object(w, 'git_sha', return_value='a'*40):
            report = w.review(self.r, self.task)
        self.assertFalse(report['execution_allowed']); self.assertIn('lock mismatch', report['disabled_reason'])

    def test_interpreter_identity_describes_this_process(self):
        actual = w.interpreter_identity()
        self.assertEqual(actual['executable'], sys.executable)
        self.assertEqual(actual['realpath'], os.path.realpath(sys.executable))
        self.assertEqual(actual['version'], platform.python_version())
        self.assertEqual(actual['implementation'], platform.python_implementation())
        self.assertEqual(actual['prefix'], sys.prefix)
        self.assertEqual(sorted(actual['dependencies']), ['capstone', 'fontTools', 'lz4.block'])
        self.assertEqual(actual['missing'],
                         [n for n, dep in actual['dependencies'].items() if not dep['available']])
        for name, dep in actual['dependencies'].items():
            if dep['available']:
                self.assertTrue(dep['version'] or dep['distribution'], name)

    def test_unimportable_dependency_is_reported_as_missing(self):
        real = importlib.import_module

        def fake(name, *args, **kwargs):
            if name == 'lz4.block':
                raise ImportError('No module named lz4')
            return real(name, *args, **kwargs)

        with patch('importlib.import_module', side_effect=fake):
            actual = w.interpreter_identity()
        self.assertEqual(actual['missing'], ['lz4.block'])
        self.assertFalse(actual['dependencies']['lz4.block']['available'])
        self.assertIsNone(actual['dependencies']['lz4.block']['version'])
        self.assertIn('lz4', actual['dependencies']['lz4.block']['error'])

    def test_changed_interpreter_or_dependency_version_invalidates_confirmation(self):
        approved = self.review()['fingerprint']
        for change in (dict(executable='/other/venv/bin/python3'),
                       dict(realpath='/other/base/bin/python3.13'),
                       dict(version='3.13.1'), dict(implementation='PyPy'),
                       dict(prefix='/other/venv'), dict(cache_tag='cpython-314')):
            with self.subTest(change=change):
                self.assertNotEqual(approved, self.review(identity=self.identity(**change))['fingerprint'])
        dependencies = {name: dict(available=True, version='1.0.0', distribution='1.0.0')
                        for name in w.PYTHON_DEPENDENCIES}
        dependencies['capstone'] = dict(available=True, version='1.0.1', distribution='1.0.1')
        changed = self.review(identity=self.identity(dependencies=dependencies))['fingerprint']
        self.assertNotEqual(approved, changed)
        # Identical input and identical environment must reproduce the fingerprint.
        self.assertEqual(approved, self.review()['fingerprint'])

    def test_missing_dependency_blocks_execution_even_when_inputs_pass(self):
        dependencies = {name: dict(available=True, version='1.0.0', distribution='1.0.0')
                        for name in w.PYTHON_DEPENDENCIES}
        dependencies['lz4.block'] = dict(available=False, version=None, distribution=None,
                                         error='No module named lz4')
        report = self.review(identity=self.identity(dependencies=dependencies))
        self.assertFalse(report['execution_allowed'])
        self.assertIn('lz4.block', report['disabled_reason'])
        self.assertEqual(report['interpreter']['missing'], ['lz4.block'])

    def test_unapproved_execution_never_runs_commands(self):
        self.owner()
        with patch.object(w, 'review', return_value=dict(execution_allowed=True, fingerprint='expected')), \
             patch.object(w.subprocess, 'run') as run:
            for approval in (None, 'stale'):
                with self.assertRaisesRegex(ValueError, 'confirmation'):
                    w.execute(self.r, self.task, approval)
            run.assert_not_called()
        self.assertFalse((self.task / 'work').exists())

    def test_existing_build_products_are_never_overwritten(self):
        self.owner(); (self.task / 'work').mkdir(); marker = self.task / 'work/keep'; marker.write_text('keep')
        with self.assertRaisesRegex(ValueError, 'no build products'):
            w.execute(self.r, self.task, 'anything')
        self.assertEqual(marker.read_text(), 'keep')

    def test_review_refuses_a_run_directory_inside_the_output_folder(self):
        inside = self.root / 'inner'
        inside.mkdir()
        with self.assertRaisesRegex(ValueError, 'outside the output folder'):
            self.review(task=inside)

    def test_review_refuses_a_task_that_already_has_a_work_folder(self):
        self.owner(); (self.task / 'work').mkdir()
        with self.assertRaisesRegex(ValueError, 'build products'):
            self.review()

    def test_executor_owner_required(self):
        self.owner(); (self.task / 'result.json').write_text('{}')
        with self.assertRaisesRegex(ValueError, 'active build'):
            w.execute(self.r, self.task, 'anything')

    def test_environment_drops_diagnostic_and_prefill_state(self):
        with patch.dict(w.os.environ, DM_ENV_FILE='private', DMSH_PREFILL='old', IOSOUT='wrong', XLATE_DEBUG='0'):
            env = w.tool_environment(self.task)
        for name in ('DM_ENV_FILE', 'DMSH_PREFILL', 'IOSOUT', 'XLATE_DEBUG'):
            self.assertNotIn(name, env)
        self.assertTrue(Path(env['DOTNET_CLI_HOME']).is_relative_to(self.task))

    def test_ios_preview_isolated_actual_and_configuration_derived_data(self):
        recipe = plan(replace(self.r, target='ios'), self.task)
        env = recipe['commands'][-1]['environment']
        # build_ipa.sh uses O=$W/build/ios/pkg and DD=$O/dd for the unsigned build.
        actual = Path(env['W']) / 'build/ios/pkg/dd'
        self.assertTrue(actual.is_relative_to(self.task))
        self.assertTrue(Path(env['DM_IOS_BUILD_DIR']).is_relative_to(self.task))
        self.assertTrue(Path(env['DM_XCODE_DERIVED_DATA']).is_relative_to(self.task))
        self.assertFalse(Path(env['DM_IOS_BUILD_DIR']).exists())

    def font(self):
        path = self.root / 'font.ttf'
        path.write_bytes(b'font fixture')
        return path

    def recipe(self, commands, app=None):
        artifact = str(app or (self.task / 'work' / 'FIFA 23.app'))
        return dict(commands=commands, preparation={'font_copy': {'source': str(self.font())}},
                    artifact=artifact, artifact_name=Path(artifact).name)

    def test_failure_keeps_the_run_record_and_removes_only_its_work_folder(self):
        self.owner()
        recipe = self.recipe([dict(stage='mock', argv=['/usr/bin/false'], environment={})])
        with patch.object(w, 'review', return_value=dict(execution_allowed=True, fingerprint='approved')), \
             patch.object(w, 'plan', return_value=recipe), patch.object(w, 'audit') as audit, \
             patch.object(w.subprocess, 'run', side_effect=subprocess.CalledProcessError(7, ['synthetic'])), \
             redirect_stdout(io.StringIO()):
            with self.assertRaises(subprocess.CalledProcessError):
                w.execute(self.r, self.task, 'approved')
            audit.assert_not_called()
        self.assertFalse((self.task / 'work').exists(), 'large intermediates are not kept by default')
        failed = json.loads((self.task / 'failure.json').read_text())
        self.assertEqual(failed['stage'], 'mock')
        self.assertEqual(failed['exit_code'], 7)
        self.assertTrue(failed['work_removed'])
        self.assertFalse(failed['work_retained'])
        self.assertTrue((self.task / 'result.json').exists(), 'the run record stays')

    def test_failure_can_retain_work_when_explicitly_requested(self):
        self.owner()
        recipe = self.recipe([dict(stage='mock', argv=['/usr/bin/false'], environment={})])
        with patch.object(w, 'review', return_value=dict(execution_allowed=True, fingerprint='approved')), \
             patch.object(w, 'plan', return_value=recipe), \
             patch.object(w.subprocess, 'run', side_effect=subprocess.CalledProcessError(7, ['synthetic'])), \
             redirect_stdout(io.StringIO()):
            with self.assertRaises(subprocess.CalledProcessError):
                w.execute(self.r, self.task, 'approved', keep_work=True)
        self.assertTrue((self.task / 'work/font/standard.ttf').exists())
        self.assertTrue(json.loads((self.task / 'failure.json').read_text())['work_retained'])

    def test_success_publishes_next_to_the_game_then_removes_work(self):
        self.owner()
        app = self.task / 'work' / 'FIFA 23.app'
        script = 'mkdir -p "%s/Contents" && printf published > "%s/Contents/Info.plist"' % (app, app)
        recipe = self.recipe([dict(stage='package-app', argv=['/bin/sh', '-c', script], environment={})])
        digest = {'value': None}

        def fake_audit(r, task, artifact, inventory_path=None):
            entries, summary = w.inventory(Path(artifact))
            digest['value'] = summary
            Path(inventory_path).write_text(json.dumps(entries))
            return dict(path=str(artifact), bytes=sum(e['bytes'] for e in entries), sha256=summary,
                        audit=dict(layout=True), game_run_verified=False)

        output = io.StringIO()
        with patch.object(w, 'review', return_value=dict(execution_allowed=True, fingerprint='approved')), \
             patch.object(w, 'plan', return_value=recipe), patch.object(w, 'audit', side_effect=fake_audit), \
             redirect_stdout(output):
            report = w.execute(self.r, self.task, 'approved')
        published = self.root / 'FIFA 23.app'
        self.assertEqual(Path(report['path']), published)
        self.assertEqual((published / 'Contents/Info.plist').read_text(), 'published')
        self.assertEqual(report['sha256'], digest['value'])
        self.assertFalse((self.task / 'work').exists())
        self.assertTrue((self.task / 'audit.json').exists())
        self.assertTrue((self.task / 'artifact-files.json').exists())
        self.assertTrue(json.loads((self.task / 'summary.json').read_text())['work_removed'])
        self.assertFalse(json.loads((self.task / 'audit.json').read_text())['game_run_verified'])
        stages = [line[len('@@NX_STAGE@@'):].strip() for line in output.getvalue().splitlines()
                  if line.startswith('@@NX_STAGE@@')]
        self.assertEqual(stages, [s['key'] for s in w.stage_plan(recipe) if s['key'] != 'revalidate'])

    def test_existing_app_next_to_the_game_is_never_overwritten(self):
        self.owner()
        existing = self.root / 'FIFA 23.app'
        existing.mkdir()
        (existing / 'keep.txt').write_text('keep')
        app = self.task / 'work' / 'FIFA 23.app'
        script = 'mkdir -p "%s/Contents" && printf second > "%s/Contents/Info.plist"' % (app, app)
        recipe = self.recipe([dict(stage='package-app', argv=['/bin/sh', '-c', script], environment={})])

        def fake_audit(r, task, artifact, inventory_path=None):
            entries, summary = w.inventory(Path(artifact))
            Path(inventory_path).write_text(json.dumps(entries))
            return dict(path=str(artifact), bytes=1, sha256=summary, audit=dict(layout=True),
                        game_run_verified=False)

        with patch.object(w, 'review', return_value=dict(execution_allowed=True, fingerprint='approved')), \
             patch.object(w, 'plan', return_value=recipe), patch.object(w, 'audit', side_effect=fake_audit), \
             redirect_stdout(io.StringIO()):
            report = w.execute(self.r, self.task, 'approved')
        self.assertEqual(Path(report['path']), self.root / 'FIFA 23 (2).app')
        self.assertEqual((existing / 'keep.txt').read_text(), 'keep')

    def test_publish_removes_only_its_own_copy_when_the_bytes_differ(self):
        built = self.root / 'built'
        built.mkdir()
        (built / 'x').write_text('x')
        with patch.object(w, 'inventory', return_value=([{'path': 'x'}], 'f' * 64)):
            with self.assertRaisesRegex(ValueError, 'differ'):
                w.publish({'sha256': 'a' * 64}, built, self.root)
        self.assertFalse((self.root / 'FIFA 23.app').exists())

    def test_publish_copies_an_ipa_as_one_file_and_verifies_its_sha256(self):
        from tools.nxrom.shader_package import digest
        built = self.root / 'FIFA 23.ipa'
        built.write_bytes(b'PK synthetic ipa')
        report = {'sha256': digest(built)}
        (self.root / 'out').mkdir(); (self.root / 'bad').mkdir()
        final = w.publish(report, built, self.root / 'out', 'FIFA 23.ipa')
        self.assertEqual(final, self.root / 'out/FIFA 23.ipa')
        self.assertEqual(final.read_bytes(), built.read_bytes())
        # A second publication never overwrites the first one.
        self.assertEqual(w.publish(report, built, self.root / 'out', 'FIFA 23.ipa').name, 'FIFA 23 (2).ipa')
        with self.assertRaisesRegex(ValueError, 'differ'):
            w.publish({'sha256': 'a' * 64}, built, self.root / 'bad', 'FIFA 23.ipa')
        self.assertFalse((self.root / 'bad/FIFA 23.ipa').exists())

    def test_ios_audit_reuses_the_existing_ipa_auditor(self):
        work = self.root / 'work'; work.mkdir()
        cache = Path(self.r.cache) / 'ios/dmsh_b/b-fixture'; cache.mkdir(parents=True)
        (cache / 'inputs.tsv').write_text('stamp')
        (cache / 'sample.metallib').write_bytes(b'MTLB' + bytes(28))
        ipa = work / 'FIFA 23.ipa'; ipa.write_bytes(b'PK synthetic ipa')
        from tools.nxrom import prepared_build
        from tools.nxrom.shader_package import digest
        with patch.object(w, 'validate_cache', return_value={'chain': 'fixture'}), \
             patch.object(w, 'cached_game', return_value=cached_profile()), \
             patch.object(prepared_build, 'audit_ipa', return_value={'bytes': ipa.stat().st_size}) as ipa_audit:
            result = w.audit(replace(self.r, target='ios'), work, ipa)
        kwargs = ipa_audit.call_args.kwargs
        self.assertEqual(kwargs['backend'], 'nsp')
        self.assertEqual(kwargs['expected_bundle_id'], 'com.ohxiaoguang.touchline23')
        self.assertEqual(kwargs['shader']['inputs_sha256'], digest(cache / 'inputs.tsv'))
        self.assertEqual(kwargs['resources'], {})
        self.assertEqual(list(kwargs['shader']['files_sha256']), ['sample.metallib'])
        self.assertEqual(result['sha256'], digest(ipa))
        self.assertTrue(result['audit']['ipa_crc'])
        self.assertTrue(result['audit']['no_bundled_game_data'])
        self.assertTrue(all(result['audit'].values()))

    def test_ios_directory_audit_reports_only_passed_applicable_checks(self):
        work = self.root / 'work'; work.mkdir()
        cache = Path(self.r.cache) / 'ios/dmsh_b/b-fixture'; cache.mkdir(parents=True)
        (cache / 'inputs.tsv').write_text('stamp')
        romfs = self.root / 'RomFS'; romfs.mkdir()
        (romfs / 'data3.big').write_bytes(b'game data')
        ipa = work / 'FIFA 23.ipa'; ipa.write_bytes(b'PK synthetic ipa')
        from tools.nxrom import prepared_build
        with patch.object(w, 'validate_cache', return_value={'chain': 'fixture'}), \
             patch.object(w, 'cached_game', return_value=cached_profile('data3.big')), \
             patch.object(prepared_build, 'audit_ipa', return_value={}) as ipa_audit:
            result = w.audit(replace(self.r, target='ios', mode='directory', romfs=str(romfs)), work, ipa)
        self.assertEqual(set(ipa_audit.call_args.kwargs['resources']), {'romfs/data3.big'})
        self.assertTrue(result['audit']['bundled_game_data'])
        self.assertNotIn('addon_content', result['audit'])
        self.assertNotIn('no_bundled_game_data', result['audit'])
        self.assertTrue(all(result['audit'].values()))

    def test_macos_directory_audit_states_its_backend_and_marker(self):
        work = self.root / 'work'; work.mkdir()
        cache = Path(self.r.cache) / 'shaders/b-fixture'; cache.mkdir(parents=True)
        (cache / 'inputs.tsv').write_text('stamp')
        (cache / 'sample.metallib').write_bytes(b'MTLB' + bytes(28))
        app = work / 'FIFA 23.app'
        stamp = app / 'Contents/Resources/msl/b-fixture/inputs.tsv'
        stamp.parent.mkdir(parents=True); stamp.write_text('stamp')
        from tools.nxrom import mac_build
        from scripts import build_mac_app
        with patch.object(w, 'validate_cache', return_value={'chain': 'fixture'}), \
             patch.object(w, 'cached_game', return_value=cached_profile('data3.big')), \
             patch.object(mac_build, 'audit_app', return_value={'bytes': 5}) as byte_audit, \
             patch.object(build_mac_app, 'audit') as layout_audit:
            result = w.audit(replace(self.r, mode='directory'), work, app)
        self.assertTrue(all(result['audit'].values()))
        self.assertEqual(byte_audit.call_args.kwargs['backend'], 'directory')
        self.assertEqual(byte_audit.call_args.kwargs['romfs_marker'], 'data3.big')
        self.assertEqual(layout_audit.call_args.args[1:3], ('directory', 'data3.big'))

    def test_cleanup_only_accepts_this_runs_own_work_folder(self):
        other = self.run / 'other'
        other.mkdir()
        (other / 'keep').write_text('keep')
        self.assertFalse(w.discard_work(other))
        self.assertTrue((other / 'keep').exists())
        self.assertFalse(w.discard_work(self.run))
        self.owner()
        (self.task / 'work').mkdir()
        (self.task / 'work/intermediate.bin').write_text('x')
        self.assertTrue(w.discard_work(self.task / 'work'))
        self.assertFalse((self.task / 'work').exists())

    def test_audit_reuses_existing_auditors_and_writes_deterministic_inventory(self):
        work = self.root / 'work'; work.mkdir()
        cache = Path(self.r.cache) / 'shaders/b-fixture'; cache.mkdir(parents=True)
        (cache / 'inputs.tsv').write_text('stamp')
        (cache / 'sample.metallib').write_bytes(b'MTLB fixture')
        app = work / 'FIFA 23.app'
        stamp = app / 'Contents/Resources/msl/b-fixture/inputs.tsv'
        stamp.parent.mkdir(parents=True); stamp.write_text('stamp')
        from tools.nxrom import mac_build
        from scripts import build_mac_app
        with patch.object(w, 'validate_cache', return_value={'chain': 'fixture'}), \
             patch.object(w, 'cached_game', return_value=cached_profile()), \
             patch.object(mac_build, 'audit_app', return_value={'bytes': 5}) as byte_audit, \
             patch.object(build_mac_app, 'audit') as layout_audit:
            result = w.audit(self.r, work, app)
        byte_audit.assert_called_once(); layout_audit.assert_called_once()
        entries = json.loads((work / 'artifact-files.json').read_text())
        expected = hashlib.sha256(json.dumps(entries, sort_keys=True, separators=(',', ':')).encode()).hexdigest()
        self.assertEqual(result['sha256'], expected); self.assertFalse(result['game_run_verified'])

    def test_bridge_preserves_underlying_nonzero_exit_status(self):
        from scripts import packaging_gui as cli
        with patch.object(sys, 'argv', ['packaging_gui.py', 'execute', '--task', str(self.task)]), \
             patch.object(w, 'execute', side_effect=subprocess.CalledProcessError(23, ['synthetic'])), \
             redirect_stdout(io.StringIO()):
            self.assertEqual(cli.main(), 23)


if __name__ == '__main__':
    unittest.main()
