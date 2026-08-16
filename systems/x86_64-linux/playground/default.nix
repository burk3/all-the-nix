# Interactive throwaway VM: brings up a window and boots verbosely to a VT.
#   nixos-rebuild build-vm --flake .#playground
#   ./result/bin/run-playground-vm          # burke / test, or ssh -p 2222
{ lib, pkgs, ... }:
{
  networking.hostName = "playground";
  time.timeZone = "America/Los_Angeles";

  t11s.enable = true;
  # server: no greetd, no desktop -- boot ends on a plain kernel VT
  t11s.systemType = "server";
  t11s.mainUser.name = "burke";
  t11s.mainUser.description = "Burke Cates";

  # base boots silently; the whole point here is watching it boot
  boot.consoleLogLevel = lib.mkForce 7;
  # console big enough to tell fonts apart
  boot.kernelParams = [ "video=1920x1080" ];

  stylix.targets.console.enable = true;

  # build-vm substitutes its own root device; this only satisfies evaluation
  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };
  boot.loader.systemd-boot.enable = true;

  # VM build only, so the throwaway password never reaches a real system
  virtualisation.vmVariant = {
    users.users.burke.initialPassword = "test";
    users.users.root.initialPassword = "test";

    # a second way in when the console is the thing under test
    services.openssh.enable = true;

    virtualisation = {
      memorySize = 4096;
      cores = 4;
      diskSize = 16384;
      graphics = true;
      forwardPorts = [
        {
          from = "host";
          host.port = 2222;
          guest.port = 22;
        }
      ];
      qemu.options = [
        "-display gtk,show-cursor=on"
        "-vga virtio"
      ];
    };
  };

  system.stateVersion = "26.05";
}
