{
  config,
  lib,
  pkgs,
  ...
}:
# make this place feel just like home
let
  cfg = config.t11s.personal;
in
with lib;
{
  options.t11s.personal = with types; {
    enable = mkEnableOption "Enable my personal configuration";
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

    programs.git.settings = {
      user.name = "Burke Cates";
      user.email = "burke.cates@gmail.com";
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
    ];

    home.sessionPath = [ "$HOME/.local/bin" ];
  };
}
