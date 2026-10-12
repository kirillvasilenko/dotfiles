# dotfiles

Setup for a new machine. Follow the steps in order; run the `install-*.sh` scripts from `~/dotfiles`.

Steps 1–3 apply to any machine. Steps 4–6 set up a remote Linux dev server reached over SSH from a Mac.

## 1. Clone

Needs Bash, Git, curl, tar and [gh](https://cli.github.com/). On macOS, install [Homebrew](https://brew.sh/) and run `brew install gh` first.

```bash
gh auth login --hostname github.com --git-protocol https --web
gh auth setup-git
git clone https://github.com/kirillvasilenko/dotfiles.git ~/dotfiles
cd ~/dotfiles
git config --global user.name "Your Name"
git config --global user.email "work@example.com"
```

Override the email per repository with `git config --local user.email "personal@example.com"`.

## 2. PATH and tools

```bash
./install-path.sh
source ~/.bashrc    # Zsh: source "${ZDOTDIR:-$HOME}/.zshrc"
./install-pixi.sh   # Linux; on macOS: ./install-brew.sh
./install-npm.sh
```

PATH gets Pixi, `~/.local/bin` and `~/dotfiles/bin`. npm installs global packages under `~/.local`, without sudo.

To change the tool set, edit [pixi/pixi-global.toml](pixi/pixi-global.toml) and run `pixi global sync` (not `pixi global install`). On macOS, edit [brew/Brewfile](brew/Brewfile) and rerun `./install-brew.sh`.

## 3. Tmux and Neovim

```bash
./install-tmux.sh
./install-nvim.sh
nvim
```

Wait for the plugins to install. Check `:Lazy` and `:Mason`; errors are in `:MasonLog`.

## 4. SSH agent forwarding

Arcadia and the MCP servers authenticate through the SSH agent forwarded from the Mac (Skotty).

On the **Mac**, add this to the server's `Host` section in `~/.ssh/config`, then reconnect:

```sshconfig
ForwardAgent yes
```

On the **server**, in a fresh shell outside tmux:

```bash
ssh-add -l   # must list keys
./install-ssh-agent.sh
```

The forwarded socket gets a new path on every connection. The script makes `~/.ssh/ssh_auth_sock` a stable link to it, refreshed at login, and points `SSH_AUTH_SOCK` there. Reconnect once more and check:

```bash
ls -l ~/.ssh/ssh_auth_sock   # a symlink to a live socket
ssh-add -l
```

## 5. Arcadia, ya and junk

Needs `arc`. Replace `YOUR_LOGIN` throughout.

```bash
mkdir -p ~/arcadia
arc mount --ssh-tokens ~/arcadia

mkdir -p ~/.local/bin
ln -s ~/arcadia/ya ~/.local/bin/ya
hash -r
command -v ya   # ~/.local/bin/ya
```

`~/junk` lives on a personal branch, and personal branches are not fetched by default:

```bash
cd ~/arcadia
arc fetch users/YOUR_LOGIN/
arc checkout -b junk arcadia/users/YOUR_LOGIN/junk
arc status   # On branch junk
ln -s ~/arcadia/junk/YOUR_LOGIN ~/junk
```

## 6. Agents

Install and authenticate Codex, Claude Code and Gemini first.

### Rules and skills

```bash
./install-agents.sh
```

Links the rules from `agents/` and the skills from `skills/` and `~/junk/skills` into each agent. It stops on a conflict: resolve it and rerun.

### Codex permissions

```bash
./install-codex-permissions.sh
```

Adds **Approve for me** and write access to `~/junk`, `~/dotfiles`, `~/.ya` and `~/slice`.

If `~/.codex/config.toml` already has permission settings, the script leaves it alone. Edit the file yourself: these lines go before any `[section]`, with `/YOUR/HOME` replaced by your home path.

```toml
approval_policy = "on-request"
approvals_reviewer = "auto_review"
sandbox_mode = "workspace-write"
sandbox_workspace_write.writable_roots = ["/YOUR/HOME/junk", "/YOUR/HOME/dotfiles", "/YOUR/HOME/.ya", "/YOUR/HOME/slice"]
```

### MCP servers

Run from a shell opened after step 4; the Codex installer refuses to run without it.

```bash
bash ~/junk/install-codex-mcp.sh
bash ~/junk/install-claude-mcp.sh
codex mcp list
claude mcp list
```

Restart the agents from this shell and check `/mcp` in each. An agent started in an old tmux session may hold a dead agent socket; restart it from a fresh shell.

## Reference

### YDB layout

```text
~/ydb/
  main/
  <branch>/
  pr-<branch>/
```

The `official` remote is `ydb-platform/ydb`, `fork` is your fork. Worktrees are created next to `main` by the helpers below.

### Scripts on PATH

- `ydb-add-worktree [-p pr] BRANCH` — run from `~/ydb/main`.
- `ydb-remove-worktree BRANCH` — removes the worktree, the merged branch and the IDE files.
- `gh-pr-comments PR` — your unresolved review threads; `-a` for everyone, `-r` to include resolved ones.
- `dev-backup` — development backups; see [backup/README.md](backup/README.md) for setup and restore.

### Not covered yet

Cloning the YDB checkout, installing the agent applications, and the remaining internal tools.
