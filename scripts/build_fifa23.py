#!/usr/bin/env python3
"""Build FIFA 23 compatibility shaders and the Mac host from local inputs.

F5 in Spyder uses the settings below; CLI arguments override them. This consumes
shader archives, not historical metallibs/overlays. Game extraction uses the
existing NSP workflow; optional module rewriting calls the existing rewriter.

The shader archives arrive either as files (--archives) or, without extracting
anything, from a mounted game image (--base [--update] --keys): FIFA 23 keeps
both of them as BIG4 members of RomFS `datax.big`.

The EASF key is discovered in the game's own program module (easf/keyfind.py)
by default -- from --exefs/main, from --key-module, or from the code section
nx_extract writes out of --base (--manifest leaves the RomFS on the image) --
and is only used once it reproduces the container's header digest. --key-file
stays the explicit private source, is consulted first, and is the fallback when
no module is available. No key is written to the log or the manifest.

The manifest names the source revision when this tree is a Git checkout. A
downloaded source archive has no .git: it builds the same way and records null
there instead of failing at the last step.
"""
# ---- Spyder settings (keep local paths out of committed source) ----
ARCHIVES = []       # shader.big and shaderboot.big (BIG4, chunkzip or EASF)
BASE = None         # or read the archives out of this XCI / base NSP
UPDATE = None       # update NSP laid over BASE (optional)
KEYS = None         # prod.keys for BASE / UPDATE
OUTPUT = None       # dedicated external build directory
KEY_FILE = None     # private JSON for EASF inputs: used first, and the fallback
KEY_MODULES = []    # extra NSO0 modules to discover the EASF key in
DISCOVER_KEYS = True  # discover the EASF key in the game's own module
JOBS = 4
EXEFS = None       # extracted original NSOs; optional, for source module regeneration

# FIFA 23 keeps both shader archives inside one RomFS file; these are its members.
DATAX = 'datax.big'
MEMBERS = ('data/fifarna/shader.big', 'data/fifarna/shaderboot.big')

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

REPO = Path(__file__).resolve().parents[1]
GAME = '01001C8016B4E000'
TOOLS = REPO / 'dm/gfx/tools'


def builds(profile):
    """-> [(version, main build id, sdk build id)] from the copied game.tsv."""
    rows = []
    for line in (profile / 'game.tsv').read_text().splitlines():
        if line.startswith('#') or not line.strip():
            continue
        column = line.split('\t')
        if column[0] != 'build':
            continue
        ids = dict(x.split('=', 1) for x in column[3:] if '=' in x)
        rows.append((column[1], ids['main'], ids['sdk']))
    return rows


def identify(fs, profile):
    """-> the profile version this image actually holds (both modules must match)."""
    for version, main, sdk in builds(profile):
        try:
            fs.check_build('main', main)
            fs.check_build('sdk', sdk)
            return version
        except OSError:
            continue
    return None


def source_state():
    """-> (revision, dirty) of this checkout, or (None, None) when it is not one.

    A source archive downloaded from a release or a Git host's "Download ZIP"
    has no .git directory, and Git may not be installed at all; neither says
    anything about the build, so the manifest records null rather than failing.
    """
    try:
        revision = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=REPO, text=True,
                                           stderr=subprocess.DEVNULL).strip()
        dirty = bool(subprocess.check_output(['git', 'status', '--porcelain'], cwd=REPO,
                                             text=True, stderr=subprocess.DEVNULL))
    except (OSError, subprocess.CalledProcessError):
        return None, None
    return revision, dirty


def code_exefs(a, out, env):
    """-> the ExeFS directory of --base, extracted by the existing nx_extract.

    `--manifest` writes the code section and a RomFS *listing* only: every shader
    byte still comes from the mount, so nothing is unpacked for the key. The
    folder is reused while it records the same base, update and extractor.
    """
    target = out / 'easf-exefs'
    marker = target / 'source.json'
    source = {'base': str(a.base.resolve()), 'base_size': a.base.stat().st_size,
              'update': str(a.update.resolve()) if a.update else None}
    if (target / 'ExeFS/main').is_file() and marker.is_file():
        if json.loads(marker.read_text()).get('source') == source:
            print(f'[note] EASF key module from the code section already in {target / "ExeFS"}')
            return target / 'ExeFS'
    executable = a.nsp_extractor or (out / 'tools/nx_extract/nx_extract')
    if not executable.is_file():
        sys.path.insert(0, str(REPO / 'scripts'))   # the repository's own builder, no new dependency
        import build_ipa_from_nsp as pipeline
        (out / 'logs').mkdir(parents=True, exist_ok=True)
        print('[note] building nx_extract to read the game\'s code section')
        executable = pipeline.build_nx_extract(REPO, out, out / 'logs', env)
    subprocess.run([str(executable), str(a.keys), str(a.base), str(a.update or '-'),
                    str(target), '--manifest'], env=env, check=True)
    if not (target / 'ExeFS/main').is_file():
        raise ValueError(f'{target} holds no ExeFS/main after nx_extract')
    marker.write_text(json.dumps({'source': source, 'extractor': str(executable)}, indent=2) + '\n')
    return target / 'ExeFS'


def key_modules(a, out, env):
    """-> the NSO0 modules to discover the EASF key in, cheapest source first.

    An ExeFS the build already has is read as it is; --key-module entries are
    taken as given; only a --base without either needs its code section
    extracted, and only then is nx_extract built or run.
    """
    modules = [Path(m) for m in a.key_module]
    exefs = Path(a.exefs) if a.exefs else None
    if exefs is None and a.base and not modules:
        exefs = code_exefs(a, out, env)
    if exefs is not None:
        main = exefs / 'main'
        if not main.is_file():
            raise ValueError(f'{exefs} holds no main module')
        modules.insert(0, main)
    return modules


def image_inputs(a, profile):
    """-> ([(member name, bytes)], info) read from --base/--update, nothing extracted.

    The mount is read-only and every read still passes IVFC; the archives stay
    inside the image and only the two member byte ranges are copied to memory.
    """
    sys.path.insert(0, str(REPO / 'tools/nxrom'))
    from resourcefs import ResourceFS, build_library
    sys.path.insert(0, str(TOOLS / 'easf'))
    import nximage
    library = a.out / 'nxrom.dylib'
    build_library(library)
    digest = hashlib.sha256()
    inputs = []
    with ResourceFS(library, base=a.base, update=a.update, keys=a.keys, title=int(GAME, 16)) as fs:
        version = identify(fs, profile)
        with fs.open(a.datax, buffering=0) as f:   # the mount caps a read at 1 MiB
            while True:
                piece = f.read(1 << 20)
                if not piece:
                    break
                digest.update(piece)
        for name in a.member:
            inputs.append((Path(name).name, nximage.member(fs, a.datax, name)))
    return inputs, {'base': str(a.base), 'update': str(a.update) if a.update else None,
                    'container': a.datax, 'container_sha256': digest.hexdigest(),
                    'version': version}


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--archives', nargs='+', type=Path, default=ARCHIVES)
    p.add_argument('--base', type=Path, default=BASE, help='XCI / base NSP to read the shader archives from')
    p.add_argument('--update', type=Path, default=UPDATE, help='update NSP laid over --base')
    p.add_argument('--keys', type=Path, default=KEYS, help='prod.keys for --base / --update')
    p.add_argument('--datax', default=DATAX, help=f'RomFS file holding the archives (default {DATAX})')
    p.add_argument('--member', action='append', default=None, help='BIG4 member to read; repeatable')
    p.add_argument('--out', type=Path, default=OUTPUT)
    p.add_argument('--key-file', type=Path, default=KEY_FILE,
                   help='private JSON key file: used first, and the fallback without a module')
    p.add_argument('--key-module', action='append', default=list(KEY_MODULES), type=Path,
                   help='NSO0 module to discover the EASF key in; repeatable')
    p.add_argument('--no-key-discovery', dest='discover_keys', action='store_false',
                   default=DISCOVER_KEYS, help='only use --key-file')
    p.add_argument('--key-scan', action='store_true',
                   help='allow the bounded read-only-segment scan when the key ID is not found verbatim')
    p.add_argument('--nsp-extractor', type=Path,
                   help='existing nx_extract executable, instead of building one for --base')
    p.add_argument('--exefs', type=Path, default=EXEFS, help='optional extracted ExeFS: rewrite main and sdk from NSO inputs')
    p.add_argument('--shaders-only', action='store_true',
                   help='stop after the shader package, so an existing Metal build can be reused')
    p.add_argument('-j', type=int, default=JOBS)
    a = p.parse_args()
    if a.j <= 0:
        p.error('-j must be positive')
    a.member = a.member or list(MEMBERS)
    if a.archives and a.base:
        p.error('pass --archives or --base, not both')
    if not a.out or not (a.archives or a.base):
        p.error('--out and either --archives or --base are required (or set the Spyder settings)')
    if a.base and not a.keys:
        p.error('--base needs --keys (the mount decrypts the image as it reads it)')
    if a.update and not a.base:
        p.error('--update is only read through --base')
    if not a.discover_keys and not a.key_file:
        p.error('--no-key-discovery needs --key-file (nothing would supply the EASF key)')
    for module in a.key_module:
        if not module.is_file():
            p.error(f'--key-module {module} does not exist')
    out = a.out.resolve()
    build = (REPO / 'build').resolve()
    if out == REPO or (REPO in out.parents and out != build and build not in out.parents):
        p.error('--out must be outside the repository, or under build/ (which Git ignores)')
    if a.key_file and (REPO == a.key_file.resolve() or REPO in a.key_file.resolve().parents):
        p.error('--key-file must be outside the repository')
    if ' ' in str(out):
        p.error('the host Makefile currently requires an output path without spaces')
    out.mkdir(parents=True, exist_ok=True)
    # A failed attempt must not leave a previous success marker looking current.
    (out / 'build-manifest.json').unlink(missing_ok=True)
    profile = out / 'profile' / GAME
    profile.mkdir(parents=True, exist_ok=True)
    for name in ('game.tsv', 'bf_want.tsv', 'pso_manifest.tsv', 'shader_pairs_extra.tsv'):   # the pair supplement must be in place before easf/prepare.py merges it into shader_pairs.tsv
        src = REPO / 'dm/games' / GAME / name
        if src.exists():
            shutil.copyfile(src, profile / name)
    env = dict(os.environ, DM_GAME=GAME, DM_GAMES_DIR=str(out / 'profile'),
               DM_GAMES_FIRST='1', DM_ROOT=str(out), J=str(a.j))
    # Homebrew's apphost does not discover its .NET runtime without DOTNET_ROOT.
    if not env.get('DOTNET_ROOT') and shutil.which('dotnet'):
        runtime = Path(shutil.which('dotnet')).resolve().parent
        if not (runtime / 'shared').is_dir() and (runtime.parent / 'libexec/shared').is_dir():
            runtime = runtime.parent / 'libexec'
        env['DOTNET_ROOT'] = str(runtime)
    def run(args):
        subprocess.run([str(x) for x in args], env=env, cwd=REPO, check=True)
    run([sys.executable, TOOLS / 'dmsh_chain.py', '--check-tools'])
    # One key source for both input modes, so a file archive and an archive read
    # out of the image decode through exactly the same resolution order.
    sys.path.insert(0, str(TOOLS / 'easf'))
    import keyfind
    import prepare as easf_prepare
    modules = []
    if a.discover_keys:
        try:
            modules = key_modules(a, out, env)
        except (OSError, subprocess.CalledProcessError, ValueError) as error:
            # Discovery is an optimisation, not a requirement: the private key
            # file below still answers, and without one the preparer says which
            # key ID it could not resolve.
            print(f'[note] no module to discover the EASF key in ({error})')
        if modules:
            print('[note] EASF key discovery: ' +
                  ', '.join(str(m) for m in modules) + (', key file first: ' + str(a.key_file) if a.key_file else ''))
    ring = keyfind.Keyring(key_file=a.key_file, modules=modules, bounded=a.key_scan)
    if a.archives:
        easf_prepare.prepare(a.archives, out / 'pkg', profile, keys=ring)
        inputs = {Path(f).name: hashlib.sha256(Path(f).read_bytes()).hexdigest() for f in a.archives}
        image = None
    else:
        # Same preparer, same output format: only the input changes from a path
        # to (member name, bytes) read out of the image.
        archives, image = image_inputs(a, profile)
        if image['version'] is None:
            print(f'[note] {a.base} does not match any build row in game.tsv; '
                  'its module build IDs are not one this profile was verified with')
        else:
            print(f'[note] image holds {image["version"]}')
        easf_prepare.prepare(archives, out / 'pkg', profile, keys=ring)
        inputs = {name: hashlib.sha256(data).hexdigest() for name, data in archives}
    if a.shaders_only:
        print(f'Prepared the shader package in {out / "pkg"}; '
              'stopping before the Metal build (--shaders-only)')
        return
    # The chain version header is global (dm/gfx/nvn/dmsh_chain.h) and committed to the repository: check it here instead of rewriting
    # it. Writing it from a build script changed a tracked file on every run, which also made source_dirty below always true.
    chain = subprocess.check_output([sys.executable, str(TOOLS / 'dmsh_chain.py')], env=env, text=True).strip()
    header = (REPO / 'dm/gfx/nvn/dmsh_chain.h').read_text()
    if f'"{chain}"' not in header:
        raise SystemExit(f'dm/gfx/nvn/dmsh_chain.h does not hold the current chain version {chain}: '
                         'run dm/gfx/tools/dmsh_chain.py --header once and commit the result')
    run([sys.executable, TOOLS / 'dmsh_build.py', out / 'pkg', out / 'shaders'])
    library = out / 'shaders' / ('b-' + chain)
    expected = {line.split('\t')[3] for line in (profile / 'shader_map.tsv').read_text().splitlines()
                if line and not line.startswith('#')}
    for key in expected:
        reflection = library / (key + '_b.json')
        if not reflection.exists() or not (library / (key + '_b.metallib')).exists():
            raise ValueError('incomplete shader build; missing output for ' + key)
        if json.loads(reflection.read_text()).get('chain') != chain:
            raise ValueError('shader reflection has a mismatched chain')
    for tool, name in [('c1_guard.py', 'c1_full.tsv'), ('cb_extent.py', 'cb_extent.tsv')]:
        run([sys.executable, TOOLS / tool, library, profile / name])
    run(['make', '-C', REPO / 'dm/host', f'GAME={GAME}', f'GEN={out / "gen"}',
         f'HOST={out / "dmhost"}', f'-j{a.j}'])
    if a.exefs:
        for module in ('main', 'sdk'):
            run([sys.executable, REPO / 'dm/tools/patch_nso.py', a.exefs / module,
                 out / 'patched', module])
    revision, dirty = source_state()
    manifest = {'chain': chain, 'host_from_source': True, 'modules_rewritten': bool(a.exefs),
                'shader_count': len(expected),
                'host_sha256': hashlib.sha256((out / 'dmhost').read_bytes()).hexdigest(),
                'tool_lock_sha256': hashlib.sha256((TOOLS / 'dmsh_chain.lock').read_bytes()).hexdigest(),
                'source_revision': revision,
                'source_dirty': dirty,
                'module_inputs': {name: hashlib.sha256((a.exefs / name).read_bytes()).hexdigest()
                                  for name in ('main', 'sdk')} if a.exefs else {},
                'inputs': inputs,
                'image': image,
                # Where the EASF key came from and which key it was, as a digest:
                # enough to prove two builds used the same key, nothing to reuse.
                'easf_keys': {'discovery': bool(a.discover_keys),
                              'modules': [str(m) for m in modules],
                              'bounded_scan': bool(a.key_scan),
                              'sources': ring.notes,
                              'sha256_16': ring.fingerprints},
                'libraries': {f.name: hashlib.sha256(f.read_bytes()).hexdigest() for f in sorted(library.glob('*.metallib'))},
                'note': 'Build evidence only; game runtime and visual/audio checks are separate.'}
    (out / 'build-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    print(f'Built source host and shaders in {out}; runtime checks are still required.')


if __name__ == '__main__':
    try:
        main()
    except (subprocess.CalledProcessError, OSError, ValueError) as error:
        print(f'[RED] FIFA compatibility build failed: {error}', file=sys.stderr)
        sys.exit(1)
