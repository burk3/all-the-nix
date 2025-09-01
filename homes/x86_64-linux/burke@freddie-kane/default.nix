{pkgs, ... }:
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
    enable = true;
    guiCommon.enable = true;
    hypr.enable = true;
    neovim.enable = true;
    shell.enable = true;
    git.enable = true;
  };


  home.packages = with pkgs; [
    mcomix
  ];

  #services.home-manager.autoExpire
  programs.git = {
    userName = "Burke Cates";
    userEmail = "burke.cates@gmail.com";
  };

  dconf.settings = {
    "org/virt-manager/virt-manager/connections" = {
      autoconnect = ["qemu:///system"];
      uris = ["qemu:///system"];
    };
  };
}