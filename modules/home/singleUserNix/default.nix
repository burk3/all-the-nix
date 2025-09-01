{ config, lib, ... }:
let
  cfg = config.t11s.singleUserNix;
in
with lib;
{
  options.t11s.singleUserNix = {
    enable = mkEnableOption "configs for when nix install mode is single-user";
  };
  config = mkIf cfg.enable {
    programs.zsh.profileExtra = ''
      source $HOME/.nix-profile/etc/profile.d/nix.sh
    '';

    programs.bash.profileExtra = ''
      source $HOME/.nix-profile/etc/profile.d/nix.sh
    '';
  };
}