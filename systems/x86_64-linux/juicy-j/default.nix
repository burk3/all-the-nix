{ pkgs, lib, inputs, ... }:
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
    kernelParams = [ "amdttm.pages_limit=27648000" "amdttm.page_pool_size=27648000" ];
  };

  ### Net
  networking.useDHCP = false;
  networking.interfaces.${ethIF}.wakeOnLan.enable = true;
  systemd.network = {
    enable = true;
    networks."10-ether" = {
      matchConfig.Name = ethIF;
      networkConfig.DHCP = "yes";
    };
  };

  networking.nftables.enable = true;
  networking.firewall = {
    enable = true;
    allowPing = true;
    allowedTCPPorts = [ 22 8080 ];
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
}


