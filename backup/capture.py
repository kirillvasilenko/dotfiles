"""Read-only source capture; also runs over SSH on Python 3.8+."""
import base64
import fnmatch
import hashlib
import io
import json
import os
from pathlib import Path
import stat
import subprocess
import sys
import tarfile
import tempfile
from datetime import datetime, timezone


class BackupError(Exception):
    pass


class Changed(BackupError):
    pass


def resolve_home(value):
    original = Path(value).expanduser().absolute()
    home = original.resolve()
    user_home = Path.home().absolute()
    junk, arcadia = user_home / 'junk', user_home / 'arcadia'
    in_junk = '..' not in original.parts and (original == junk or junk in original.parents)
    arcadia = arcadia.resolve()
    if not in_junk and (home == arcadia or arcadia in home.parents):
        raise BackupError('Using arcadia as the home directory is forbidden')
    return home


def relative_path(value, pattern=False):
    if not isinstance(value, str) or not value or '\x00' in value:
        raise BackupError('Expected a nonempty home-relative path')
    parts = value.split('/')
    if any(p in ('', '.', '..', '.git') for p in parts) or value.startswith('/'):
        raise BackupError('Unsafe path: ' + value)
    if pattern and (any(c in parts[0] for c in '*?[') or '**' in parts):
        raise BackupError('Discovery needs a literal first directory and no **: ' + value)
    if parts[0] == 'arcadia':
        raise BackupError('Traversal of arcadia is forbidden')
    return parts


def owned(path):
    if path.name == 'arcadia' and path.parent == Path.home().resolve():
        raise BackupError('Traversal of arcadia is forbidden')
    info = path.lstat()
    if info.st_uid != os.getuid():
        raise BackupError('Source belongs to another user: ' + str(path))
    return info


def no_link_parents(home, relative):
    current = home
    for part in relative_path(relative)[:-1]:
        current = current / part
        if stat.S_ISLNK(owned(current).st_mode):
            raise BackupError('Refusing to traverse a symlink: ' + str(current))


def discover(home, pattern):
    parts = relative_path(pattern, pattern=True)
    current = [home]
    for part in parts:
        following = []
        for parent in current:
            if parent != home:
                info = owned(parent)
                if stat.S_ISLNK(info.st_mode):
                    raise BackupError('Refusing to discover through a symlink: ' + str(parent))
                if not stat.S_ISDIR(info.st_mode):
                    continue
            if any(c in part for c in '*?['):
                with os.scandir(parent) as entries:
                    following.extend(Path(e.path) for e in entries if fnmatch.fnmatchcase(e.name, part))
            else:
                path = parent / part
                if os.path.lexists(path):
                    following.append(path)
        current = sorted(following)
    return current


def matches(path, pattern):
    if not isinstance(pattern, str) or not pattern:
        raise BackupError('Untracked patterns must be nonempty strings')
    parts = pattern.split('/')
    if any(p in ('', '.', '..', '.git') for p in parts):
        raise BackupError('Unsafe untracked pattern: ' + pattern)
    names = path.split('/')

    def match(a, b):
        if not b:
            return not a
        if b[0] == '**':
            return match(a, b[1:]) or bool(a) and match(a[1:], b)
        return bool(a) and fnmatch.fnmatchcase(a[0], b[0]) and match(a[1:], b[1:])

    return match(names, parts)


def git(repo, *args, allowed=(0,), data=None, extra_env=None):
    env = dict(os.environ, GIT_OPTIONAL_LOCKS='0', GIT_TERMINAL_PROMPT='0', LC_ALL='C')
    for key in ('GIT_DIR', 'GIT_WORK_TREE', 'GIT_INDEX_FILE', 'GIT_COMMON_DIR',
                'GIT_OBJECT_DIRECTORY', 'GIT_ALTERNATE_OBJECT_DIRECTORIES', 'GIT_EXTERNAL_DIFF'):
        env.pop(key, None)
    env.update(extra_env or {})
    result = subprocess.run(
        ['git', '-c', 'core.fsmonitor=false', '-c', 'core.quotePath=true', '-c', 'core.splitIndex=false',
         '-c', 'diff.autoRefreshIndex=false', '-c', 'diff.algorithm=myers', '-c', 'diff.indentHeuristic=false',
         '-c', 'diff.suppressBlankEmpty=false',
         '-C', str(repo), *args], input=data, stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env,
    )
    if result.returncode not in allowed:
        raise BackupError('Git failed in {}: {}'.format(repo, result.stderr.decode(errors='replace').strip()))
    return result.stdout


def git_state(home, repo, untracked):
    relative = repo.relative_to(home).as_posix()
    no_link_parents(home, relative)
    if repo.is_symlink():
        raise BackupError('Git checkout is a symlink: ' + relative)
    owned(repo)
    top = Path(os.fsdecode(git(repo, 'rev-parse', '--show-toplevel').rstrip(b'\n')))
    if top.resolve() != repo.resolve():
        raise BackupError('Git selection must be a checkout root: ' + relative)
    gitdir = Path(os.fsdecode(git(repo, 'rev-parse', '--absolute-git-dir').rstrip(b'\n')))
    for name in ('MERGE_HEAD', 'CHERRY_PICK_HEAD', 'REVERT_HEAD', 'rebase-merge',
                 'rebase-apply', 'sequencer', 'BISECT_LOG', 'index.lock'):
        if (gitdir / name).exists():
            raise BackupError('Unsupported Git operation in {}: {}'.format(relative, name))
    if git(repo, 'ls-files', '--unmerged', '-z'):
        raise BackupError('Unmerged index in ' + relative)
    if git(repo, 'config', '--bool', 'core.sparseCheckout', allowed=(0, 1)).strip() == b'true':
        raise BackupError('Sparse checkout is unsupported: ' + relative)
    index = git(repo, 'ls-files', '--stage', '-z')
    if any(row.startswith(b'160000 ') for row in index.split(b'\x00')):
        raise BackupError('Submodules are unsupported: ' + relative)
    flags = git(repo, 'ls-files', '-v', '-z')
    if any(row and (row[:1].islower() or row[:1] == b'S') for row in flags.split(b'\x00')):
        raise BackupError('Assume-unchanged/skip-worktree entries are unsupported: ' + relative)
    head = git(repo, 'rev-parse', '--verify', 'HEAD').decode().strip()
    branch = git(repo, 'symbolic-ref', '--quiet', '--short', 'HEAD', allowed=(0, 1)).decode().strip() or None
    visible = git(repo, 'diff', '--cached', '--name-only', '-z', '--ita-visible-in-index', 'HEAD', '--')
    invisible = git(repo, 'diff', '--cached', '--name-only', '-z', '--ita-invisible-in-index', 'HEAD', '--')
    if visible != invisible:
        raise BackupError('Intent-to-add entries are unsupported; stage or unstage them first: ' + relative)
    options = ('--binary', '--full-index', '--no-ext-diff', '--no-textconv', '--no-renames',
               '--no-color', '--src-prefix=a/', '--dst-prefix=b/', '--unified=3', '--ignore-submodules=none',
               '--no-relative', '--inter-hunk-context=0', '-O' + os.devnull)
    staged = git(repo, 'diff', '--cached', *options, 'HEAD', '--')
    unstaged = git(repo, 'diff', *options, '--')
    others = [os.fsdecode(p) for p in git(repo, 'ls-files', '--others', '--exclude-standard', '-z').split(b'\x00') if p]
    selected = sorted(p for p in others if any(matches(p, pattern) for pattern in untracked))
    return {
        'path': relative, 'head': head, 'branch': branch,
        'untracked': selected, 'omitted_untracked_count': len(others) - len(selected),
        'index_sha256': hashlib.sha256(index + flags).hexdigest(),
        'staged': staged, 'unstaged': unstaged,
    }


def selections(home, config):
    roots, repositories, missing = set(), {}, []
    for pattern in config.get('files', {}).get('include', []):
        found = discover(home, pattern)
        roots.update(found)
        if not found:
            missing.append(pattern)
    for group in config.get('git', []):
        for pattern in group['include']:
            found = [p for p in discover(home, pattern) if not p.is_symlink() and (p / '.git').exists()]
            if not found:
                missing.append('git:' + pattern)
            for repo in found:
                if repo in repositories:
                    raise BackupError('Checkout selected by multiple Git patterns: ' + str(repo))
                repositories[repo] = group.get('untracked', [])
    states = [git_state(home, repo, patterns) for repo, patterns in sorted(repositories.items())]
    for state in states:
        roots.update(home / state['path'] / p for p in state['untracked'])
    if not roots and not states:
        raise BackupError('No configured paths or Git checkouts matched')
    return roots, states, sorted(missing)


def signature(info):
    return (info.st_dev, info.st_ino, info.st_mode, info.st_size, info.st_mtime_ns, info.st_ctime_ns)


def inventory(home, roots):
    entries = {}

    def visit(path):
        relative = path.relative_to(home).as_posix()
        relative_path(relative)
        if relative in entries:
            return
        no_link_parents(home, relative)
        info = owned(path)
        if not stat.S_ISLNK(info.st_mode) and stat.S_IMODE(info.st_mode) & ~0o777:
            raise BackupError('Special permission bits are unsupported: ' + relative)
        if stat.S_ISDIR(info.st_mode):
            if os.path.lexists(path / '.git'):
                raise BackupError('Select checkouts under [[git]], not [files]: ' + relative)
            kind, target = 'directory', None
        elif stat.S_ISREG(info.st_mode):
            kind, target = 'file', None
        elif stat.S_ISLNK(info.st_mode):
            kind, target = 'symlink', os.readlink(path)
        else:
            raise BackupError('Unsupported file type: ' + relative)
        entries[relative] = (signature(info), kind, target)
        if kind == 'directory':
            with os.scandir(path) as children:
                for child in sorted(children, key=lambda x: x.name):
                    visit(Path(child.path))

    for root in sorted(roots):
        visit(root)
    return entries


class DigestReader:
    def __init__(self, stream):
        self.stream = stream
        self.digest = hashlib.sha256()

    def read(self, size=-1):
        data = self.stream.read(size)
        self.digest.update(data)
        return data


def open_source(home, relative, expected):
    no_link_parents(home, relative)
    descriptor = os.open(home / relative, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    stream = os.fdopen(descriptor, 'rb')
    if signature(os.fstat(stream.fileno())) != expected:
        stream.close()
        raise Changed('Source changed: ' + relative)
    return stream


def add_bytes(archive, name, data):
    info = tarfile.TarInfo(name)
    info.size, info.mode = len(data), 0o600
    archive.addfile(info, io.BytesIO(data))


def capture_once(home, config, output):
    roots, states, missing = selections(home, config)
    output = Path(output).resolve()
    for root in roots:
        if not root.is_symlink() and (root == output or root in output.parents):
            raise BackupError('Backup archive is inside a selected source path: ' + str(root))
    entries = inventory(home, roots)
    records = {}
    with tarfile.open(output, 'w:gz', dereference=False) as archive:
        for relative, (expected, kind, target) in sorted(entries.items()):
            info = tarfile.TarInfo('home/' + relative)
            info.mode = stat.S_IMODE(expected[2])
            info.mtime = expected[4] / 1_000_000_000
            record = {'kind': kind, 'mode': info.mode}
            if kind == 'directory':
                info.type = tarfile.DIRTYPE
                archive.addfile(info)
            elif kind == 'symlink':
                info.type, info.linkname = tarfile.SYMTYPE, target
                record['target'] = target
                archive.addfile(info)
            else:
                info.size = expected[3]
                with open_source(home, relative, expected) as stream:
                    reader = DigestReader(stream)
                    archive.addfile(info, reader)
                    if signature(os.fstat(stream.fileno())) != expected:
                        raise Changed('File changed while copying: ' + relative)
                record.update(size=info.size, sha256=reader.digest.hexdigest())
            records[relative] = record
        git_records = []
        for number, state in enumerate(states):
            record = {k: v for k, v in state.items() if k not in ('staged', 'unstaged', 'index_sha256')}
            for kind in ('staged', 'unstaged'):
                name = 'git/{}/{}.patch'.format(number, kind)
                add_bytes(archive, name, state[kind])
                record[kind + '_patch'] = name
                record[kind + '_sha256'] = hashlib.sha256(state[kind]).hexdigest()
            git_records.append(record)
        after_roots, after_states, after_missing = selections(home, config)
        if (roots, states, missing) != (after_roots, after_states, after_missing) or entries != inventory(home, after_roots):
            raise Changed('Selections or Git state changed during capture')
        for relative, record in records.items():
            if record['kind'] == 'file':
                with open_source(home, relative, entries[relative][0]) as stream:
                    reader = DigestReader(stream)
                    while reader.read(1024 * 1024):
                        pass
                    if reader.digest.hexdigest() != record['sha256'] or signature(os.fstat(stream.fileno())) != entries[relative][0]:
                        raise Changed('File content changed during capture: ' + relative)
        manifest = {
            'format': 1, 'captured_at': datetime.now(timezone.utc).isoformat(),
            'source_home': str(home), 'files': records, 'git': git_records,
            'missing_patterns': missing,
            'limitations': ['Git HEAD commits must be available separately; local commits are not included.',
                            'Live capture is checked for changes but is not an atomic filesystem snapshot.',
                            'Conversation files are copied unchanged; application databases are not reconstructed.'],
        }
        add_bytes(archive, 'manifest.json', json.dumps(manifest, indent=2, ensure_ascii=True).encode())
    return manifest


def capture(home, config, output, attempts=3):
    home = resolve_home(home)
    if not home.is_dir():
        raise BackupError('Source home must be an existing directory')
    if home.stat().st_uid != os.getuid():
        raise BackupError('Source belongs to another user: ' + str(home))
    for attempt in range(attempts):
        try:
            return capture_once(home, config, output)
        except (Changed, FileNotFoundError) as error:
            if attempt == attempts - 1:
                raise BackupError('Source did not stabilize after {} attempts: {}'.format(attempts, error)) from error


def remote_main(home=None):
    os.umask(0o077)
    config = json.loads(base64.b64decode(sys.argv[1]))
    with tempfile.TemporaryDirectory(prefix='dev-backup-export-') as temp:
        output = Path(temp) / 'snapshot.tar.gz'
        capture(home or config.get('home', '~'), config, output)
        with output.open('rb') as source:
            while True:
                block = source.read(1024 * 1024)
                if not block:
                    break
                sys.stdout.buffer.write(block)


if __name__ == '__main__':
    try:
        remote_main()
    except (BackupError, OSError, ValueError) as error:
        print('Backup failed: ' + str(error), file=sys.stderr)
        sys.exit(1)
