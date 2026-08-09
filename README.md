# dotfiles

## Neovim

```bash
./install-nvim.sh
```

## Personal scripts (`bin/`)

Executable helpers live in [`bin/`](bin/) (e.g. `ydb-add-worktree` / `ydb-remove-worktree`, mirroring `git worktree add|remove`). Home Manager adds that directory via `home.sessionPath` in `nix/home/common.nix`.

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
