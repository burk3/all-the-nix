# Disk layout for earl (ASUS Zenbook A16, Snapdragon X2 Elite), for the
# btrfs reinstall (path B: back up, wipe-install from the microSD rescue,
# restore /home).
#
# Internal NVMe (Samsung 9100 PRO), GPT:
#   ESP  (2G,   vfat)  -> /boot   ~65 MB kernel + ~36 MB initrd per generation
#   root (rest)        -> [LUKS2 "cryptroot" ->] btrfs, zstd-compressed
#                         subvolumes @, @home, @nix, @log
#
# `luks` below wraps the btrfs in a LUKS2 container. Off for the reinstall;
# LUKS comes after it (or with a later re-reinstall), unlocked by Tang over
# the network, a keyfile on the in-slot
# microSD, or TPM2 (+PIN) now that glymur-flake has the fTPM driver; a typed
# passphrase alone would stop unattended lab reboots. No swap partition
# (hibernation is off; zram below). The microSD rescue uses other filesystem
# labels (LABESP/a16-nixos); disko mounts by partlabel, so they never clash.
# Install with `sudo install-for-real` from earl's installer ISO
# (t11s.forRealInstaller in default.nix), which refuses a device that isn't
# on NVMe and checks \EFI\BOOT\BOOTAA64.EFI on the new ESP before it says
# done; don't restart without it.
let
  luks = false;

  btrfs = {
    type = "btrfs";
    extraArgs = [ "-f" ];
    subvolumes =
      let
        mountOptions = [
          "compress=zstd:1"
          "noatime"
        ];
      in
      {
        "@" = {
          mountpoint = "/";
          inherit mountOptions;
        };
        "@home" = {
          mountpoint = "/home";
          inherit mountOptions;
        };
        "@nix" = {
          mountpoint = "/nix";
          inherit mountOptions;
        };
        # Kept across root rollbacks; the journal is the lab's record.
        "@log" = {
          mountpoint = "/var/log";
          inherit mountOptions;
        };
      };
  };
in
{
  disko.devices.disk.main = {
    type = "disk";
    # Overridden at install time (--disk / disko-install --disk main ...).
    device = "/dev/nvme0n1";
    content = {
      type = "gpt";
      partitions = {
        ESP = {
          priority = 1;
          type = "EF00";
          size = "2G";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = [
              "fmask=0077"
              "dmask=0077"
            ];
          };
        };
        root = {
          priority = 2;
          size = "100%";
          content =
            if luks then
              {
                type = "luks";
                name = "cryptroot";
                settings.allowDiscards = true;
                # The unlock method (Tang clevis binding or a keyfile on the
                # microSD) is added by the unlock work; disko only creates the
                # container.
                content = btrfs;
              }
            else
              btrfs;
        };
      };
    };
  };

  zramSwap.enable = true;
}
