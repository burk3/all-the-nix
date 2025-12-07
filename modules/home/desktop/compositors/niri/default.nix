{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) mkDefault mkEnableOption;
  cfg = config.t11s.desktop.compositor.niri;
in
{
  options.t11s.desktop.compositor.niri.enable = mkEnableOption "enable niri compositor config";
  config = lib.mkIf cfg.enable {
    t11s.desktop.lockAndIdle.desktopSpecific.niri =
      let
        niri = lib.getExe config.programs.niri.package;
      in
      {
        desktopString = "niri";
        dpmsOff = mkDefault "${niri} msg action power-off-monitors";
        dpmsOn = mkDefault "${niri} msg action power-on-monitors";
        afterSleepScript = mkDefault "";
      };
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
      gestures.hot-corners.enable = false;
      layout = {
        preset-column-widths = [
          { proportion = 1.0 / 3.0; }
          { proportion = 1.0 / 2.0; }
          { proportion = 2.0 / 3.0; }
        ];
        default-column-width = {
          proportion = 1.0 / 3.0;
        };
        gaps = 16;
        center-focused-column = "never";
        focus-ring = {
          enable = true;
          width = 2;
          active.gradient = {
            from = "hsl(11deg, 59%, 67%)";
            to = "hsl(0deg, 60%, 67%)";
            angle = 45;
          };
        };
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
            proportion = 2.0 / 3.0;
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
            _: 8.0
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
      binds = import ./binds.nix { inherit config lib; };
      switch-events = {
        lid-close.action.spawn = [
          "systemctl"
          "suspend"
        ];
      };
    };
  };
}
