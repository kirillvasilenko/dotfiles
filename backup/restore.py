"""Preview and restore selected snapshot contents on Python 3.8+."""
from contextlib import contextmanager
import hashlib
import json
import os
from pathlib import Path
import shutil
import stat
import sys
import tarfile
import tempfile
import unicodedata

from archive import sha256, validate_archive
from capture import BackupError, git, git_state, relative_path, resolve_home, signature


class Conflicts(BackupError):
    pass


def target_path(home, relative):
    parts = relative_path(relative)
    current = home
    for part in parts[:-1]:
        current = current / part
        if os.path.lexists(current):
            info = current.lstat()
            if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid():
                raise BackupError('Unsafe destination parent: ' + str(current))
    return home.joinpath(*parts)


def file_state(path):
    if not os.path.lexists(path):
        return None
    info = path.lstat()
    if info.st_uid != os.getuid():
        raise BackupError('Destination belongs to another user: ' + str(path))
    if stat.S_ISLNK(info.st_mode):
        return {'kind': 'symlink', 'target': os.readlink(path)}
    if stat.S_ISDIR(info.st_mode):
        return {'kind': 'directory'}
    if not stat.S_ISREG(info.st_mode):
        raise BackupError('Unsupported destination file type: ' + str(path))
    descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    with os.fdopen(descriptor, 'rb') as stream:
        before = os.fstat(stream.fileno())
        digest = sha256(stream)
        after = os.fstat(stream.fileno())
    if signature(info) != signature(before) or signature(before) != signature(after):
        raise BackupError('Destination changed while checking: ' + str(path))
    return {'kind': 'file', 'mode': stat.S_IMODE(info.st_mode), 'size': info.st_size, 'sha256': digest}


def comparable(record):
    if record['kind'] == 'directory':
        return {'kind': 'directory'}
    if record['kind'] == 'symlink':
        return {'kind': 'symlink', 'target': record['target']}
    return record


def under(path, parent):
    return path == parent or path.startswith(parent + '/')


def selection(manifest, paths):
    for path in paths:
        relative_path(path)
    files = {name: record for name, record in manifest['files'].items()
             if not paths or any(under(name, parent) for parent in paths)}
    repos = [record for record in manifest['git']
             if not paths or any(under(record['path'], parent) for parent in paths)]
    for parent in paths:
        if not any(under(name, parent) for name in files) and not any(under(r['path'], parent) for r in repos):
            raise BackupError('Nothing stored at selection: ' + parent + '; select a checkout root for Git patches')
    return files, repos


def patch_paths(repo, patch):
    if not patch:
        return set()
    rows = git(repo, 'apply', '--numstat', '-z', '-', data=patch).split(b'\0')
    paths = set()
    for row in rows:
        if not row:
            continue
        fields = row.split(b'\t', 2)
        if len(fields) != 3 or not fields[2]:
            raise BackupError('Unsupported patch path format')
        name = os.fsdecode(fields[2])
        relative_path(name)
        paths.add(name)
    return paths


def patch_state(repo, patches):
    staged, unstaged = patches['staged'], patches['unstaged']
    if not staged and not unstaged:
        tree = git(repo, 'rev-parse', 'HEAD^{tree}').strip()
        return {'staged': tree, 'unstaged': tree, 'deleted': set()}
    with tempfile.TemporaryDirectory(prefix='dev-backup-check-patches-') as temp:
        work = Path(temp)
        objects = work / 'objects'
        objects.mkdir()
        source_objects = Path(os.fsdecode(git(repo, 'rev-parse', '--git-path', 'objects')).strip())
        if not source_objects.is_absolute():
            source_objects = repo / source_objects
        env = {'GIT_INDEX_FILE': str(work / 'index'), 'GIT_OBJECT_DIRECTORY': str(objects),
               'GIT_ALTERNATE_OBJECT_DIRECTORIES': json.dumps(str(source_objects.resolve()), ensure_ascii=False)}
        git(repo, 'read-tree', 'HEAD', extra_env=env)
        state = {}
        for kind, patch in (('staged', staged), ('unstaged', unstaged)):
            if patch:
                git(repo, 'apply', '--cached', '--whitespace=nowarn', '-', data=patch, extra_env=env)
            state[kind] = git(repo, 'write-tree', extra_env=env).strip()
        deleted = git(repo, 'diff', '--cached', '--name-only', '--diff-filter=D', '-z', 'HEAD', '--', extra_env=env)
        state['deleted'] = {os.fsdecode(name) for name in deleted.split(b'\0') if name}
        return state


def git_plan(home, record, archive):
    repo = target_path(home, record['path'])
    if not repo.is_dir() or repo.is_symlink() or not (repo / '.git').exists():
        raise BackupError('Missing checkout {}; prepare it at HEAD {}'.format(record['path'], record['head']))
    try:
        current = git_state(home, repo, [])
    except BackupError as error:
        raise BackupError('Cannot read checkout {}; required HEAD {}. {}'.format(
            record['path'], record['head'], error)) from error
    if current['head'] != record['head']:
        raise BackupError('HEAD mismatch in {}: need {}, found {}'.format(record['path'], record['head'], current['head']))
    patches = {}
    for kind in ('staged', 'unstaged'):
        with archive.extractfile(record[kind + '_patch']) as stream:
            patches[kind] = stream.read()
    expected = patch_state(repo, patches)
    current_trees = expected if all(current[k] == patches[k] for k in ('staged', 'unstaged')) else patch_state(repo, current)
    if all(current_trees[k] == expected[k] for k in ('staged', 'unstaged')):
        action = 'unchanged'
    elif not current['staged'] and not current['unstaged']:
        action = 'apply'
    elif current_trees['staged'] == expected['staged'] and not current['unstaged']:
        action = 'finish'
    elif patches['staged'] and not current['staged'] and current_trees['unstaged'] == expected['staged']:
        action = 'index'
    else:
        raise BackupError('Different existing Git changes in ' + record['path'])
    names = patch_paths(repo, patches['staged']) | patch_paths(repo, patches['unstaged'])
    for name in names:
        target_path(home, record['path'] + '/' + name)
    if action != 'unchanged':
        first = patches['staged'] if action == 'apply' and patches['staged'] else patches['unstaged']
        if first:
            git(repo, 'apply', '--check', '--whitespace=nowarn', '-', data=first)
    return {'path': record['path'], 'action': action, 'before': current, 'patches': patches,
            'affected': names, 'deleted': expected['deleted'], 'expected': expected}


def check_collisions(home, paths):
    parent = home
    while not parent.exists():
        parent = parent.parent
    with tempfile.TemporaryDirectory(prefix='.dev-backup-filesystem-', dir=parent) as temp:
        probe = Path(temp)
        (probe / 'CaseProbe').touch()
        insensitive = (probe / 'caseprobe').exists()
        (probe / '\u00e9').touch()
        normalizes = (probe / 'e\u0301').exists()
    seen = {}
    for name in paths:
        for i in range(1, len(name.split('/')) + 1):
            path = '/'.join(name.split('/')[:i])
            key = unicodedata.normalize('NFD', path) if normalizes else path
            key = key.casefold() if insensitive else key
            if key in seen and seen[key] != path:
                raise BackupError('Destination filesystem cannot distinguish {} and {}'.format(seen[key], path))
            seen[key] = path
            current = home
            for part in path.split('/'):
                if current.is_symlink():
                    raise BackupError('Destination parent is a symlink: ' + str(current))
                child = current / part
                if os.path.lexists(child) and current.is_dir():
                    if part not in os.listdir(current):
                        raise BackupError('Destination spelling/case conflict: ' + path)
                current = child


def plan_restore(snapshot, home, paths):
    manifest = validate_archive(snapshot)
    home = resolve_home(home)
    if home.exists() and (not home.is_dir() or home.stat().st_uid != os.getuid()):
        raise BackupError('Destination home must be a directory owned by you')
    files, repos = selection(manifest, paths)
    conflicts, file_plans, git_plans = [], [], []
    with tarfile.open(snapshot, 'r:gz') as archive:
        for record in repos:
            try:
                git_plans.append(git_plan(home, record, archive))
            except (BackupError, OSError) as error:
                conflicts.append(str(error))
        deleted = {p['path'] + '/' + name for p in git_plans for name in p['deleted']}
        will_delete = {p['path'] + '/' + name for p in git_plans if p['action'] == 'apply'
                       for name in p['deleted']}
        for name, record in sorted(files.items()):
            try:
                target = target_path(home, name)
                before = file_state(target)
                if name not in will_delete and before is not None and before != comparable(record):
                    raise BackupError('Different existing file: ' + name)
                if record['mode'] & ~0o777:
                    raise BackupError('Special permission bits are unsupported: ' + name)
                action = 'create' if before is None or name in will_delete else 'unchanged'
                file_plans.append({'path': name, 'record': record, 'action': action, 'before': before})
            except (BackupError, OSError) as error:
                conflicts.append(str(error))
    affected = {p['path'] + '/' + name for p in git_plans for name in p['affected']}
    try:
        check_collisions(home, set(files) | affected)
        for name in (affected & set(files)) - deleted:
            raise BackupError('File selected both as a patch and ordinary file: ' + name)
    except (BackupError, OSError) as error:
        conflicts.append(str(error))
    return {'home': home, 'files': file_plans, 'git': git_plans, 'conflicts': conflicts}


def display_plan(plan):
    print('Destination: ' + str(plan['home']))
    for repo in plan['git']:
        print('Git {}: {}'.format(repo['action'], repo['path']))
    created = [p['path'] for p in plan['files'] if p['action'] == 'create']
    for name in created[:30]:
        print('Create: ' + name)
    if len(created) > 30:
        print('... and {} more files/directories'.format(len(created) - 30))
    print('Files/directories: {} to create, {} already identical'.format(len(created), len(plan['files']) - len(created)))
    for conflict in plan['conflicts']:
        print('CONFLICT: ' + conflict)


def ensure_parents(home, name):
    target = target_path(home, name)
    target.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    target_path(home, name)
    return target


def create_file(home, entry, archive):
    target = ensure_parents(home, entry['path'])
    record = entry['record']
    current = file_state(target)
    if current == comparable(record):
        return
    if current is not None:
        raise BackupError('Destination changed since preview: ' + entry['path'])
    if record['kind'] == 'directory':
        target.mkdir(mode=0o700)
    elif record['kind'] == 'symlink':
        target.symlink_to(record['target'])
    else:
        descriptor, temp = tempfile.mkstemp(prefix='.dev-backup-restore-', dir=target.parent)
        try:
            with os.fdopen(descriptor, 'wb') as output, archive.extractfile('home/' + entry['path']) as source:
                shutil.copyfileobj(source, output)
                output.flush()
                os.fsync(output.fileno())
                os.fchmod(output.fileno(), record['mode'])
            os.link(temp, target)
        finally:
            os.unlink(temp)
    if file_state(target) != comparable(record):
        raise BackupError('Restored file verification failed: ' + entry['path'])


@contextmanager
def restore_lock(home):
    import fcntl
    key = hashlib.sha256(os.fsencode(home)).hexdigest()
    directory = Path(tempfile.gettempdir()) / ('dev-backup-restore-' + str(os.getuid()))
    directory.mkdir(mode=0o700, exist_ok=True)
    info = directory.lstat()
    if directory.is_symlink() or info.st_uid != os.getuid() or stat.S_IMODE(info.st_mode) != 0o700:
        raise BackupError('Unsafe restore lock directory')
    fd = os.open(directory / key, os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    with os.fdopen(fd, 'a') as stream:
        try:
            fcntl.flock(stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise BackupError('Another restore is running for this destination') from None
        yield


def restore(snapshot, home, paths=(), apply=False):
    requested_home = home
    home = resolve_home(home)
    with restore_lock(home):
        plan = plan_restore(snapshot, requested_home, paths)
        display_plan(plan)
        if plan['conflicts']:
            raise Conflicts('Restore blocked; resolve the conflicts first. Nothing was restored.')
        if not apply:
            print('Preview only. Add --apply to restore.')
            return plan
        home.mkdir(parents=True, exist_ok=True, mode=0o700)
        try:
            for entry in plan['files']:
                current = file_state(target_path(home, entry['path']))
                if current != entry['before']:
                    raise BackupError('Destination changed since preview: ' + entry['path'])
            for item in plan['git']:
                repo = target_path(home, item['path'])
                current = git_state(home, repo, [])
                for key in ('head', 'branch', 'staged', 'unstaged', 'index_sha256'):
                    if current[key] != item['before'][key]:
                        raise BackupError('Git state changed since preview: ' + item['path'])
                if item['action'] == 'apply' and item['patches']['staged']:
                    git(repo, 'apply', '--whitespace=nowarn', '-', data=item['patches']['staged'])
                if item['action'] in ('apply', 'index') and item['patches']['staged']:
                    git(repo, 'apply', '--cached', '--whitespace=nowarn', '-', data=item['patches']['staged'])
                if item['action'] != 'unchanged' and item['patches']['unstaged']:
                    git(repo, 'apply', '--whitespace=nowarn', '-', data=item['patches']['unstaged'])
                after = git_state(home, repo, [])
                if any(after[kind] != item['patches'][kind] for kind in ('staged', 'unstaged')):
                    actual = patch_state(repo, after)
                    if any(actual[kind] != item['expected'][kind] for kind in ('staged', 'unstaged')):
                        raise BackupError('Git verification failed: ' + item['path'])
            with tarfile.open(snapshot, 'r:gz') as archive:
                for entry in plan['files']:
                    create_file(home, entry, archive)
            for entry in reversed(plan['files']):
                if entry['action'] == 'create' and entry['record']['kind'] == 'directory':
                    target_path(home, entry['path']).chmod(entry['record']['mode'])
        except (BackupError, OSError) as error:
            raise BackupError('Restore interrupted; some entries may already be restored. ' + str(error)) from error
        print('Restore completed and verified.')
        return plan


def remote_main(options):
    os.umask(0o077)
    try:
        with tempfile.TemporaryDirectory(prefix='dev-backup-import-') as temp:
            snapshot = Path(temp) / 'snapshot.tar.gz'
            with snapshot.open('wb') as output:
                shutil.copyfileobj(sys.stdin.buffer, output)
            with snapshot.open('rb') as stream:
                if sha256(stream) != options['sha256']:
                    raise BackupError('Transferred snapshot checksum mismatch')
            restore(snapshot, options.get('home') or Path.home(), options['paths'], options['apply'])
        return 0
    except (BackupError, OSError, ValueError, KeyError, TypeError, tarfile.TarError, EOFError) as error:
        print('dev-backup restore: ' + str(error), file=sys.stderr)
        return 1
