{ pkgs, ... }:
{
  home.username = "kir-vasilenko";
  home.homeDirectory = "/home/kir-vasilenko";

  home.packages = with pkgs; [
    # Remote/server-only tools go here.
  ];
}
