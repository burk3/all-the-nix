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
in
{
  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      (mkIf (cfg.bar == "noctalia") {
        home.packages = [ config.programs.noctalia-shell.package ];
        programs.niri.settings.spawn-at-startup = [
          {
            command = [
              "${lib.getExe config.programs.noctalia-shell.package}"
            ];
          }
        ];
        programs.noctalia-shell = {
          enable = true;
          settings = {
            bar = {
              density = "compact";
              position = "top";
              showCapsule = false;
              widgets = {
                left = [
                  {
                    id = "ControlCenter";
                    useDistroLogo = true;
                  }
                  {
                    id = "Network";
                  }
                  {
                    id = "Bluetooth";
                  }
                ];
                center = [
                  {
                    hideUnoccupied = false;
                    id = "Workspace";
                    labelMode = "none";
                  }
                ];
                right = [
                  {
                    alwaysShowPercentage = false;
                    id = "Battery";
                    warningThreshold = 30;
                  }
                  {
                    formatHorizontal = "HH:mm";
                    formatVertical = "HH:mm";
                    id = "Clock";
                    useMonospacedFont = true;
                    usePrimaryColor = true;
                  }
                ];
              };
            };
            colorSchemes.predefinedScheme = "Tokyo-Night";
            general = {
              avatarImage = "/home/burke/.face";
              radiusRatio = 0.2;
            };
            location = {
              name = "Seattle";
            };
          };
        };
      })
      (mkIf (cfg.launcher == "noctalia") (
        lib.mkAssert (config.t11s.desktop.bar == "noctalia")
          ''need to have `t11s.desktop.bar = "noctalia";` in order to use the noctalia launcher''
          {
            t11s.desktop._launcherCmd = "${lib.getExe config.programs.noctalia-shell.package} ipc call launcher toggle";
          }
      ))
    ]
  );
}
