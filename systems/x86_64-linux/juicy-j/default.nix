{
  pkgs,
  lib,
  inputs,
  ...
}:
let
  ethIF = "enp191s0";
  wifiIF = "wlp192s0";
in
{
  imports = [
    inputs.nixos-hardware.nixosModules.framework-desktop-amd-ai-max-300-series
    ./hardware-configuration.nix
  ];
  ### identity
  networking.hostName = "juicy-j";
  time.timeZone = "America/Los_Angeles";

  t11s.enable = true;
  t11s.caches.enable = true;
  t11s.systemType = "workstation";
  t11s.mainUser.name = "burke";
  t11s.mainUser.description = "Burke Cates";
  t11s.remotebuild.serveBuilds = true;

  ### firmware/hardware/lowlevel
  boot = {
    lanzaboote = {
      enable = true;
      pkiBundle = "/var/lib/sbctl";
    };
    # loader.systemd-boot.enable = true;
    loader.systemd-boot.enable = lib.mkForce false;
    loader.efi.canTouchEfiVariables = true;
    initrd.systemd.enable = true;
    initrd.systemd.tpm2.enable = true;

    # set max memory that can be used for GPU
    kernelParams = [
      "amdttm.pages_limit=27648000"
      "amdttm.page_pool_size=27648000"
    ];
  };

  ### Net
  networking.useDHCP = false;
  networking.interfaces.${ethIF}.wakeOnLan.enable = true;
  systemd.network = {
    enable = true;
    networks."10-ether" = {
      matchConfig.Name = ethIF;
      networkConfig.DHCP = "yes";
      dhcpV4Config.UseDNS = false;
      dhcpV6Config.UseDNS = false;
      dns = builtins.map (addr: addr + "%${ethIF}#one.one.one.one") [
        "1.1.1.1"
        "1.0.0.1"
        "[2606:4700:4700::1111]"
        "[2606:4700:4700::1001]"
      ];
    };
  };

  networking.nftables.enable = true;
  networking.firewall = {
    enable = true;
    allowPing = true;
    allowedTCPPorts = [
      22
      8080
    ];
  };

  ### Software
  services.sshd.enable = true;
  services.xserver.displayManager.gdm.autoSuspend = false;
  environment.systemPackages = with pkgs; [ via ];

  # doesn't work for now. ollama just doesn't support :(
  #services.ollama = {
  #  enable = true;
  #  acceleration = "rocm";
  #  environmentVariables = {
  #    HCC_AMDGPU_TARGET = "gfx1151";
  #  };
  #  rocmOverrideGfx = "11.5.1";
  #};

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "24.11"; # Did you read the comment?
}
