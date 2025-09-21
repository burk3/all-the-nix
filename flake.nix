{
  description = "A very basic flake";

  inputs = {
    nixpkgs.url = "https://flakehub.com/f/NixOS/nixpkgs/0";

    snowfall-lib = {
      url = "github:snowfallorg/lib";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager/release-25.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    catppuccin = {
      url = "github:catppuccin/nix/release-25.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    niri.url = "github:sodiboo/niri-flake";
    programsdb = {
      url = "github:wamserma/flake-programs-sqlite";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
    lanzaboote = {
      url = "github:nix-community/lanzaboote/v0.4.2";
      # Optional but recommended to limit the size of your system closure.
      inputs.nixpkgs.follows = "nixpkgs";
    };
    determinate.url = "https://flakehub.com/f/DeterminateSystems/determinate/*";
    nixos-wsl = {
      url = "github:nix-community/NixOS-WSL";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs:
    inputs.snowfall-lib.mkFlake {
      # You must provide our flake inputs to Snowfall Lib.
      inherit inputs;

      # The `src` must be the root of the flake. See configuration
      # in the next section for information on how you can move your
      # Nix files to a separate directory.
      src = ./.;

      snowfall.namespace = "t11s";

      alias = {
        shells.default = "nix-dev";
      };

      homes.modules = with inputs; [ catppuccin.homeModules.catppuccin ];
      systems.modules.nixos = with inputs; [
        catppuccin.nixosModules.catppuccin
        determinate.nixosModules.default
        lanzaboote.nixosModules.lanzaboote
        niri.nixosModules.niri
        programsdb.nixosModules.programs-sqlite
      ];
      systems.hosts.lofty305-wsl-nixos.modules = with inputs; [
        nixos-wsl.nixosModules.default
      ];

      outputs-builder = channels: { formatter = channels.nixpkgs.nixfmt-tree; };

      channels-config = {
        # Allow unfree packages.
        allowUnfree = true;
      };
    };
}
