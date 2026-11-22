# Live-system module of the for-real installer (efiBootloader = "systemd-boot"):
# replaces the ISO's GRUB EFI image with a FAT image that boots systemd-boot
# into one Type #1 entry with the live kernel, initrd and, when the live system
# names one (hardware.deviceTree.name), its DTB. Everything the firmware and
# systemd-boot read is on that FAT image, which is the El Torito EFI image of
# the ISO and, dd'ed to a USB stick, its EFI system partition. The initrd then
# finds the ISO9660 by label as usual (config.lib.isoFileSystems).
#
# Why systemd-boot rather than GRUB's `devicetree`: nixpkgs' ISO GRUB image is
# built without the fdt module and isn't configurable from outside, and
# systemd-boot with a `devicetree` line is what devicetree laptops already boot
# with from their ESP (the NixOS bootloader with installDeviceTree).
{
  config,
  lib,
  pkgs,
  modulesPath,
  ...
}:
let
  efiArch = pkgs.stdenv.hostPlatform.efiArch;
  sdBoot = "${config.systemd.package}/lib/systemd/boot/efi/systemd-boot${efiArch}.efi";
  dt = config.hardware.deviceTree;
  withDtb = dt.enable && dt.name != null;
  kernel = "${config.boot.kernelPackages.kernel}/${config.system.boot.loader.kernelFile}";
  initrd = "${config.system.build.initialRamdisk}/${config.system.boot.loader.initrdFile}";
  timeout =
    if config.boot.loader.timeout == null then "menu-force" else toString config.boot.loader.timeout;

  esp =
    pkgs.runCommand "for-real-installer-esp.img"
      {
        nativeBuildInputs = with pkgs.buildPackages; [
          dosfstools
          mtools
          libfaketime
        ];
        strictDeps = true;
      }
      ''
        mkdir -p tree/EFI/BOOT tree/EFI/systemd tree/EFI/nixos tree/loader/entries
        cp ${sdBoot} tree/EFI/BOOT/BOOT${lib.toUpper efiArch}.EFI
        cp ${sdBoot} tree/EFI/systemd/systemd-boot${efiArch}.efi
        cp ${kernel} tree/EFI/nixos/kernel
        cp ${initrd} tree/EFI/nixos/initrd
        ${lib.optionalString withDtb "cp ${dt.package}/${dt.name} tree/EFI/nixos/devicetree.dtb"}
        cat > tree/loader/loader.conf <<EOF
        timeout ${timeout}
        default installer.conf
        editor yes
        EOF
        cat > tree/loader/entries/installer.conf <<EOF
        title ${config.system.nixos.distroName} ${config.system.nixos.label} installer (${config.networking.hostName})
        linux /EFI/nixos/kernel
        initrd /EFI/nixos/initrd
        ${lib.optionalString withDtb "devicetree /EFI/nixos/devicetree.dtb"}
        options init=${config.system.build.toplevel}/init ${toString config.boot.kernelParams}
        EOF
        find tree -exec touch --date=2000-01-01 {} +

        # FAT32 with room for the FAT and directories (as iso-image.nix's efiImg).
        kib=$(du -s --block-size=1K --apparent-size tree | cut -f1)
        kib=$(( (kib * 105 / 100 + 8192) / 1024 * 1024 ))
        truncate -s ''${kib}K $out
        mkfs.vfat -F 32 --invariant -i 12345678 -n EFIBOOT $out
        (cd tree
          for d in $(find . -mindepth 1 -type d | sort); do faketime "2000-01-01 00:00:00" mmd -i $out "::/''${d#./}"; done
          for f in $(find . -type f | sort); do mcopy -pm -i $out "$f" "::/''${f#./}"; done)
        mdir -/ -i $out ::/
        fsck.vfat -vn $out
      '';

  # Without an isohybrid MBR (x86 BIOS boot only) xorriso writes no partition
  # table at all, so a dd'ed stick would boot only on firmware that reads El
  # Torito from a USB disk. Write a GPT into the ISO's (empty) 32 KiB system
  # area whose one partition, an ESP, is exactly the El Torito EFI image;
  # the backup GPT goes into 1 MiB appended after the ISO9660 data. Linux
  # still finds the ISO9660 on the whole disk by its label.
  gpt = ''
    iso=$out/iso/$isoName
    lba=$(xorriso -indev "$iso" -report_el_torito plain 2>/dev/null |
      awk '/^El Torito boot img/ && $7 == "UEFI" { print $NF }')
    [ -n "$lba" ] || { echo "no UEFI El Torito image in $iso" >&2; exit 1; }
    start=$((lba * 4))
    size=$(( $(stat -c %s ${esp}) / 512 ))
    truncate -s +1M "$iso"
    sfdisk --wipe never --no-reread --no-tell-kernel "$iso" <<EOF
    label: gpt
    label-id: 1A16150E-0000-4000-8000-000000000000
    first-lba: 34
    start=$start, size=$size, type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B, uuid=1A16150E-0001-4000-8000-000000000000, name="EFIBOOT"
    EOF
    sfdisk --dump "$iso"
    got=$(sfdisk -J "$iso" | jq '.partitiontable.partitions[0].start')
    [ "$got" = "$start" ] || { echo "ESP placed at $got, not $start" >&2; exit 1; }
  '';
in
{
  # Drop GRUB's EFI image and directory; this one takes their place.
  isoImage.makeEfiBootable = lib.mkForce false;
  isoImage.contents = [
    {
      source = esp;
      target = "/boot/efi.img";
    }
  ];

  # iso-image.nix only marks an EFI boot image when makeEfiBootable is set;
  # this is its system.build.isoImage with ours marked instead, plus a GPT.
  system.build.isoImage = lib.mkForce (
    (
      pkgs.callPackage "${modulesPath}/../lib/make-iso9660-image.nix" {
        inherit (config.isoImage)
          compressImage
          volumeID
          contents
          squashfsCompression
          ;
        isoName = "${config.image.baseName}.iso";
        squashfsContents = config.isoImage.storeContents;
        efiBootable = true;
        efiBootImage = "boot/efi.img";
        syslinux = if config.isoImage.makeBiosBootable then pkgs.syslinux else null;
      }
      // lib.optionalAttrs config.isoImage.makeBiosBootable {
        bootable = true;
        bootImage = "/isolinux/isolinux.bin";
      }
      // lib.optionalAttrs (config.isoImage.makeUsbBootable && config.isoImage.makeBiosBootable) {
        usbBootable = true;
        isohybridMbrImage = "${pkgs.syslinux}/share/syslinux/isohdpfx.bin";
      }
    ).overrideAttrs
      (old: {
        nativeBuildInputs = old.nativeBuildInputs ++ [
          pkgs.buildPackages.util-linux
          pkgs.buildPackages.jq
        ];
        buildCommandPath = pkgs.writeText "make-iso9660-image-gpt.sh" (
          let
            script = builtins.readFile old.buildCommandPath;
            anchor = "$xorriso -output $out/iso/$isoName\n";
          in
          assert lib.assertMsg (lib.hasInfix anchor script) "make-iso9660-image.sh changed: no `${anchor}`";
          lib.replaceStrings [ anchor ] [ (anchor + gpt) ] script
        );
      })
  );

  system.build.forRealInstallerEsp = esp;
}
