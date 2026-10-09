# Development backups

Save files, Codex and Claude conversations, and uncommitted Git changes from a local
or SSH machine. Backups are stored on the machine running the command.

## Setup

Needs Python 3.11+ and Git locally; Python 3.8+ and Git over SSH.

From `~/dotfiles`:

```sh
mkdir -p -m 700 ~/.config/dev-backup
cp -n backup/config.example.toml ~/.config/dev-backup/config.toml
chmod 600 ~/.config/dev-backup/config.toml
$EDITOR ~/.config/dev-backup/config.toml
dev-backup check-config
```

In your config:

| Setting | Meaning |
| --- | --- |
| `host` | SSH name, or `"local"` |
| `home` | Base folder on that machine; usually `"~"` |
| `backup_dir` | Where to save backups locally |
| `files.include` | Files and folders to copy, relative to `home` |
| `git.include` | Git checkouts to save changes from |
| `git.untracked` | Extra untracked files to save, such as `"*.md"` |
| `keep_snapshots` | How many backups to keep |
| `interval_minutes` | Time between automatic backups |

Keep your real config and backups outside dotfiles.

## Daily use

```sh
dev-backup backup           # Make a backup now.
dev-backup status           # Show the last backup and any failure.
dev-backup restore          # Preview restoring the latest backup.
dev-backup restore --apply  # Apply the restore.
```

Restore uses the machine, home, and backup folder from the config.
It restores everything unless you select a path:

```sh
dev-backup restore --path-to-restore ydb/main
dev-backup restore --snapshot /full/path/to/snapshot.tar.gz
dev-backup restore --host local --home /tmp/recovery
```

Add `--apply` to write files. Both `backup` and `restore` accept `--host` and `--home`.
See `dev-backup COMMAND --help` for all options.

Each backup is a full archive. Oldest backups are deleted above your limit.
Failed backups keep previous ones.

Restore skips identical content and stops on conflicts. Git checkouts must exist
at the saved HEAD commit. Repositories and unpushed commits are not backed up.
Stop editing while restoring. An interrupted restore may be partly complete.

## Automatic backups on macOS

```sh
dev-backup schedule    # Start now, then repeat at the configured interval.
dev-backup unschedule # Stop the schedule; keep the backups.
```

Runs with the terminal closed and starts again when you log in after a restart.
Pauses while asleep or logged out. SSH must work without password prompts.
Failures retry next interval; check `status` and logs in `backup_dir`.

Config edits apply next run. After changing the interval or backup folder,
run `unschedule`, then `schedule`. Unschedule before moving a config file.

## Several machines

Use a separate config and backup folder per machine. Every command accepts `--config`:

```sh
dev-backup --config ~/.config/dev-backup/server-a.toml backup
dev-backup --config ~/.config/dev-backup/server-a.toml schedule
```
