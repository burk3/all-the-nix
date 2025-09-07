# Edit this configuration file to define what should be installed on
# your system. Help is available in the configuration.nix(5) man page, on
# https://search.nixos.org/options and in the NixOS manual (`nixos-help`).

# NixOS-WSL specific options are documented on the NixOS-WSL repository:
# https://github.com/nix-community/NixOS-WSL

{ config, lib, pkgs, ... }:

{
  networking.hostName = "lofty305-wsl-nixos";
  time.timeZone = "America/Los_Angeles";

  wsl.enable = true;
  wsl.defaultUser = "burke";

  t11s.enable = true;
  t11s.mainUser.name = "burke";
  t11s.mainUser.description = "Burke Cates";
  t11s.resolved1111 = false;
  t11s.systemType = "wsl";

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It's perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "25.05"; # Did you read the comment?
}
