{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) mkIf;
  cfg = config.t11s.desktop;
  noctaliaCfg = cfg.noctalia;
  noctalia = config.programs.noctalia.package;
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
      description = ''
        apps to be pinned. since v5 the launcher no longer keeps its own pin
        list, so these land in the dock's pinned list (`[dock] pinned`) and are
        only visible when the dock is enabled.
      '';
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
      {
        programs.noctalia = {
          enable = true;
          # started by graphical-session.target rather than niri's
          # spawn-at-startup, so it restarts on crash and on config change
          systemd.enable = true;
          settings = {
            shell = {
              avatar_path = "${config.home.homeDirectory}/.face";
              corner_radius_scale = 0.2;
              # the unit restarts whenever the config changes; without this,
              # apps launched from noctalia share its cgroup and die with it
              launch_apps_as_systemd_services = true;
            };
            bar.main = {
              position = noctaliaCfg.barPosition;
              # v4 density = "compact"
              thickness = 26;
              # v4 barType = "simple": bar runs the full length of the screen
              margin_ends = 0;
              capsule = false;
              start = [ "control-center" ];
              center = [ "workspaces" ];
              end = [
                "network"
              ]
              ++ lib.optional cfg.bluetoothSupport.enable "bluetooth"
              ++ [
                "battery"
                "clock"
              ];
            };
            widget = {
              # v5 dropped useDistroLogo, but takes an arbitrary image
              control-center = {
                custom_image = "${pkgs.nixos-icons}/share/icons/hicolor/scalable/apps/nix-snowflake.svg";
                custom_image_colorize = false;
              };
              workspaces = {
                show_labels = false;
                hide_when_empty = false;
              };
              battery.show_label = false;
              clock.format = "{:%H:%M}";
              clock.color = "primary";
            };
            weather.unit = "imperial";
            battery.warning_threshold = 30;
            dock.pinned = noctaliaCfg.pinnedApps;
            location.address = noctaliaCfg.location;
          };
        };
      }
      # stylix ships a noctalia v5 target, but only on master -- release-26.05
      # still has the v4-only one, which silently no-ops against
      # `programs.noctalia`. Do it ourselves until the next stylix release; then
      # this block becomes `stylix.targets.noctalia.enable = true;`.
      (mkIf config.stylix.enable {
        programs.noctalia = {
          settings = {
            theme = {
              source = "custom";
              custom_palette = "stylix";
              mode = if config.stylix.polarity == "light" then "light" else "dark";
            };
            shell.font_family = config.stylix.fonts.sansSerif.name;
            widget.clock.font_family = config.stylix.fonts.monospace.name;
            wallpaper = {
              enabled = true;
              default.path = config.stylix.image;
            };
          };

          # the palette parser requires a `dark` section, and requires each
          # section it finds to carry a `terminal` block.
          customPalettes.stylix.dark = with config.lib.stylix.colors.withHashtag; {
            mPrimary = base0D;
            mOnPrimary = base00;
            mSecondary = base0E;
            mOnSecondary = base00;
            mTertiary = base0C;
            mOnTertiary = base00;
            mError = base08;
            mOnError = base00;
            mSurface = base00;
            mOnSurface = base05;
            mHover = base0C;
            mOnHover = base00;
            mSurfaceVariant = base01;
            mOnSurfaceVariant = base04;
            mOutline = base03;
            mShadow = base00;

            terminal = {
              foreground = base05;
              background = base00;
              cursor = base05;
              cursorText = base00;
              selectionFg = base05;
              selectionBg = base02;
              normal = {
                black = base00;
                red = base08;
                green = base0B;
                yellow = base0A;
                blue = base0D;
                magenta = base0E;
                cyan = base0C;
                white = base05;
              };
              bright = {
                black = base03;
                red = base08;
                green = base0B;
                yellow = base0A;
                blue = base0D;
                magenta = base0E;
                cyan = base0C;
                white = base07;
              };
            };
          };
        };
      })
      (mkIf (cfg.launcher == "noctalia") {
        t11s.desktop._launcherCmd = "${lib.getExe noctalia} msg panel-toggle launcher";
      })
    ]
  );
}
