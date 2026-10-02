{ config, lib, ... }:
let
  cfg = config.t11s.caches;
  inherit (config.t11s) systemType;
  hasScreen = (systemType == "workstation") || (systemType == "laptop");
in
with lib;
{
  options.t11s.caches = {
    enable = mkEnableOption "enable some standard set of caches for stuff in this flake";
  };
  config = mkIf cfg.enable {
    nix.settings.substituters = [
      "https://nix-community.cachix.org"
      "https://cache.numtide.com"
    ]
    # noctalia is the desktop shell, so only hosts with a screen build it
    ++ optional hasScreen "https://noctalia.cachix.org";

    nix.settings.trusted-public-keys = [
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
    ]
    ++ optional hasScreen "noctalia.cachix.org-1:pCOR47nnMEo5thcxNDtzWpOxNFQsBRglJzxWPp3dkU4=";
  };
}
