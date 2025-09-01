{ pkgs, ... }:
{
  imports = [ ./ai.nix ];
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

  # stuff
  t11s = {
    enable = true;
    neovim.enable = true;
    shell.enable = true;
    git.enable = true;
    wslSSHAgent = true;
  };

  programs.git = {
    userName = "Burke Cates";
    userEmail = "burke.cates@gmail.com";
  };

  programs.neovim.plugins = with pkgs.vimPlugins; [
    vim-go
  ];

  home.sessionPath = [
    "/home/burke/.npm-global/bin"
  ];

  # this will make starship faster on wsl when in windows directories
  programs.starship.settings.git_status.windows_starship =
    "/mnt/c/Program Files/starship/bin/starship.exe";
  # TODO pull this via a non-flake input for great good
}
