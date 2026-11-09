{
  description = "nixos vms: netbird (dmz, pve-2), edge (traefik + adguard home, pve-1)";

  inputs = {
    # unstable: the services.netbird.server module + netbird 0.77.x live here.
    # pin to a release once it carries the server module if you want calmer upgrades.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # per-lab values. defaults to the example; real builds point it at the dir with private.yml:
    # --override-input private path:<repo>/ansible/group_vars/all/private (update.sh does)
    private = {
      url = "path:../ansible/group_vars/all/private";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, disko, private, ... }:
    let
      system = "x86_64-linux";
      facts = import ./facts.nix { pkgs = nixpkgs.legacyPackages.${system}; inherit private; };
      # one folder per host, same disk layout everywhere
      host = name: nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit facts; };
        modules = [
          disko.nixosModules.disko
          ./base/disko.nix
          (./. + "/${name}/configuration.nix")
        ];
      };
    in
    {
      nixosConfigurations.netbird = host "netbird";
      nixosConfigurations.edge = host "edge";
    };
}
