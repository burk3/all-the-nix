{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.t11s;
in
{
  options.t11s.enable = lib.mkEnableOption "standard t11s home stuff";
  config = lib.mkIf cfg.enable {
    # stylix is configured home-side so standalone homeConfigurations are themed
    # the same as home-manager under NixOS; modules/nixos/base follows the main
    # user's values rather than pushing its own down.
    stylix.enable = lib.mkDefault true;
    stylix.autoEnable = lib.mkDefault false;
    stylix.base16Scheme = lib.mkDefault "${pkgs.base16-schemes}/share/themes/tender.yaml";
    stylix.polarity = lib.mkDefault "dark";
    # autoEnable would turn on ~100 targets and fight the hand-written hyprland
    # colors; these two are what the portal reads for app dark mode.
    stylix.targets.gnome.enable = true;
    stylix.targets.gtk.enable = true;
  };
}
