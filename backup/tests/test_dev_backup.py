import base64
import errno
from contextlib import redirect_stdout, redirect_stderr
from datetime import timedelta
import hashlib
import io
import json
import os
from pathlib import Path
import stat
import struct
import subprocess
import sys
import tarfile
import tempfile
import unittest
from unittest.mock import patch
import zlib

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import capture
import client


def fixture_repository(path, base=None, staged=None, working=None, intent=()):
    base = base if base is not None else {'file.txt': (0o100644, b'base\n')}
    staged = staged if staged is not None else base
    working = working if working is not None else staged
    gitdir = path / '.git'
    (gitdir / 'objects').mkdir(parents=True)
    (gitdir / 'refs/heads').mkdir(parents=True)
    (gitdir / 'HEAD').write_text('ref: refs/heads/topic\n')
    (gitdir / 'config').write_text('[core]\nrepositoryformatversion = 0\nbare = false\nfilemode = true\n')

    def object_id(kind, data):
        data = kind.encode() + b' ' + str(len(data)).encode() + b'\0' + data
        digest = hashlib.sha1(data).hexdigest()
        target = gitdir / 'objects' / digest[:2] / digest[2:]
        target.parent.mkdir(exist_ok=True)
        target.write_bytes(zlib.compress(data))
        return bytes.fromhex(digest)

    tree = b''
    for name, (mode, content) in sorted(base.items()):
        tree += ('{:o} '.format(mode) + name).encode() + b'\0' + object_id('blob', content)
    tree_id = object_id('tree', tree).hex()
    raw_commit = ('tree ' + tree_id + '\nauthor Fixture <fixture@example.com> 1 +0000\n'
                  'committer Fixture <fixture@example.com> 1 +0000\n\nfixture\n').encode()
    head = object_id('commit', raw_commit).hex()
    (gitdir / 'refs/heads/topic').write_text(head + '\n')
    index = b'DIRC' + struct.pack('!II', 3 if intent else 2, len(staged))
    for name, (mode, content) in sorted(staged.items()):
        entry = struct.pack('!10I', 0, 0, 0, 0, 0, 0, mode, 0, 0, len(content))
        entry += object_id('blob', content) + struct.pack('!H', len(name.encode()) | (0x4000 if name in intent else 0))
        if name in intent:
            entry += struct.pack('!H', 0x2000)
        entry += name.encode() + b'\0'
        index += entry + b'\0' * (-len(entry) % 8)
    (gitdir / 'index').write_bytes(index + hashlib.sha1(index).digest())
    for name, (mode, content) in working.items():
        target = path / name
        target.parent.mkdir(parents=True, exist_ok=True)
        if mode == 0o120000:
            target.symlink_to(os.fsdecode(content))
        else:
            target.write_bytes(content)
            target.chmod(stat.S_IMODE(mode))
    return head


class BackupTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='dev-backup-test-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.home = self.root / 'home'
        self.home.mkdir()
        self.destination = self.root / 'backups'
        self.config = client.validate_config({
            'host': 'fixture-host', 'backup_dir': str(self.destination),
            'files': {'include': ['notes']},
        })
        (self.home / 'notes').mkdir()
        (self.home / 'notes/plan.md').write_bytes(b'review plan\n')
        self.output = self.root / 'snapshot.tar.gz'

    def capture(self):
        capture.capture(self.home, self.config, self.output)
        return client.validate_archive(self.output)

    def run_backup(self):
        def sender(config, output):
            capture.capture(self.home, config, output)
        with redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()):
            return client.run_backup(self.config, sender=sender)

    def select_git(self, patterns=None):
        self.config['files'] = {'include': []}
        self.config['git'] = [{'include': ['repos/*'], 'untracked': patterns or []}]
        return self.home / 'repos/project'

    def test_plain_files_preserve_content_modes_empty_dirs_and_symlinks(self):
        (self.home / 'notes/empty').mkdir()
        (self.home / 'notes/plan.md').chmod(0o751)
        (self.home / 'notes/link').symlink_to('/unavailable/target')
        manifest = self.capture()
        self.assertEqual(manifest['files']['notes/plan.md']['mode'], 0o751)
        self.assertEqual(manifest['files']['notes/empty']['kind'], 'directory')
        self.assertEqual(manifest['files']['notes/link']['target'], '/unavailable/target')
        with tarfile.open(self.output) as archive:
            self.assertEqual(archive.extractfile('home/notes/plan.md').read(), b'review plan\n')

    def test_conversations_copied_byte_for_byte_without_parsing(self):
        (self.home / 'notes/rollout.jsonl').write_bytes(b'{"type":"session_meta"}\n{"unfinished":')
        self.capture()
        with tarfile.open(self.output) as archive:
            self.assertEqual(archive.extractfile('home/notes/rollout.jsonl').read(), b'{"type":"session_meta"}\n{"unfinished":')

    def test_missing_patterns_reported_and_empty_selection_fails(self):
        self.config['files']['include'].append('missing')
        self.assertEqual(self.capture()['missing_patterns'], ['missing'])
        self.config['files']['include'] = ['missing']
        with self.assertRaisesRegex(capture.BackupError, 'No configured paths'):
            self.capture()

    def test_new_matching_directories_are_discovered(self):
        self.config['files']['include'] = ['projects/*/sync']
        for name in ('first', 'second'):
            target = self.home / 'projects' / name / 'sync'
            target.mkdir(parents=True)
            (target / 'file').write_text(name)
            manifest = self.capture()
            self.assertIn('projects/' + name + '/sync/file', manifest['files'])

    def test_untracked_plans_are_captured_and_ignored_outputs_are_not(self):
        repo = self.select_git(['*.md', 'notes/**'])
        fixture_repository(repo)
        (repo / 'review_plan.md').write_text('review')
        (repo / 'implementation_plan.md').write_text('implementation')
        (repo / 'notes/deep').mkdir(parents=True)
        (repo / 'notes/deep/plan.txt').write_text('notes')
        (repo / 'build.md').write_text('ignored')
        (repo / 'unselected.txt').write_text('not selected')
        (repo / '.git/info').mkdir()
        (repo / '.git/info/exclude').write_text('build.md\n')
        manifest = self.capture()
        self.assertEqual(manifest['git'][0]['untracked'], ['implementation_plan.md', 'notes/deep/plan.txt', 'review_plan.md'])
        self.assertNotIn('repos/project/build.md', manifest['files'])
        self.assertEqual(manifest['git'][0]['omitted_untracked_count'], 1)

    def test_ignored_folder_can_be_selected_as_whole_directory(self):
        repo = self.select_git()
        fixture_repository(repo)
        (repo / '.git/info').mkdir()
        (repo / '.git/info/exclude').write_text('sync/\n')
        (repo / 'sync').mkdir()
        (repo / 'sync/notes.md').write_text('ignored but explicitly selected')
        self.config['files']['include'] = ['repos/*/sync']
        self.assertIn('repos/project/sync/notes.md', self.capture()['files'])

    def test_patches_cover_staging_deletion_binary_modes_and_new_tracked_files(self):
        base = {'edit.txt': (0o100644, b'base\n'), 'delete.txt': (0o100644, b'delete\n'),
                'binary': (0o100644, b'\x00base'), 'run': (0o100644, b'run\n')}
        staged = dict(base, **{'edit.txt': (0o100644, b'staged\n'), 'new file': (0o100644, b'new\n')})
        del staged['delete.txt']
        working = dict(staged, **{'edit.txt': (0o100644, b'unstaged\n'), 'binary': (0o100644, b'\x00changed'),
                                 'run': (0o100755, b'run\n')})
        repo = self.select_git()
        head = fixture_repository(repo, base, staged, working)
        index_before = (repo / '.git/index').read_bytes()
        manifest = self.capture()
        record = manifest['git'][0]
        self.assertEqual(record['head'], head)
        self.assertEqual(record['branch'], 'topic')
        self.assertEqual((repo / '.git/index').read_bytes(), index_before)
        with tarfile.open(self.output) as archive:
            staged_patch = archive.extractfile(record['staged_patch']).read()
            unstaged_patch = archive.extractfile(record['unstaged_patch']).read()
        self.assertIn(b'+staged', staged_patch)
        self.assertNotIn(b'+unstaged', staged_patch)
        self.assertIn(b'deleted file mode', staged_patch)
        self.assertIn(b'new file mode', staged_patch)
        self.assertIn(b'+unstaged', unstaged_patch)
        self.assertIn(b'GIT binary patch', unstaged_patch)
        self.assertIn(b'new mode 100755', unstaged_patch)
        for label, content, patch_bytes, flags in [('base', base, staged_patch, ['--cached']),
                                                  ('index', staged, unstaged_patch, [])]:
            target = self.root / label
            fixture_repository(target, content)
            result = subprocess.run(['git', '-C', str(target), 'apply', '--check', *flags, '-'],
                                    input=patch_bytes, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr.decode())

    def test_external_diff_and_textconv_are_disabled(self):
        repo = self.select_git()
        fixture_repository(repo, working={'file.txt': (0o100644, b'changed\n')})
        (repo / '.gitattributes').write_text('file.txt diff=custom\n')
        with (repo / '.git/config').open('a') as stream:
            stream.write('[diff "custom"]\ncommand = false\ntextconv = false\n')
        self.assertEqual(len(self.capture()['git']), 1)

    def test_detached_head_is_recorded(self):
        repo = self.select_git()
        head = fixture_repository(repo)
        (repo / '.git/HEAD').write_text(head + '\n')
        self.assertIsNone(self.capture()['git'][0]['branch'])

    def test_linked_worktree_git_file_is_supported(self):
        repo = self.select_git()
        fixture_repository(repo)
        gitdir = self.home / 'metadata'
        (repo / '.git').rename(gitdir)
        (repo / '.git').write_text('gitdir: ' + str(gitdir) + '\n')
        self.assertEqual(self.capture()['git'][0]['path'], 'repos/project')

    def test_active_git_operation_fails_capture(self):
        repo = self.select_git()
        fixture_repository(repo)
        for operation in ('MERGE_HEAD', 'rebase-merge', 'index.lock'):
            with self.subTest(operation=operation):
                marker = repo / '.git' / operation
                marker.write_text('fixture')
                with self.assertRaisesRegex(capture.BackupError, 'Unsupported Git operation'):
                    self.capture()
                marker.unlink()

    def test_intent_to_add_is_rejected_instead_of_losing_index_state(self):
        repo = self.select_git()
        staged = {'file.txt': (0o100644, b'base\n'), 'new.md': (0o100644, b'')}
        fixture_repository(repo, staged=staged, working=dict(staged, **{'new.md': (0o100644, b'new\n')}),
                           intent=['new.md'])
        with self.assertRaisesRegex(capture.BackupError, 'Intent-to-add'):
            self.capture()

    def test_full_checkout_file_selection_is_rejected(self):
        fixture_repository(self.home / 'repo')
        self.config['files']['include'] = ['repo']
        with self.assertRaisesRegex(capture.BackupError, 'Select checkouts'):
            self.capture()

    def test_duplicate_git_selections_fail(self):
        repo = self.select_git()
        fixture_repository(repo)
        self.config['git'].append({'include': ['repos/project']})
        with self.assertRaisesRegex(capture.BackupError, 'multiple Git patterns'):
            self.capture()

    def test_unsafe_config_paths_fail(self):
        for value in ('../outside', '/outside', 'arcadia/project', '*/project', 'repos/**', 'repo/.git', 'notes/../other'):
            with self.subTest(value=value), self.assertRaises(capture.BackupError):
                capture.discover(self.home, value)

    def test_broader_home_cannot_bypass_arcadia_guard(self):
        (self.home / 'arcadia').mkdir()
        with patch('capture.Path.home', return_value=self.home):
            for pattern in ('home/arcadia', 'home/arcadia/*'):
                with self.subTest(pattern=pattern), self.assertRaisesRegex(capture.BackupError, 'arcadia'):
                    capture.capture(self.root, {'files': {'include': [pattern]}}, self.output)

    def test_arcadia_alias_is_rejected_but_explicit_junk_is_allowed(self):
        mount = self.root / 'mount'
        (mount / 'scratch').mkdir(parents=True)
        (self.home / 'arcadia').symlink_to(mount)
        (self.home / 'junk').symlink_to(mount / 'scratch')
        with patch('capture.Path.home', return_value=self.home):
            with self.assertRaisesRegex(capture.BackupError, 'arcadia'):
                capture.resolve_home(self.home / 'arcadia')
            self.assertEqual(capture.resolve_home(self.home / 'junk'), (mount / 'scratch').resolve())
            with self.assertRaisesRegex(capture.BackupError, 'arcadia'):
                capture.resolve_home(self.home / 'junk/..')

    def test_directory_symlinks_are_never_followed(self):
        outside = self.root / 'outside'
        outside.mkdir()
        (outside / 'secret').write_text('never copy')
        (self.home / 'notes/link').symlink_to(outside, target_is_directory=True)
        manifest = self.capture()
        self.assertNotIn('notes/link/secret', manifest['files'])
        self.config['files']['include'] = ['notes/link/*']
        with self.assertRaisesRegex(capture.BackupError, 'symlink'):
            self.capture()

    def test_other_users_files_are_rejected(self):
        with patch('capture.os.getuid', return_value=os.getuid() + 1):
            with self.assertRaisesRegex(capture.BackupError, 'another user'):
                self.capture()

    def test_special_files_are_rejected(self):
        os.mkfifo(self.home / 'notes/pipe')
        with self.assertRaisesRegex(capture.BackupError, 'Unsupported file type'):
            self.capture()

    def test_changing_source_is_retried(self):
        original = capture.inventory
        calls = []

        def inventory(home, roots):
            calls.append(1)
            if len(calls) == 2:
                (self.home / 'notes/plan.md').write_text('changed')
            return original(home, roots)

        with patch('capture.inventory', side_effect=inventory):
            manifest = self.capture()
        self.assertEqual(manifest['files']['notes/plan.md']['sha256'], hashlib.sha256(b'changed').hexdigest())

    def test_unstable_source_never_succeeds(self):
        with patch('capture.capture_once', side_effect=capture.Changed('busy')) as attempt:
            with self.assertRaisesRegex(capture.BackupError, 'after 3 attempts'):
                self.capture()
        self.assertEqual(attempt.call_count, 3)

    def test_archive_keeps_case_distinct_names_without_extraction(self):
        manifest = {'format': 1, 'git': [], 'files': {}}
        with tarfile.open(self.output, 'w:gz') as archive:
            for name, content in [('A', b'upper'), ('a', b'lower')]:
                capture.add_bytes(archive, 'home/' + name, content)
                manifest['files'][name] = {'kind': 'file', 'size': len(content), 'mode': 0o600,
                                         'sha256': hashlib.sha256(content).hexdigest()}
            capture.add_bytes(archive, 'manifest.json', json.dumps(manifest).encode())
        self.assertEqual(client.validate_archive(self.output), manifest)

    def test_corrupt_archive_rejected(self):
        self.capture()
        self.output.write_bytes(self.output.read_bytes()[:-8])
        with self.assertRaises((EOFError, OSError, capture.BackupError)):
            client.validate_archive(self.output)

    def test_manifest_hash_mismatch_rejected(self):
        manifest = {'format': 1, 'git': [], 'files': {'file': {'kind': 'file', 'mode': 0o600, 'size': 1, 'sha256': 'wrong'}}}
        with tarfile.open(self.output, 'w:gz') as archive:
            capture.add_bytes(archive, 'home/file', b'x')
            capture.add_bytes(archive, 'manifest.json', json.dumps(manifest).encode())
        with self.assertRaisesRegex(capture.BackupError, 'do not match'):
            client.validate_archive(self.output)

    def test_invalid_manifest_selection_types_are_rejected(self):
        with tarfile.open(self.output, 'w:gz') as archive:
            capture.add_bytes(archive, 'manifest.json', b'{"format": 1, "files": [], "git": []}')
        with self.assertRaisesRegex(capture.BackupError, 'Invalid manifest selections'):
            client.validate_archive(self.output)

    def test_archive_traversal_rejected(self):
        with tarfile.open(self.output, 'w:gz') as archive:
            capture.add_bytes(archive, '../escape', b'x')
        with self.assertRaisesRegex(capture.BackupError, 'Unsafe path'):
            client.validate_archive(self.output)

    def test_failed_transfer_keeps_previous_snapshot_and_cleans_partial(self):
        original = self.run_backup()

        def broken(config, output):
            output.write_bytes(b'incomplete')
            raise capture.BackupError('disconnected')

        with self.assertRaisesRegex(capture.BackupError, 'disconnected'):
            client.run_backup(self.config, sender=broken)
        self.assertEqual(client.snapshots(self.destination), [original])
        self.assertFalse(list((self.destination / 'snapshots').glob('.partial-*')))
        self.assertEqual(json.loads((self.destination / 'status.json').read_text())['error'], 'disconnected')

    def test_invalid_transfer_is_not_published(self):
        def invalid(config, output):
            output.write_bytes(b'not an archive')
        with self.assertRaises(OSError):
            client.run_backup(self.config, sender=invalid)
        self.assertFalse(client.snapshots(self.destination))

    def test_retention_removes_only_old_successful_snapshots(self):
        self.config['keep_snapshots'] = 2
        first = self.run_backup()
        unrelated = self.destination / 'snapshots/manual-notes'
        unrelated.mkdir()
        second, third = self.run_backup(), self.run_backup()
        self.assertFalse(first.exists())
        self.assertEqual(client.snapshots(self.destination), [second, third])
        self.assertTrue(unrelated.exists())

    def test_damaged_old_receipt_does_not_block_new_backups_or_retention(self):
        self.config['keep_snapshots'] = 1
        old = self.run_backup()
        (old / 'receipt.json').write_text('{broken')
        latest = self.run_backup()
        self.assertEqual(client.snapshots(self.destination), [latest])
        self.assertFalse(old.exists())

    def test_special_permissions_are_rejected_during_capture(self):
        (self.home / 'notes').chmod(0o1700)
        with self.assertRaisesRegex(capture.BackupError, 'Special permission'):
            self.capture()

    def test_overlapping_backup_is_rejected(self):
        client.private_directory(self.destination)
        with client.lock(self.destination):
            with self.assertRaisesRegex(capture.BackupError, 'already running'):
                self.run_backup()

    def test_status_reports_stale_and_previous_failure(self):
        self.run_backup()
        out = io.StringIO()
        with redirect_stdout(out), patch('client.utcnow', return_value=client.utcnow() + timedelta(hours=1)):
            self.assertEqual(client.status(self.config), 1)
        self.assertIn('STALE', out.getvalue())
        client.atomic_json(self.destination / 'status.json', {'error': 'disconnected'})
        with redirect_stdout(io.StringIO()):
            self.assertEqual(client.status(self.config), 1)

    def test_success_clears_previous_failure(self):
        self.run_backup()
        client.atomic_json(self.destination / 'status.json', {'error': 'old failure'})
        self.run_backup()
        with redirect_stdout(io.StringIO()):
            self.assertEqual(client.status(self.config), 0)

    def test_private_permissions(self):
        previous = os.umask(0o077)
        try:
            snapshot = self.run_backup()
        finally:
            os.umask(previous)
        for path in (self.destination, snapshot, snapshot / 'snapshot.tar.gz', snapshot / 'receipt.json'):
            self.assertEqual(path.stat().st_mode & 0o077, 0)

    def test_public_destination_and_config_are_refused(self):
        with self.assertRaisesRegex(capture.BackupError, 'outside the dotfiles'):
            client.outside_repository(client.REPOSITORY / 'private-backups')
        config_path = self.root / 'config.toml'
        config_path.write_text('host = "example"\n')
        config_path.chmod(0o644)
        with self.assertRaisesRegex(capture.BackupError, 'mode 600'):
            client.read_config(config_path)

    def test_unknown_configuration_is_rejected(self):
        self.config['files']['exclude'] = ['*.tmp']
        with self.assertRaisesRegex(capture.BackupError, 'only include'):
            client.validate_config(self.config)

    def test_git_group_requires_a_selection(self):
        self.config['git'] = [{'untracked': ['*.md']}]
        with self.assertRaisesRegex(capture.BackupError, 'nonempty include'):
            client.validate_config(self.config)

    def test_untracked_globs_respect_path_boundaries(self):
        self.assertTrue(capture.matches('review_plan.md', '*.md'))
        self.assertFalse(capture.matches('nested/review_plan.md', '*.md'))
        self.assertTrue(capture.matches('notes/a/b/plan.md', 'notes/**'))
        self.assertTrue(capture.matches('plan.md', '**/*.md'))
        self.assertTrue(capture.matches('nested/plan.md', '**/*.md'))

    def test_failed_launchd_install_removes_only_new_plist(self):
        failure = subprocess.CalledProcessError(1, 'launchctl', stderr=b'fixture failure')
        with patch('client.sys.platform', 'darwin'), patch('client.Path.home', return_value=self.home):
            with patch('client.subprocess.run', side_effect=failure):
                with self.assertRaisesRegex(capture.BackupError, 'fixture failure'):
                    client.schedule(self.config, self.root / 'config.toml', True)
        self.assertFalse((self.home / 'Library/LaunchAgents' / (client.schedule_label(self.root / 'config.toml') + '.plist')).exists())

    def test_failed_launchd_removal_retains_plist(self):
        target = self.home / 'Library/LaunchAgents' / (client.schedule_label(self.root / 'config.toml') + '.plist')
        target.parent.mkdir(parents=True)
        target.write_bytes(b'fixture')
        failure = subprocess.CompletedProcess('launchctl', 1, stderr=b'fixture failure')
        with patch('client.sys.platform', 'darwin'), patch('client.Path.home', return_value=self.home):
            with patch('client.subprocess.run', return_value=failure):
                with self.assertRaisesRegex(capture.BackupError, 'schedule retained'):
                    client.schedule(self.config, self.root / 'config.toml', False)
        self.assertEqual(target.read_bytes(), b'fixture')

    def test_unloaded_job_can_still_be_unscheduled(self):
        config = self.root / 'config.toml'
        target = self.home / 'Library/LaunchAgents' / (client.schedule_label(config) + '.plist')
        target.parent.mkdir(parents=True)
        target.write_bytes(b'fixture')
        absent = subprocess.CompletedProcess('launchctl', errno.ESRCH, stderr=b'No such process')
        with patch('client.sys.platform', 'darwin'), patch('client.Path.home', return_value=self.home):
            with patch('client.subprocess.run', return_value=absent), redirect_stdout(io.StringIO()):
                client.schedule(None, config, False)
        self.assertFalse(target.exists())

    def test_ssh_transfer_passes_script_and_selection_without_source_installation(self):
        self.config['home'] = '~/work'
        def process(command, **kwargs):
            self.assertEqual(command[-2], 'fixture-host')
            self.assertIn('BatchMode=yes', command)
            encoded = command[-1].split()[-1]
            self.assertEqual(json.loads(base64.b64decode(encoded))['files'], {'include': ['notes']})
            self.assertEqual(json.loads(base64.b64decode(encoded))['home'], '~/work')
            self.assertIn(b'def remote_main', kwargs['stdin'].read())
            kwargs['stdout'].write(b'archive')
            return subprocess.CompletedProcess(command, 0, b'', b'')
        with patch('client.subprocess.run', side_effect=process):
            client.transfer(self.config, self.output)
        self.assertEqual(self.output.read_bytes(), b'archive')

    def test_remote_export_protocol_runs_with_temporary_home(self):
        encoded = base64.b64encode(json.dumps({'files': self.config['files'], 'git': [], 'home': str(self.home)}).encode()).decode()
        with (client.REPOSITORY / 'backup/capture.py').open('rb') as script, self.output.open('wb') as output:
            result = subprocess.run([sys.executable, '-', encoded], stdin=script, stdout=output,
                                    stderr=subprocess.PIPE)
        self.assertEqual(result.returncode, 0, result.stderr.decode())
        self.assertIn('notes/plan.md', client.validate_archive(self.output)['files'])


if __name__ == '__main__':
    unittest.main()
