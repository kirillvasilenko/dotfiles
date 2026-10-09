"""Snapshot integrity checks shared by backup and restore."""
import gzip
import hashlib
import json
from pathlib import Path
import re
import tarfile

from capture import BackupError, relative_path


def sha256(stream):
    digest = hashlib.sha256()
    while True:
        block = stream.read(1024 * 1024)
        if not block:
            break
        digest.update(block)
    return digest.hexdigest()


def validate_archive(path):
    with gzip.open(path, 'rb') as stream:
        while stream.read(1024 * 1024):
            pass
    actual, manifest = {}, None
    with tarfile.open(path, 'r:gz') as archive:
        for member in archive:
            relative_path(member.name)
            if member.name in actual:
                raise BackupError('Duplicate archive entry: ' + member.name)
            mode = member.mode
            if member.isfile():
                with archive.extractfile(member) as stream:
                    if member.name == 'manifest.json':
                        if member.size > 64 * 1024 * 1024:
                            raise BackupError('Manifest too large')
                        manifest = json.load(stream)
                        actual[member.name] = None
                        continue
                    actual[member.name] = {'kind': 'file', 'mode': mode, 'size': member.size, 'sha256': sha256(stream)}
            elif member.isdir():
                actual[member.name] = {'kind': 'directory', 'mode': mode}
            elif member.issym():
                actual[member.name] = {'kind': 'symlink', 'mode': mode, 'target': member.linkname}
            else:
                raise BackupError('Unsupported archive member: ' + member.name)
    if not isinstance(manifest, dict) or manifest.get('format') != 1:
        raise BackupError('Missing or unsupported manifest')
    if not isinstance(manifest.get('files'), dict) or not isinstance(manifest.get('git'), list):
        raise BackupError('Invalid manifest selections')
    expected = {'manifest.json': None}
    for name, record in manifest['files'].items():
        relative_path(name)
        expected['home/' + name] = record
    repositories = set()
    for state in manifest['git']:
        if not isinstance(state, dict):
            raise BackupError('Invalid Git manifest entry')
        relative_path(state['path'])
        if state['path'] in repositories:
            raise BackupError('Duplicate Git checkout: ' + state['path'])
        repositories.add(state['path'])
        for kind in ('staged', 'unstaged'):
            name = state[kind + '_patch']
            if name in expected or not re.fullmatch(r'git/\d+/(staged|unstaged)\.patch', name):
                raise BackupError('Invalid patch path')
            expected[name] = {'kind': 'file', 'mode': 0o600, 'size': actual.get(name, {}).get('size'),
                              'sha256': state[kind + '_sha256']}
    if actual != expected:
        raise BackupError('Archive contents do not match the manifest')
    for name in actual:
        for parent in Path(name).parents:
            record = actual.get(parent.as_posix())
            if record is not None and record['kind'] != 'directory':
                raise BackupError('Archive entry underneath a non-directory: ' + name)
    return manifest
