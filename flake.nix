{
  description = "A very basic flake";
  nixConfig = {
    extra-substituters = [ "https://noctalia.cachix.org" ];
    extra-trusted-public-keys = [ "noctalia.cachix.org-1:pCOR47nnMEo5thcxNDtzWpOxNFQsBRglJzxWPp3dkU4=" ];
  };

  inputs = {
    nixpkgs.url = "https://flakehub.com/f/NixOS/nixpkgs/0";
    #nixpkgs.url = "github:NixOS/nixpkgs/release-26.05";
    unstable.url = "https://flakehub.com/f/NixOS/nixpkgs/0.1";

    snowfall-lib = {
      url = "github:snowfallorg/lib";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # nixos-generators = {
    #   url = "github:nix-community/nixos-generators";
    #   inputs.nixpkgs.follows = "nixpkgs";
    # };
    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    niri.url = "github:sodiboo/niri-flake";
    programsdb = {
      url = "github:wamserma/flake-programs-sqlite";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    lanzaboote = {
      url = "github:nix-community/lanzaboote/v1.1.0";
      # Optional but recommended to limit the size of your system closure.
      inputs.nixpkgs.follows = "nixpkgs";
    };
    determinate.url = "https://flakehub.com/f/DeterminateSystems/determinate/*";
    stylix = {
      url = "github:nix-community/stylix/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixos-wsl = {
      url = "github:nix-community/NixOS-WSL";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    system76-scheduler-niri = {
      url = "github:Kirottu/system76-scheduler-niri";
      inputs.nixpkgs.follows = "unstable";
    };
    quickshell = {
      url = "git+https://git.outfoxxed.me/quickshell/quickshell";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    noctalia = {
      url = "github:noctalia-dev/noctalia-shell/legacy-v4";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    systemctl-toggle = {
      url = "github:burk3/systemctl-toggle";
      inputs.nixpkgs.follows = "unstable";
    };
    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    mikrotik-exporter = {
      url = "github:burk3/mikrotik-exporter";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-amd-ai = {
      #url = "github:noamsto/nix-amd-ai";
      url = "github:burk3/nix-amd-ai/fix/sdcpp-rocm-libatomic";
      inputs.nixpkgs.follows = "unstable";
    };
  };

  outputs =
    inputs:
    let
      flake = inputs.snowfall-lib.mkFlake {
        # You must provide our flake inputs to Snowfall Lib.
        inherit inputs;

        # The `src` must be the root of the flake. See configuration
        # in the next section for information on how you can move your
        # Nix files to a separate directory.
        src = ./.;

        snowfall.namespace = "t11s";

        overlays = with inputs; [
          # Pass the system *string* (`system = …`), not the elaborated platform
          # attrset (`localSystem = prev.stdenv.hostPlatform`). The attrset
          # carries lazy fields bound to the outer pkgs fixpoint, which the
          # nested `import nixpkgs` forces mid-stage-build and re-enters this
          # same fixpoint -> infinite recursion under newer nixpkgs. A bare
          # string is re-elaborated fresh inside unstable, fully decoupled.
          (_final: prev: {
            unstable = import inputs.unstable {
              inherit (prev.stdenv.hostPlatform) system;
              config.allowUnfree = true;
            };
          })
          systemctl-toggle.overlays.default
          niri.overlays.niri
        ];
        alias = {
          shells.default = "nix-dev";
        };

        homes.modules = with inputs; [
          noctalia.homeModules.default
        ];
        homes.users."burke@freddie-kane".modules = with inputs; [
          system76-scheduler-niri.homeModules.default
        ];

        systems.modules.nixos = with inputs; [
          determinate.nixosModules.default
          stylix.nixosModules.stylix
          (
            { lib, ... }:
            {
              config.stylix.autoEnable = lib.mkDefault false;
            }
          )
          lanzaboote.nixosModules.lanzaboote
          niri.nixosModules.niri
          programsdb.nixosModules.programs-sqlite
          agenix.nixosModules.default
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
    in
    flake
    // {
      hydraJobs = {
        nixos = inputs.nixpkgs.lib.mapAttrs (
          _: cfg: cfg.config.system.build.toplevel
        ) flake.nixosConfigurations;
      };
    };
}
