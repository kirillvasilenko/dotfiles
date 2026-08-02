# dotfiles

## Neovim

```bash
./install-nvim.sh
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
