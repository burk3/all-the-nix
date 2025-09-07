# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).
{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.t11s;
  isWsl = cfg.systemType == "wsl";
  hasScreen = (cfg.systemType == "workstation") || (cfg.systemType == "laptop");
in
with lib;
{
  options.t11s = with types; {
    enable = mkEnableOption "standard t11s host stuff";
    mainUser.name = mkOption {
      type = str;
      description = "main user of these systems. account will be created and be trusted user";
    };
    mainUser.description = mkOption {
      type = str;
      default = "";
      description = "Description of the main user";
    };
    resolved1111 = mkOption {
      type = bool;
      default = true;
      description = "Enable resolvd and use 1.1.1.1 as fallback";
    };
    privateNet = mkOption {
      type = bool;
      default = true;
      description = "Is the network this thing is connected to probably private?";
    };
    systemType = mkOption {
      type = enum [
        "laptop"
        "workstation"
        "wsl"
        "server"
      ];
      description = "what kinda box is it?";
    };
  };
  config = mkIf cfg.enable {
    nix.extraOptions = ''
      experimental-features = nix-command flakes
      builders-use-substitutes = true
      lazy-trees = true
    '';

    # Allow unfree packages
    nix.settings.trusted-users = [ cfg.mainUser.name ];
    nixpkgs.config.allowUnfree = true;

    # for nixbuild.net
    programs.ssh.extraConfig = ''
      Host eu.nixbuild.net
        PubkeyAcceptedKeyTypes ssh-ed25519
        ServerAliveInterval 60
        IPQoS throughput
        IdentityFile /root/.ssh/nixbuild-dot-net
    '';
    programs.ssh.knownHosts = {
      nixbuild = {
        hostNames = [ "eu.nixbuild.net" ];
        publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPIQCZc54poJ8vqawd8TraNryQeJnvH1eLpIDgbiqymM";
      };
    };

    # enable tpm2 and some features
    security.tpm2 = mkIf (!isWsl) {
      enable = true;
      pkcs11.enable = true;
      tctiEnvironment.enable = true;
    };

    # vanity
    catppuccin.enable = true;
    catppuccin.accent = "teal";

    # Bootloader.
    boot = mkIf (!isWsl) {
      # Enable "Silent Boot"
      consoleLogLevel = 0;
      initrd.verbose = true;
      # Hide the OS choice for bootloaders.
      # It's still possible to open the bootloader list by pressing any key
      # It will just not appear on screen unless a key is pressed
      loader.timeout = 2;
    };

    # lets try resolved for dns stuff?
    services.resolved = mkIf ((!isWsl) || cfg.resolved1111) {
      enable = true;
      fallbackDns = [
        "1.1.1.1#one.one.one.one"
        "1.0.0.1#one.one.one.one"
      ];
    };

    # TIME SYNC
    networking.timeServers = [
      "time1.facebook.com"
      "time2.facebook.com"
      "time3.facebook.com"
      "time4.facebook.com"
      "time5.facebook.com"
    ];
    # default is timesyncd which is probably fine

    # for hyprlock
    # pam shouldn't use fprint since hyprlock will do fprint in parallel on its own
    security.pam.services.hyprlock.fprintAuth = cfg.systemType == "laptop";
    services.fprintd.enable = cfg.systemType == "laptop";

    # virty bois
    virtualisation.podman = {
      enable = !isWsl;
      dockerCompat = true;
    };
    virtualisation.containers = mkIf (!isWsl) {
      enable = true;
      containersConf.settings = {
        engine.compose_warning_logs = false;
      };
    };

    # tailscale
    services.tailscale.enable = !isWsl;

    # Select internationalisation properties.
    i18n.defaultLocale = "en_US.UTF-8";

    i18n.extraLocaleSettings = {
      LC_ADDRESS = "en_US.UTF-8";
      LC_IDENTIFICATION = "en_US.UTF-8";
      LC_MEASUREMENT = "en_US.UTF-8";
      LC_MONETARY = "en_US.UTF-8";
      LC_NAME = "en_US.UTF-8";
      LC_NUMERIC = "en_US.UTF-8";
      LC_PAPER = "en_US.UTF-8";
      LC_TELEPHONE = "en_US.UTF-8";
      LC_TIME = "en_GB.UTF-8";
    };

    # fix command-not-found dbpath for flakes
    #environment.etc."programs.sqlite".source = programsdb.packages.${pkgs.system}.programs-sqlite;
    #programs.command-not-found.dbPath = "/etc/programs.sqlite";

    # Enable the X11 windowing system.
    services.xserver.enable = hasScreen;

    # Enable the GNOME Desktop Environment.
    services.xserver.displayManager.gdm.enable = hasScreen;

    # lets add hyprland in there as well, why the fuck not
    programs.hyprland = {
      enable = hasScreen;
      withUWSM = true;
    };
    programs.uwsm.enable = hasScreen;
    programs.iio-hyprland.enable = hasScreen;

    # niri compositor
    programs.niri.enable = hasScreen;

    # Configure keymap in X11
    services.xserver.xkb = {
      layout = "us";
      variant = "";
    };

    # Enable CUPS to print documents.
    services.printing.enable = mkIf hasScreen true;

    # mdns for discovery!
    services.avahi = mkIf ((!isWsl) && cfg.privateNet) {
      enable = true;
      nssmdns4 = true;
      openFirewall = true;
    };

    hardware.bluetooth = mkIf hasScreen {
      enable = true; # enables support for Bluetooth
      powerOnBoot = true; # powers up the default Bluetooth controller on boot
      settings.General.Enable = "Source,Sink,Media,Socket";
    };
    services.blueman.enable = mkIf hasScreen true;

    # Enable sound with pipewire.
    services.pulseaudio.enable = false;
    security.rtkit.enable = mkIf hasScreen true;
    services.pipewire = mkIf hasScreen {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
      # If you want to use JACK applications, uncomment this
      #jack.enable = true;

      # use the example session manager (no others are packaged yet so this is enabled by default,
      # no need to redefine it in your config for now)
      #media-session.enable = true;
      wireplumber.extraConfig.bluetoothEnhancements = {
        "monitor.bluez.properties" = {
          "bluez5.enable-sbc-xq" = true;
          "bluez5.enable-msbc" = true;
          "bluez5.enable-hw-volume" = true;
          "bluez5.roles" = [
            "hsp_hs"
            "hsp_ag"
            "hfp_hf"
            "hfp_ag"
            "a2dp_sink"
            "a2dp_source"
            "bap_sink"
            "bap_source"
          ];
        };
      };
    };

    # Enable touchpad support (enabled default in most desktopManager).
    # services.xserver.libinput.enable = true;

    services.fwupd.enable = !isWsl;

    # so far needed for zsh.
    environment.pathsToLink = [ "/share/zsh" ];

    # add zsh to /etc/shells
    environment.shells = with pkgs; [ zsh ];
    # Prevent the new user dialog in zsh
    #system.userActivationScripts.zshrc = "touch .zshrc";

    # Define a user account. Don't forget to set a password with ‘passwd’.
    users.users.${cfg.mainUser.name} = {
      isNormalUser = true;
      description = cfg.mainUser.description;
      shell = pkgs.zsh;
      extraGroups = [
        "docker"
        "podman"
        "libvirtd"
        "networkmanager"
        "wheel"
        "tss"
      ];
    };

    # zsh
    programs.zsh.enable = true;

    # Install firefox.
    programs.firefox.enable = hasScreen;

    # The Editor
    programs.neovim = {
      enable = true;
      defaultEditor = true;
      vimAlias = true;
    };

    # more stuff for everyone
    programs.git.enable = true;
    programs.steam.enable = hasScreen;

    # mullvad vpn?
    services.mullvad-vpn = mkIf hasScreen {
      enable = true;
      package = pkgs.mullvad-vpn;
    };


    # List packages installed in system profile. To search, run:
    # $ nix search wget
    environment.systemPackages = with pkgs; [
      nix-tree
      curl
      wget
      file
      htop
      iotop
      killall
      dig
      jq
    ]
    ++ optionals hasScreen [
      wooting-udev-rules
      wootility
      google-chrome
      adwaita-icon-theme
      fluent-gtk-theme
      fluent-icon-theme
      mission-center
      iosevka
      nvtopPackages.full
    ]
    ++ optionals (!isWsl) [
      podman-compose
      sbctl
    ];

    fonts.enableDefaultPackages = hasScreen;

    # hint Electron apps to use Wayland:
    environment.sessionVariables.NIXOS_OZONE_WL = "1";

    # for some node stuff I guess
    programs.nix-ld.enable = true;

    programs.wireshark.enable = hasScreen;

    # Some programs need SUID wrappers, can be configured further or are
    # started in user sessions.
    # programs.mtr.enable = true;
    # programs.gnupg.agent = {
    #   enable = true;
    #   enableSSHSupport = true;
    # };

    # List services that you want to enable:

    # Enable the OpenSSH daemon.
    # services.openssh.enable = true;
  };
}
