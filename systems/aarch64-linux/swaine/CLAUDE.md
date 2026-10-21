# swaine

Orange Pi 6 Plus (CIX CD8180 "Sky1", 12 cores, 16G), headless. An **aarch64-linux remote builder** for juicy-j and freddie-kane, and Hydra's aarch64 builder (it builds its own closure). Disposable: no encryption, reimage rather than repair.

## Kernel

`vendorKernel` (a `let` binding in `default.nix`) picks one of two kernels:

- **`false` (default): mainline `linuxPackages_latest`.** It comes from cache.nixos.org. In ACPI mode it drives the NVMe, both RTL8126 ports (r8169) and KVM; the stock ISO (7.3) confirmed this on 2026-10-20. It has no Orange Pi 6 Plus devicetree, so the board boots in ACPI mode (`acpi=force`). `default.nix` copies the vendor cmdline minus the display and GPU parts. `efifb` stays on, because mainline has no CIX display driver, so the EFI framebuffer is the HDMI console.
- **`true`: the CIX vendor 6.6 kernel**, from the `nixos-cix-cd8180` flake input. The board module (`nixosModules.orangepi6plus`) is imported only in this mode. It brings the vendor kernel, firmware, the GPU/NPU/ISP/VPU drivers and their userspace, and its own cmdline. No cache has it for this nixpkgs, so it builds here. Gotchas:
  - The flake disables NixOS GRUB and only fills the ESP for its SD image, so swaine uses systemd-boot in both modes.
  - `boot.kernelPackages` gets `features.efiBootStub = true` in passthru, because linuxManualConfig leaves `features` empty and that fails systemd-boot's assertion.
  - The module sets `boot.initrd.availableKernelModules` and `includeDefaultModules` with `mkForce`.
  - Its kernel config has no F2FS, bcachefs, ZRAM or `ntsync`. That is why the root filesystem is btrfs and swap is a partition.

In both modes, `efi=noruntime` leaves no EFI variables, so systemd-boot runs from the removable path `EFI/BOOT/BOOTAA64.EFI`. The debug UART is `ttyAMA2` at 115200 (mainline in ACPI mode enumerates ttyAMA0-3).

## Install (from the stock ISO, on the box)

1. Boot the stock NixOS aarch64 minimal ISO. Give root a way in: `sudo passwd root`, or a key in `/root/.ssh/authorized_keys`.
2. Check `ls -l /dev/disk/by-path` against `disko.nix`. disko does not check the path before partitioning.
3. Copy the flake source over as plain files, then build and install on the box. It evaluates and builds locally, and fetches only signed paths from the binary caches:
   ```sh
   git ls-files -z --cached --others --exclude-standard | tar --null -T - -cz | ssh root@<ip> 'mkdir -p src && tar -xz -C src'
   ssh root@<ip>
   export NIX_CONFIG="experimental-features = nix-command flakes pipe-operators"
   nix build -o disko "path:/root/src#nixosConfigurations.swaine.config.system.build.diskoScript"
   ./disko --yes-wipe-all-disks
   nixos-install --flake "path:/root/src#swaine" --no-root-passwd --no-channel-copy
   nixos-enter --root /mnt -c 'passwd burke'    # optional: console logins
   ```
   ssh with a user cert works without a password, because sshd trusts the user CA.

   nixos-anywhere from juicy-j failed here (2026-10-20). Determinate Nix 2.35 copying to the ISO's Nix 2.34 over `ssh-ng` was refused with "lacks a signature by a trusted key", even though the store reported `Trusted: 1`. `nix copy --no-check-sigs` gets through, but nixos-anywhere has no way to pass that flag.
4. First boot:
   ```sh
   sudo tailscale up
   sudo t11s-sign-host-key      # prompts for the burke@t11s.net provisioner password
   ```
   The renewal timer keeps the cert fresh after that. The CA won't renew an expired cert, so if swaine is off for more than 30 days, run `t11s-sign-host-key` again.
5. Clients trust swaine's host key through the CA. Nothing is pinned in `modules/nixos/remotebuilder`.

`t11s.forRealInstaller` is still on, as an offline alternative. Its ISO brings the vendor kernel along when `vendorKernel` is set.

## After first boot

- `t11s.nixbuild-dot-net` is disabled on juicy-j and freddie-kane now that swaine builds their aarch64 derivations. The module is still in the flake.

## ccache

`/var/cache/ccache` is in every build's sandbox, and is also mounted at `/tmp/ccache`, the path the vendor kernel hard-codes. It is world-writable (`0777`), and `ccache.conf` there supplies `umask = 000` and the kernel sloppiness flags to builds that don't set their own.

That is because of `auto-allocate-uids` (on for container tests). Each build runs as its own uid and gid (`start-id` plus a slot), outside `nixbld`, so NixOS's `programs.ccache` (`0770 root:nixbld`) would be unwritable, and a group-writable entry from one slot is not writable from another. A ccache user that sets `CCACHE_UMASK=007` itself defeats this. The cost: any build or local user can plant objects in it. Stats: `CCACHE_DIR=/var/cache/ccache ccache -s`.

## Metrics

`t11s.nodeMetrics` runs node-exporter on :9100 (tailscale0 only). juicy-j scrapes it in the `node-tailnet` job.
