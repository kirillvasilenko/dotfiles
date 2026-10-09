from contextlib import redirect_stdout
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
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import capture
import client
import restore
from test_dev_backup import fixture_repository


class RestoreTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='dev-restore-test-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.source = self.root / 'source'
        self.target = self.root / 'target'
        self.source.mkdir()
        self.snapshot = self.root / 'snapshot.tar.gz'
        self.config = {'files': {'include': []}, 'git': [{'include': ['repo'], 'untracked': ['*.md']}]}

    def backup(self):
        capture.capture(self.source, self.config, self.snapshot)

    def restore(self, apply=True, paths=()):
        with redirect_stdout(io.StringIO()):
            return restore.restore(self.snapshot, self.target, paths, apply)

    def plain_backup(self):
        self.config = {'files': {'include': ['notes']}, 'git': []}
        (self.source / 'notes/empty').mkdir(parents=True)
        (self.source / 'notes/plan.md').write_bytes(b'plan\n')
        (self.source / 'notes/plan.md').chmod(0o751)
        (self.source / 'notes/link').symlink_to('/absent/target')
        self.backup()

    def test_git_round_trip_preserves_staging_binary_deletions_modes_and_untracked(self):
        base = {'edit': (0o100644, b'base\n'), 'delete': (0o100644, b'delete\n'),
                'binary': (0o100644, b'\0base'), 'run': (0o100644, b'run\n'),
                'link': (0o120000, b'old-target')}
        staged = dict(base, edit=(0o100644, b'staged\n'), new=(0o100644, b'new\n'), binary=(0o100644, b'\0staged'))
        del staged['delete']
        working = dict(staged, edit=(0o100644, b'unstaged\n'), binary=(0o100644, b'\0unstaged'),
                       run=(0o100755, b'run\n'), link=(0o120000, b'new-target'))
        fixture_repository(self.source / 'repo', base, staged, working)
        (self.source / 'repo/review_plan.md').write_bytes(b'review\n')
        self.backup()
        fixture_repository(self.target / 'repo', base)
        self.restore()
        source_state = capture.git_state(self.source, self.source / 'repo', ['*.md'])
        target_state = capture.git_state(self.target, self.target / 'repo', ['*.md'])
        for key in ('head', 'branch', 'staged', 'unstaged', 'untracked'):
            self.assertEqual(target_state[key], source_state[key], key)
        self.assertEqual((self.target / 'repo/binary').read_bytes(), b'\0unstaged')
        self.assertEqual((self.target / 'repo/review_plan.md').read_bytes(), b'review\n')
        self.assertFalse((self.target / 'repo/delete').exists())
        self.assertTrue((self.target / 'repo/run').stat().st_mode & stat.S_IXUSR)
        self.assertEqual(os.readlink(self.target / 'repo/link'), 'new-target')

    def test_preview_does_not_modify_git_index_objects_or_worktree(self):
        fixture_repository(self.source / 'repo', staged={'file.txt': (0o100644, b'staged\n')},
                           working={'file.txt': (0o100644, b'working\n')})
        self.backup()
        fixture_repository(self.target / 'repo')
        with (self.target / 'repo/.git/config').open('a') as stream:
            stream.write('[core]\nsplitIndex = true\n')
        before = {p.relative_to(self.target): p.read_bytes() for p in self.target.rglob('*') if p.is_file()}
        self.restore(apply=False)
        after = {p.relative_to(self.target): p.read_bytes() for p in self.target.rglob('*') if p.is_file()}
        self.assertEqual(before, after)

    def test_diff_preferences_do_not_change_restore_results(self):
        base = {name: (0o100644, b'base\n') for name in ('a', 'b')}
        working = {name: (0o100644, b'changed\n') for name in base}
        fixture_repository(self.source / 'repo', base, working=working)
        order = self.root / 'diff-order'
        order.write_text('b\na\n')
        with (self.source / 'repo/.git/config').open('a') as stream:
            stream.write('[diff]\norderFile = ' + str(order) + '\ninterHunkContext = 20\n')
        self.backup()
        fixture_repository(self.target / 'repo', base)
        self.restore()
        for name in base:
            self.assertEqual((self.target / 'repo' / name).read_bytes(), b'changed\n')
        self.assertEqual(self.restore()['git'][0]['action'], 'unchanged')

    def test_repeat_restore_is_noop(self):
        fixture_repository(self.source / 'repo', staged={'file.txt': (0o100644, b'staged\n')},
                           working={'file.txt': (0o100644, b'working\n')})
        (self.source / 'repo/implementation_plan.md').write_text('plan')
        self.backup()
        fixture_repository(self.target / 'repo')
        self.restore()
        index = (self.target / 'repo/.git/index').read_bytes()
        stamp = (self.target / 'repo/implementation_plan.md').stat().st_mtime_ns
        plan = self.restore()
        self.assertEqual(plan['git'][0]['action'], 'unchanged')
        self.assertEqual((self.target / 'repo/.git/index').read_bytes(), index)
        self.assertEqual((self.target / 'repo/implementation_plan.md').stat().st_mtime_ns, stamp)

    def test_restore_with_different_diff_drivers_preserves_staging(self):
        content = b'SPECIAL header\nordinary label\n' + b'0\n' * 10 + b'base\n'
        base = {'.gitattributes': (0o100644, b'code.txt diff=custom\n'), 'code.txt': (0o100644, content)}
        staged = dict(base, **{'code.txt': (0o100644, content.replace(b'base', b'staged'))})
        working = dict(base, **{'code.txt': (0o100644, content.replace(b'base', b'working'))})
        fixture_repository(self.source / 'repo', base, staged, working)
        with (self.source / 'repo/.git/config').open('a') as stream:
            stream.write('[diff "custom"]\nxfuncname = ^SPECIAL.*\n')
        self.backup()
        fixture_repository(self.target / 'repo', base)
        self.restore()
        self.assertEqual((self.target / 'repo/code.txt').read_bytes(), working['code.txt'][1])
        self.assertEqual(capture.git(self.target / 'repo', 'show', ':code.txt'), staged['code.txt'][1])
        self.assertEqual(self.restore()['git'][0]['action'], 'unchanged')

    def test_staged_deletion_and_recreated_untracked_file_round_trip(self):
        base = {'plan.md': (0o100644, b'old\n')}
        fixture_repository(self.source / 'repo', base, staged={}, working={'plan.md': (0o100644, b'recreated\n')})
        self.backup()
        fixture_repository(self.target / 'repo', base)
        self.restore()
        self.assertEqual((self.target / 'repo/plan.md').read_bytes(), b'recreated\n')
        self.assertEqual(capture.git_state(self.target, self.target / 'repo', ['*.md'])['untracked'], ['plan.md'])
        self.assertEqual(self.restore()['git'][0]['action'], 'unchanged')

    def test_dirty_checkout_blocks_all_writes(self):
        fixture_repository(self.source / 'repo', working={'file.txt': (0o100644, b'saved\n')})
        (self.source / 'repo/review_plan.md').write_text('plan')
        self.backup()
        fixture_repository(self.target / 'repo', working={'file.txt': (0o100644, b'newer work\n')})
        with self.assertRaisesRegex(restore.Conflicts, 'Nothing was restored'):
            self.restore()
        self.assertFalse((self.target / 'repo/review_plan.md').exists())
        self.assertEqual((self.target / 'repo/file.txt').read_bytes(), b'newer work\n')

    def test_wrong_head_and_missing_checkout_are_reported(self):
        fixture_repository(self.source / 'repo')
        self.backup()
        plan = restore.plan_restore(self.snapshot, self.target, ())
        self.assertIn('Missing checkout', plan['conflicts'][0])
        fixture_repository(self.target / 'repo', base={'file.txt': (0o100644, b'other head\n')})
        plan = restore.plan_restore(self.snapshot, self.target, ())
        self.assertIn('HEAD mismatch', plan['conflicts'][0])

    def test_empty_repository_preview_includes_required_commit(self):
        head = fixture_repository(self.source / 'repo')
        self.backup()
        fixture_repository(self.target / 'repo')
        (self.target / 'repo/.git/refs/heads/topic').unlink()
        plan = restore.plan_restore(self.snapshot, self.target, ())
        self.assertIn('required HEAD ' + head, plan['conflicts'][0])

    def test_plain_files_restore_to_different_home(self):
        self.plain_backup()
        self.restore()
        self.assertEqual((self.target / 'notes/plan.md').read_bytes(), b'plan\n')
        self.assertEqual(stat.S_IMODE((self.target / 'notes/plan.md').stat().st_mode), 0o751)
        self.assertTrue((self.target / 'notes/empty').is_dir())
        self.assertEqual(os.readlink(self.target / 'notes/link'), '/absent/target')

    def test_selected_file_does_not_restore_siblings(self):
        self.plain_backup()
        self.restore(paths=['notes/plan.md'])
        self.assertTrue((self.target / 'notes/plan.md').is_file())
        self.assertFalse((self.target / 'notes/empty').exists())
        self.assertFalse((self.target / 'notes/link').is_symlink())

    def test_selected_checkout_leaves_other_checkout_alone(self):
        fixture_repository(self.source / 'repo', working={'file.txt': (0o100644, b'first\n')})
        fixture_repository(self.source / 'other', working={'file.txt': (0o100644, b'second\n')})
        self.config['git'][0]['include'].append('other')
        self.backup()
        fixture_repository(self.target / 'repo')
        self.restore(paths=['repo'])
        self.assertEqual((self.target / 'repo/file.txt').read_bytes(), b'first\n')
        self.assertFalse((self.target / 'other').exists())

    def test_file_conflict_blocks_other_missing_files(self):
        self.plain_backup()
        (self.target / 'notes').mkdir(parents=True)
        (self.target / 'notes/plan.md').write_text('different')
        with self.assertRaises(restore.Conflicts):
            self.restore()
        self.assertFalse((self.target / 'notes/empty').exists())
        self.assertEqual((self.target / 'notes/plan.md').read_text(), 'different')

    def test_symlink_parent_is_not_traversed(self):
        self.plain_backup()
        outside = self.root / 'outside'
        outside.mkdir()
        self.target.mkdir()
        (self.target / 'notes').symlink_to(outside)
        with self.assertRaises(restore.Conflicts):
            self.restore()
        self.assertEqual(list(outside.iterdir()), [])

    def test_selected_path_cannot_escape_home(self):
        self.plain_backup()
        for path in ('../outside', '/absolute', 'notes/.git', 'arcadia/anything'):
            with self.subTest(path=path), self.assertRaises(capture.BackupError):
                self.restore(paths=[path])
        self.assertFalse(self.target.exists())

    def test_staged_addition_does_not_overwrite_ignored_existing_file(self):
        staged = {'file.txt': (0o100644, b'base\n'), 'new.md': (0o100644, b'saved\n')}
        fixture_repository(self.source / 'repo', staged=staged)
        self.backup()
        fixture_repository(self.target / 'repo')
        (self.target / 'repo/.git/info').mkdir()
        (self.target / 'repo/.git/info/exclude').write_text('new.md\n')
        (self.target / 'repo/new.md').write_text('existing')
        with self.assertRaises(restore.Conflicts):
            self.restore()
        self.assertEqual((self.target / 'repo/new.md').read_text(), 'existing')

    def test_resumed_restore_checks_recreated_file_conflicts_before_writing(self):
        base = {'plan.md': (0o100644, b'old\n'), 'edit': (0o100644, b'base\n')}
        staged = {'edit': base['edit']}
        working = {'edit': (0o100644, b'changed\n'), 'plan.md': (0o100644, b'saved\n')}
        fixture_repository(self.source / 'repo', base, staged, working)
        self.backup()
        fixture_repository(self.target / 'repo', base, staged)
        (self.target / 'repo/plan.md').write_text('different work\n')
        with self.assertRaises(restore.Conflicts):
            self.restore()
        self.assertEqual((self.target / 'repo/edit').read_bytes(), b'base\n')
        self.assertEqual((self.target / 'repo/plan.md').read_text(), 'different work\n')

    def test_restore_finishes_after_staged_changes_were_applied(self):
        staged = {'file.txt': (0o100644, b'staged\n')}
        working = {'file.txt': (0o100644, b'working\n')}
        fixture_repository(self.source / 'repo', staged=staged, working=working)
        self.backup()
        fixture_repository(self.target / 'repo', staged=staged)
        plan = self.restore()
        self.assertEqual(plan['git'][0]['action'], 'finish')
        self.assertEqual((self.target / 'repo/file.txt').read_bytes(), b'working\n')

    def test_restore_finishes_if_interrupted_before_index_update(self):
        staged = {'file.txt': (0o100644, b'staged\n')}
        fixture_repository(self.source / 'repo', staged=staged, working={'file.txt': (0o100644, b'working\n')})
        self.backup()
        fixture_repository(self.target / 'repo', working=staged)
        plan = self.restore()
        self.assertEqual(plan['git'][0]['action'], 'index')
        self.assertEqual((self.target / 'repo/file.txt').read_bytes(), b'working\n')

    def test_conflicted_git_operation_is_rejected(self):
        fixture_repository(self.source / 'repo')
        self.backup()
        fixture_repository(self.target / 'repo')
        (self.target / 'repo/.git/MERGE_HEAD').write_text('fixture')
        with self.assertRaises(restore.Conflicts):
            self.restore()

    def test_parallel_restore_is_rejected(self):
        self.plain_backup()
        with restore.restore_lock(self.target):
            with self.assertRaisesRegex(capture.BackupError, 'Another restore'):
                self.restore()

    def test_corrupt_snapshot_is_not_restored(self):
        self.plain_backup()
        self.snapshot.write_bytes(self.snapshot.read_bytes()[:-8])
        with self.assertRaises((EOFError, OSError, capture.BackupError)):
            self.restore()
        self.assertFalse(self.target.exists())

    def test_duplicate_checkout_records_are_rejected_before_restore(self):
        fixture_repository(self.source / 'repo', working={'file.txt': (0o100644, b'changed\n')})
        self.backup()
        with tarfile.open(self.snapshot, 'r:gz') as archive:
            members = [(member, archive.extractfile(member).read()) for member in archive]
        with tarfile.open(self.snapshot, 'w:gz') as archive:
            for member, data in members:
                if member.name == 'manifest.json':
                    manifest = json.loads(data)
                    manifest['git'].append(manifest['git'][0])
                    data = json.dumps(manifest).encode()
                capture.add_bytes(archive, member.name, data)
        with self.assertRaisesRegex(capture.BackupError, 'Duplicate Git checkout'):
            self.restore()
        self.assertFalse(self.target.exists())

    def test_receipt_checksum_is_checked(self):
        self.plain_backup()
        self.snapshot.with_name('receipt.json').write_text(json.dumps({'format': 1, 'sha256': '0' * 64}))
        with self.assertRaisesRegex(capture.BackupError, 'checksum'):
            client.snapshot_file(self.snapshot)

    def test_remote_restore_protocol(self):
        self.plain_backup()
        with self.snapshot.open('rb') as stream:
            checksum = client.sha256(stream)
        options = {'home': str(self.target), 'paths': ['notes'], 'apply': True, 'sha256': checksum}
        with self.snapshot.open('rb') as stream:
            result = subprocess.run([sys.executable, '-B', '-c', client.restore_program(options)], stdin=stream,
                                    capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.target / 'notes/plan.md').read_bytes(), b'plan\n')
        self.assertIn('completed and verified', result.stdout)

    def test_local_cli_does_not_require_private_config(self):
        self.plain_backup()
        with redirect_stdout(io.StringIO()), patch('client.DEFAULT_CONFIG', self.root / 'missing.toml'):
            result = client.main(['restore', '--snapshot', str(self.snapshot), '--host', 'local',
                                  '--home', str(self.target), '--path-to-restore', 'notes', '--apply'])
        self.assertEqual(result, 0)
        self.assertTrue((self.target / 'notes/plan.md').is_file())

    def test_case_collisions_are_reported_on_case_insensitive_destination(self):
        probe = self.root / 'Probe'
        probe.touch()
        if not (self.root / 'probe').exists():
            self.skipTest('Requires a case insensitive filesystem')
        manifest = {'format': 1, 'git': [], 'files': {}}
        with tarfile.open(self.snapshot, 'w:gz') as archive:
            for name in ('A', 'a'):
                content = name.encode()
                capture.add_bytes(archive, 'home/' + name, content)
                manifest['files'][name] = {'kind': 'file', 'size': 1, 'mode': 0o600,
                                         'sha256': hashlib.sha256(content).hexdigest()}
            capture.add_bytes(archive, 'manifest.json', json.dumps(manifest).encode())
        with self.assertRaises(restore.Conflicts):
            self.restore()
        self.assertFalse(self.target.exists())


if __name__ == '__main__':
    unittest.main()
