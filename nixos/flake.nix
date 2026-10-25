{
  description = "netbird control-plane host (dmz, pve-2)";

  inputs = {
    # unstable: the services.netbird.server module + netbird 0.77.x live here.
    # pin to a release once it carries the server module if you want calmer upgrades.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, disko, ... }:
    let
      system = "x86_64-linux";
      facts = import ./facts.nix { pkgs = nixpkgs.legacyPackages.${system}; };
    in
    {
      nixosConfigurations.netbird = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit facts; };
        modules = [
          disko.nixosModules.disko
          ./netbird/disko.nix
          ./netbird/configuration.nix
        ];
      };
    };
}
