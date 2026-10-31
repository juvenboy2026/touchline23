#!/usr/bin/env python3
"""Run the source-built FIFA host with an isolated copy of a local save.

Spyder F5 settings below can be filled locally. CLI arguments override settings.
The original save and RomFS are read-only inputs to this launcher. Logs,
control commands, screenshots and game writes belong to the external run dir.
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


def main():
    p = argparse.ArgumentParser(description=__doc__)
    for name, default in [('build', BUILD), ('romfs', ROMFS), ('save-source', SAVE_SOURCE), ('run-dir', RUN_DIR)]:
        p.add_argument('--' + name, type=Path, default=default)
    p.add_argument('--seconds', type=float, default=SECONDS)
    p.add_argument('--keys', default='', help='existing DM_KEYS input sequence')
    a = p.parse_args()
    if any(x is None for x in (a.build, a.romfs, a.save_source, a.run_dir)):
        p.error('--build, --romfs, --save-source and --run-dir are required')
    build, romfs, save, run = (x.resolve() for x in (a.build, a.romfs, a.save_source, a.run_dir))
    if run == REPO or REPO in run.parents or run == save or save in run.parents or run in save.parents:
        p.error('use a separate external run directory, outside the original save')
    if run.exists():
        p.error('--run-dir must be new; this avoids overwriting an earlier test')
    if a.seconds <= 0:
        p.error('--seconds must be positive')
    manifest = json.loads((build / 'build-manifest.json').read_text())
    if not manifest.get('modules_rewritten'):
        p.error('build with --exefs first: this launcher requires freshly rewritten modules')
    run.mkdir(parents=True)
    shutil.copytree(save, run / 'save')
    (run / 'temp').mkdir()
    (run / 'control.txt').touch()
    env = {k: v for k, v in os.environ.items() if not k.startswith('DM_')}
    env.update(DM_GAME=GAME, DM_ROOT=str(run), DM_ROMFS=str(romfs), DM_SAVE=str(run / 'save'),
               DM_TEMP=str(run / 'temp'), DM_GAMES_DIR=str(build / 'profile'), DM_GAMES_FIRST='1',
               DM_NVN_SHMAP=str(build / 'profile' / GAME / 'shader_map.tsv'),
               DM_MSL_DIR=str(build / 'shaders'), DM_WINDOW='1', DM_AUDIO='1',
               DM_CTL=str(run / 'control.txt'), DM_KEYS=a.keys)
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
              'chain': manifest['chain'], 'note': 'Runtime completion alone does not verify visuals or commentary.'}
    (run / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result))
    return 0 if timed_out else rc


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (OSError, ValueError) as error:
        print(f'[RED] FIFA run failed: {error}', file=sys.stderr)
        sys.exit(1)
