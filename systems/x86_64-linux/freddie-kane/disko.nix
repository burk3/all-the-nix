# Declarative disk layout for freddie-kane (Framework 13 AMD 7040).
#
# Single NVMe, GPT:
#   ESP       (1G,   vfat)  -> /boot
#   cryptswap (64G,  LUKS2) -> swap (== RAM, resume target for hibernate)
#   cryptroot (rest, LUKS2) -> btrfs, zstd-compressed subvolumes
#
# Block-level LUKS2 (not btrfs-native encryption), so it's fully compatible
# with lanzaboote Measured Boot (systemd-pcrlock). Both LUKS containers are
# created with a passphrase at install time; TPM2+PIN unlock is enrolled
# against the pcrlock policy AFTER first boot -- see the runbook in CLAUDE.md.
#
# disko generates fileSystems.*, swapDevices, and boot.initrd.luks.devices.*
# from this, replacing what used to live in hardware-configuration.nix.
{
  disko.devices.disk.main = {
    type = "disk";
    # Overridden at install time by `disko-install --disk main <device>`.
    device = "/dev/nvme0n1";
    content = {
      type = "gpt";
      partitions = {
        ESP = {
          priority = 1;
          type = "EF00";
          size = "1G";
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

        cryptswap = {
          priority = 2;
          size = "64G"; # == RAM, for hibernate
          content = {
            type = "luks";
            name = "cryptswap";
            settings = {
              allowDiscards = true;
              bypassWorkqueues = true;
            };
            content = {
              type = "swap";
              resumeDevice = true; # sets boot.resumeDevice -> /dev/mapper/cryptswap
            };
          };
        };

        cryptroot = {
          priority = 3;
          size = "100%";
          content = {
            type = "luks";
            name = "cryptroot";
            settings = {
              allowDiscards = true;
              bypassWorkqueues = true;
            };
            content = {
              type = "btrfs";
              extraArgs = [ "-f" ];
              subvolumes = {
                "@" = {
                  mountpoint = "/";
                  mountOptions = [
                    "compress=zstd"
                    "noatime"
                  ];
                };
                "@home" = {
                  mountpoint = "/home";
                  mountOptions = [
                    "compress=zstd"
                    "noatime"
                  ];
                };
                "@nix" = {
                  mountpoint = "/nix";
                  mountOptions = [
                    "compress=zstd"
                    "noatime"
                  ];
                };
              };
            };
          };
        };
      };
    };
  };
}
