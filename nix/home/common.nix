{ pkgs, ... }:
{
  # Shared packages for every machine. Host files add more via home.packages.
  home.packages = with pkgs; [
    neovim
    ripgrep
    fd # fast find; handy for telescope / CLI search
    tree-sitter # CLI required by nvim-treesitter (main) to build parsers
    go # mason builds some LSPs (e.g. sqls) with `go`
    python3 # newer than macOS system Python; plugins/tools that call python3
    nodejs # mason / some LSPs and formatters install or run via npm/node
  ];

  # Let Home Manager manage its own bindings; don't rewrite the whole bashrc yet.
  programs.home-manager.enable = true;

  # Bump only when HM release notes say to; never change casually.
  home.stateVersion = "25.05";
}
