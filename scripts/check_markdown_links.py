#!/usr/bin/env python3
"""Check repository Markdown paths and GitHub-style heading anchors locally.

External URLs are listed with --external for a separate network review. Original
third-party source text is never rewritten by this check. No network is required.
"""
import argparse
import json
from pathlib import Path
import re
import subprocess
from urllib.parse import unquote, urlsplit

ROOT = Path(__file__).resolve().parents[1]
LINK = re.compile(r'!?\[[^\]\n]*\]\(\s*(<[^>]+>|(?:\\.|[^()\s]|\([^()\s]*\))+)')
REFERENCE = re.compile(r'^\s{0,3}\[[^\]]+\]:\s*(<[^>]+>|\S+)', re.M)


def visible_markdown(text):
    result, fence = [], None
    for line in text.splitlines():
        match = re.match(r'^\s*(`{3,}|~{3,})', line)
        if match:
            marker = match.group(1)
            if fence is None:
                fence = marker
            elif marker[0] == fence[0] and len(marker) >= len(fence):
                fence = None
            result.append('')
        else:
            result.append(line if fence is None else '')
    return '\n'.join(result)


def anchors(text):
    text = visible_markdown(text)
    found, counts = set(), {}
    for value in re.findall(r'(?m)^ {0,3}#{1,6}\s+(.+?)\s*#*\s*$', text):
        value = re.sub(r'<[^>]*>', '', value).replace('`', '').lower()
        value = re.sub(r'[^\w\-\s]', '', value, flags=re.UNICODE).replace(' ', '-')
        count = counts.get(value, 0)
        counts[value] = count + 1
        found.add(value + ('-' + str(count) if count else ''))
    found.update(re.findall(r'<a\s+(?:name|id)=["\']([^"\']+)', text, re.I))
    return found


def destinations(text):
    text = visible_markdown(text)
    return [(text.count('\n', 0, m.start()) + 1, m.group(1).strip('<>'))
            for pattern in (LINK, REFERENCE) for m in pattern.finditer(text)]


def check(root=ROOT):
    paths = subprocess.check_output(['git', '-C', str(root), 'ls-files', '--cached', '--others', '--exclude-standard', '-z', '--', '*.md']).decode().strip('\0').split('\0')
    errors, external, count = [], set(), 0
    for name in filter(None, paths):
        source = root / name
        if not source.exists():
            continue
        text = source.read_text()
        external.update(url.rstrip('.,;:') for url in re.findall(r'https?://[^\s<>"`\)\]]+', visible_markdown(text)))
        for line, url in destinations(text):
            parts = urlsplit(url)
            if parts.scheme or parts.netloc:
                if parts.scheme in ('http', 'https'):
                    external.add(url)
                continue
            count += 1
            target = (source.parent / unquote(parts.path)).resolve() if parts.path else source
            if not target.exists():
                errors.append({'file': name, 'line': line, 'target': url, 'error': 'missing path'})
            elif parts.fragment and target.suffix.lower() == '.md' and unquote(parts.fragment) not in anchors(target.read_text()):
                errors.append({'file': name, 'line': line, 'target': url, 'error': 'missing anchor'})
    return {'markdown_files': len(list(filter(None, paths))), 'local_links': count,
            'errors': errors, 'external_urls': sorted(external)}


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--json', action='store_true')
    p.add_argument('--external', action='store_true')
    args = p.parse_args()
    result = check()
    if args.json:
        print(json.dumps(result, indent=2, ensure_ascii=False))
    else:
        for item in result['errors']:
            print('[RED] {file}:{line}: {error}: {target}'.format(**item))
        print('Markdown: %d files, %d local links, %d errors' %
              (result['markdown_files'], result['local_links'], len(result['errors'])))
        if args.external:
            print('\n'.join(result['external_urls']))
    return bool(result['errors'])


if __name__ == '__main__':
    raise SystemExit(main())
