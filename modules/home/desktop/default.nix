{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) mkIf mkEnableOption mkOption;
  cfg = config.t11s.desktop;
in
{
  # noctalia is the whole shell (bar, launcher, lock, idle, notifications, OSD).
  # No bar selection on purpose: enabling this module means using noctalia.
  imports = [
    ./lock-idle.nix
    ./bars/noctalia.nix
  ];
  options.t11s.desktop =
    let
      inherit (lib) types;
    in
    {
      enable = mkEnableOption "standard desktop configs";
      networkManager.enable = mkEnableOption "using NetworkManager";
      bluetoothSupport.enable = mkEnableOption "bluetooth stuff";
      services = {
        gnome-keyring.enable = mkOption {
          description = "enable and configure gnome-keyring";
          type = types.bool;
          default = true;
        };
      };
      launcher = mkOption {
        description = "program launcher to use";
        type = types.enum [
          "fuzzel"
          "noctalia"
        ];
        default = "fuzzel";
      };
      _launcherCmd = mkOption {
        type = types.str;
      };
    };
  config = mkIf cfg.enable (
    lib.mkMerge [
      {
        t11s.desktop.lockAndIdle.enable = lib.mkDefault true;
        home.packages = with pkgs; [
          brightnessctl
          pavucontrol
          posy-cursors
          # fonts
          iosevka
        ];

        fonts.fontconfig = {
          enable = true;
          defaultFonts.monospace = [
            "Iosevka"
            "Berkeley Mono"
          ];
        };

        home.pointerCursor = {
          name = "Posy_Cursor_Black";
          package = pkgs.posy-cursors;
          x11.enable = true;
          gtk.enable = true;
          # one day
          #    hyprcursor.enable = true;
        };
      }
      (lib.mkIf (cfg.launcher == "fuzzel") {
        programs.fuzzel = {
          enable = true;
          package = pkgs.unstable.fuzzel;
          settings.main.enable-mouse = "no";
        };
        t11s.desktop._launcherCmd = "${lib.getExe config.programs.fuzzel.package}";
      })
      (lib.mkIf cfg.services.gnome-keyring.enable {
        services.gnome-keyring = {
          enable = true;
          components = [
            "pkcs11"
            "secrets"
          ];
        };
        # set ssh-agent to use the gnome-keyring socket
        # dont need to do this anymore i dont think.
        #home.sessionVariables = {
        #  SSH_AUTH_SOCK = "\${XDG_RUNTIME_DIR:-/run/user/$UID}/gcr/ssh";
        #};
      })
    ]
  );
}
