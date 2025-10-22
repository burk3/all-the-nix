{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) mkEnableOption mkIf;
  cfg = config.t11s.niri;
in
{
  options.t11s.niri = {
    enable = mkEnableOption "Enable niri configuration/systemd setup?";
  };
  config = mkIf cfg.enable {
    home.packages = with pkgs; [
      brightnessctl
    ];
    programs.niri.settings = {
      xwayland-satellite = {
        enable = true;
        path = lib.getExe pkgs.xwayland-satellite-unstable;
      };
      input.keyboard.numlock = true;
      input.focus-follows-mouse.enable = true;
      input.touchpad = {
        enable = true;
        dwt = true;
        natural-scroll = true;
        click-method = "clickfinger";
        scroll-factor = 0.5;
        tap = false;
      };
      layout = {
        preset-column-widths = [
          { proportion = 1. / 3.; }
          { proportion = 1. / 2.; }
          { proportion = 2. / 3.; }
        ];
        default-column-width = {
          proportion = 1. / 3.;
        };
        gaps = 16;
        center-focused-column = "never";
        border = {
          enable = false;
          width = 2;
          active.color = "#ffc87f";
          inactive.color = "#505050";
          urgent.color = "#9b0000";
        };
        shadow = {
          enable = true;
          softness = 10;
          spread = 4;
          offset.x = 3;
          offset.y = 3;
          color = "#0007";
        };
      };
      screenshot-path = "~/Pictures/Screenshots/Screenshot from %Y-%m-%d %H-%M-%S.png";
      window-rules = [
        {
          matches = [ { app-id = "firefox$"; } ];
          default-column-width = {
            proportion = 2. / 3.;
          };
        }
        {
          matches = [
            {
              app-id = "firefox$";
              title = "^Picture-in-Picture$";
            }
          ];
          open-floating = true;
        }
        {
          matches = [ { app-id = "^org\\.wezfurlong\\.wezterm$"; } ];
          default-column-width = { };
        }
        {
          matches = [ { app-id = "^mpv$"; } ];
          open-floating = true;
        }
        {
          geometry-corner-radius = lib.genAttrs [ "top-left" "top-right" "bottom-left" "bottom-right" ] (
            _: 8.
          );
          clip-to-geometry = true;
        }
        {
          matches = [
            {
              app-id = "^steam$";
              title = "^notificationtoasts";
            }
          ];
          open-floating = true;
        }
      ];
      layer-rules = [
        {
          matches = [ { namespace = "^launcher$"; } ];
          baba-is-float = true;
        }
      ];
      binds = import ./binds.nix { inherit config; };
      switch-events = {
        lid-close.action.spawn = [
          "systemctl"
          "suspend"
        ];
      };
    };
    programs.fuzzel = {
      enable = true;
      package = pkgs.unstable.fuzzel;
      settings.main.enable-mouse = "no";
    };
  };
}
