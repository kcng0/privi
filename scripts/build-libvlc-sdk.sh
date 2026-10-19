#!/usr/bin/env bash
# Build/distribute the locked native SDK; this does not publish or enable it.
set -euo pipefail
REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
exec python3 - "$REPO_ROOT" "$@" <<'PY'
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import struct
import subprocess
import sys
import tarfile
import tempfile
import time
import zipfile

ROOT = Path(sys.argv[1])
LOCK_PATH = ROOT / 'third_party/libvlc/source-lock.json'
LOCK = json.loads(LOCK_PATH.read_text())
SCRIPT = ROOT / 'scripts/build-libvlc-sdk.sh'
TARGETS = {t['abi']: t for t in LOCK['targets']}
BUNDLE = 'libvlc-sdk.tar.xz'
AAR = 'libvlc-privi.aar'
SOURCE_STATE_KEYS = tuple(f'{name}_patched_{kind}' for name in ('jni', 'vlc')
                          for kind in ('commit', 'tree'))
DEPENDENCY_GROUPS = {'contrib-tarballs': ('contrib', 'tarballs'),
                     'tools-tarballs': ('extras', 'tools')}
DEPENDENCY_STORAGE = 'sha256-cas-v1'


def fail(message):
    raise RuntimeError(message)


def sha(path):
    h = hashlib.sha256()
    with Path(path).open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            h.update(block)
    return h.hexdigest()


def write_json(path, value):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, sort_keys=True, indent=2) + '\n')


def run(args, cwd=None, env=None, timeout=300):
    return subprocess.check_output(args, cwd=cwd, env=env, timeout=timeout,
                                   text=True, stderr=subprocess.STDOUT).strip()


def check_sha(path, expected):
    if not re.fullmatch('[0-9a-f]{64}', expected or ''):
        fail('Expected an explicit lowercase SHA-256 for ' + str(path))
    actual = sha(path)
    if actual != expected:
        fail(f'SHA-256 mismatch for {path}: expected {expected}, got {actual}')


def fresh_dir(path):
    path = Path(path).resolve()
    path.mkdir(parents=True, exist_ok=True)
    if any(path.iterdir()):
        fail(f'Refusing to overwrite nonempty directory {path}; use a fresh build directory')
    return path


def independent_output(output, *inputs):
    output = Path(output).resolve()
    for source in inputs:
        source = Path(source).resolve()
        if output == source or output.is_relative_to(source) or source.is_relative_to(output):
            fail('Build output and input directories must be disjoint: ' + str(output))


def archive_tree(source, dest, epoch):
    # Normalize archive metadata; the compiler itself is not claimed bit-reproducible.
    def normalize(info):
        info.uid = info.gid = 0
        info.uname = info.gname = ''
        info.mtime = epoch
        return info
    dest.parent.mkdir(parents=True, exist_ok=True)
    with tarfile.open(dest, 'w:xz', preset=6) as archive:
        for path in sorted(source.iterdir()):
            archive.add(path, arcname=path.name, filter=normalize)


def extract(archive, dest):
    # Archives are hash-verified before use. Reject escaping links/paths as well.
    with tarfile.open(archive, 'r:*') as tar:
        tar.extractall(dest, filter='data')


def copy_file(source, dest):
    dest.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, dest)


def fetch(url, dest, expected=None):
    dest.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(['curl', '--fail', '--location', '--retry', '3', '--connect-timeout', '30',
                    '--max-time', '600', '--proto', '=https', '--output', str(dest), url], check=True)
    if expected:
        check_sha(dest, expected)


def checkout(spec, dest):
    subprocess.run(['git', 'init', '--quiet', str(dest)], check=True)
    subprocess.run(['git', '-C', str(dest), 'fetch', '--quiet', '--depth=1',
                    spec['repository'], spec['commit']], check=True, timeout=600)
    subprocess.run(['git', '-C', str(dest), 'checkout', '--quiet', '--detach', 'FETCH_HEAD'], check=True)
    if run(['git', 'rev-parse', 'HEAD'], dest) != spec['commit']:
        fail('Upstream checkout did not resolve to the locked commit: ' + str(dest))


def patch_inputs():
    paths = []
    for entry in LOCK['patches']:
        if entry.get('target', 'vlc') not in ('vlc', 'jni'):
            fail('Custom patch target must be vlc or jni: ' + entry['path'])
        path = ROOT / entry['path']
        if not path.resolve().is_relative_to(ROOT / 'third_party/libvlc/patches'):
            fail('Custom patches must stay in third_party/libvlc/patches')
        check_sha(path, entry['sha256'])
        paths.append(path)
    actual = set((ROOT / 'third_party/libvlc/patches').glob('*.patch'))
    if actual != set(paths):
        fail('Every custom .patch must occur exactly once in the ordered source lock')
    if len(paths) != len(set(paths)):
        fail('Duplicate patch in source lock')
    return paths


def custom_patch_records():
    return [dict(entry, target=entry.get('target', 'vlc')) for entry in LOCK['patches']]


def source_state(work):
    state = {}
    for name, path in [('jni', work / 'libvlcjni'), ('vlc', work / 'libvlcjni/vlc')]:
        state[name + '_patched_commit'] = run(['git', 'rev-parse', 'HEAD'], path)
        state[name + '_patched_tree'] = run(['git', 'rev-parse', 'HEAD^{tree}'], path)
    return state


def check_prepared_sources(work, info):
    actual = source_state(work)
    for key in SOURCE_STATE_KEYS:
        if actual[key] != info[key]:
            fail('Prepared source revision/tree changed: ' + key)
    for name, path in [('jni', work / 'libvlcjni'), ('vlc', work / 'libvlcjni/vlc')]:
        result = subprocess.run(['git', 'diff', '--quiet', 'HEAD', '--'], cwd=path)
        if result.returncode:
            fail(f'Prepared {name} working tree/index differs from its recorded commit (git diff exit {result.returncode})')


def prepare(args):
    patches = patch_inputs()
    independent_output(args.output_dir, args.work_dir)
    work = fresh_dir(args.work_dir)
    out = fresh_dir(args.output_dir)
    jni = work / 'libvlcjni'
    checkout(LOCK['jni'], jni)
    vlc = jni / 'vlc'
    checkout(LOCK['vlc'], vlc)
    epoch = int(run(['git', 'show', '-s', '--format=%ct', 'HEAD'], vlc))
    env = dict(os.environ, GIT_COMMITTER_NAME='Privi SDK builder',
               GIT_COMMITTER_EMAIL='sdk-build@privi.invalid', GIT_COMMITTER_DATE=f'@{epoch} +0000')
    official = sorted((jni / 'libvlc/patches').glob('*.patch'))
    if len(official) != LOCK['vlc']['official_patch_count']:
        fail('Official JNI patch count differs from the source lock')
    official_records = [{'name': p.name, 'sha256': sha(p)} for p in official]
    # This is the same git-am/message-id contract as upstream get-vlc.sh.
    subprocess.run(['git', 'am', '--message-id', *map(str, official)], cwd=vlc, env=env, check=True)
    repositories = {'vlc': vlc, 'jni': jni}
    changed = set()
    # Preserve the global lock order even when adjacent patches target different repos.
    for entry, patch in zip(LOCK['patches'], patches):
        target = entry.get('target', 'vlc')
        subprocess.run(['git', 'apply', '--index', str(patch)], cwd=repositories[target], check=True)
        changed.add(target)
    for target in sorted(changed):
        subprocess.run(['git', '-c', 'user.name=Privi SDK builder', '-c',
                        'user.email=sdk-build@privi.invalid', 'commit', '--quiet',
                        f'--date=@{epoch} +0000', '-m', 'Apply locked Privi native patches'],
                       cwd=repositories[target], env=env, check=True)
    patched = source_state(work)
    # Upstream confirms its tested VLC commit and all 20 Message-Ids are present.
    # With an existing VLC directory and no --reset it only checks; enforce that
    # neither the JNI nor VLC source was changed by this upstream invocation.
    subprocess.run(['./buildsystem/get-vlc.sh'], cwd=jni, check=True)
    check_prepared_sources(work, patched)
    fetch(LOCK['official_aar']['url'], work / 'official.aar', LOCK['official_aar']['sha256'])
    inputs = [SCRIPT, LOCK_PATH, ROOT / '.github/workflows/libvlc-sdk.yml', *patches]
    readme = ROOT / 'third_party/libvlc/README.md'
    if readme.exists():
        inputs.append(readme)
    for path in inputs:
        copy_file(path, work / 'inputs' / path.relative_to(ROOT))
    prepared = {
        'format': 1, 'project_commit': run(['git', 'rev-parse', 'HEAD'], ROOT),
        'source_lock_sha256': sha(LOCK_PATH), 'build_script_sha256': sha(SCRIPT),
        'source_date_epoch': epoch, 'source_lock': LOCK,
        **patched,
        'custom_patches': custom_patch_records(),
        'official_patches': official_records,
    }
    write_json(work / 'prepared.json', prepared)
    print('Prepared fixed source tree:', prepared['vlc_patched_tree'])
    print('Prepared fixed JNI tree:', prepared['jni_patched_tree'])
    if not args.skip_archive:
        archive_tree(work, out / 'prepared.tar.xz', epoch)


def prepared_input(work):
    info = json.loads((work / 'prepared.json').read_text())
    if info['source_lock_sha256'] != sha(LOCK_PATH) or info['build_script_sha256'] != sha(SCRIPT):
        fail('Prepared source does not match the checked-out source lock and build script')
    check_sha(work / 'official.aar', LOCK['official_aar']['sha256'])
    if info['custom_patches'] != custom_patch_records():
        fail('Prepared patch target/order/hash differs from the checked-out source lock')
    check_prepared_sources(work, info)
    return info


def dependency_file(name):
    return bool(re.search(r'\.(tar\.(gz|bz2|xz|lz|lzma|zst)|tgz|zip|githash)$', name))


def dependency_inventory(value):
    if not isinstance(value, dict) or not value:
        fail('Dependency source inventory must be a nonempty object')
    for relative, digest in value.items():
        if not isinstance(relative, str) or '\\' in relative or '\x00' in relative:
            fail('Invalid dependency source path')
        parts = relative.split('/')
        if (len(parts) != 2 or parts[0] not in DEPENDENCY_GROUPS
                or parts[1] in ('', '.', '..') or not dependency_file(parts[1])):
            fail('Dependency source path must name a direct contrib/tool archive or .githash: ' + relative)
        if not isinstance(digest, str) or not re.fullmatch('[0-9a-f]{64}', digest):
            fail('Invalid dependency source SHA-256: ' + relative)
        if relative.endswith('.githash') and relative[:-len('.githash')] + '.tar.xz' not in value:
            fail('Dependency .githash has no corresponding original .tar.xz: ' + relative)
    if not any(relative.startswith('contrib-tarballs/') and not relative.endswith('.githash')
               for relative in value):
        fail('No contrib source archives in the dependency inventory')
    return value


def dependency_records(directory, prepared):
    if directory.is_symlink() or not directory.is_dir() or {p.name for p in directory.iterdir()} != set(TARGETS):
        fail('Dependency source provenance must cover exactly the locked ABI list')
    records = {}
    for abi, target in TARGETS.items():
        base = directory / abi
        if base.is_symlink() or not base.is_dir():
            fail('Invalid dependency source provenance directory: ' + abi)
        for name in ['provenance.json', 'dependency-source-sha256.json']:
            path = base / name
            if path.is_symlink() or not path.is_file():
                fail('Missing regular dependency source provenance file: ' + str(path))
        record = json.loads((base / 'provenance.json').read_text())
        for key in ['project_commit', 'source_lock_sha256', 'build_script_sha256',
                    'custom_patches', *SOURCE_STATE_KEYS]:
            if record[key] != prepared[key]:
                fail('ABI outputs came from different source inputs: ' + abi + '/' + key)
        if record['target'] != target or set(record['libraries']) != set(LOCK['native_libraries']):
            fail('Dependency source ABI target differs from the source lock: ' + abi)
        inventory = dependency_inventory(record['dependency_sources'])
        if json.loads((base / 'dependency-source-sha256.json').read_text()) != inventory:
            fail('Dependency source inventory differs from ABI provenance: ' + abi)
        records[abi] = record
    return records


def dependency_store(store, records):
    expected = {digest for record in records.values() for digest in record['dependency_sources'].values()}
    if store.is_symlink() or not store.is_dir():
        fail('Missing regular dependency source content store')
    actual = set()
    for path in store.iterdir():
        if path.is_symlink() or not path.is_file() or not re.fullmatch('[0-9a-f]{64}', path.name):
            fail('Invalid dependency source content-store entry: ' + str(path))
        check_sha(path, path.name)
        actual.add(path.name)
    if actual != expected:
        fail('Dependency source content store has missing or unexpected archives/sidecars')


def collect_dependency_sources(parts, records, source):
    store = source / 'dependency-sources/sha256'
    store.mkdir(parents=True)
    for abi, record in records.items():
        inventory = record['dependency_sources']
        with tempfile.TemporaryDirectory(prefix='privi-libvlc-deps-') as temporary:
            deps = Path(temporary)
            original_part = parts / 'source-parts' / (abi + '.tar.xz')
            if original_part.is_symlink() or not original_part.is_file():
                fail('Missing regular dependency source-part archive: ' + abi)
            with tarfile.open(original_part, 'r:xz') as archive:
                seen = set()
                for member in archive.getmembers():
                    if member.isdir() and member.name.rstrip('/') in DEPENDENCY_GROUPS:
                        continue
                    if not member.isfile() or member.name not in inventory or member.name in seen:
                        fail('Unexpected, duplicate or unsafe dependency source archive member: ' + member.name)
                    seen.add(member.name)
                if seen != set(inventory):
                    fail('Dependency source-part members differ from ABI inventory: ' + abi)
                archive.extractall(deps, filter='data')
            for relative, digest in inventory.items():
                original = deps / relative
                check_sha(original, digest)
                dest = store / digest
                if dest.exists():
                    check_sha(dest, digest)
                else:
                    copy_file(original, dest)
    dependency_store(store, records)


def restore_dependency_sources(work, abi, prepared):
    directory = work / 'build-provenance'
    source_cache = work / 'dependency-sources'
    if 'dependency_source_storage' not in prepared:
        if any(path.exists() or path.is_symlink() for path in [directory, source_cache]):
            fail('Dependency source inputs require an explicit source-offer storage declaration')
        return  # Only a fresh upstream prepare downloads its own original inputs.
    if prepared['dependency_source_storage'] != DEPENDENCY_STORAGE:
        fail('Unknown source-offer dependency storage mode')
    if source_cache.is_symlink() or not source_cache.is_dir() or {p.name for p in source_cache.iterdir()} != {'sha256'}:
        fail('Incomplete or unexpected dependency source content store')
    records = dependency_records(directory, prepared)
    store = source_cache / 'sha256'
    dependency_store(store, records)
    inventory = records[abi]['dependency_sources']
    vlc = work / 'libvlcjni/vlc'
    if (work / 'libvlcjni').is_symlink() or vlc.is_symlink():
        fail('Dependency source destination repository must not be a symlink')
    destinations = []
    # Preflight every existing destination before restoring any bytes. In
    # particular, extracting one ABI must never overwrite another ABI's archive.
    for group, components in DEPENDENCY_GROUPS.items():
        base = vlc
        for component in components:
            if base.is_symlink() or (base.exists() and not base.is_dir()):
                fail('Unsafe dependency cache directory: ' + str(base))
            base = base / component
        if base.is_symlink() or (base.exists() and not base.is_dir()):
            fail('Unsafe dependency cache directory: ' + str(base))
        if base.exists():
            for path in base.iterdir():
                if dependency_file(path.name) and group + '/' + path.name not in inventory:
                    fail('Unexpected existing dependency archive/sidecar for ' + abi + ': ' + str(path))
    for relative, digest in inventory.items():
        group, name = relative.split('/')
        dest = vlc.joinpath(*DEPENDENCY_GROUPS[group], name)
        if dest.is_symlink() or (dest.exists() and not dest.is_file()):
            fail('Unsafe dependency source destination: ' + str(dest))
        if dest.exists():
            check_sha(dest, digest)
        destinations.append((dest, digest))
    for dest, digest in destinations:
        if not dest.exists():
            copy_file(store / digest, dest)
        check_sha(dest, digest)
    print(f'Restored {len(inventory)} original dependency archives/sidecars for {abi}')


def build(args):
    work = Path(args.work_dir).resolve()
    independent_output(args.output_dir, work)
    out = fresh_dir(args.output_dir)
    info = prepared_input(work)
    target = TARGETS[args.abi]
    if os.environ.get('PRIVI_LIBVLC_BUILD_IMAGE') != target['image']:
        fail('Set PRIVI_LIBVLC_BUILD_IMAGE to the locked container digest; use that container')
    ndk = Path(os.environ['ANDROID_NDK'])
    revision = re.search(r'^Pkg.Revision\s*=\s*(\S+)', (ndk / 'source.properties').read_text(), re.M)
    if not revision or revision[1] != target['ndk']:
        fail('Container NDK revision differs from the locked SDK build')
    jni = work / 'libvlcjni'
    vlc = jni / 'vlc'
    if (jni / 'libvlc/jni/libs').exists():
        fail('Native output already exists; refusing a mixed or incremental SDK build')
    restore_dependency_sources(work, args.abi, info)
    diagnostics = out / 'diagnostics'
    diagnostics.mkdir()
    log = diagnostics / f'{args.abi}.log'
    command = ['./buildsystem/compile-libvlc.sh', '-a', args.abi, *LOCK['compile_flags']]
    env = dict(os.environ, SOURCE_DATE_EPOCH=str(info['source_date_epoch']),
               TZ='UTC', LC_ALL='C.UTF-8', MAKEFLAGS=f'-j{args.jobs}',
               VLC_TARBALLS=str(vlc / 'contrib/tarballs'), **LOCK['build_environment'])
    started = time.time()
    # No --with-prebuilt-contribs: core, bundled modules, contribs and JNI are rebuilt.
    with log.open('w') as stream:
        result = subprocess.run(['timeout', '--signal=TERM', '--kill-after=60',
                                 str(args.timeout_seconds), *command], cwd=jni, env=env,
                                stdout=stream, stderr=subprocess.STDOUT)
    write_json(diagnostics / f'{args.abi}-status.json', {
        'exit_code': result.returncode, 'elapsed_seconds': round(time.time() - started),
        'command': command, 'target': target,
    })
    if result.returncode:
        print('\n'.join(log.read_text(errors='replace').splitlines()[-100:]), file=sys.stderr)
        fail(f'Native build failed for {args.abi}, exit {result.returncode}; full log: {log}')
    native = jni / 'libvlc/jni/libs' / args.abi
    produced = sorted(p.name for p in native.glob('*.so'))
    if produced != sorted(LOCK['native_libraries']):
        fail(f'Native output differs from the locked complete library set: {produced}')
    provenance = out / 'abi' / args.abi
    provenance.mkdir(parents=True)
    toolchain = ndk / 'toolchains/llvm/prebuilt/linux-x86_64'
    lib_info = {}
    readelf = toolchain / 'bin/llvm-readelf'
    for name in produced:
        source = native / name
        # ELF machine checks prevent an incorrectly labelled ABI from being packaged.
        with source.open('rb') as stream:
            header = stream.read(20)
        machine = struct.unpack_from('<H', header, 18)[0]
        expected = {'arm64-v8a': 183, 'armeabi-v7a': 40, 'x86_64': 62}[args.abi]
        if header[:4] != b'\x7fELF' or machine != expected:
            fail(f'Wrong ELF architecture for {args.abi}/{name}')
        copy_file(source, out / 'native' / args.abi / name)
        lib_info[name] = {'sha256': sha(source), 'size': source.stat().st_size}
        (provenance / (name + '.elf.txt')).write_text(run([str(readelf), '-h', '-l', '-d', str(source)]))
    build_dir = vlc / ('build-android-' + target['triplet'])
    for name in ['config.log', 'config.status', 'config.h', 'ndk/libvlcjni-modules.c']:
        copy_file(build_dir / name, provenance / Path(name).name)
    contrib = vlc / 'contrib' / ('contrib-android-' + target['triplet'])
    copy_file(contrib / 'config.mak', provenance / 'contrib-config.mak')
    # The exact built-in module list and configure output accompany every ABI.
    modules = re.findall(r'vlc_entry__(\w+),', (provenance / 'libvlcjni-modules.c').read_text())
    write_json(provenance / 'modules.json', modules)
    source_part = work / ('source-part-' + args.abi)
    source_part.mkdir()
    for base, dest in [(vlc / 'contrib/tarballs', 'contrib-tarballs'),
                       (vlc / 'extras/tools', 'tools-tarballs')]:
        for path in sorted(base.iterdir()):
            if path.is_file() and dependency_file(path.name):
                if path.is_symlink():
                    fail('Dependency source archive/sidecar must not be a symlink: ' + str(path))
                copy_file(path, source_part / dest / path.name)
    notices = out / 'licenses' / args.abi
    copy_file(jni / 'LICENSE', notices / 'jni/LICENSE')
    for base, label in [(jni / 'libvlc', 'jni'), (vlc, 'vlc'), (ndk, 'ndk')]:
        if label == 'vlc':
            roots = [vlc / 'contrib', vlc / 'extras/tools']
            for path in vlc.glob('COPYING*'):
                copy_file(path, notices / label / path.name)
        elif label == 'ndk':
            roots = []
            for base_path in [ndk, toolchain]:
                for name in ['NOTICE', 'NOTICE.toolchain', 'source.properties',
                             'AndroidVersion.txt', 'clang_source_info.md']:
                    path = base_path / name
                    if path.is_file():
                        copy_file(path, notices / label / path.relative_to(ndk))
        else:
            roots = [base]
        for scan in roots:
            for parent, directories, files in os.walk(scan):
                directories[:] = [d for d in directories if d not in ['.git', '.libs', 'autom4te.cache']]
                for name in files:
                    if re.match(r'^(COPYING|LICENSE|LICENCE|NOTICE|COPYRIGHT|AUTHORS)([._-].*)?$', name, re.I):
                        path = Path(parent) / name
                        if path.is_file():
                            copy_file(path, notices / label / path.relative_to(base))
    if not any((source_part / 'contrib-tarballs').glob('*')):
        fail('No downloaded contrib source archives were captured')
    inventory = {str(p.relative_to(source_part)): sha(p) for p in sorted(source_part.rglob('*')) if p.is_file()}
    dependency_inventory(inventory)
    write_json(provenance / 'dependency-source-sha256.json', inventory)
    archive_tree(source_part, out / 'source-parts' / (args.abi + '.tar.xz'), info['source_date_epoch'])
    record = dict(info, target=target, compile_command=command, libraries=lib_info,
                  build_environment=LOCK['build_environment'], effective_uid=os.geteuid(),
                  ndk_runtime_sha256=sha(toolchain / 'sysroot/usr/lib' / target['triplet'] / 'libc++_shared.so'),
                  modules=modules, dependency_sources=inventory)
    write_json(provenance / 'provenance.json', record)
    print(f'Built {args.abi}: {len(modules)} bundled modules, {len(inventory)} dependency source archives')


def package(args):
    work = Path(args.work_dir).resolve()
    parts = Path(args.input_dir).resolve()
    independent_output(args.output_dir, work, parts)
    out = fresh_dir(args.output_dir)
    prepared = prepared_input(work)
    records = dependency_records(parts / 'abi', prepared)
    expected = set()
    for abi, target in TARGETS.items():
        record = records[abi]
        if record['target'] != target or set(record['libraries']) != set(LOCK['native_libraries']):
            fail('Incomplete or differently configured ABI output: ' + abi)
        for name, details in record['libraries'].items():
            path = parts / 'native' / abi / name
            check_sha(path, details['sha256'])
            expected.add(str(path.relative_to(parts / 'native')))
    actual = {str(p.relative_to(parts / 'native')) for p in (parts / 'native').rglob('*.so')}
    if actual != expected:
        fail('Unexpected/missing native libraries in the three-ABI package')
    provenance = dict(prepared, abis=records,
                      dependency_source_storage=DEPENDENCY_STORAGE,
                      java_resources='Unmodified non-jni entries of the hash-pinned official AAR',
                      license_configuration='Upstream g: GPLv3; includes mixed upstream dependency licenses')
    with zipfile.ZipFile(work / 'official.aar') as original, zipfile.ZipFile(out / AAR, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=9) as aar:
        for entry in original.infolist():
            if not entry.filename.startswith('jni/'):
                aar.writestr(entry, original.read(entry))
        for relative in sorted(expected):
            entry = zipfile.ZipInfo('jni/' + relative, date_time=(1980, 1, 1, 0, 0, 0))
            entry.compress_type = zipfile.ZIP_DEFLATED
            entry.external_attr = 0o100644 << 16
            aar.writestr(entry, (parts / 'native' / relative).read_bytes(), compresslevel=9)
        aar.writestr('META-INF/privi-libvlc-provenance.json', json.dumps(provenance, sort_keys=True))
    with tempfile.TemporaryDirectory(prefix='privi-libvlc-source-') as temp:
        source = Path(temp)
        # Keep the shallow public Git metadata: upstream revision generation and
        # get-vlc.sh need it. No authenticated remote or app checkout is copied.
        shutil.copytree(work / 'libvlcjni', source / 'libvlcjni')
        shutil.copytree(work / 'inputs', source / 'inputs')
        # The original prepare/native provenance stays unchanged. A source
        # offer explicitly requires its preserved offline dependency inputs.
        write_json(source / 'prepared.json', dict(prepared, dependency_source_storage=DEPENDENCY_STORAGE))
        copy_file(work / 'official.aar', source / 'official.aar')
        collect_dependency_sources(parts, records, source)
        shutil.copytree(parts / 'abi', source / 'build-provenance')
        archive_tree(source, out / 'libvlc-corresponding-source.tar.xz', prepared['source_date_epoch'])
    archive_tree(parts / 'licenses', out / 'libvlc-licenses.tar.xz', prepared['source_date_epoch'])
    provenance['aar_sha256'] = sha(out / AAR)
    write_json(out / 'libvlc-provenance.json', provenance)
    (out / 'LIBVLC_SHA256SUMS').write_text(''.join(
        f'{sha(p)}  {p.name}\n' for p in sorted(out.iterdir()) if p.is_file()))
    # One durable, hash-pinnable public asset contains the SDK and its source offer.
    with tempfile.TemporaryDirectory(prefix='privi-libvlc-bundle-') as temp:
        bundle = Path(temp) / BUNDLE
        archive_tree(out, bundle, prepared['source_date_epoch'])
        copy_file(bundle, out / BUNDLE)
    (out / (BUNDLE + '.sha256')).write_text(f'{sha(out / BUNDLE)}  {BUNDLE}\n')
    print('SDK_BUNDLE_SHA256=' + sha(out / BUNDLE))
    print('SDK_AAR_SHA256=' + sha(out / AAR))


def verify_bundle(bundle, expected, commit, dest):
    check_sha(bundle, expected)
    extract(bundle, dest)
    checksums = dest / 'LIBVLC_SHA256SUMS'
    listed = set()
    for line in checksums.read_text().splitlines():
        digest, name = line.split('  ', 1)
        if Path(name).name != name or name in listed:
            fail('Invalid or duplicate SDK checksum entry')
        check_sha(dest / name, digest)
        listed.add(name)
    required = {AAR, 'libvlc-provenance.json', 'libvlc-corresponding-source.tar.xz', 'libvlc-licenses.tar.xz'}
    if listed != required:
        fail('Incomplete SDK/source/license bundle')
    info = json.loads((dest / 'libvlc-provenance.json').read_text())
    if info['project_commit'] != commit or info['source_lock_sha256'] != sha(LOCK_PATH):
        fail('SDK commit or source lock differs from the explicitly selected input')
    if info['source_lock'] != LOCK or set(info['abis']) != set(TARGETS):
        fail('SDK provenance does not cover the locked three-ABI build')
    if info['custom_patches'] != custom_patch_records():
        fail('SDK provenance patch target/order/hash differs from the source lock')
    check_sha(dest / AAR, info['aar_sha256'])
    with zipfile.ZipFile(dest / AAR) as aar:
        for abi, record in info['abis'].items():
            if any(record[key] != info[key] for key in (*SOURCE_STATE_KEYS, 'custom_patches')):
                fail('AAR ABI provenance came from different JNI/VLC source trees: ' + abi)
            for name, details in record['libraries'].items():
                if hashlib.sha256(aar.read(f'jni/{abi}/{name}')).hexdigest() != details['sha256']:
                    fail('AAR native bytes differ from SDK provenance')
    return info


def consume(args):
    patch_inputs()
    if not re.fullmatch('[0-9a-f]{40}', args.commit):
        fail('--commit must be the full SDK workflow source commit')
    out = fresh_dir(args.output_dir)
    bundle = out / BUNDLE
    if args.command == 'fetch-run':
        if not re.fullmatch('[0-9]+', args.run_id):
            fail('--run-id must be a numeric successful same-repository SDK workflow run')
        repository = os.environ['GITHUB_REPOSITORY']
        source = json.loads(run(['gh', 'api', f'repos/{repository}/actions/runs/{args.run_id}']))
        if not (source['head_repository']['full_name'] == repository
                and source['path'] == '.github/workflows/libvlc-sdk.yml'
                and source['status'] == 'completed' and source['conclusion'] == 'success'
                and source['head_sha'] == args.commit):
            fail('Selected run is not a successful same-repository SDK workflow at --commit')
        subprocess.run(['gh', 'run', 'download', args.run_id, '--repo', repository,
                        '--name', 'privi-libvlc-sdk', '--dir', str(out)], check=True)
    else:
        if not args.url.startswith('https://github.com/') or '/releases/download/' not in args.url:
            fail('Use a permanent HTTPS GitHub Release SDK bundle asset URL')
        fetch(args.url, bundle, args.sha256)
    contents = out / 'contents'
    contents.mkdir()
    info = verify_bundle(bundle, args.sha256, args.commit, contents)
    (out / (BUNDLE + '.sha256')).write_text(f'{sha(bundle)}  {BUNDLE}\n')
    receipt = {'bundle_sha256': sha(bundle), 'sdk_commit': args.commit,
               'sdk_run_id': getattr(args, 'run_id', None), 'sdk_url': getattr(args, 'url', None),
               'aar_sha256': info['aar_sha256'], 'source_lock_sha256': info['source_lock_sha256']}
    write_json(out / 'LIBVLC_SDK_INPUT.json', receipt)
    # Gradle verifies the explicit file/hash pair again. There is no Maven fallback.
    variables = {
        'ORG_GRADLE_PROJECT_priviLibvlcAar': str(contents / AAR),
        'ORG_GRADLE_PROJECT_priviLibvlcAarSha256': info['aar_sha256'],
        'PRIVI_LIBVLC_BUNDLE': str(bundle),
        'PRIVI_LIBVLC_RECEIPT': str(out / 'LIBVLC_SDK_INPUT.json'),
    }
    if os.environ.get('GITHUB_ENV'):
        with open(os.environ['GITHUB_ENV'], 'a') as env:
            for name, value in variables.items():
                if '\n' in value or '\r' in value:
                    fail('Invalid newline in SDK path')
                env.write(name + '=' + value + '\n')
    print(json.dumps(variables, indent=2))


parser = argparse.ArgumentParser(description='Build or explicitly select the locked complete LibVLC SDK')
commands = parser.add_subparsers(dest='command', required=True)
commands.add_parser('plan')
for command in ['prepare', 'build', 'package']:
    sub = commands.add_parser(command)
    sub.add_argument('--work-dir', required=True)
    sub.add_argument('--output-dir', required=True)
    if command == 'prepare':
        sub.add_argument('--skip-archive', action='store_true', help='Prepare a local working tree without the workflow transport archive')
    if command == 'build':
        sub.add_argument('--abi', choices=list(TARGETS), required=True)
        sub.add_argument('--jobs', type=int, default=2)
        sub.add_argument('--timeout-seconds', type=int, default=18000)
    if command == 'package':
        sub.add_argument('--input-dir', required=True)
for command in ['fetch-run', 'fetch-release']:
    sub = commands.add_parser(command)
    sub.add_argument('--run-id' if command == 'fetch-run' else '--url', required=True)
    sub.add_argument('--commit', required=True)
    sub.add_argument('--sha256', required=True, help='Expected SHA-256 of the entire SDK bundle, not just its AAR')
    sub.add_argument('--output-dir', required=True)
args = parser.parse_args(sys.argv[2:])
try:
    if args.command == 'plan':
        print(json.dumps({'include': LOCK['targets']}, separators=(',', ':')))
    elif args.command == 'prepare':
        prepare(args)
    elif args.command == 'build':
        if args.jobs < 1 or args.timeout_seconds < 1:
            fail('Build jobs and timeout must be positive integers')
        build(args)
    elif args.command == 'package':
        package(args)
    else:
        consume(args)
except (RuntimeError, OSError, ValueError, KeyError, subprocess.SubprocessError, tarfile.TarError, zipfile.BadZipFile) as error:
    print('LibVLC SDK error:', error, file=sys.stderr)
    if isinstance(error, subprocess.CalledProcessError) and error.output:
        print(error.output, file=sys.stderr)
    sys.exit(1)
PY
