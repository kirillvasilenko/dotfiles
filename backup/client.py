"""Mac-initiated private snapshots and launchd scheduling."""
import argparse
import base64
from contextlib import contextmanager
from datetime import datetime, timezone
import fcntl
import errno
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shlex
import shutil
import subprocess
import sys
import tarfile
import tempfile
import tomllib

from capture import BackupError, capture, matches, relative_path
from archive import sha256, validate_archive

DEFAULT_CONFIG = Path.home() / '.config/dev-backup/config.toml'
REPOSITORY = Path(__file__).resolve().parent.parent
LABEL = 'local.dev-backup'
SNAPSHOT_NAME = re.compile(r'^\d{8}T\d{12}Z$')


def utcnow():
    return datetime.now(timezone.utc)


def outside_repository(path):
    resolved = path.resolve()
    if resolved == REPOSITORY or REPOSITORY in resolved.parents:
        raise BackupError('Keep private configuration and backups outside the dotfiles repository')


def private_directory(path):
    outside_repository(path)
    path.mkdir(parents=True, mode=0o700, exist_ok=True)
    info = path.lstat()
    if path.is_symlink() or info.st_uid != os.getuid() or info.st_mode & 0o077:
        raise BackupError('Directory must be owned by you, not a symlink, and mode 700: ' + str(path))


def validate_config(config, require_selection=True, require_backup_dir=True):
    allowed = {'host', 'home', 'backup_dir', 'interval_minutes', 'keep_snapshots', 'files', 'git'}
    if 'destination' in config:
        raise BackupError('Rename destination to backup_dir in your configuration')
    unknown = set(config) - allowed
    if unknown:
        raise BackupError('Unknown configuration keys: ' + ', '.join(sorted(unknown)))
    host = config.get('host')
    if not isinstance(host, str) or not re.fullmatch(r'[A-Za-z0-9_][A-Za-z0-9_.@-]*', host):
        raise BackupError('host must be an SSH alias, user@host, or local')
    home = config.setdefault('home', '~')
    if not isinstance(home, str) or '\x00' in home or not (home == '~' or home.startswith('~/') or Path(home).is_absolute()):
        raise BackupError('home must be ~, an absolute path, or start with ~/')
    destination = config.get('backup_dir')
    if require_backup_dir or destination is not None:
        if not isinstance(destination, str) or '\x00' in destination or not Path(destination).expanduser().is_absolute():
            raise BackupError('backup_dir must be an absolute path or start with ~/')
    for key, default in (('interval_minutes', 10), ('keep_snapshots', 144)):
        value = config.setdefault(key, default)
        if type(value) is not int or value < 1:
            raise BackupError(key + ' must be a positive integer')
    files, groups = config.setdefault('files', {}), config.setdefault('git', [])
    if not isinstance(files, dict) or set(files) - {'include'}:
        raise BackupError('[files] supports only include')
    if not isinstance(groups, list):
        raise BackupError('Use [[git]] sections')
    selections = [files.get('include', [])]
    for group in groups:
        if not isinstance(group, dict) or set(group) - {'include', 'untracked'}:
            raise BackupError('[[git]] supports only include and untracked')
        if not group.get('include'):
            raise BackupError('Each [[git]] section needs a nonempty include array')
        selections.append(group.get('include', []))
        patterns = group.get('untracked', [])
        if not isinstance(patterns, list):
            raise BackupError('untracked must be an array')
        for pattern in patterns:
            matches('validation', pattern)
    for patterns in selections:
        if not isinstance(patterns, list):
            raise BackupError('include must be an array')
        for pattern in patterns:
            relative_path(pattern, pattern=True)
    if require_selection and not any(selections):
        raise BackupError('Configure at least one include path')
    return config


def read_config(path, overrides=None, require_selection=True, require_backup_dir=True):
    outside_repository(path)
    info = path.lstat()
    if path.is_symlink() or info.st_uid != os.getuid() or info.st_mode & 0o077:
        raise BackupError('Configuration must be owned by you, not a symlink, and mode 600: ' + str(path))
    with path.open('rb') as stream:
        config = tomllib.load(stream)
    config.update(overrides or {})
    return validate_config(config, require_selection, require_backup_dir)


def atomic_json(path, value):
    descriptor, temp = tempfile.mkstemp(prefix='.' + path.name, dir=path.parent)
    try:
        with os.fdopen(descriptor, 'w') as stream:
            json.dump(value, stream, indent=2)
            stream.write('\n')
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temp, path)
    finally:
        if os.path.exists(temp):
            os.unlink(temp)


def transfer(config, output):
    if config['host'] == 'local':
        capture(config['home'], config, output)
        with output.open('rb') as stream:
            os.fsync(stream.fileno())
        return
    selection = {key: config[key] for key in ('files', 'git', 'home')}
    encoded = base64.b64encode(json.dumps(selection).encode()).decode()
    command = shlex.join(['python3', '-', encoded])
    with Path(__file__).with_name('capture.py').open('rb') as script, output.open('wb') as stream:
        result = subprocess.run(
            ['ssh', '-T', '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=15',
             '-o', 'ServerAliveInterval=15', '-o', 'ServerAliveCountMax=3',
             '--', config['host'], command], stdin=script, stdout=stream,
            stderr=subprocess.PIPE, timeout=3600,
        )
        if result.returncode:
            raise BackupError('SSH capture failed: ' + result.stderr.decode(errors='replace').strip())
        stream.flush()
        os.fsync(stream.fileno())


@contextmanager
def lock(destination):
    descriptor = os.open(destination / '.lock', os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    with os.fdopen(descriptor, 'a') as stream:
        try:
            fcntl.flock(stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise BackupError('Another backup is already running') from None
        yield


def snapshots(destination):
    root = destination / 'snapshots'
    if not root.exists():
        return []
    return sorted(path for path in root.iterdir()
                  if SNAPSHOT_NAME.fullmatch(path.name) and path.is_dir() and not path.is_symlink())


def read_receipt(path):
    receipt = path / 'receipt.json'
    try:
        data = json.loads(receipt.read_text())
        if not isinstance(data, dict) or data.get('format') != 1:
            raise ValueError('unsupported format')
        if not re.fullmatch(r'[0-9a-f]{64}', data.get('sha256', '')):
            raise ValueError('missing or invalid checksum')
        return data
    except (OSError, ValueError, TypeError) as error:
        raise BackupError('Invalid snapshot receipt {}: {}'.format(receipt, error)) from error


def prune(destination, keep):
    for path in snapshots(destination)[:-keep]:
        shutil.rmtree(path)


def run_backup(config, sender=transfer):
    destination = Path(config['backup_dir']).expanduser()
    private_directory(destination)
    with lock(destination):
        root = destination / 'snapshots'
        private_directory(root)
        started = utcnow().isoformat()
        try:
            with tempfile.TemporaryDirectory(prefix='.partial-', dir=root) as temp:
                work = Path(temp)
                output = work / 'snapshot.tar.gz'
                sender(config, output)
                manifest = validate_archive(output)
                with output.open('rb') as stream:
                    checksum = sha256(stream)
                completed = utcnow()
                name = completed.strftime('%Y%m%dT%H%M%S%fZ')
                receipt = {
                    'format': 1, 'started_at': started, 'completed_at': completed.isoformat(),
                    'sha256': checksum, 'bytes': output.stat().st_size,
                    'files': len(manifest['files']), 'checkouts': len(manifest['git']),
                    'missing_patterns': manifest['missing_patterns'],
                }
                atomic_json(work / 'receipt.json', receipt)
                os.rename(work, root / name)
            atomic_json(destination / 'status.json', {'last_attempt': started, 'error': None})
            prune(destination, config['keep_snapshots'])
        except Exception as error:
            atomic_json(destination / 'status.json', {'last_attempt': started, 'error': str(error)})
            raise
    print('Saved ' + str(root / name / 'snapshot.tar.gz'))
    if receipt['missing_patterns']:
        print('No matches: ' + ', '.join(receipt['missing_patterns']), file=sys.stderr)
    return root / name


def status(config):
    destination = Path(config['backup_dir']).expanduser()
    records = snapshots(destination)
    state_path = destination / 'status.json'
    state = json.loads(state_path.read_text()) if state_path.exists() else {}
    if not records:
        print('No successful backups')
        if state.get('error'):
            print('Last failure: ' + state['error'])
        return 1
    path = records[-1]
    receipt = read_receipt(path)
    if not (path / 'snapshot.tar.gz').is_file():
        raise BackupError('Missing snapshot archive: ' + str(path))
    age = (utcnow() - datetime.fromisoformat(receipt['completed_at'])).total_seconds()
    stale = age > config['interval_minutes'] * 60 * 3
    print('Last success: ' + receipt['completed_at'])
    print('Snapshot: ' + str(path / 'snapshot.tar.gz'))
    print('Age: {:.1f} minutes{}'.format(age / 60, ' (STALE)' if stale else ''))
    if receipt['missing_patterns']:
        print('No matches: ' + ', '.join(receipt['missing_patterns']))
    if state.get('error'):
        print('Last failure: ' + state['error'])
    return 1 if stale or state.get('error') else 0


def schedule_label(config_path):
    identity = hashlib.sha256(os.fsencode(config_path.expanduser().resolve())).hexdigest()[:16]
    name = re.sub(r'[^A-Za-z0-9_-]', '-', config_path.stem)[:40]
    return LABEL + '.' + name + '.' + identity


def launchd_plist(config, config_path):
    destination = Path(config['backup_dir']).expanduser()
    label = schedule_label(config_path)
    return {
        'Label': label,
        'ProgramArguments': [sys.executable, str(REPOSITORY / 'backup/dev-backup'),
                             '--config', str(config_path.resolve()), 'backup'],
        'StartInterval': config['interval_minutes'] * 60,
        'RunAtLoad': True,
        'ProcessType': 'Background',
        'EnvironmentVariables': {'PATH': '/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin'},
        'StandardOutPath': str(destination / (label + '.log')),
        'StandardErrorPath': str(destination / (label + '-error.log')),
        'Umask': 0o077,
    }


def schedule(config, config_path, install):
    if sys.platform != 'darwin':
        raise BackupError('Scheduling is supported on macOS with launchd')
    label = schedule_label(config_path)
    target = Path.home() / 'Library/LaunchAgents' / (label + '.plist')
    domain = 'gui/' + str(os.getuid())
    if not install:
        if not target.exists():
            raise BackupError('No installed schedule for ' + str(config_path))
        result = subprocess.run(['launchctl', 'bootout', domain + '/' + label], capture_output=True)
        if result.returncode not in (0, errno.ESRCH):
            raise BackupError('launchctl failed; schedule retained: ' + result.stderr.decode(errors='replace'))
        target.unlink()
        print('Schedule removed for ' + str(config_path))
        return
    private_directory(Path(config['backup_dir']).expanduser())
    if target.exists():
        raise BackupError('Schedule already exists; run unschedule before replacing it')
    target.parent.mkdir(parents=True, exist_ok=True)
    with target.open('xb') as stream:
        plistlib.dump(launchd_plist(config, config_path), stream)
    try:
        subprocess.run(['launchctl', 'bootstrap', domain, str(target)], check=True, capture_output=True)
    except (OSError, subprocess.CalledProcessError) as error:
        target.unlink()
        detail = error.stderr.decode(errors='replace') if isinstance(error, subprocess.CalledProcessError) else str(error)
        raise BackupError('launchctl failed: ' + detail) from error
    print('Scheduled {} every {} minutes; first backup starts now'.format(config_path, config['interval_minutes']))


def snapshot_file(path):
    path = path.expanduser().resolve()
    receipt = None
    if path.is_dir():
        receipt = read_receipt(path)
        path = path / 'snapshot.tar.gz'
    elif path.with_name('receipt.json').exists():
        receipt = read_receipt(path.parent)
    with path.open('rb') as stream:
        checksum = sha256(stream)
    if receipt is not None and receipt['sha256'] != checksum:
        raise BackupError('Snapshot checksum does not match its receipt')
    validate_archive(path)
    return path, checksum


def restore_program(options):
    sources = {name: Path(__file__).with_name(name + '.py').read_text()
               for name in ('capture', 'archive', 'restore')}
    return ('import sys, types, json\n'
            'sys.dont_write_bytecode = True\n'
            'sources = ' + repr(sources) + '\n'
            'for name, source in sources.items():\n'
            ' module = types.ModuleType(name)\n'
            ' sys.modules[name] = module\n'
            ' exec(compile(source, name + ".py", "exec"), module.__dict__)\n'
            'sys.exit(sys.modules["restore"].remote_main(' + repr(options) + '))\n')


def run_restore(args, config):
    from restore import restore
    selected = args.snapshot
    if selected is not None and not selected.expanduser().is_absolute():
        raise BackupError('--snapshot must be an absolute archive or snapshot-directory path')
    if selected is None:
        records = snapshots(Path(config['backup_dir']).expanduser())
        if not records:
            raise BackupError('No successful snapshots in ' + config['backup_dir'])
        selected = records[-1]
    snapshot, checksum = snapshot_file(selected)
    print('Snapshot: ' + str(snapshot), flush=True)
    if config['host'] == 'local':
        home = Path(config['home']).expanduser()
        outside_repository(home)
        with tempfile.TemporaryDirectory(prefix='dev-backup-restore-snapshot-') as temp:
            saved = Path(temp) / 'snapshot.tar.gz'
            shutil.copyfile(snapshot, saved)
            with saved.open('rb') as stream:
                if sha256(stream) != checksum:
                    raise BackupError('Snapshot changed while preparing restore')
            restore(saved, home, args.paths, args.apply)
        return 0
    options = {'sha256': checksum, 'home': config['home'], 'paths': args.paths, 'apply': args.apply}
    encoded = base64.b64encode(restore_program(options).encode()).decode()
    bootstrap = 'import base64; exec(compile(base64.b64decode(' + repr(encoded) + '), "restore", "exec"))'
    command = shlex.join(['python3', '-c', bootstrap])
    print(('Applying restore' if args.apply else 'Previewing restore') + ' over SSH', flush=True)
    with snapshot.open('rb') as stream:
        result = subprocess.run(['ssh', '-T', '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=15',
                                 '-o', 'ServerAliveInterval=15', '-o', 'ServerAliveCountMax=3',
                                 '--', config['host'], command], stdin=stream)
    if result.returncode:
        raise BackupError('Remote restore failed; see the report above')
    return 0


def command_config(args):
    path = (args.config or DEFAULT_CONFIG).expanduser()
    overrides = {name: getattr(args, name) for name in ('host', 'home', 'backup_dir')
                 if getattr(args, name, None) is not None}
    needs_selection = args.command in ('backup', 'schedule', 'check-config')
    needs_storage = args.command != 'restore' or args.snapshot is None
    if args.config is None and not path.exists() and args.command == 'restore' and args.snapshot is not None and args.host:
        return path, validate_config(overrides, require_selection=False, require_backup_dir=False)
    return path, read_config(path, overrides, needs_selection, needs_storage)


def main(argv=None):
    os.umask(0o077)
    parser = argparse.ArgumentParser(description='Back up and restore selected files and Git changes locally or over SSH.',
                                     allow_abbrev=False)
    parser.add_argument('--config', type=Path, help='Config file (default: ~/.config/dev-backup/config.toml)')
    commands = parser.add_subparsers(dest='command', required=True)
    parsers = {}
    for command, help_text in (
            ('backup', 'Create a new snapshot'), ('restore', 'Preview a restore; add --apply to write changes'),
            ('status', 'Show the latest backup and failures'), ('check-config', 'Validate the configuration'),
            ('schedule', 'Enable automatic backups for this config'), ('unschedule', 'Disable this config’s schedule')):
        subparser = commands.add_parser(command, help=help_text, allow_abbrev=False)
        subparser.add_argument('--config', type=Path, default=argparse.SUPPRESS,
                               help='Config file (default: ~/.config/dev-backup/config.toml)')
        parsers[command] = subparser
    for command in ('backup', 'restore'):
        parsers[command].add_argument('--host', help='SSH alias or local (default: config host)')
        parsers[command].add_argument('--home', help='Base directory on that machine (default: config home, or ~)')
    parsers['backup'].add_argument('--backup-dir', help='Local snapshot storage directory (default: config backup_dir)')
    parsers['restore'].add_argument('--snapshot', type=Path,
                                    help='Explicit archive or snapshot-directory path (default: latest in config backup_dir)')
    parsers['restore'].add_argument('--path-to-restore', dest='paths', metavar='PATH', action='append', default=[],
                                    help='Home-relative path in the snapshot; repeatable; default: entire snapshot')
    parsers['restore'].add_argument('--apply', action='store_true', help='Apply the restore; default: preview only')
    args = parser.parse_args(argv)
    try:
        if args.command == 'unschedule':
            schedule(None, (args.config or DEFAULT_CONFIG).expanduser(), False)
            return 0
        config_path, config = command_config(args)
        if args.command == 'backup':
            run_backup(config)
        elif args.command == 'restore':
            return run_restore(args, config)
        elif args.command == 'status':
            return status(config)
        elif args.command == 'schedule':
            schedule(config, config_path, True)
        else:
            print('Configuration OK')
        return 0
    except (BackupError, OSError, ValueError, KeyError, TypeError, tarfile.TarError,
            EOFError, subprocess.SubprocessError) as error:
        print('dev-backup: ' + str(error), file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
