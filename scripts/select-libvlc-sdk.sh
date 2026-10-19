#!/usr/bin/env bash
# Select the production SDK, or an explicitly pinned candidate, without fallback.
set -euo pipefail
REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
exec python3 - "$REPO_ROOT" "$@" <<'PY'
import argparse
import errno
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tarfile
import tempfile
from urllib.parse import urlsplit
import uuid

ROOT = Path(sys.argv[1])
BUNDLE = 'libvlc-sdk.tar.xz'
AAR = 'libvlc-privi.aar'
MANIFEST = ROOT / 'third_party/libvlc/distribution.json'
LOCK_PATH = ROOT / 'third_party/libvlc/source-lock.json'
RECEIPT = 'LIBVLC_SDK_INPUT.json'


def fail(message):
    raise RuntimeError(message)


def sha(path):
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(block)
    return digest.hexdigest()


def digest_field(value, length, label):
    if not isinstance(value, str) or not re.fullmatch('[0-9a-f]{' + str(length) + '}', value):
        fail(label + ' must be an explicit full lowercase hexadecimal digest')
    return value


def release_url(value):
    parsed = urlsplit(value)
    if (parsed.scheme != 'https' or parsed.netloc != 'github.com'
            or not re.fullmatch(r'/[^/]+/[^/]+/releases/download/[^/]+/[^/]+', parsed.path)
            or parsed.query or parsed.fragment):
        fail('sdk_url must be a permanent HTTPS GitHub Release asset URL without query or fragment')
    return value


def verify_cache(directory, expected, *, expected_aar=None):
    # Bind extracted files to the hash-pinned archive, rather than trusting a
    # mutable checksum/provenance file next to them in the build cache.
    bundle = directory / BUNDLE
    if not bundle.is_file() or sha(bundle) != expected['sdk_sha256']:
        fail('SDK cache bundle is missing or has a SHA-256 mismatch: ' + str(directory))
    if (directory / (BUNDLE + '.sha256')).read_text().strip() != expected['sdk_sha256'] + '  ' + BUNDLE:
        fail('SDK cache bundle checksum sidecar does not match the selected bundle')
    with tarfile.open(bundle, 'r:xz') as archive:
        members = {member.name: member for member in archive.getmembers()}
        if len(members) != len(archive.getmembers()):
            fail('SDK bundle has duplicate archive members')
        checksum_member = members.get('LIBVLC_SHA256SUMS')
        if checksum_member is None or not checksum_member.isfile():
            fail('SDK bundle has no regular checksum manifest')
        checksums = archive.extractfile(checksum_member).read().decode('utf-8')
    contents = directory / 'contents'
    listed = {}
    for line in checksums.splitlines():
        digest, name = line.split('  ', 1)
        digest_field(digest, 64, 'Bundle member SHA-256')
        if Path(name).name != name or name in listed:
            fail('Invalid or duplicate SDK bundle checksum entry')
        listed[name] = digest
    required = {AAR, 'libvlc-provenance.json', 'libvlc-corresponding-source.tar.xz', 'libvlc-licenses.tar.xz'}
    if set(listed) != required:
        fail('Incomplete SDK/source/license bundle')
    for name, digest in listed.items():
        path = contents / name
        if not path.is_file() or path.is_symlink() or sha(path) != digest:
            fail('SDK cached contents are missing or changed: ' + str(path))
    lock = json.loads(LOCK_PATH.read_text())
    info = json.loads((contents / 'libvlc-provenance.json').read_text())
    receipt = json.loads((directory / RECEIPT).read_text())
    patches = [dict(entry, target=entry.get('target', 'vlc')) for entry in lock['patches']]
    if (info['project_commit'] != expected['sdk_commit']
            or info['source_lock_sha256'] != sha(LOCK_PATH) or info['source_lock'] != lock
            or info['custom_patches'] != patches
            or set(info['abis']) != {target['abi'] for target in lock['targets']}):
        fail('SDK cache provenance does not match the selected commit and current source lock')
    for entry in lock['patches']:
        if sha(ROOT / entry['path']) != entry['sha256']:
            fail('Current SDK patch bytes do not match the source lock')
    aar_hash = listed[AAR]
    if info['aar_sha256'] != aar_hash or (expected_aar is not None and aar_hash != expected_aar):
        fail('SDK AAR SHA-256 differs from its pinned distribution or provenance')
    if any(receipt.get(key) != value for key, value in {
            'bundle_sha256': expected['sdk_sha256'], 'sdk_commit': expected['sdk_commit'],
            'aar_sha256': aar_hash, 'source_lock_sha256': sha(LOCK_PATH)}.items()):
        fail('SDK cache input receipt does not match its pinned bundle/commit/AAR/source lock')
    return aar_hash


def emit(directory, aar_hash, *, write_env):
    variables = {
        'ORG_GRADLE_PROJECT_priviLibvlcAar': str(directory / 'contents' / AAR),
        'ORG_GRADLE_PROJECT_priviLibvlcAarSha256': aar_hash,
        'PRIVI_LIBVLC_BUNDLE': str(directory / BUNDLE),
        'PRIVI_LIBVLC_RECEIPT': str(directory / RECEIPT),
    }
    if write_env and os.environ.get('GITHUB_ENV'):
        if any('\n' in value or '\r' in value for value in variables.values()):
            fail('Invalid newline in SDK path')
        with open(os.environ['GITHUB_ENV'], 'a') as output:
            for name, value in variables.items():
                output.write(name + '=' + value + '\n')
    print(json.dumps(variables, indent=2))


def main():
    parser = argparse.ArgumentParser(description='Select the pinned production LibVLC SDK or an explicit candidate')
    for flag, env in [('run-id', 'SDK_RUN_ID'), ('url', 'SDK_URL'), ('commit', 'SDK_COMMIT'), ('sha256', 'SDK_SHA256')]:
        parser.add_argument('--' + flag, default=os.environ.get(env, ''))
    parser.add_argument('--check', action='store_true', help='Verify only the default manifest cache; never download or write environment')
    args = parser.parse_args(sys.argv[2:])
    explicit = any([args.run_id, args.url, args.commit, args.sha256])
    if args.check and explicit:
        fail('--check accepts only the default distribution manifest, without SDK inputs')
    if explicit:
        if bool(args.run_id) == bool(args.url):
            fail('Choose exactly one sdk_run_id or sdk_url; sdk_commit/sdk_sha256 require a source')
        if args.run_id and not re.fullmatch('[0-9]+', args.run_id):
            fail('sdk_run_id must be a numeric successful same-repository SDK workflow run')
        selected = {'sdk_commit': args.commit, 'sdk_sha256': args.sha256}
        if args.url:
            selected['sdk_url'] = release_url(args.url)
        expected_aar = None
    else:
        if not MANIFEST.is_file():
            fail('Production LibVLC distribution is not pinned: third_party/libvlc/distribution.json is missing; select explicit SDK inputs until the audited bundle is published')
        selected = json.loads(MANIFEST.read_text())
        selected['sdk_url'] = release_url(selected['sdk_url'])
        expected_aar = digest_field(selected['aar_sha256'], 64, 'aar_sha256')
    digest_field(selected['sdk_commit'], 40, 'sdk_commit')
    digest_field(selected['sdk_sha256'], 64, 'sdk_sha256')
    parent = ROOT / 'build' / ('libvlc-sdk-input' if explicit else 'libvlc-sdk-cache')
    # Explicit candidates always go through producer validation, including the
    # requested workflow run identity. They cannot be satisfied by another run's
    # previously cached receipt, even when the bundle hash happens to match.
    final = parent / (selected['sdk_sha256'] + '-' + uuid.uuid4().hex if explicit else selected['sdk_sha256'])
    if not explicit and final.exists():
        aar_hash = verify_cache(final, selected, expected_aar=expected_aar)
    elif args.check:
        fail('Pinned LibVLC SDK cache is missing; run make native-sdk (or bash scripts/select-libvlc-sdk.sh) before building Android')
    else:
        parent.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix='.select-', dir=parent) as temporary:
            fresh = Path(temporary) / 'sdk'
            command = ['bash', str(ROOT / 'scripts/build-libvlc-sdk.sh')]
            command += ['fetch-run', '--run-id', args.run_id] if args.run_id else ['fetch-release', '--url', selected['sdk_url']]
            command += ['--commit', selected['sdk_commit'], '--sha256', selected['sdk_sha256'], '--output-dir', str(fresh)]
            environment = dict(os.environ)
            environment.pop('GITHUB_ENV', None)
            if args.run_id and not environment.get('GITHUB_REPOSITORY'):
                environment['GITHUB_REPOSITORY'] = subprocess.check_output(
                    ['gh', 'repo', 'view', '--json', 'nameWithOwner', '--jq', '.nameWithOwner'],
                    cwd=ROOT, text=True, timeout=30).strip()
            subprocess.run(command, env=environment, check=True, stdout=subprocess.PIPE, text=True)
            aar_hash = verify_cache(fresh, selected, expected_aar=expected_aar)
            if final.exists():
                # A concurrent successful default selection owns this directory.
                # Never replace or delete it; validate it before using it.
                aar_hash = verify_cache(final, selected, expected_aar=expected_aar)
            else:
                try:
                    fresh.rename(final)
                except OSError as error:
                    if error.errno not in (errno.EEXIST, errno.ENOTEMPTY):
                        raise
                    aar_hash = verify_cache(final, selected, expected_aar=expected_aar)
    emit(final, aar_hash, write_env=not args.check)


try:
    main()
except (RuntimeError, OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError, tarfile.TarError) as error:
    print('LibVLC SDK selection error:', error, file=sys.stderr)
    sys.exit(1)
PY
