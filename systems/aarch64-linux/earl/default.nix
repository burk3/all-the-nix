{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
# earl, Burke's ASUS Zenbook A16 (UX3607OA, Snapdragon X2 Elite Extreme /
# Glymur). No private inputs:
#
#   hardware   inputs.glymur-flake.nixosModules.default: kernel, firmware
#              (ASUS BSP), DTB/cmdline, speakers, fTPM, board quirks
#   lab        inputs.glymur-flake.nixosModules.lab: serial console,
#              heartbeat, boot counting, observability, a16-snap, bench
#   this file  identity, t11s knobs, disk layout, desktop choices, and the
#              lab's own values (observer address, serial number, access)
#
# Both modules come in through flake.nix (systems.hosts.earl.modules).
#
# This is the system for the btrfs reinstall (disko.nix, after 26.11). The A16 still runs the bring-up repo's
# ext4 system until then; the pre-switch check below refuses to install earl
# there. Deploy with `nixos-rebuild boot` + reboot, never `switch`, so boot
# counting can fall back from a bad generation.
{
  imports = [
    inputs.disko.nixosModules.disko
    ./disko.nix
  ];

  ### identity
  networking.hostName = "earl";
  time.timeZone = "America/Los_Angeles";

  t11s.enable = true;
  t11s.caches.enable = true;
  t11s.systemType = "laptop";
  t11s.mainUser.name = "burke";
  t11s.mainUser.description = "Burke Cates";
  t11s.internalCA.enable = true;
  # aarch64 builds go to swaine (the A16 resets under sustained build load).
  t11s.remotebuild.hosts = [ "swaine" ];

  ### hardware (glymur-flake). The kernel is built with glymur-flake's pinned
  ### nixpkgs, so bumping this repo's nixpkgs doesn't rebuild it, and it stays
  ### the derivation the bring-up tested.
  hardware.asus-zenbook-a16 = {
    kernel.pkgs = inputs.glymur-flake.lib.kernelPkgs;
    # The two optional lab patches (default off): on, so the kernel stays
    # the one the bring-up tested; turn off when no longer needed.
    kernel.labPatches.dpLinkTrainingFaultInjection.enable = true;
    kernel.labPatches.qmpComboDpPowerOnDiag.enable = true;
    # ccache in swaine's (and this host's) build sandbox for kernel builds.
    kernel.ccache.enable = true;
    audio.speakers.dsp.enable = true;
    irEmitter.stage = "first-light";
    howdy = {
      enable = true;
      pamServices = [ "sudo" ];
    };
    # The firmware TPM (/dev/tpm0, /dev/tpmrm0; on by default, stated here
    # because LUKS/TPM plans depend on it). systemd's TPM2 units stay off
    # (the board default) until the driver has many boots behind it.
    tpm.enable = true;
  };

  ### lab (glymur-flake's lab module, this lab's values)
  # juicy-j as the observer, the A16-end FTDI.
  lab.network.observer.address = "10.1.1.20";
  lab.zenbook.serialConsole.serial = "A106VJGP";
  lab.zenbook.ccacheHost.enable = true;
  lab.zenbook = {
    observability.enable = true;
    snap.enable = true;
    bench.enable = true;
  };
  # Lab access for agents (root over SSH; t11s.internalCA trusts the
  # step-CA user certs), and root shells on the serial line.
  services.openssh.enable = true;
  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINB1Sw6DgkSfZhsFcNig7dY3IcFbyCYCvIp4gvr9gDeY burke@juicy-j"
  ];
  boot.initrd.systemd.emergencyAccess = true;
  systemd.services.emergency.environment.SYSTEMD_SULOGIN_FORCE = "1";
  systemd.services.rescue.environment.SYSTEMD_SULOGIN_FORCE = "1";

  ### boot: systemd-boot with boot counting (the lab module), boot + reboot
  # No USB autosuspend while SSH depends on a USB NIC.
  boot.kernelParams = [ "usbcore.autosuspend=-1" ];
  boot.loader.systemd-boot.enable = true;
  # 10 generations fit the 2 GiB ESP (~100 MB each).
  boot.loader.systemd-boot.configurationLimit = 10;
  # The firmware ignores BootOrder writes; systemd-boot is reached through
  # \EFI\BOOT\BOOTAA64.EFI.
  boot.loader.efi.canTouchEfiVariables = false;
  networking.networkmanager.enable = true;

  # Refuse to install earl onto the A16's current ext4 system (the bring-up
  # repo's zenbook-a16): its fileSystems are disko.nix's btrfs subvolumes,
  # which don't exist there, so the new default entry would not mount root.
  # Runs before the bootloader is touched, for switch/boot/test alike.
  # Override (only if you know the layout matches): NIXOS_NO_CHECK=1.
  system.preSwitchChecks.earl-btrfs-root = ''
    fstype=$(${pkgs.util-linux}/bin/findmnt -n -o FSTYPE --target / || true)
    if [ "$fstype" = ext4 ]; then
      echo "earl expects the btrfs layout of systems/aarch64-linux/earl/disko.nix;" >&2
      echo "/ here is ext4 (the bring-up repo's zenbook-a16). Not installing $1 ($2)." >&2
      exit 1
    fi
  '';

  ### installer: `nix build .#nixosConfigurations.earl.config.system.build.for-real-installer-iso`,
  ### dd to a USB stick, boot it from the Esc menu, `sudo install-for-real`.
  t11s.forRealInstaller = {
    enable = true;
    # The firmware gives no usable devicetree: systemd-boot loads the
    # live system's DTB (the board's, with its overlays) before the kernel.
    efiBootloader = "systemd-boot";
    liveModules = [
      inputs.glymur-flake.nixosModules.default
      {
        # earl's kernel settings (pinned package set, lab patches, the lab
        # module's Kconfig, ccache), so the live system boots the same
        # kernel derivation: one build, the kernel the bring-up tested.
        hardware.asus-zenbook-a16.kernel = {
          inherit (config.hardware.asus-zenbook-a16.kernel)
            pkgs
            variant
            config
            labPatches
            extraPatches
            ccache
            ;
        };
        # ... and the same DTB overlays (the board's plus this one).
        hardware.asus-zenbook-a16.irEmitter.stage = config.hardware.asus-zenbook-a16.irEmitter.stage;
        # The board's curated initrd list and firmware subset, not the
        # installer's generic PC modules and all of linux-firmware. The DSPs
        # still start in the initrd (firmware.dsp.mode = "initrd", as on
        # earl and the microSD rescue), before the ISO's USB stick is used;
        # `lab.a16.dsp=off` at the systemd-boot editor skips them.
        hardware.enableAllHardware = lib.mkForce false;
        # Nothing to play or seal in an installer.
        hardware.asus-zenbook-a16.audio.enable = false;
        hardware.asus-zenbook-a16.tpm.enable = false;
        boot.kernelParams = [
          # The ISO is on USB: no autosuspend (dwc3/PHY suspend bugs).
          "usbcore.autosuspend=-1"
          # Kernel messages also on the lab's FTDI serial line (a16-obs
          # records it); the last console, the screen, gets the shell.
          "console=ttyUSB0,115200"
          "console=tty0"
        ];
      }
    ];
    # Only the internal NVMe: never the microSD reader or the USB stick.
    preInstallChecks = map (disk: ''
      tran=$(lsblk -dno TRAN ${disk})
      if [[ $tran != nvme ]]; then
        echo "${disk} is on '$tran', not the internal NVMe:" >&2
        lsblk -o NAME,SIZE,TRAN,MODEL,SERIAL >&2
        exit 1
      fi
      echo "    ${disk}: $(lsblk -dno MODEL,SERIAL,SIZE ${disk})"
    '') (lib.mapAttrsToList (_: d: d.device) config.disko.devices.disk);
  };

  ### desktop services the bring-up system had through Plasma (gen 119):
  ### battery state for noctalia, power profiles, removable media.
  services.upower.enable = true;
  services.power-profiles-daemon.enable = true;
  services.udisks2.enable = true;

  ### base-module overrides for this machine
  # Firmware/BIOS/EC updates only with Burke's explicit approval, by hand.
  services.fwupd.enable = lib.mkForce false;
  # x86 Steam can't run here (steam-aarch64 would be a separate input).
  programs.steam.enable = false;

  ### suspend: s2idle only (mem_sleep_default comes from the hardware module)
  systemd.sleep.settings.Sleep = {
    AllowHibernation = "no";
    AllowHybridSleep = "no";
    AllowSuspendThenHibernate = "no";
  };
  services.logind.settings.Login.HandlePowerKey = "suspend";
  boot.extraModprobeConfig = ''
    options cfg80211 ieee80211_regdom=US
  '';

  environment.systemPackages = with pkgs; [
    dtc
    pciutils
    stress-ng
    usbutils
    nvme-cli
    smartmontools
    libcamera
    v4l-utils
    tpm2-tools
  ];

  # A fresh install (the btrfs reinstall), on 26.11.
  system.stateVersion = "26.11";
}
