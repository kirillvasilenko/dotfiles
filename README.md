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

## Personal scripts (`bin/`)

Executable helpers live in [`bin/`](bin/) (e.g. `ydb-add-worktree` / `ydb-remove-worktree`, mirroring `git worktree add|remove`). Home Manager adds that directory via `home.sessionPath` in `nix/home/common.nix`.

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

**Caveat:** `home.packages` binaries land in `~/.nix-profile/bin`, which Nix already puts on `PATH`. `home.sessionPath` only writes `~/.nix-profile/etc/profile.d/hm-session-vars.sh` — shells must source that file. Because this setup does not let Home Manager manage bash yet, add to `~/.bashrc`:

```bash
# Home Manager session variables (PATH for ~/dotfiles/bin, etc.)
if [ -f "$HOME/.nix-profile/etc/profile.d/hm-session-vars.sh" ]; then
  . "$HOME/.nix-profile/etc/profile.d/hm-session-vars.sh"
fi
```

Current shell (after `home-manager switch`):

```bash
source ~/.nix-profile/etc/profile.d/hm-session-vars.sh
```

## Agent skills (`skills/`)

Skills shared by every coding agent live in [`skills/`](skills/), one directory per skill with a
`SKILL.md`. Cursor and Claude Code discover them through symlinks. Claude Code also writes its own synced skills into `~/.claude/skills`, so that one must be a real directory with one symlink per skill, never a link to the whole `skills/` directory (otherwise the synced bundle lands in this repo):

```bash
ln -s ~/dotfiles/skills ~/.cursor/skills
mkdir -p ~/.claude/skills
for s in ~/dotfiles/skills/*/; do ln -s "$s" ~/.claude/skills/; done
```

Codex has no skill loader; `~/.codex/AGENTS.md` points it at the directory instead.

## Nix / Home Manager

Declarative CLI tools live under [`nix/`](nix/):

| Flake output | Machine |
|---|---|
| `kir@macbook` | personal macOS |
| `kir@remote` | shared Ubuntu server |

Shared packages: `nix/home/common.nix`  
Host-only packages: `nix/home/hosts/{macbook,remote}.nix`

```bash
# first time (from the nix/ directory): nix flake lock

# apply on this remote (use nix run if `home-manager` isn't on PATH yet)
nix run home-manager -- switch --flake ~/dotfiles/nix#kir@remote

# apply on the Mac
nix run home-manager -- switch --flake ~/dotfiles/nix#kir@macbook
```

Adding/removing packages in `*.nix` does **not** need `flake lock` again — just re-run `switch`.  
Use `nix flake update` (in `nix/`) only when you want newer package versions from nixpkgs.

Adjust `home.username` / `home.homeDirectory` in the host files if needed.
