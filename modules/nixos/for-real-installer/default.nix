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
# that (its kernel, firmware) in `liveModules`.
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
  };

  config = mkIf cfg.enable {
    system.build.for-real-installer-iso =
      let
        toplevel = config.system.build.toplevel;
        diskoScript = config.system.build.diskoScript; # wipe+format+mount, device baked from disko.nix
        hostName = config.networking.hostName;
        mainUser = config.t11s.mainUser.name;
        disks = mapAttrsToList (_: disk: disk.device) config.disko.devices.disk;
        hasLuks = config.boot.initrd.luks.devices != { };

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
          read -rp "Type 'install' to continue: " confirm
          [[ "$confirm" == "install" ]] || { echo "aborted."; exit 1; }

          echo ">>> Partition + format + mount"
          ${diskoScript}

          echo ">>> Installing ${hostName} from the baked closure (offline)"
          nixos-install --system ${toplevel} --no-root-passwd --no-channel-copy

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

            networking.hostName = mkForce "${hostName}-installer";
            system.stateVersion = config.system.stateVersion;
          }
        );
      in
      installer.config.system.build.isoImage;
  };
}
