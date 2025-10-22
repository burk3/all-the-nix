{ pkgs, ... }:
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
  home.stateVersion = "24.11"; # Please read the comment before changing.

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;

  t11s = {
    personal.enable = true;
    guiCommon.enable = true;
    hypr.enable = true;
    niri.enable = true;
    neovim.enable = true;
    shell.enable = true;
    git.enable = true;
  };

  services.wlsunset = {
    enable = true;
    latitude = 47.677;
    longitude = -122.385;
  };

  home.packages = with pkgs; [
    mcomix
    kubectl
  ];

  dconf.settings = {
    "org/virt-manager/virt-manager/connections" = {
      autoconnect = [ "qemu:///system" ];
      uris = [ "qemu:///system" ];
    };
  };
}
