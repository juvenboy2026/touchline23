#!/usr/bin/env python3
"""Run the source-built FIFA host with an isolated copy of a local save.

Spyder F5 settings below can be filled locally. CLI arguments override settings.
The original save and the game resources are read-only inputs to this launcher.
Logs, control commands, screenshots and game writes belong to the external run dir.

--build takes any directory holding a built host: build/work from the wrappers,
or an output directory of scripts/build_fifa23.py. The launcher reads what the
host itself reads (dmhost, patched/<module>.patched.bin, shaders/b-<chain>) and
does not require a build manifest; one is used only to name the chain when it is
there. Resources come either from --romfs (an extracted tree) or from the same
containers the build read (--base [--update] --prod-keys).
"""
BUILD = None
ROMFS = None
SAVE_SOURCE = None
RUN_DIR = None
SECONDS = 900

import argparse
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import time

REPO = Path(__file__).resolve().parents[1]
GAME = '01001C8016B4E000'


def missing_modules(build):
    """-> the profile's modules the rewriter has not written into <build>/patched.

    Every build path writes the rewriter's own <module>.patched.bin and
    <module>.fixups.tsv, so they are what proves the modules were rewritten; a
    manifest would only be written by one of those paths.
    """
    sys.path.insert(0, str(REPO / 'dm/games'))
    import game
    patched = build / 'patched'
    return [n for n in game.load(GAME).words('modules')
            if not (patched / (n + '.patched.bin')).is_file()
            or not (patched / (n + '.fixups.tsv')).is_file()]


def shader_chain(build):
    """-> the chain version this build's library carries, for the result record.

    The manifest names it when the build wrote one; otherwise the single
    b-<chain> directory under shaders is the answer, and a build without one
    (or with several) is recorded as unknown rather than guessed.
    """
    manifest = build / 'build-manifest.json'
    if manifest.is_file():
        try:
            chain = json.loads(manifest.read_text()).get('chain')
        except ValueError:
            chain = None
        if chain:
            return chain
    libraries = sorted((build / 'shaders').glob('b-*'))
    return libraries[0].name[2:] if len(libraries) == 1 else None


def main():
    p = argparse.ArgumentParser(description=__doc__)
    for name, default in [('build', BUILD), ('romfs', ROMFS), ('save-source', SAVE_SOURCE), ('run-dir', RUN_DIR)]:
        p.add_argument('--' + name, type=Path, default=default)
    p.add_argument('--base', type=Path, help='base XCI / NSP: read the resources from the container instead of --romfs')
    p.add_argument('--update', type=Path, help='update NSP laid over --base')
    p.add_argument('--prod-keys', type=Path, help='prod.keys for --base / --update')
    p.add_argument('--seconds', type=float, default=SECONDS)
    p.add_argument('--keys', default='', help='existing DM_KEYS input sequence')
    a = p.parse_args()
    if any(x is None for x in (a.build, a.save_source, a.run_dir)):
        p.error('--build, --save-source and --run-dir are required')
    if (a.romfs is None) == (a.base is None):
        p.error('pass either --romfs (an extracted RomFS) or --base (a container), not both')
    if a.update and not a.base:
        p.error('--update is only read through --base')
    if a.base and not a.prod_keys:
        p.error('--base needs --prod-keys')
    build, save, run = (x.resolve() for x in (a.build, a.save_source, a.run_dir))
    if run == REPO or REPO in run.parents or run == save or save in run.parents or run in save.parents:
        p.error('use a separate external run directory, outside the original save')
    if run.exists():
        p.error('--run-dir must be new; this avoids overwriting an earlier test')
    if a.seconds <= 0:
        p.error('--seconds must be positive')
    if not (build / 'dmhost').is_file():
        p.error(f'{build} holds no dmhost: --build takes a build directory, not an App or an artifact')
    missing = missing_modules(build)
    if missing:
        p.error(f'{build}/patched lacks {", ".join(missing)}: build with --exefs first '
                '(this launcher requires freshly rewritten modules)')
    run.mkdir(parents=True)
    shutil.copytree(save, run / 'save')
    (run / 'temp').mkdir()
    (run / 'control.txt').touch()
    env = {k: v for k, v in os.environ.items() if not k.startswith('DM_')}
    env.update(DM_GAME=GAME, DM_ROOT=str(run), DM_SAVE=str(run / 'save'),
               DM_TEMP=str(run / 'temp'), DM_GAMES_DIR=str(build / 'profile'), DM_GAMES_FIRST='1',
               DM_NVN_SHMAP=str(build / 'profile' / GAME / 'shader_map.tsv'),
               DM_MSL_DIR=str(build / 'shaders'), DM_WINDOW='1', DM_AUDIO='1',
               DM_CTL=str(run / 'control.txt'), DM_KEYS=a.keys)
    # Both resource modes the builders produce: an extracted RomFS tree, or the
    # containers the App and the wrapper builds read (hle_fs.c reads the same
    # variables there).
    if a.base:
        env.update(DM_RESOURCE_BACKEND='nsp', DM_RESOURCE_NSP=str(a.base.resolve()),
                   DM_RESOURCE_KEYS=str(a.prod_keys.resolve()))
        if a.update:
            env['DM_RESOURCE_UPDATE'] = str(a.update.resolve())
    else:
        env.update(DM_RESOURCE_BACKEND='directory', DM_ROMFS=str(a.romfs.resolve()))
    start = time.monotonic()
    with (run / 'runtime.log').open('wb') as log:
        host = subprocess.Popen([str(build / 'dmhost'), str(build / 'patched')], env=env,
                                cwd=run, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
        timed_out = False
        try:
            rc = host.wait(timeout=a.seconds)
        except subprocess.TimeoutExpired:
            timed_out = True
            os.killpg(host.pid, signal.SIGTERM)
            try:
                rc = host.wait(timeout=15)
            except subprocess.TimeoutExpired:
                os.killpg(host.pid, signal.SIGKILL)
                rc = host.wait()
    result = {'exit': rc, 'time_limit_reached': timed_out, 'elapsed_seconds': round(time.monotonic() - start, 1),
              'chain': shader_chain(build), 'note': 'Runtime completion alone does not verify visuals or commentary.'}
    (run / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result))
    return 0 if timed_out else rc


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (OSError, ValueError) as error:
        print(f'[RED] FIFA run failed: {error}', file=sys.stderr)
        sys.exit(1)
