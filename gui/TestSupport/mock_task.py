#!/usr/bin/env python3
"""Authored synthetic process fixtures; no game data or build tools."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import time

p = argparse.ArgumentParser()
p.add_argument('mode')
p.add_argument('--root', type=Path, required=True)
p.add_argument('--secret', default='')
p.add_argument('--repository', type=Path)
a = p.parse_args()
if a.repository:
    revision = subprocess.run(['git', 'rev-parse', 'HEAD'], cwd=a.repository, check=True, capture_output=True, text=True).stdout
    (a.root / 'revision.txt').write_text(revision)
if a.mode == 'success':
    print('finished', flush=True)
elif a.mode == 'logs':
    for i in range(5):
        print('tick ' + str(i), flush=True); time.sleep(0.08)
elif a.mode == 'stderr':
    print('synthetic warning', file=sys.stderr, flush=True)
elif a.mode == 'burst':
    for i in range(10000):
        print('burst-' + str(i) + ' ' + 'x' * 100)
elif a.mode == 'environment':
    (a.root / 'environment.json').write_text(json.dumps({k: os.environ[k] for k in
        ('TMPDIR', 'DOTNET_CLI_HOME', 'CLANG_MODULE_CACHE_PATH', 'SWIFTPM_MODULECACHE_OVERRIDE')}))
    (a.root / 'revision.txt').write_text('a' * 40)
elif a.mode == 'fail':
    print('synthetic failure', file=sys.stderr, flush=True); sys.exit(23)
elif a.mode == 'signal':
    os.kill(os.getpid(), signal.SIGTERM)
elif a.mode == 'secret':
    # Deliberately split the sensitive value across OS writes.
    sys.stdout.write(a.secret[:len(a.secret)//2]); sys.stdout.flush(); time.sleep(0.1)
    print(a.secret[len(a.secret)//2:], flush=True)
    print('aes_key=00112233445566778899aabbccddeeff', file=sys.stderr, flush=True)
elif a.mode in ('long', 'tree', 'ignore', 'orphan'):
    if a.mode == 'ignore':
        signal.signal(signal.SIGINT, signal.SIG_IGN); signal.signal(signal.SIGTERM, signal.SIG_IGN)
    if a.mode in ('tree', 'orphan'):
        child = subprocess.Popen([sys.executable, __file__, 'ignore', '--root', str(a.root)])
        (a.root / 'child.pid').write_text(str(child.pid))
        until = time.monotonic() + 2
        while not (a.root / 'child-ready').exists() and time.monotonic() < until:
            time.sleep(0.01)
    (a.root / ('child-ready' if a.mode == 'ignore' else 'parent.pid')).write_text(str(os.getpid()))
    print('mock group running', flush=True)
    if a.mode == 'orphan':
        sys.exit(0)
    while True:
        (a.root / (str(os.getpid()) + '.heartbeat')).write_text(str(time.monotonic_ns()))
        print('working', flush=True); time.sleep(0.04)
elif a.mode == 'artifact':
    output = a.root / 'synthetic-artifact.txt'; output.write_text('synthetic fixture\n')
    (a.root / 'audit.json').write_text(json.dumps(dict(path=str(output), bytes=output.stat().st_size,
        sha256=hashlib.sha256(output.read_bytes()).hexdigest(), audit={'fixture_checked': True}, game_run_verified=False)))
    print('synthetic artifact audited', flush=True)
