{ config, lib, ... }:
let
  cfg = config.t11s.caches;
in
with lib;
{
  options.t11s.caches = {
    enable = mkEnableOption "enable some standard set of caches for stuff in this flake";
  };
  config = mkIf cfg.enable {
    nix.settings.substituters = [
      "https://nix-community.cachix.org"
    ];

    nix.settings.trusted-public-keys = [
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    ];
  };
}
