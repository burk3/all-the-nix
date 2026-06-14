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
  noctaliaCfg = cfg.noctalia;
in
{
  options.t11s.desktop.noctalia = {
    barPosition = lib.mkOption {
      type = lib.types.enum [
        "top"
        "left"
        "bottom"
        "right"
      ];
      default = "top";
      description = "where to stick the noctalia bar";
    };
    pinnedApps = lib.mkOption {
      description = "apps to be pinned";
      type = lib.types.listOf lib.types.str;
      default = [ ];
    };
    location = lib.mkOption {
      description = "location for weather and stuff";
      type = lib.types.str;
      default = "Seattle";
    };
  };

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
              position = cfg.noctalia.barPosition;
              showCapsule = false;
              widgets = {
                left = [
                  {
                    id = "ControlCenter";
                    useDistroLogo = true;
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
                    defaultSettings = {
                      compactMode = false;
                      defaultPeerAction = "copy-ip";
                      hideDisconnected = false;
                      hideMullvadExitNodes = true;
                      loginServer = "";
                      pingCount = 5;
                      refreshInterval = 5000;
                      showIpAddress = true;
                      showPeerCount = true;
                      showSearchBar = false;
                      sshUsername = "";
                      taildropDownloadDir = "~/Downloads";
                      taildropEnabled = true;
                      taildropReceiveMode = "operator";
                      terminalCommand = "";
                    };
                    id = "plugin:tailscale";
                  }
                  {
                    id = "Network";
                  }
                  {
                    id = "Bluetooth";
                  }
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
              avatarImage = "/home/${config.home.username}/.face";
              radiusRatio = 0.2;
            };
            location = {
              name = noctaliaCfg.location;
            };
            appLauncher.pinnedApps = noctaliaCfg.pinnedApps;
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
