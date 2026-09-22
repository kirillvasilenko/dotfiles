# dotfiles

## Neovim

```bash
./install-nvim.sh
```

## Tmux

```bash
./install-tmux.sh
```

Symlinks `~/.tmux.conf` to [`tmux/.tmux.conf`](tmux/.tmux.conf), clones [TPM](https://github.com/tmux-plugins/tpm) into `~/.tmux/plugins/tpm` (or updates it), and installs the `@plugin` entries so `<prefix>I` is not needed on a fresh machine. Re-run it after adding a plugin to the config, or press `<prefix>I` inside tmux.

## npm

```bash
./install-npm.sh
```

Symlinks `~/.npmrc` to [`npm/.npmrc`](npm/.npmrc), which sets npm's global prefix to `~/.local`, so `npm install -g` (and self-updaters such as `codex update`) never need root and never depend on where `node` itself lives (a system `/usr/local` owned by root, a read-only store, a pixi env). Global packages land in `~/.local/lib/node_modules` with their binaries in `~/.local/bin`, which must be on `PATH`.

## Personal scripts (`bin/`)

Executable helpers live in [`bin/`](bin/) (e.g. `ydb-add-worktree` / `ydb-remove-worktree`, mirroring `git worktree add|remove`). Put the directory on `PATH` (see [CLI tools](#cli-tools)).

`gh-pr-comments` lists the review threads you're part of in a GitHub PR, each with a permalink straight to your own comment. It exists because GitHub unanchors a thread from the diff as soon as a commit touches the commented line: the thread is flagged `Outdated`, drops off the Files changed tab, and the comments panel will not reliably open it. The permalink still works, so the job is getting the list of URLs. It queries GraphQL `reviewThreads` rather than the REST comments endpoint, because REST reports neither `isOutdated` nor `isResolved`.

```bash
gh-pr-comments https://github.com/owner/repo/pull/1234   # yours, unresolved (the default)
gh-pr-comments 1234        # from inside the checkout
gh-pr-comments -r 1234     # yours, resolved and unresolved
gh-pr-comments -a 1234     # everyone's, unresolved
gh-pr-comments -ar 1234    # everyone's, everything
gh-pr-comments -m 1234     # markdown    -i: fzf picker    -u LOGIN: someone else's
```

Output columns are the thread's resolution state (`OPEN`/`resolved`) and its diff anchoring (`OUTDATED`/`current`) — independent of each other. Unresolved sorts first. Needs `gh auth login`.

## Agent skills (`skills/`)

Skills shared by every coding agent live in [`skills/`](skills/), one directory per skill with a
`SKILL.md`. Cursor and Claude Code discover them through symlinks. Claude Code also writes its own synced skills into `~/.claude/skills`, so that one must be a real directory with one symlink per skill, never a link to the whole `skills/` directory (otherwise the synced bundle lands in this repo):

```bash
ln -s ~/dotfiles/skills ~/.cursor/skills
mkdir -p ~/.claude/skills
for s in ~/dotfiles/skills/*/; do ln -s "$s" ~/.claude/skills/; done
```

Codex has no skill loader; `~/.codex/AGENTS.md` points it at the directory instead.

## CLI tools

The same tool set (neovim, tmux, ripgrep, fd, tree-sitter CLI, node, go, python) is installed per user, without root, by the native package manager of each platform. Both files are plain lists you edit by hand.

### macOS: Homebrew

```bash
./install-brew.sh
```

Runs `brew bundle` on [`brew/Brewfile`](brew/Brewfile). Edit the file and re-run to add or remove tools.

### Linux: pixi (conda-forge)

```bash
./install-pixi.sh
```

Installs [pixi](https://pixi.sh) (one static binary in `~/.pixi/bin`) if missing, symlinks `~/.pixi/manifests/pixi-global.toml` to [`pixi/pixi-global.toml`](pixi/pixi-global.toml), and runs `pixi global sync`. Everything lives under `~/.pixi`; conda-forge packages bring their own libraries, so no system packages are needed. No environment activation: each exposed command is a launcher in `~/.pixi/bin`.

To change tools, edit the manifest and run `pixi global sync`. Do **not** use `pixi global install`: it rewrites the manifest in its own layout.

### PATH

Nothing edits your shell rc. Add once to `~/.bashrc` (or `~/.zshrc`), first so these win over `/usr/local` and system copies:

```bash
export PATH="$HOME/.pixi/bin:$HOME/.local/bin:$HOME/dotfiles/bin:$PATH"
```

On macOS Homebrew's own `brew shellenv` line replaces the `~/.pixi/bin` part.
