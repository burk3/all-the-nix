{
  lib,
  pkgs,
  inputs,
  ...
}:
let
  # Secure Boot + Measured Boot are turned on *after* the initial install.
  # A fresh install boots with systemd-boot and a LUKS passphrase only, because
  # lanzaboote can't sign the boot chain before its sbctl keys exist. Once the
  # system is up and the sbctl keys are generated + enrolled in firmware, flip
  # this to true and `nixos-rebuild boot`, then enroll the TPM2+PIN keyslot.
  # Full sequence in ./CLAUDE.md.
  secureBoot = true;
in
{
  imports = [
    inputs.nixos-hardware.nixosModules.framework-13-7040-amd
    inputs.disko.nixosModules.disko
    ./hardware-configuration.nix
    ./disko.nix
    ./power.nix
  ];

  ###### TEMP
  services.pipewire.alsa.support32Bit = lib.mkForce false;

  ### identity
  networking.hostName = "freddie-kane"; # Define your hostname.
  time.timeZone = "America/Los_Angeles";
  #time.timeZone = "America/New_York";

  t11s.enable = true;
  t11s.caches.enable = true;
  t11s.systemType = "laptop";
  t11s.mainUser.name = "burke";
  t11s.mainUser.description = "Burke Cates";
  t11s.remotebuild.hosts = [ "juicy-j.dab-ling.ts.net" ];
  t11s.internalCA.enable = true;
  # offline reinstall ISO: nix build .#nixosConfigurations.freddie-kane.config.system.build.for-real-installer-iso
  t11s.forRealInstaller.enable = true;

  stylix.enable = true;
  stylix.autoEnable = false;
  stylix.base16Scheme = "${pkgs.base16-schemes}/share/themes/rose-pine-moon.yaml";
  stylix.targets.console.enable = true;

  virtualisation.libvirtd.enable = true;
  programs.virt-manager.enable = true;
  users.users.burke.extraGroups = [ "libvirtd" ];
  environment.systemPackages = with pkgs; [
    dnsmasq
  ];

  ### nixbuild.net
  nix = {
    # settings = {
    #   substituters = [ "ssh://eu.nixbuild.net?priority=100" ];
    #   trusted-public-keys = [ "nixbuild.net/GLER5I-1:2UGRxSmQWU22LD27+UepgZlASKaFyk4YOwXoH/Wln9U=" ];
    # };
    distributedBuilds = true;
    buildMachines = [
      {
        hostName = "eu.nixbuild.net";
        system = "aarch64-linux";
        maxJobs = 100;
        supportedFeatures = [
          "benchmark"
          "big-parallel"
        ];
        sshKey = "/root/.ssh/nixbuild-dot-net";
      }
    ];
  };

  ### firmware/hardware/lowlevel
  boot = {
    plymouth.enable = true;
    # boot.resumeDevice is set by disko's cryptswap (resumeDevice = true).
    lanzaboote = lib.mkIf secureBoot {
      enable = true;
      pkiBundle = "/var/lib/sbctl";
      configurationLimit = 8;
      # Measured Boot: lanzaboote builds a systemd-pcrlock TPM2 policy over
      # these PCRs and re-seals it on every nixos-rebuild, so generation/kernel
      # updates don't lock you out. PCR 4 covers the bootloader + stub (and thus
      # transitively initrd/kernel/cmdline), 7 = Secure Boot state, 0 = firmware.
      # Replaces the old systemIdentity/ensure-pcr PCR-15 check. Enroll the LUKS
      # TPM2+PIN keyslot against /var/lib/systemd/pcrlock.json post-install --
      # see ./CLAUDE.md.
      measuredBoot = {
        enable = true;
        pcrs = [
          0
          4
          7
        ];
      };
    };
    kernelParams = [
      "quiet"
      "splash"
      "shell_on_fail"
      "loglevel=3"
      "rd.systemd.show_status=false"
      "rd.udev.log_level=3"
      "udev.log_priority=3"
    ];
    # systemd-boot for the plain install; lanzaboote replaces it once secureBoot.
    loader.systemd-boot.enable = lib.mkForce (!secureBoot);
    loader.efi.canTouchEfiVariables = true;
    initrd.systemd.enable = true;
    initrd.systemd.tpm2.enable = true;
    extraModprobeConfig = ''
      options cfg80211 ieee80211_regdom="US"
    '';
  };

  hardware.wirelessRegulatoryDatabase = true;

  services.hardware.bolt.enable = true;

  ### Net
  networking.networkmanager.enable = true;
  networking.networkmanager.wifi.powersave = true;

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  networking.nftables.enable = true;
  networking.firewall = {
    enable = true;

    allowPing = true;
    allowedTCPPorts = [ 8000 ];
  };

  ### music making stuff?
  services.pipewire.jack.enable = true;
  services.pipewire.alsa.enable = true;
  security.rtkit.enable = true; # for pipewire rt scheduling
  # lower buffer sizes
  #  services.pipewire.extraConfig.pipewire = {
  #    "92-low-latency" = {
  #      "context.properties" = {
  #        "default.clock.rate" = 48000;
  #        "default.clock.quantum" = 64; # ~1.3ms latency
  #        "default.clock.min-quantum" = 64;
  #      };
  #    };
  #  };

  ### Software
  services.desktopManager.gnome.enable = true;

  ### system76-scheduler
  # seems like it prioritizes the foreground process which sounds kinda neat. and
  # there's a home-manager module to make it work with niri!
  services.system76-scheduler.enable = true;

  ### dont change this probably
  system.stateVersion = "24.11"; # Did you read the comment?
}
