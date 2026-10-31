#!/usr/bin/env python3
"""Review candidate changes for common private artifacts before staging/commit.

This conservative local scan prints findings by path/line only, never secret
values. It is a supplement to manual provenance review, not a proof of copyright
or secret absence. With --staged, inspect the exact staged blob contents.
With --history BASE, inspect every changed file version in BASE..HEAD, including
versions subsequently replaced or deleted. No finding prints the matched value.
"""
import argparse
from pathlib import Path
import re
import subprocess
import sys

REPO = Path(__file__).resolve().parents[1]
TEXT = {'.py', '.c', '.cs', '.h', '.m', '.md', '.swift', '.tsv', '.lock', '.sh'}
DENIED = {'.nsp', '.xci', '.nsz', '.nca', '.keys', '.key', '.metallib', '.air',
          '.ncz', '.nso', '.nro', '.dylib', '.exe', '.o', '.a', '.zip', '.ipa',
          '.raw', '.pcm', '.bin', '.png', '.jpg', '.mp4', '.log', '.metal'}
PATTERNS = [
    ('personal absolute path', re.compile(r'/(?:Users|Volumes)/')),
    ('private key block', re.compile(r'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----')),
    ('authentication token', re.compile(r'(?<![A-Za-z0-9_])(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|sk-[A-Za-z0-9_-]{20,})')),
    ('literal secret assignment', re.compile(r'''(?i)(?:api_key|access_token|secret_key)\s*[=:]\s*["'][^"']{12,}["']''')),
    ('embedded AES key', re.compile(r'''(?i)bytes\.fromhex\(["'][0-9a-f]{32}["']\)''')),
    ('credential-bearing URL', re.compile(r'https?://[^\s/@:]+:[^\s/@]+@')),
    ('private network endpoint', re.compile(r'https?://(?:localhost|127\.0\.0\.1|10\.\d+\.\d+\.\d+|192\.168\.\d+\.\d+)(?=[:/\s]|$)')),
]


# Files whose Chinese text is UI copy or a non-ASCII test fixture, not stray prose:
# the packaging engine's zh-Hans messages, the tests that assert them, and the
# filesystem tests that create Chinese directory names. All other checks still run
# on them.
LOCALIZED_PATHS = (
    'tools/packaging_gui/',
    'scripts/build_packaging_gui.py',
    'scripts/tests/test_packaging_games.py',
    'scripts/tests/test_packaging_gui.py',
    'dm/resource/tests/test_resource_discovery.py',
    'dm/host/tests/t_fs_mod.c',
)


def git(*args):
    return subprocess.check_output(['git', '-C', str(REPO), *args])


def has_head():
    return subprocess.run(['git', '-C', str(REPO), 'rev-parse', '--verify', '-q', 'HEAD'],
                          stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0


def working_tree():
    """Files eligible for publication, including untracked, non-ignored files."""
    return sorted(set(git('ls-files', '--cached', '--others', '--exclude-standard', '-z')
                      .decode().strip('\0').split('\0')) - {''})


def owned_artwork(name, data):
    """The App icons are drawn by assets/app-icon/make_icon.swift, not game artwork.

    They are PNGs, so the binary rule cannot read them; the clearance is that the
    committed script makes exactly this mark from shapes and a system font.
    """
    return name.startswith('assets/app-icon/') and data[:8] == b'\x89PNG\r\n\x1a\n'


def inspect(name, data, unchanged=()):
    file = Path(name)
    if owned_artwork(name, data):
        return []
    if file.suffix.lower() in DENIED or (file.suffix not in TEXT and file.name not in ('Makefile', '.gitignore', 'requirements-fifa23.txt')):
        return [f'{name}: file type requires separate manual clearance']
    if len(data) > 1024 * 1024 or b'\0' in data:
        return [f'{name}: binary or unusually large candidate']
    try:
        source = data.decode('utf-8')
    except UnicodeDecodeError:
        return [f'{name}: non-UTF-8 content requires manual clearance']
    findings = []
    # The GUI and bilingual documentation are explicitly localized. This only
    # scopes the language style check; all credential/path checks still apply.
    parts = file.parts
    localized = ((file.suffix == '.md' and (parts[0] == 'docs' or file.name in ('README.md', 'README.zh-CN.md')))
                 or (file.suffix == '.swift' and parts[:2] in (('gui', 'Sources'), ('gui', 'Tests')))
                 or name.startswith(LOCALIZED_PATHS))
    for line, value in enumerate(source.splitlines(), 1):
        if value in unchanged:
            continue
        for kind, pattern in PATTERNS:
            if pattern.search(value):
                findings.append(f'{name}:{line}: {kind}')
        if not localized and any('\u4e00' <= c <= '\u9fff' for c in value):
            findings.append(f'{name}:{line}: non-English source text')
    return findings


def history(base):
    # Resolve the ref before it is used as a revision range. Never compare only
    # the final tree: that would miss a secret removed in a later commit.
    base = git('rev-parse', '--verify', base + '^{commit}').decode().strip()
    commits = git('rev-list', '--reverse', base + '..HEAD').decode().splitlines()
    versions, names, findings = set(), set(), []
    for commit in commits:
        changed = git('diff-tree', '--no-commit-id', '--name-only', '-r', '--diff-filter=ACMRT', '-z', commit).decode().split('\0')
        for name in filter(None, changed):
            blob = git('rev-parse', commit + ':' + name).decode().strip()
            if (name, blob) in versions:
                continue
            versions.add((name, blob))
            names.add(name)
            findings.extend(commit[:12] + ':' + f for f in inspect(name, git('cat-file', 'blob', blob)))
    return commits, names, versions, findings


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--staged', action='store_true')
    p.add_argument('--history', metavar='BASE', help='scan all changed blob versions in BASE..HEAD')
    a = p.parse_args()
    if a.history:
        if a.staged:
            p.error('--history and --staged are separate review scopes')
        commits, names, versions, findings = history(a.history)
        for finding in findings:
            print(finding)
        print(f'Reviewed {len(commits)} commits, {len(names)} paths, {len(versions)} file versions; {len(findings)} findings. Manual provenance review remains required.')
        return bool(findings)
    if not has_head() and not a.staged:
        # Before the first commit there is no HEAD to diff against: review the
        # whole working tree and treat nothing as already-reviewed.
        names = set(working_tree())
        findings = []
        for name in sorted(names):
            findings.extend(inspect(name, (REPO / name).read_bytes()))
        for finding in findings:
            print(finding)
        print(f'Reviewed {len(names)} working-tree paths (no commit yet); {len(findings)} findings. '
              'Manual provenance review remains required.')
        return bool(findings)
    names = set(git('diff', '--cached' if a.staged else 'HEAD', '--name-only', '--diff-filter=ACMR', '-z').decode().strip('\0').split('\0'))
    if not a.staged:
        names.update(git('ls-files', '--others', '--exclude-standard', '-z').decode().strip('\0').split('\0'))
    findings = []
    for name in sorted(names - {''}):
        file = REPO / name
        data = git('show', ':' + name) if a.staged else file.read_bytes()
        previous = subprocess.run(['git', '-C', str(REPO), 'show', 'HEAD:' + name], capture_output=True)
        unchanged = set(previous.stdout.decode('utf-8', errors='replace').splitlines()) if previous.returncode == 0 else set()
        findings.extend(inspect(name, data, unchanged))
    for finding in findings:
        print(finding)
    print(f'Reviewed {len(names - {""})} candidate paths; {len(findings)} findings. Manual provenance review remains required.')
    return bool(findings)


if __name__ == '__main__':
    sys.exit(main())
