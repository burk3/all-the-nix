{
  pkgs,
  lib,
  inputs,
  ...
}:
{
  imports = [
    inputs.nixos-hardware.nixosModules.framework-13-7040-amd
    ./hardware-configuration.nix
    ./power.nix
  ];
  ### identity
  networking.hostName = "freddie-kane"; # Define your hostname.
  time.timeZone = "America/Los_Angeles";

  t11s.enable = true;
  t11s.caches.enable = true;
  t11s.systemType = "laptop";
  t11s.mainUser.name = "burke";
  t11s.mainUser.description = "Burke Cates";
  t11s.remotebuild.hosts = [ "juicy-j.dab-ling.ts.net" ];

  ### nix
  #  nix = {
  #    settings = {
  #      substituters = [ "ssh://eu.nixbuild.net" ];
  #      trusted-public-keys = [ "nixbuild.net/GLER5I-1:2UGRxSmQWU22LD27+UepgZlASKaFyk4YOwXoH/Wln9U=" ];
  #    };
  #    distributedBuilds = true;
  #    buildMachines = [
  #      {
  #        hostName = "eu.nixbuild.net";
  #        system = "x86_64-linux";
  #        maxJobs = 100;
  #        supportedFeatures = [ "benchmark" "big-parallel" ];
  #        sshKey = "/root/.ssh/nixbuild-dot-net";
  #      }
  #    }
  #      hostName = "lil-debbie.lan";
  #      maxJobs = 48;
  #      sshUser = "nixbuilder";
  #      sshKey = "/root/.ssh/id_ed25519";
  #      system = "x86_64-linux";
  #      protocol = "ssh-ng";
  #      supportedFeatures = [ "nixos-test" "big-parallel" "kvm" ];
  #    }
  #    ];
  #  };

  ### firmware/hardware/lowlevel
  boot = {
    plymouth.enable = true;
    resumeDevice = "/dev/disk/by-label/swap";
    lanzaboote = {
      enable = true;
      pkiBundle = "/var/lib/sbctl";
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
    # loader.systemd-boot.enable = true;
    loader.systemd-boot.enable = lib.mkForce false;
    loader.efi.canTouchEfiVariables = true;
    initrd.systemd.enable = true;
    initrd.systemd.tpm2.enable = true;
  };

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
  services.xserver.desktopManager.gnome.enable = true;
  services.ollama = {
    enable = true;
    acceleration = "rocm";
    environmentVariables = {
      HCC_AMDGPU_TARGET = "gfx1103"; # used to be necessary, but doesn't seem to anymore
    };
    rocmOverrideGfx = "11.0.3";
  };

  ### dont change this probably
  system.stateVersion = "24.11"; # Did you read the comment?
}
