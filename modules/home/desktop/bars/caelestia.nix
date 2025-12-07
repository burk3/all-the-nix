{
  config,
  lib,
  ...
}:
let
  inherit (lib) mkIf;
  cfg = config.t11s.desktop;
in
{
  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      (mkIf (cfg.bar == "caelestia") {
        programs.caelestia = {
          enable = true;
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
