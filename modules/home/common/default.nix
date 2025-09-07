{
  config,
  lib,
  pkgs,
  ...
}:
# make this place feel just like home
let
  cfg = config.t11s;
in
with lib;
{
  options.t11s = with types; {
    enable = mkEnableOption "Enable base configuration";
    catppuccinFlavor = mkOption {
      type = str;
      default = "frappe";
      description = "which flavor of catppuccin to use";
    };
    catppuccinAccent = mkOption {
      type = str;
      default = "teal";
      description = "which highlight of catppuccin to use";
    };
  };
  config = lib.mkIf cfg.enable {
    catppuccin = {
      enable = true;
      accent = cfg.catppuccinAccent;
      flavor = cfg.catppuccinFlavor;
    };

    programs.btop.enable = true;
    programs.bottom.enable = true;
    programs.bat.enable = true;
    programs.nh.enable = true;

    home.packages = with pkgs; [
      cachix
      unzip
      nmap
      dig
      nmap
    ];

    home.sessionPath = [ "$HOME/.local/bin" ];
  };
}
