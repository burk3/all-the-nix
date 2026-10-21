{
  inputs,
  lib,
  pkgs,
  ...
}:
let
  # Mainline (cache.nixos.org; ARCH_CIX, Sky1 PCIe and RTL8126 via r8169) or
  # the CIX vendor kernel from nixos-cix-cd8180, which is never cached for
  # this nixpkgs and brings the GPU/NPU/ISP/VPU drivers a builder does not
  # use. Mainline drives the NVMe, both NICs and KVM here in ACPI mode
  # (checked from the stock ISO, 2026-10-20).
  vendorKernel = false;

  board = inputs.nixos-cix-cd8180.nixosModules.orangepi6plus;
  ccacheDir = "/var/cache/ccache";
in
{
  # With vendorKernel the board module supplies the kernel, firmware and the
  # ACPI-mode kernel cmdline, including the consoles set below for mainline.
  imports = [
    inputs.disko.nixosModules.disko
    ./disko.nix
  ]
  ++ lib.optional vendorKernel board;

  ### identity
  networking.hostName = "swaine";
  time.timeZone = "America/Los_Angeles";

  t11s.enable = true;
  t11s.caches.enable = true;
  t11s.systemType = "server";
  t11s.mainUser.name = "burke";
  t11s.mainUser.description = "Burke Cates";
  t11s.remotebuild.serveBuilds = true;
  t11s.internalCA.enable = true;
  t11s.nodeMetrics.enable = true;
  # nix build .#nixosConfigurations.swaine.config.system.build.for-real-installer-iso
  # (the first install used nixos-anywhere from the stock ISO instead)
  t11s.forRealInstaller = {
    enable = true;
    # the stock installer kernel is mainline; the vendor one has to be brought along
    liveModules = lib.optional vendorKernel board;
  };

  ### boot
  # The board ships UEFI in SPI flash. The vendor flake's own GRUB path only
  # fills the ESP when building its SD image, so use systemd-boot instead.
  # efi=noruntime leaves no EFI variables to write, so bootctl relies on the
  # removable-media path EFI/BOOT/BOOTAA64.EFI.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = false;
  # The menu's countdown never fires on this firmware (first boot sat in the
  # menu until Enter). timeout 0 boots the default entry without waiting on a
  # timer; hold a key during boot to get the menu.
  boot.loader.timeout = 0;
  boot.kernelPackages =
    if vendorKernel then
      # The vendor kernel is built with CONFIG_EFI_STUB=y, but
      # linuxManualConfig leaves `features` empty, which fails systemd-boot's
      # EFI-stub assertion. passthru only, so the kernel derivation is
      # unchanged.
      lib.mkForce (
        pkgs.linuxPackagesFor (
          pkgs.cixSky1VendorKernel.overrideAttrs (old: {
            passthru = old.passthru // {
              features = (old.passthru.features or { }) // {
                efiBootStub = true;
              };
            };
          })
        )
      )
    else
      pkgs.linuxPackages_latest;
  # The vendor cmdline minus its display and GPU/VPU parts. efifb stays on:
  # mainline has no CIX display driver, so the EFI framebuffer is the HDMI
  # console.
  boot.kernelParams = lib.optionals (!vendorKernel) [
    "console=ttyAMA2,115200" # debug UART (PL011 at 0x040d0000)
    "console=tty0" # HDMI; listed last, so it is /dev/console
    "earlycon" # from the ACPI SPCR table
    "efi=noruntime" # CIX firmware's runtime services are broken
    "acpi=force"
    "arm-smmu-v3.disable_bypass=0"
    "pcie_aspm=off" # NVMe stability, per the vendor
  ];
  # systemd only starts a getty on the primary console (tty0)
  systemd.services."serial-getty@ttyAMA2" = {
    enable = true;
    wantedBy = [ "getty.target" ];
  };

  ### nix
  # One build per CPU (12). Clients are told the same in remotebuilder
  # hostConfigs and juicy-j's Hydra machines file.
  nix.settings.max-jobs = "auto";
  nix.settings.cores = 0;
  # Container (systemd-nspawn) NixOS tests, as on juicy-j: each build gets
  # its own auto-allocated uid range. Settings from the nixpkgs manual,
  # "Running Tests"; clients learn of uid-range from remotebuilder hostConfigs.
  nix.settings.auto-allocate-uids = true;
  nix.settings.extra-system-features = [ "uid-range" ];
  nix.settings.use-cgroups = true;
  nix.settings.experimental-features = [
    "auto-allocate-uids"
    "cgroups"
  ];

  # A persistent ccache for builds that opt into it, mainly kernels while
  # iterating on aarch64 closures. The vendor kernel derivation hardcodes
  # CCACHE_DIR=/tmp/ccache, so the cache is also mounted there; ccacheStdenv
  # uses the real path. `CCACHE_DIR=/var/cache/ccache ccache -s` shows stats.
  #
  # World-writable, not programs.ccache's 0770 root:nixbld: with
  # auto-allocate-uids each build runs as its own uid and gid (start-id plus
  # a slot), outside nixbld, and the next build may get a different slot.
  # So entries must be writable by anyone. The price: any build or local
  # user can plant objects, and clients substitute this store unsigned.
  #
  # ccache.conf in the cache dir holds defaults for builds that don't set
  # their own (CCACHE_* env wins), which the vendor kernel doesn't:
  # - umask: 000, for the reason above.
  # - sloppiness: kernels regenerate autoconf.h and friends every build, so
  #   compare include contents, not timestamps; otherwise ccache drops out of
  #   direct mode for every file that includes them.
  nix.settings.extra-sandbox-paths = [
    ccacheDir
    "/tmp/ccache=${ccacheDir}"
  ];
  environment.systemPackages = [ pkgs.ccache ];
  systemd.tmpfiles.rules =
    let
      ccacheConf = lib.concatMapStrings (line: "${line}\\n") [
        "umask = 000"
        "sloppiness = include_file_mtime,include_file_ctime,time_macros"
      ];
    in
    [
      "d ${ccacheDir} 0777 root root -"
      "f+ ${ccacheDir}/ccache.conf 0644 root root - ${ccacheConf}"
    ];

  ### net
  # DHCP on whichever wired port is plugged in (two RTL8126 ports).
  networking.useDHCP = false;
  systemd.network = {
    enable = true;
    wait-online.anyInterface = true;
    networks."10-wired" = {
      matchConfig.Type = "ether";
      matchConfig.Name = "en*";
      networkConfig.DHCP = "yes";
    };
  };

  networking.nftables.enable = true;
  networking.firewall = {
    enable = true;
    allowPing = true;
    allowedTCPPorts = [ 22 ];
  };

  services.openssh.enable = true;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  system.stateVersion = "26.05"; # Did you read the comment?
}
