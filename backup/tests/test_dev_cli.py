from contextlib import redirect_stdout, redirect_stderr
import io
import json
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import client


class InterfaceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='dev-backup-cli-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.home = self.root / 'source'
        (self.home / 'notes').mkdir(parents=True)
        (self.home / 'notes/plan.md').write_text('first version')
        self.storage = self.root / 'backups'
        self.config = self.root / 'config.toml'
        self.write_config(self.config, self.home, self.storage)

    def write_config(self, path, home, storage, host='local', keep=2):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text('host = ' + json.dumps(host) + '\nhome = ' + json.dumps(str(home))
                        + '\nbackup_dir = ' + json.dumps(str(storage))
                        + '\nkeep_snapshots = ' + str(keep) + '\n[files]\ninclude = ["notes"]\n')
        path.chmod(0o600)

    def command(self, *args, config=None, success=True):
        output, errors = io.StringIO(), io.StringIO()
        with redirect_stdout(output), redirect_stderr(errors):
            result = client.main(['--config', str(config or self.config), *map(str, args)])
        if success:
            self.assertEqual(result, 0, output.getvalue() + errors.getvalue())
        else:
            self.assertEqual(result, 1)
        return output.getvalue() + errors.getvalue()

    def test_local_backup_and_latest_restore_round_trip(self):
        self.command('backup')
        (self.home / 'notes/plan.md').write_text('latest version')
        self.command('backup')
        target = self.root / 'recovery'
        output = self.command('restore', '--host', 'local', '--home', target)
        self.assertIn('Preview only', output)
        self.assertFalse(target.exists())
        self.command('restore', '--host', 'local', '--home', target, '--apply')
        self.assertEqual((target / 'notes/plan.md').read_text(), 'latest version')

    def test_explicit_snapshot_takes_precedence_over_latest(self):
        self.command('backup')
        first = client.snapshots(self.storage)[-1] / 'snapshot.tar.gz'
        (self.home / 'notes/plan.md').write_text('later')
        self.command('backup')
        target = self.root / 'old-recovery'
        self.command('restore', '--snapshot', first, '--home', target, '--apply')
        self.assertEqual((target / 'notes/plan.md').read_text(), 'first version')

    def test_default_machine_and_home_are_used_for_restore(self):
        self.command('backup')
        (self.home / 'notes/plan.md').unlink()
        self.command('restore', '--apply')
        self.assertEqual((self.home / 'notes/plan.md').read_text(), 'first version')

    def test_retention_during_local_restore_does_not_remove_its_input(self):
        import restore
        self.command('backup')
        latest = client.snapshots(self.storage)[-1]
        original = restore.plan_restore
        def plan(*args):
            result = original(*args)
            (latest / 'snapshot.tar.gz').unlink()
            return result
        target = self.root / 'recovery'
        with patch('restore.plan_restore', side_effect=plan):
            self.command('restore', '--home', target, '--apply')
        self.assertEqual((target / 'notes/plan.md').read_text(), 'first version')

    def test_backup_host_home_and_storage_can_be_overridden(self):
        self.write_config(self.config, '/unused/remote/home', self.storage, host='fixture-server')
        destination = self.root / 'other-backups'
        with patch('client.subprocess.run') as ssh:
            self.command('backup', '--host', 'local', '--home', self.home, '--backup-dir', destination)
            ssh.assert_not_called()
        records = client.snapshots(destination)
        self.assertEqual(len(records), 1)
        manifest = client.validate_archive(records[0] / 'snapshot.tar.gz')
        self.assertEqual(manifest['source_home'], str(self.home))
        self.assertFalse(self.storage.exists())

    def test_no_completed_snapshots_reports_clear_error(self):
        self.storage.mkdir()
        (self.storage / 'snapshots/.partial-test').mkdir(parents=True)
        output = self.command('restore', success=False)
        self.assertIn('No successful snapshots', output)

    def test_corrupt_latest_does_not_silently_restore_older_snapshot(self):
        self.command('backup')
        self.command('backup')
        (client.snapshots(self.storage)[-1] / 'snapshot.tar.gz').write_bytes(b'corrupt')
        target = self.root / 'recovery'
        output = self.command('restore', '--home', target, '--apply', success=False)
        self.assertIn('checksum', output)
        self.assertFalse(target.exists())

    def test_incomplete_latest_snapshot_never_falls_back(self):
        self.command('backup')
        self.command('backup')
        latest = client.snapshots(self.storage)[-1]
        receipt = (latest / 'receipt.json').read_bytes()
        for missing in ('receipt.json', 'snapshot.tar.gz'):
            with self.subTest(missing=missing):
                (latest / 'receipt.json').write_bytes(receipt)
                (latest / missing).unlink()
                target = self.root / 'recovery'
                self.command('restore', '--home', target, '--apply', success=False)
                self.assertFalse(target.exists())

    def test_configs_have_independent_snapshots_and_retention(self):
        other_home = self.root / 'other-source'
        (other_home / 'notes').mkdir(parents=True)
        (other_home / 'notes/plan.md').write_text('other machine')
        other_config, other_storage = self.root / 'other.toml', self.root / 'other-backups'
        self.write_config(self.config, self.home, self.storage, keep=1)
        self.write_config(other_config, other_home, other_storage, keep=1)
        self.command('backup')
        old = client.snapshots(self.storage)[0]
        self.command('backup', config=other_config)
        other = client.snapshots(other_storage)[0]
        self.command('backup')
        self.assertFalse(old.exists())
        self.assertTrue(other.exists())
        target = self.root / 'other-recovery'
        self.command('restore', '--home', target, '--apply', config=other_config)
        self.assertEqual((target / 'notes/plan.md').read_text(), 'other machine')

    def test_config_can_appear_after_command(self):
        with redirect_stdout(io.StringIO()):
            result = client.main(['check-config', '--config', str(self.config)])
        self.assertEqual(result, 0)

    def test_local_backup_cannot_capture_its_own_storage(self):
        storage = self.home / 'notes/backups'
        self.write_config(self.config, self.home, storage)
        output = self.command('backup', success=False)
        self.assertIn('inside a selected source path', output)
        self.assertEqual(client.snapshots(storage), [])

    def test_ssh_restore_uses_config_defaults_and_explicit_overrides(self):
        self.command('backup')
        self.write_config(self.config, '~/remote-home', self.storage, host='configured-server')
        original = client.restore_program
        calls = []
        def program(options):
            calls.append(options)
            return original(options)
        with patch('client.restore_program', side_effect=program), patch('client.subprocess.run') as ssh:
            ssh.return_value = subprocess.CompletedProcess('ssh', 0)
            self.command('restore')
            self.assertEqual(ssh.call_args.args[0][-2], 'configured-server')
            self.assertEqual(calls[-1]['home'], '~/remote-home')
            self.assertFalse(calls[-1]['apply'])
            self.command('restore', '--host', 'other-server', '--home', '/different/home', '--path-to-restore', 'notes')
            self.assertEqual(ssh.call_args.args[0][-2], 'other-server')
            self.assertEqual(calls[-1]['home'], '/different/home')
            self.assertEqual(calls[-1]['paths'], ['notes'])

    def test_schedules_are_independent_even_for_matching_config_filenames(self):
        first, second = self.root / 'one/config.toml', self.root / 'two/config.toml'
        first_config = dict(client.read_config(self.config), interval_minutes=7)
        second_config = dict(first_config, backup_dir=str(self.root / 'second-backups'))
        self.assertNotEqual(client.schedule_label(first), client.schedule_label(second))
        with patch('client.Path.home', return_value=self.root / 'user'), patch('client.sys.platform', 'darwin'):
            with patch('client.subprocess.run', return_value=subprocess.CompletedProcess('launchctl', 0)) as launchctl:
                with redirect_stdout(io.StringIO()):
                    client.schedule(first_config, first, True)
                    client.schedule(second_config, second, True)
                jobs = self.root / 'user/Library/LaunchAgents'
                first_job = jobs / (client.schedule_label(first) + '.plist')
                second_job = jobs / (client.schedule_label(second) + '.plist')
                self.assertTrue(first_job.exists())
                self.assertTrue(second_job.exists())
                job = plistlib.loads(second_job.read_bytes())
                self.assertEqual(job['ProgramArguments'][-2:], [str(second), 'backup'])
                self.assertTrue(Path(job['ProgramArguments'][0]).is_absolute())
                self.assertTrue(Path(job['ProgramArguments'][1]).is_absolute())
                self.assertEqual(job['StartInterval'], 420)
                self.assertEqual(job['Umask'], 0o077)
                self.assertTrue(job['RunAtLoad'])
                with redirect_stdout(io.StringIO()):
                    client.schedule(None, first, False)
                self.assertFalse(first_job.exists())
                self.assertTrue(second_job.exists())
                self.assertEqual(launchctl.call_args.args[0][-1].split('/')[-1], client.schedule_label(first))

    def test_unschedule_does_not_require_the_config_file_to_still_exist(self):
        missing = self.root / 'missing.toml'
        with patch('client.schedule') as schedule:
            self.command('unschedule', config=missing)
        schedule.assert_called_once_with(None, missing, False)

    def test_legacy_config_reports_required_rename(self):
        self.config.write_text(self.config.read_text().replace('backup_dir =', 'destination ='))
        output = self.command('check-config', success=False)
        self.assertIn('Rename destination to backup_dir', output)


if __name__ == '__main__':
    unittest.main()
