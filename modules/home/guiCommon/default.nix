{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) mkEnableOption mkIf;
  cfg = config.t11s.guiCommon;
in
{
  options.t11s.guiCommon = {
    enable = mkEnableOption "enable common gui apps/configs";
  };
  config = mkIf cfg.enable {
    home.packages = with pkgs; [
      vscode.fhs
      bitwarden-desktop
      legcord
      spotify
      playerctl
      pinta
      inkscape
      remmina
      brogue-ce
      # fonts
      monoid
      victor-mono
      iosevka
    ];

    programs.imv.enable = true;
    programs.mpv.enable = true;
    programs.zathura.enable = true;

    programs.ghostty = {
      enable = true;
      enableZshIntegration = true;
      enableBashIntegration = true;
      settings = {
        window-decoration = false;
        cursor-style = "block";
        font-family = [
          "Iosevka"
        ];
        font-size = 8;
        # Potentially good light themes; (bws) means black and white are swapped in numbered colors
        # - Material
        # - iceberg-light (bws)
        # - nord-light - not enough contrast
        # - ayu_light - very bright, maybe not enough contrast
        # - catppuccin-latte - very grey black and whites might be good
        # - NvimLight
        # - rose-pine-dawn (bws)
        # - seoulbones_light (bws)
        #theme = "light:ayu_light,dark:nord";
        theme = "catppuccin-${config.catppuccin.flavor}";
      };
    };
  };
}
