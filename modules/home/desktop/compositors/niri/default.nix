{
  config,
  lib,
  pkgs,
  inputs,
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
            from = "#ea9a97"; # rose
            to = "#eb6f92"; # love
            angle = 45;
          };
        };
        border = {
          enable = false;
          width = 2;
          active.color = "#f6c177"; # gold
          inactive.color = "#56526e"; # highlight high
          urgent.color = "#eb6f92"; # love
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
        ## not supported in the module yet. see end of file
        # {
        #   # from noctilia-shell docs
        #   # apps: blur them all without xray for a better look
        #   background-effect = {
        #     blur = true;
        #     xray = false;
        #   };
        # }
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
        {
          matches = [ { namespace = "^noctilia-overview*"; } ];
          place-within-backdrop = true;
        }
        ## not supported in module yet. see end of file.
        # {
        #   # from noctilia-shell docs
        #   # Noctilia: blur everywhere without xray for a better look
        #   matches = [ { namespace = "^noctalia-(background|launcher-overlay|dock)-.*$"; } ];
        #   background-effect = {
        #     xray = false;
        #   };
        # }
      ];
      binds = import ./binds.nix { inherit config lib pkgs; };
      switch-events = {
        lid-close.action.spawn = [
          "systemctl"
          "suspend"
        ];
      };
    };
    ## dirty hack!
    # the following uses a niri flake internal api to write some configs that
    # are unsupported by the module as of now. i expect these will go away at
    # some point.
    xdg.configFile.niri-config.source =
      let
        inherit (inputs.niri.lib.internal) validated-config-for;
        inherit (config.programs.niri) finalConfig package;
      in
      lib.mkForce (
        validated-config-for pkgs package ''
          ${finalConfig}

          window-rule {
            background-effect {
              blur true
              xray false
            }
          }

          layer-rule {
            match namespace="^noctalia-(background|launcher-overlay|dock)-.*$"
            background-effect {
              xray false
            }
          }
        ''
      );
  };
}
