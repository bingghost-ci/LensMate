#!/usr/bin/env python3
"""Read tracked upstream files and inventory review leads; never execute their code.

This is a lexical inventory, not a vulnerability scanner or a network capture.
URLs omit queries/fragments/userinfo; secret matches report locations only.
"""
import csv
import datetime
import hashlib
import json
from pathlib import Path
import re
import subprocess
from urllib.parse import urlsplit

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / 'docs/audit/2026-10-24'
REPOSITORIES = ['OpenVision', 'OpenGlasses', 'meta-wearables-dat-ios']
EXTENSIONS = {'.swift', '.m', '.mm', '.h', '.c', '.cpp', '.plist', '.xcprivacy',
              '.entitlements', '.yml', '.yaml', '.json', '.sh', '.js', '.ts', '.py',
              '.html', '.pbxproj', '.xcconfig', '.toml'}
URL = re.compile(r'\b(?:https?|wss?)://[^\s<>"\x27`]+')
NETWORK = re.compile(r'URLSession|URLRequest\(|webSocketTask|NWConnection|NWListener|'
                     r'URLProtocol|WKWebView|\.dataTask\(|\.upload\(|\.bytes\(for:|'
                     r'fetch\(|requests\.(?:get|post)|urllib\.request|\bcurl\b')
SECRETS = {
    'private-key-header': re.compile(r'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----'),
    'google-key-shape': re.compile(r'\bAIza[A-Za-z0-9_-]{35}\b'),
    'provider-key-shape': re.compile(r'\bsk-(?:proj-)?[A-Za-z0-9_-]{30,}\b'),
    'github-token-shape': re.compile(r'\b(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{40,})\b'),
    'aws-access-id-shape': re.compile(r'\bAKIA[A-Z0-9]{16}\b'),
}


def git(repo, *args):
    return subprocess.check_output(['git', '-C', str(repo), *args]).decode().strip()


def scope(path):
    lower = path.lower()
    if any(x in lower for x in ['test', 'fixture', 'contract']):
        return 'test-or-fixture'
    if lower.startswith(('vendor/', 'transport/')):
        return 'vendor-or-transport'
    if lower.startswith(('docs/', 'reports/', 'site/', 'plugins/', '.cursor/', '.claude/', 'skillpacks/')) or ('/' not in lower and lower.endswith('.html')):
        return 'documentation-or-site'
    if lower.startswith(('scripts/', 'ci_scripts/', '.github/', 'tools/', 'telemetry/')) or lower.endswith(('.yml', '.yaml', '.sh', '.pbxproj', '.toml')):
        return 'build-or-tooling'
    return 'app-or-sample'


def main():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    manifest, endpoints, calls, secret_locations, counts = [], [], [], [], {}
    for name in REPOSITORIES:
        repo = ROOT / 'references' / name
        tracked = subprocess.check_output(['git', '-C', str(repo), 'ls-files', '-z']).decode().split('\0')
        tracked = [p for p in tracked if p]
        source_files = source_lines = lfs_pointers = symlinks = 0
        hashes = hashlib.sha256()
        for relative in tracked:
            path = repo / relative
            if path.is_symlink():
                symlinks += 1
                continue
            if not path.is_file():
                continue
            data = path.read_bytes()
            hashes.update(relative.encode() + b'\0' + hashlib.sha256(data).digest())
            if data.startswith(b'version https://git-lfs.github.com/spec/v1'):
                lfs_pointers += 1
            if path.suffix not in EXTENSIONS or len(data) > 4_000_000:
                continue
            try:
                lines = data.decode('utf-8').splitlines()
            except UnicodeDecodeError:
                continue
            source_files += 1
            source_lines += len(lines)
            category = scope(relative)
            for number, line in enumerate(lines, 1):
                for match in URL.finditer(line):
                    raw = match.group().split('\\')[0]
                    try:
                        parsed = urlsplit(raw)
                        host = parsed.hostname or '<dynamic>'
                        endpoint = parsed.scheme + '://' + host + parsed.path
                    except ValueError:
                        host, endpoint = '<dynamic>', '<unparsed dynamic URL>'
                    endpoints.append([name, category, relative, number, host, endpoint])
                if NETWORK.search(line):
                    calls.append([name, category, relative, number])
                for rule, regex in SECRETS.items():
                    if regex.search(line):
                        secret_locations.append({'repository': name, 'scope': category,
                                                 'file': relative, 'line': number, 'rule': rule})
        counts[name] = {'tracked_files': len(tracked), 'text_files_scanned': source_files,
                        'text_lines_scanned': source_lines, 'lfs_pointer_files': lfs_pointers,
                        'symlinks_not_followed': symlinks}
        manifest.append({'name': name, 'local_path': 'references/' + name,
                         'remote': git(repo, 'remote', 'get-url', 'origin'),
                         'commit': git(repo, 'rev-parse', 'HEAD'),
                         'commit_date': git(repo, 'log', '-1', '--format=%cI'),
                         'tree': git(repo, 'rev-parse', 'HEAD^{tree}'),
                         'tracked_content_sha256': hashes.hexdigest(),
                         'shallow': git(repo, 'rev-parse', '--is-shallow-repository') == 'true',
                         'worktree_clean': not bool(git(repo, 'status', '--porcelain')),
                         'submodules': git(repo, 'submodule', 'status'),
                         **counts[name]})
    for name, fields, rows in [
        ('endpoint-inventory.csv', ['repository', 'scope', 'file', 'line', 'host', 'endpoint_no_query'], endpoints),
        ('network-call-sites.csv', ['repository', 'scope', 'file', 'line'], calls),
    ]:
        with (OUTPUT / name).open('w', newline='') as f:
            writer = csv.writer(f)
            writer.writerow(fields)
            writer.writerows(rows)
    (OUTPUT / 'source-manifest.json').write_text(json.dumps({
        'recorded_at_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'repositories': manifest,
        'boundary': 'Shallow source checkouts. No submodule/LFS payload/dependency resolution, upstream scripts, builds, credentials, or paid API calls executed.'
    }, ensure_ascii=False, indent=2) + '\n')
    (OUTPUT / 'scan-summary.json').write_text(json.dumps({
        'method': 'Lexical inventory only. Comments, examples and unused code can match. Absence is not proof of no network activity.',
        'included_text_extensions': sorted(EXTENSIONS),
        'max_text_file_bytes': 4_000_000,
        'scope_labels': 'Heuristic file classification only, not runtime reachability. Source line counts include data JSON and vendored code, not manual review coverage.',
        'counts': counts, 'url_occurrences': len(endpoints), 'network_call_occurrences': len(calls),
        'secret_pattern_locations': secret_locations,
    }, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({'counts': counts, 'urls': len(endpoints), 'network_call_sites': len(calls),
                      'secret_pattern_matches': len(secret_locations)}, ensure_ascii=False))


if __name__ == '__main__':
    main()
