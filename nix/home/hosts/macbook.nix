{ pkgs, ... }:
{
  # Change username/homeDirectory if your Mac account name differs.
  home.username = "kir-vasilenko";
  home.homeDirectory = "/Users/kir-vasilenko";

  home.packages = with pkgs; [
    # Mac-only tools go here.
  ];
}
