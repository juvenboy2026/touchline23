#!/usr/bin/env python3
"""GUI bridge: list the profiles, identify a game, check a build, or run one.

Every action goes through the same generic engine
(`tools/packaging_gui/engine.py`): the game is named by the Title ID the native
reader reports, the profile comes from `dm/games/<title ID>`, and FIFA 23 differs
from any other game only in its profile and its Shader archive format.
"""
import argparse
from dataclasses import fields
import json
from pathlib import Path
import sys
import subprocess

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from tools.packaging_gui.engine import Request, inspect, plan, redact


# Report files this bridge may create inside an executor-owned directory.
REPORTS = ('review.json', 'identify.json', 'check.json', 'games.json', 'settings.json')


def display(value):
    """One check's detail as a single line, whether it is text or a mapping."""
    if isinstance(value, str):
        return value
    if isinstance(value, dict):
        return ' · '.join(f'{k}={v}' for k, v in value.items())
    return str(value)


def summary(checks):
    return [dict(name=c['name'], ok=bool(c['ok']), detail=display(c['detail'])) for c in checks]


def write_report(path, payload):
    if path is None:
        return
    if not (path.parent / 'result.json').is_file() or path.name not in REPORTS:
        raise ValueError('Report requires an executor-owned task directory')
    with path.open('x') as stream:
        json.dump(payload, stream, indent=2, ensure_ascii=False)


def catalog(index=None):
    """-> every registered profile with its capability and its recorded evidence."""
    from tools.packaging_gui import registry
    if index is not None:
        return registry.load_index(index)
    return registry.catalog()


def identify(request):
    from tools.packaging_gui import games, folder
    try:
        request = folder.resolve(request)
    except (OSError, ValueError) as error:
        return dict(ok=False, kind='error', title_id=None, title_hex=None,
                    game=None, name=None, message=str(error))
    found = games.identify(request.base, request.keys, request.library,
                           update=request.update or None)
    if request.automatic and found['ok']:
        from tools.packaging_gui import automatic, registry
        from tools.nxrom.resourcefs import ResourceFS
        try:
            profile = registry.by_key(found['game'])
            with ResourceFS(request.library, base=request.base, update=request.update or None, keys=request.keys) as fs:
                version = automatic.mounted_version(fs, profile)
            found['program_version'] = version
            found['display_version'] = profile.display_of(version)
        except (OSError, ValueError) as exc:
            found['message'] += ' · ' + str(exc)
    return redact(found, request)


def check(request, task):
    """Identify, inspect, plan and review in one interpreter, one report set."""
    from tools.packaging_gui import workflow
    from tools.packaging_gui.workflow import review as build_review
    found = identify(request)
    if not found['ok']:
        return dict(schema=1, identified=found, input_checks_passed=False, checks=[], issues=[],
                    plan=None, execution_allowed=False, disabled_reason=found['message']), None
    # The resource decided which game this is; the plan builds exactly that
    # profile, whatever the caller may have passed as --game.
    request.game = found['game']
    checked = inspect(request)
    try:
        recipe = plan(request, task)
        reviewed = build_review(request, task)
    except (OSError, ValueError, KeyError) as exc:
        return dict(schema=1, identified=found,
                    input_checks_passed=bool(checked['input_checks_passed']),
                    checks=summary(checked['checks']), issues=checked['issues'],
                    plan=None, execution_allowed=False,
                    disabled_reason=str(exc)), None
    # The stage list travels with the review, so the confirmation the human
    # makes and the progress the window shows come from the same plan.
    reviewed['stages'] = workflow.stage_plan(recipe)
    return dict(schema=1, identified=found,
                input_checks_passed=bool(checked['input_checks_passed']),
                checks=summary(checked['checks']), issues=checked['issues'],
                plan=dict(commands=len(recipe['commands']),
                          stages=workflow.stage_plan(recipe),
                          artifact=reviewed['artifact_path'],
                          program_version=recipe['program_version'],
                          shader_source_versions=recipe['shader_source_versions']),
                execution_allowed=reviewed['execution_allowed'],
                disabled_reason=reviewed['disabled_reason']), reviewed


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('games', 'identify', 'inspect', 'plan', 'check', 'review', 'execute', 'cache-status', 'cache-clear', 'tools'))
    parser.add_argument('--expected-bytes', type=int, default=-1)
    parser.add_argument('--prepared-cache')
    parser.add_argument('--prepared-shader-action', choices=('reuse', 'generate'))
    parser.add_argument('--task', help='new task path for recipe preview; never created')
    parser.add_argument('--report', type=Path, help='new report JSON file inside an executor-owned task')
    parser.add_argument('--approval', help='fingerprint from the human-confirmed review')
    parser.add_argument('--keep-work', action='store_true',
                        help='keep this run’s temporary work folder after a failure')
    parser.add_argument('--revision-report', type=Path, help='new revision file inside the executor task')
    parser.add_argument('--games-index', type=Path,
                        help='read the game catalog from a bundle instead of scanning dm/games')
    for field in fields(Request):
        parser.add_argument('--' + field.name.replace('_', '-'), type=int if field.name in ('jobs', 'resource_bytes') else str,
                            default=field.default)
    args = parser.parse_args()
    request = Request(**{f.name: getattr(args, f.name) for f in fields(Request)})
    from contextlib import ExitStack
    with ExitStack() as stack:
      try:
        from tools.packaging_gui import automatic, cache
        if args.action in ('cache-status', 'cache-clear', 'tools'):
            if args.action == 'tools':
                payload = automatic.tool_status()
            elif args.action == 'cache-clear':
                payload = cache.clear(request.cache_root, args.expected_bytes)
            else:
                payload = cache.status(request.cache_root)
            write_report(args.report, payload)
            print(json.dumps(payload))
            return 0
        if request.automatic:
            request.library = str(Path(__file__).resolve().parents[1] / 'bin/nxrom.dylib')
            if args.action not in ('games', 'identify'):
                stack.enter_context(cache.lease(request.cache_root))
                request.task_work = str(Path(args.task or '').resolve() / 'work')
                selection = ((args.prepared_cache, args.prepared_shader_action)
                             if args.action == 'execute' and args.prepared_cache and args.prepared_shader_action else None)
                request = automatic.resolve(request, selection)
        if args.action == 'games':
            payload = catalog(args.games_index)
            write_report(args.report, payload)
            print(json.dumps(payload, ensure_ascii=False, indent=2))
            return 0
        if args.revision_report:
            if args.revision_report.name != 'revision.txt' or not (args.revision_report.parent / 'result.json').is_file():
                raise ValueError('Revision report requires an executor-owned directory')
            from tools.packaging_gui.workflow import git_sha
            with args.revision_report.open('x') as stream:
                stream.write(git_sha() + '\n')
        if args.action == 'identify':
            found = identify(request)
            write_report(args.report, found)
            print(json.dumps(found, ensure_ascii=False, indent=2))
            return 0 if found['ok'] else 1
        if args.action == 'check':
            report, reviewed = check(request, args.task or '')
            if args.report:
                if reviewed is not None:
                    write_report(args.report, reviewed)
                write_report(args.report.parent / 'check.json', redact(report, request))
            print(json.dumps(redact(report, request), ensure_ascii=False, indent=2))
            return 0 if report['execution_allowed'] else 1
        if args.action in ('review', 'execute'):
            from tools.packaging_gui.workflow import review, execute
            if args.action == 'execute':
                execute(request, args.task or '', args.approval, keep_work=args.keep_work)
                return 0
            result = review(request, args.task or '')
            if args.report:
                write_report(args.report, result)
            print(json.dumps(redact(result, request), ensure_ascii=False, indent=2))
            return 0 if result['execution_allowed'] else 1
        result = inspect(request) if args.action == 'inspect' else plan(request, args.task or '')
        print(json.dumps(redact(result, request), ensure_ascii=False, indent=2))
        return 0 if args.action == 'plan' or result['input_checks_passed'] else 1
      except (OSError, ValueError, KeyError, subprocess.CalledProcessError) as exc:
        if args.action == 'check' and args.report:
            found = identify(request)
            report = dict(schema=1, identified=found, input_checks_passed=False,
                          checks=[dict(name='automatic-preparation', ok=False, detail=str(exc))],
                          issues=['automatic-preparation'], plan=None, execution_allowed=False,
                          disabled_reason=str(exc))
            write_report(args.report.parent / 'check.json', redact(report, request))
        print(json.dumps(redact({'error': str(exc), 'execution_enabled': False}, request), ensure_ascii=False))
        return exc.returncode if isinstance(exc, subprocess.CalledProcessError) and 0 < exc.returncode < 256 else 1


if __name__ == '__main__':
    sys.exit(main())
