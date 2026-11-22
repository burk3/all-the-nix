{
  pkgs,
  lib,
  config,
  ...
}:
{
  # Home Manager needs a bit of information about you and the paths it should
  # manage.
  home.username = "burke";
  home.homeDirectory = "/home/burke";

  # This value determines the Home Manager release that your configuration is
  # compatible with. This helps avoid breakage when a new Home Manager release
  # introduces backwards incompatible changes.
  #
  # You should not change this value, even if you update Home Manager. If you do
  # want to update the value, then make sure to first check the Home Manager
  # release notes.
  home.stateVersion = "26.05"; # Please read the comment before changing.

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;

  t11s = {
    enable = true;
    personal.enable = true;
    guiCommon.enable = true;
    neovim.enable = true;
    shell.enable = true;
    git.enable = true;
    eternal-terminal.enable = true;
    desktop = {
      enable = true;
      compositor.niri.enable = true;
      # pick the session in tuigreet (Ctrl-S / F3); the system side is already
      # enabled in modules/nixos/base
      compositor.hyprland.enable = true;
      launcher = "noctalia";
      bluetoothSupport.enable = true;
      networkManager.enable = true;
      services.gnome-keyring.enable = true;
      noctalia.pinnedApps = [ "firefox" ];
    };
    helix.enable = true;
    et-ghostty = {
      enable = true;
      desktopEntries.enable = true;
      profiles = {
        juicy-j.host = "juicy-j.dab-ling.ts.net";
        juicy-j.settings.theme = "Birds Of Paradise";
        bronson.host = "bronson.dab-ling.ts.net";
        bronson.settings.theme = "Tomorrow Night Eighties";
      };
    };
  };

  programs.ghostty.package = pkgs.unstable.ghostty;

  stylix.autoEnable = true;
  # t11s.desktop's hyprland module sets its own decoration colours
  stylix.targets.hyprland.enable = false;
  stylix.base16Scheme = "${pkgs.base16-schemes}/share/themes/terracotta.yaml";
  # Use Charcoal Light instead of guiCommon's shared Ghostty theme.
  programs.ghostty.settings.theme = lib.mkForce "stylix";
  # noctalia's wallpaper comes from stylix.image
  stylix.image = pkgs.fetchurl {
    url = "https://raw.githubusercontent.com/dharmx/walls/e8d8a42e4fbecb2cf9619995edbc7ce19610bbd8/anime/a_bird_on_a_branch.png";
    hash = "sha256-3x0BwyKCKiTXLw+4Y8M8b4g7iI0rbUlZ+ILDEjpsob8=";
  };
  stylix.fonts = {
    sansSerif = {
      package = pkgs.inter;
      name = "Inter";
    };
    serif = {
      package = pkgs.ibm-plex;
      name = "IBM Plex Serif";
    };
    monospace = {
      package = pkgs.iosevka;
      name = "Iosevka";
    };
    emoji = {
      package = pkgs.noto-fonts-emoji-blob-bin;
      name = "Blobmoji";
    };
  };
  # noctalia schedules day/night off `[location]`, which the desktop module sets
  programs.noctalia.settings.nightlight = {
    enabled = true;
    temperature_night = 3000;
    temperature_day = 6500;
  };
  programs.niri.settings.binds."XF86AudioMedia" = {
    allow-when-locked = true;
    action.spawn = [
      "${lib.getExe config.programs.noctalia.package}"
      "msg"
      "nightlight-toggle"
    ];
  };

  home.packages = with pkgs; [
    mcomix
    kubectl
    brogue-ce
    # GNOME Camera: the RGB webcam through PipeWire's libcamera camera node
    # (the camera portal); no camera app comes with niri/Hyprland.
    snapshot
  ];

}
