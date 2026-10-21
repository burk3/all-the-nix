# Declarative disk layout for swaine (Orange Pi 6 Plus), a disposable builder.
#
# Single NVMe (Samsung 990 Pro 1TB), GPT:
#   ESP  (1G,   vfat)  -> /boot
#   swap (32G)         -> 2x RAM; big-parallel builds on 16G spill here
#   root (rest, btrfs) -> zstd-compressed subvolumes
#
# No encryption: it holds nothing but store paths, and a passphrase would block
# unattended reboots. btrfs rather than f2fs: the vendor kernel has no F2FS
# (or bcachefs), and btrfs data checksums catch on-disk corruption before
# clients substitute it. Clients trust this store unsigned (`trusted=true`).
#
# disko generates fileSystems.* and swapDevices from this, mounted by
# partlabel, so `device` only matters at install time.
{
  disko.devices.disk.main = {
    type = "disk";
    # The one NVMe, as the stock NixOS ISO (mainline, ACPI) saw it on
    # 2026-10-20: behind the root port at bus c0, in PCI segment 0000.
    device = "/dev/disk/by-path/pci-0000:c1:00.0-nvme-1";
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

        swap = {
          priority = 2;
          size = "32G";
          content = {
            type = "swap";
            discardPolicy = "both";
          };
        };

        root = {
          priority = 3;
          size = "100%";
          content = {
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
              };
          };
        };
      };
    };
  };
}
