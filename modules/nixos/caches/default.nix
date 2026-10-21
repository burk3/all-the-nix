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
      # burk3's own flakes (nix-exporter), pushed from their GitHub Actions
      "https://burk3.cachix.org"
    ]
    # noctalia is the desktop shell, so only hosts with a screen build it
    ++ optional hasScreen "https://noctalia.cachix.org";

    nix.settings.trusted-public-keys = [
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
      "burk3.cachix.org-1:lrEh0jbE0525QZA8hcH/Sx2EuZT6mWzm5qyV5PO6nbc="
    ]
    ++ optional hasScreen "noctalia.cachix.org-1:pCOR47nnMEo5thcxNDtzWpOxNFQsBRglJzxWPp3dkU4=";
  };
}
