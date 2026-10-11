# dotfiles

Follow in order. Run install scripts from `~/dotfiles` on the machine being set up.

## GitHub and Git

Prerequisites: Bash, Git, curl, tar, [gh](https://cli.github.com/); [Homebrew](https://brew.sh/) on macOS.

On macOS, install `gh` before continuing (it is also included in the Brewfile):

```bash
brew install gh
```

```bash
gh auth login --hostname github.com --git-protocol https --web
gh auth setup-git
git clone https://github.com/kirillvasilenko/dotfiles.git ~/dotfiles
cd ~/dotfiles
```

Replace the example name and email:

```bash
git config --global user.name "Your Name"
git config --global user.email "work@example.com"
```

Override per repository with `git config --local user.email "personal@example.com"`.

## PATH and tools

```bash
./install-path.sh
source ~/.bashrc  # Zsh: source "${ZDOTDIR:-$HOME}/.zshrc"
./install-pixi.sh  # Linux; on macOS use ./install-brew.sh instead
./install-npm.sh
```

PATH includes Pixi, `~/.local/bin`, and `~/dotfiles/bin`. npm installs global packages under `~/.local` without sudo.

To change tools, edit [pixi/pixi-global.toml](pixi/pixi-global.toml) and run `pixi global sync` (not `pixi global install`). On macOS, edit [brew/Brewfile](brew/Brewfile) and rerun the installer.

## Tmux and Neovim

```bash
./install-tmux.sh
./install-nvim.sh
nvim
```

Wait for plugins to install. Check `:Lazy` and `:Mason`; errors are in `:MasonLog`.

## Agent rules and skills

Install and authenticate your agent applications separately, then:

```bash
./install-agents.sh
```

For Codex's default permissions, run once:

```bash
./install-codex-permissions.sh
```

This adds **Approve for me** and write access to `~/junk`, `~/dotfiles`, `~/.ya`,
and `~/slice`. Restart Codex afterward.

If permission settings already exist, edit them in `~/.codex/config.toml` instead.
These settings go before any `[section]`; replace `/YOUR/HOME` with your home path:

```toml
approval_policy = "on-request"
approvals_reviewer = "auto_review"
sandbox_mode = "workspace-write"
sandbox_workspace_write.writable_roots = ["/YOUR/HOME/junk", "/YOUR/HOME/dotfiles", "/YOUR/HOME/.ya", "/YOUR/HOME/slice"]
```

## SSH forwarding and Arcadia

Requires Skotty on the Mac and `arc` on Linux. On the **Mac**, add this inside the new server's `Host` section in `~/.ssh/config`:

```sshconfig
ForwardAgent yes
```

Reconnect. In the fresh **Linux shell**, before attaching to tmux:

```bash
echo "$SSH_AUTH_SOCK"
ssh-add -l
```

The socket must be set and keys listed. The forwarded socket path changes on every connection, so give it a stable name:

```bash
cd ~/dotfiles
./install-ssh-agent.sh
```

It adds a hook to `~/.ssh/rc` that links `~/.ssh/ssh_auth_sock` to the forwarded socket at login, and points `SSH_AUTH_SOCK` at that link in the shell rc. Reconnect once more and check:

```bash
ls -l ~/.ssh/ssh_auth_sock  # a symlink to a live socket
ssh-add -l
```

Then, unless already mounted:

```bash
mkdir -p ~/arcadia
arc mount --ssh-tokens ~/arcadia
```

## ya and junk

```bash
cd ~/arcadia
./ya --help
mkdir -p ~/.local/bin
ln -s ~/arcadia/ya ~/.local/bin/ya
hash -r
command -v ya  # should resolve under ~/.local/bin
```

Skip links that already exist. Replace `YOUR_LOGIN` with your junk directory name. If the directory lives on a personal branch, fetch and check it out first; personal branches are not fetched by default:

```bash
cd ~/arcadia
arc fetch users/YOUR_LOGIN/
arc branch --all
arc checkout -b junk arcadia/users/YOUR_LOGIN/junk
arc status  # On branch junk
```

```bash
ln -s ~/arcadia/junk/YOUR_LOGIN ~/junk
```

## MCP servers

Run from a shell reconnected after `install-ssh-agent.sh`; the Codex installer refuses to run without its `~/.ssh/rc` hook:

```bash
mkdir -p ~/.mcp
chmod 700 ~/.mcp
cd ~/arcadia
ya whoami
ya tool mcp --help
bash ~/junk/install-codex-mcp.sh
codex mcp list
```

The installer points MCP processes at `~/.ssh/ssh_auth_sock` and repairs existing registrations. Fully restart Codex from this shell; check connections with `/mcp`. Old tmux/agent processes may have a missing or expired socket.

For Claude, after installing it:

```bash
bash ~/junk/install-claude-mcp.sh
claude mcp list
```

## YDB layout

```text
~/ydb/
  main/
  <branch>/
  pr-<branch>/
```

Use `official` for `ydb-platform/ydb` and `fork` for your fork. Run worktree helpers from `~/ydb/main`; they create sibling directories.

## Personal scripts

Already on PATH:

- `ydb-add-worktree [-p pr] BRANCH` — run from `~/ydb/main`.
- `ydb-remove-worktree BRANCH` — remove its worktree, merged branch, and IDE files.
- `gh-pr-comments PR` — your unresolved review threads; `-a` for everyone, `-r` to include resolved threads.

## Development backups

Code, configuration example, tests, and [setup and restore instructions](backup/README.md)
live under `backup/`. The `dev-backup` command is linked from `bin/`.

## Still to set up

YDB checkout, remaining internal tools, and agent application installation.
