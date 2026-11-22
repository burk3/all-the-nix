# Exposes `config.system.build.for-real-installer-iso` on a host: a minimal,
# fully-offline installer ISO for *that* host.
#
# The ISO is a separate minimal NixOS live system (just a shell) — NOT this host
# extended with the CD profile — so none of the host's config (resumeDevice,
# LUKS/swap units, bootloader, desktop) leaks into the live environment. It
# bakes the host's toplevel closure and disko script onto the medium; booting it
# gives a shell where `sudo install-for-real` wipes+formats+mounts per the host's
# disko config and installs the baked system. No network, no binary cache.
#
# Requires the host to use disko (provides `system.build.diskoScript`). A host
# the stock installer kernel cannot boot or drive passes the modules that fix
# that (its kernel, firmware) in `liveModules`; a devicetree board whose
# firmware supplies no usable DT sets `efiBootloader = "systemd-boot"`, so the
# live system's DTB is loaded before the kernel.
#
# Build:  nix build .#nixosConfigurations.<host>.config.system.build.for-real-installer-iso
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.t11s.forRealInstaller;
  efiArch = pkgs.stdenv.hostPlatform.efiArch;
  removableEfi = "EFI/BOOT/BOOT${lib.toUpper efiArch}.EFI";
in
with lib;
{
  options.t11s.forRealInstaller = {
    enable = mkEnableOption "an offline `system.build.for-real-installer-iso` for this host (requires disko)";
    liveModules = mkOption {
      type = types.listOf types.deferredModule;
      default = [ ];
      description = "extra NixOS modules for the live system, e.g. a board module that supplies the kernel";
    };
    efiBootloader = mkOption {
      type = types.enum [
        "grub"
        "systemd-boot"
      ];
      default = "grub";
      description = ''
        What the ISO's El Torito EFI image boots.
        - grub: nixpkgs' stock ISO menu (kernel and initrd on the ISO9660).
          Off x86 the ISO has no partition table, so a dd'ed stick needs
          firmware that reads El Torito from a disk.
        - systemd-boot: a Type #1 loader entry with the live kernel, initrd
          and, when the live system sets hardware.deviceTree.name, its DTB
          (`devicetree`), all in the EFI image, which a GPT in the ISO also
          lists as the ESP (for a dd'ed stick). For boards whose firmware
          gives no usable devicetree. The entry can be edited at the menu
          (`e`).
      '';
    };
    preInstallChecks = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = ''
        Shell snippets run by install-for-real before anything is changed
        (after the disk-exists check, before the confirmation prompt). A
        snippet that fails aborts the install; print why to stderr. Each
        runs as its own script under `set -euo pipefail`.
      '';
    };
    postInstallChecks = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = ''
        Shell snippets run after nixos-install, with the new system still
        mounted at /mnt. A failing snippet makes install-for-real exit
        non-zero with a warning not to reboot. Hosts whose firmware boots
        only the removable-media path (systemd-boot without
        canTouchEfiVariables) get a check for it by default.
      '';
    };
  };

  config = mkIf cfg.enable {
    # The firmware only boots \EFI\BOOT\BOOT<arch>.EFI when NixOS doesn't
    # write a boot entry; make sure bootctl put it there.
    t11s.forRealInstaller.postInstallChecks =
      optional (config.boot.loader.systemd-boot.enable && !config.boot.loader.efi.canTouchEfiVariables)
        ''
          f=/mnt${config.boot.loader.efi.efiSysMountPoint}/${removableEfi}
          if [[ ! -s "$f" ]]; then
            echo "$f is missing or empty: the firmware has nothing to boot." >&2
            exit 1
          fi
          echo "    $f present ($(stat -c %s "$f") bytes)"
        '';

    system.build =
      let
        toplevel = config.system.build.toplevel;
        diskoScript = config.system.build.diskoScript; # wipe+format+mount, device baked from disko.nix
        hostName = config.networking.hostName;
        mainUser = config.t11s.mainUser.name;
        disks = mapAttrsToList (_: disk: disk.device) config.disko.devices.disk;
        hasLuks = config.boot.initrd.luks.devices != { };

        # Each check is its own script (set -euo pipefail); all of them run,
        # and any failure fails the group.
        runChecks =
          name: checks:
          concatImapStrings (i: c: ''
            ${pkgs.writeShellScript "${name}-${toString i}" "set -euo pipefail\n${c}"} || failed=1
          '') checks;

        installForReal = pkgs.writeShellScriptBin "install-for-real" ''
          set -euo pipefail
          if [[ "''${EUID:-$(id -u)}" -ne 0 ]]; then
            echo "run me as root: sudo install-for-real" >&2
            exit 1
          fi
          echo "This ERASES the disk(s) in ${hostName}'s disko config and installs ${hostName}."
          ${optionalString hasLuks ''echo "You will be prompted to set the LUKS passphrase."''}
          # disko.nix names disks by path; a wrong guess there would otherwise
          # fail halfway through partitioning
          for disk in ${escapeShellArgs disks}; do
            if [[ ! -b "$disk" ]]; then
              echo "$disk does not exist. Disks here, by path:" >&2
              ls -l /dev/disk/by-path >&2
              echo "Fix disko.nix for ${hostName} and rebuild the ISO." >&2
              exit 1
            fi
          done
          ${optionalString (cfg.preInstallChecks != [ ]) ''
            failed=0
            ${runChecks "pre-install-check" cfg.preInstallChecks}
            if [[ $failed != 0 ]]; then
              echo "A pre-install check failed; nothing was changed." >&2
              exit 1
            fi
          ''}
          read -rp "Type 'install' to continue: " confirm
          [[ "$confirm" == "install" ]] || { echo "aborted."; exit 1; }

          echo ">>> Partition + format + mount"
          ${diskoScript}

          echo ">>> Installing ${hostName} from the baked closure (offline)"
          nixos-install --system ${toplevel} --no-root-passwd --no-channel-copy

          ${optionalString (cfg.postInstallChecks != [ ]) ''
            echo ">>> Checking the installed system"
            failed=0
            ${runChecks "post-install-check" cfg.postInstallChecks}
            if [[ $failed != 0 ]]; then
              echo "!!! A post-install check failed. Do NOT reboot: fix it with /mnt still mounted" >&2
              echo "!!! (e.g. nixos-enter --root /mnt), or re-run install-for-real." >&2
              exit 1
            fi
          ''}

          # root stays locked (--no-root-passwd); ${mainUser} is in wheel, so set
          # its password here -> written to the installed /etc/shadow. mutableUsers
          # is true, so it persists across rebuilds.
          echo ">>> Set a login password for ${mainUser}:"
          until nixos-enter --root /mnt -c "passwd ${mainUser}"; do
            echo "    passwd failed; try again."
          done

          echo ">>> Done. Reboot, ${optionalString hasLuks "unlock with your passphrase, "}log in as ${mainUser}."
        '';

        installer = pkgs.nixos (
          { modulesPath, ... }:
          {
            imports = [
              "${modulesPath}/installer/cd-dvd/installation-cd-minimal.nix"
            ]
            ++ optional (cfg.efiBootloader == "systemd-boot") ./systemd-boot-iso.nix
            ++ cfg.liveModules;

            # pkgs.nixos hands the live system this host's pkgs instance, which
            # is already configured; nixpkgs.config set by liveModules (e.g. an
            # unfree predicate) would fail the external-instance assertion.
            nixpkgs.config = mkForce { };

            # Bake this host's whole closure onto the ISO -> install is offline.
            isoImage.storeContents = [ toplevel ];

            environment.systemPackages = [ installForReal ];

            # Minimal installer: no ZFS (slims the squashfs; host is btrfs anyway).
            boot.supportedFilesystems.zfs = mkForce false;

            # pkgs.nixos's nixpkgs source carries no version info; name the
            # live system (and the ISO file) after the host's nixpkgs.
            system.nixos = { inherit (config.system.nixos) versionSuffix revision; };

            networking.hostName = mkForce "${hostName}-installer";
            system.stateVersion = config.system.stateVersion;
          }
        );
      in
      {
        for-real-installer-iso = installer.config.system.build.isoImage;
        # The live system's evaluation (.config, .options), for inspection
        # and VM tests.
        for-real-installer = installer;
      };
  };
}
