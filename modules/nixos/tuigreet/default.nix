{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.t11s.tuigreet;
  inherit (lib)
    mkEnableOption
    mkIf
    mkOption
    mkPackageOption
    types
    ;

  desktops = config.services.displayManager.sessionData.desktops;

  # tuigreet cannot hide an individual session, so hand it a filtered copy
  waylandSessions =
    if cfg.hiddenSessions == [ ] then
      "${desktops}/share/wayland-sessions"
    else
      pkgs.runCommandLocal "wayland-sessions-filtered" { } ''
        mkdir -p $out
        cp ${desktops}/share/wayland-sessions/*.desktop $out/
        rm -f ${lib.concatMapStringsSep " " (s: "$out/${s}") cfg.hiddenSessions}
      '';

  format = pkgs.formats.toml { };
in
{
  options.t11s.tuigreet = {
    enable = mkEnableOption "tuigreet greeter via greetd";
    package = mkPackageOption pkgs "tuigreet" { };

    hiddenSessions = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [ "hyprland.desktop" ];
      description = "wayland session .desktop files to keep out of the picker";
    };

    configFile = mkOption {
      type = types.path;
      readOnly = true;
      # toml has no null, so an option left unset is dropped rather than rendered
      default = format.generate "tuigreet.toml" (lib.filterAttrsRecursive (_: v: v != null) cfg.settings);
      defaultText = lib.literalMD "rendered from `settings`";
      description = "the rendered config, for `tuigreet --mock --config`";
    };

    settings = mkOption {
      default = { };
      description = ''
        tuigreet's TOML config. Rendered to the store and passed as `--config`,
        which replaces the /etc and ~ layers rather than stacking onto them.
        `tuigreet --dump-config` prints the full schema.
      '';
      type = types.submodule {
        freeformType = format.type;
        options = {
          session.sessions_dirs = mkOption {
            type = types.listOf types.path;
            default = [ waylandSessions ];
            defaultText = lib.literalMD "the aggregated wayland sessions, minus `hiddenSessions`";
            description = "directories scanned for wayland sessions";
          };
          session.xsessions_dirs = mkOption {
            type = types.listOf types.path;
            default = [ "${desktops}/share/xsessions" ];
            defaultText = lib.literalMD "the aggregated X11 sessions";
            description = "directories scanned for X11 sessions";
          };
          background.kind = mkOption {
            type = types.enum [
              "doom"
              "matrix"
              "none"
            ];
            default = "none";
            description = "background animation rendered behind the login UI";
          };
        };
      };
    };
  };

  config = mkIf cfg.enable {
    services.greetd = {
      enable = true;
      useTextGreeter = true;
      settings.default_session.command = "${lib.getExe cfg.package} --config ${cfg.configFile}";
    };
  };
}
