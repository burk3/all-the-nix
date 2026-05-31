{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
let
  inherit (lib) mkIf;
  cfg = config.t11s.desktop;

  # caelestia-niri pins app2unit back to v1.0.3 (nix/app2unit.nix) via
  # `pkgs.app2unit.overrideAttrs`, swapping only the src. nixpkgs 26.05 bumped
  # app2unit to 1.4.1 and added a postFixup (gated on `withTerminalSupport`) that
  # `--replace-fail`s the `A2U__TERMINAL_HANDLER=xdg-terminal-exec` line — which
  # doesn't exist in the v1.0.3 source, so the inherited postFixup aborts the
  # build. Override the shell's app2unit arg back to the current nixpkgs build.
  caelestiaPackage =
    inputs.caelestia-niri.packages.${pkgs.stdenv.hostPlatform.system}.with-cli.override
      { app2unit = pkgs.app2unit; };
in
{
  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      (mkIf (cfg.bar == "caelestia") {
        programs.caelestia = {
          enable = true;
          package = caelestiaPackage;
          systemd.enable = true;
          cli.enable = true;
          settings = {
            launcher = {
              enabled = true;
              dragThreshold = 50;
              vimKeybinds = false;
              enableDangerousActions = false;
              maxShown = 7;
              maxWallpapers = 9;
              specialPrefix = "@";
              useFuzzy = {
                apps = false;
                actions = false;
                schemes = false;
                variants = false;
                wallpapers = false;
              };
              showOnHover = false;
              actionPrefix = ">";
              actions = [
                {
                  name = "Calculator";
                  icon = "calculate";
                  description = "Do simple math equations (powered by Qalc)";
                  command = [
                    "autocomplete"
                    "calc"
                  ];
                  enabled = true;
                  dangerous = false;
                }
              ];
            };
          };
        };
        t11s.desktop.wallpaper.enable = lib.mkOverride 900 false;
      })
      (mkIf (config.t11s.desktop.launcher == "caelestia") (
        lib.mkAssert (config.t11s.desktop.bar == "caelestia")
          ''need to have `t11s.desktop.bar = "caelestia";` in order to use the caelestia launcher''
          {
            t11s.desktop._launcherCmd = "${lib.getExe config.programs.caelestia.cli.package} shell drawers toggle launcher";
          }
      ))
    ]
  );
}
