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
  };
  config = lib.mkIf cfg.enable {
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
      glow
    ];

    age.secrets."private-nix.conf" = {
      file = ../../../secrets/private-nix.conf.age;
      path = "/home/${config.home.username}/.config/nix/private-nix.conf";
    };
    nix.extraOptions = ''
      !include ${config.age.secrets."private-nix.conf".path}
    '';
    home.sessionPath = [ "$HOME/.local/bin" ];
  };
}
