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
    neovim.enable = true;
    shell.enable = true;
    git.enable = true;
    desktop = {
      enable = true;
      compositor.niri.enable = true;
      bar = "caelestia";
      launcher = "caelestia";
      bluetoothSupport.enable = true;
      networkManager.enable = true;
      services.gnome-keyring.enable = true;
    };
  };

  # seeing if this gets bluetooth working again
  services.blueman-applet.enable = true;
  services.wlsunset = {
    enable = true;
    temperature.night = 2500;
    ## ncc
    # latitude = 39.3;
    # longitude = -75.3;
    ## sea
    latitude = 47.6;
    longitude = -122.3;
  };

  services.system76-scheduler-niri.enable = true;

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
