{ pkgs, lib, inputs, ... }:
{
  imports = [
    inputs.nixos-hardware.nixosModules.framework-desktop-amd-ai-max-300-series
    ./hardware-configuration.nix
  ];
  ### identity
  networking.hostName = "juicy-j";
  time.timeZone = "America/Los_Angeles";

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
  systemd.network = {
    enable = true;
    networks."10-ether" = {
      matchConfig.Type = "ether";
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


