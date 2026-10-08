# dotfiles

Follow in order. Run install scripts from `~/dotfiles` on the machine being set up.

## GitHub and Git

Prerequisites: Bash, Git, curl, tar, [gh](https://cli.github.com/); [Homebrew](https://brew.sh/) on macOS.

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

Links rules and individual skills for Codex, Claude Code, and Gemini. Resolve any reported conflicts and rerun. Restart agents afterward.

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

The socket must be set and keys listed. Then, unless already mounted:

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

Skip links that already exist. Replace `YOUR_LOGIN` with your junk directory name; make its branch available first if needed:

```bash
ln -s ~/arcadia/junk/YOUR_LOGIN ~/junk
```

## MCP servers

Run from a shell with working SSH forwarding:

```bash
mkdir -p ~/.mcp
chmod 700 ~/.mcp
cd ~/arcadia
ya whoami
ya tool mcp --help
bash ~/junk/install-codex-mcp.sh
codex mcp list
```

The installer forwards `SSH_AUTH_SOCK` to MCP processes and repairs existing registrations. Fully restart Codex from this shell; check connections with `/mcp`. Old tmux/agent processes may have a missing or expired socket.

For Claude, after installing it, run `bash ~/junk/install-claude-mcp.sh`.

## Personal scripts

Already on PATH:

- `ydb-add-worktree [-p pr] BRANCH` — run from the main YDB checkout.
- `ydb-remove-worktree BRANCH` — remove its worktree, merged branch, and IDE files.
- `gh-pr-comments PR` — your unresolved review threads; `-a` for everyone, `-r` to include resolved threads.

## Still to set up

YDB checkout, remaining internal tools, agent application installation, and automatic off-machine backups of unfinished work, review notes, and agent conversations. Test restoring those backups.
