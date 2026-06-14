{
  pkgs,
  lib,
  inputs,
  ...
}:
let
  ethIF = "enp191s0";
  _wifiIF = "wlp192s0";
  sfpIF = "sfp0";
in
{
  imports = [
    inputs.nixos-hardware.nixosModules.framework-desktop-amd-ai-max-300-series
    ./hardware-configuration.nix
    ./rke2.nix
    ./monitoring.nix
    ./hydra.nix
    ./openclaw-host.nix
    ./ai.nix
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
  t11s.internalCA.enable = true;

  stylix.enable = true;
  stylix.autoEnable = false;
  stylix.base16Scheme = "${pkgs.base16-schemes}/share/themes/rose-pine-moon.yaml";
  stylix.targets.console.enable = true;

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
    wait-online.enable = true;
    networks."10-ether" = {
      matchConfig.Name = ethIF;
      networkConfig.DHCP = "yes";
      dhcpV4Config.UseDNS = true;
      dhcpV6Config.UseDNS = true;
    };
    networks."20-sfp" = {
      matchConfig.Name = sfpIF;
      networkConfig.DHCP = "yes";
      dhcpV4Config.UseDNS = true;
      dhcpV6Config.UseDNS = true;
    };
  };

  networking.nftables.enable = true;
  networking.firewall = {
    enable = true;
    allowPing = true;
    allowedTCPPorts = [
      22
      8080
      5201
    ];
  };

  ### Hardware services
  services.hardware.bolt.enable = true;
  services.udev.extraRules = ''
    SUBSYSTEM=="net", ACTION=="add", ATTR{address}=="24:5e:be:94:19:42", NAME="sfp0"
  '';

  ### Software
  services.sshd.enable = true;
  environment.systemPackages = with pkgs; [ via ];

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "24.11"; # Did you read the comment?
}
