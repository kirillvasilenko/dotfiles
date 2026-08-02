{
  description = "Kir's Home Manager configs (macbook + remote)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { nixpkgs, home-manager, ... }:
    let
      mkHome =
        {
          system,
          modules,
        }:
        home-manager.lib.homeManagerConfiguration {
          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfree = true;
          };
          inherit modules;
        };
    in
    {
      # MacBook (adjust system if Intel: x86_64-darwin)
      homeConfigurations."kir@macbook" = mkHome {
        system = "aarch64-darwin";
        modules = [
          ./home/common.nix
          ./home/hosts/macbook.nix
        ];
      };

      # Shared Ubuntu remote (this machine)
      homeConfigurations."kir@remote" = mkHome {
        system = "x86_64-linux";
        modules = [
          ./home/common.nix
          ./home/hosts/remote.nix
        ];
      };
    };
}
