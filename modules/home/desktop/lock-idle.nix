{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) mkIf concatMapAttrsStringSep;
  cfg = config.t11s.desktop;
  # generate a bunch of scripts that do different things based on XDG_CURRENT_DESKTOP.
  # other modules (namely the compositors) will set these.
  mkCase = case: code: ''
    ${case})
      ${code}
      ;;
  '';
  mkDesktopSpecificScript =
    scriptName:
    pkgs.writeShellScript scriptName ''
      case $XDG_CURRENT_DESKTOP in
      ${concatMapAttrsStringSep "\n" (
        _key: desktop: mkCase desktop.desktopString desktop.${scriptName}
      ) cfg.lockAndIdle.desktopSpecific}
      esac
    '';
  dpmsOn = mkDesktopSpecificScript "dpmsOn";
  dpmsOff = mkDesktopSpecificScript "dpmsOff";
  afterSleepScript = mkDesktopSpecificScript "afterSleepScript";
in
{
  options.t11s.desktop.lockAndIdle =
    let
      inherit (lib) types mkOption mkEnableOption;
    in
    {
      enable = mkEnableOption "enable hypridle and hyprlock on idle";
      desktopSpecific = mkOption {
        description = "actions that get run depending on current desktop. detected via $XDG_SESSION_DESKTOP";
        type =
          with types;
          let
            mkActionOption =
              description:
              mkOption {
                inherit description;
                type = types.str;
              };
          in
          attrsOf (submodule {
            options = {
              desktopString = mkOption {
                description = "string to match with $XDG_SESSION_DESKTOP";
                type = str;
              };
              dpmsOn = mkActionOption "call to set dpms on";
              dpmsOff = mkActionOption "call to set dpms off";
              afterSleepScript = mkActionOption "call when waking up from sleep";
            };
          });
      };
    };
  config = mkIf (cfg.enable && cfg.lockAndIdle.enable) {
    home.packages = with pkgs; [
      nerd-fonts.ubuntu
      nerd-fonts.jetbrains-mono
    ];
    # {{{ hyprlock
    programs.hyprlock = {
      enable = true;
      settings = {
        "$font" = "JetBrainsMono Nerd Font";
        general = {
          disable_loading_bar = true;
          hide_cursor = true;
        };
        background = [
          {
            monitor = "";
            path =
              let
                wallpapers = pkgs.fetchFromGitHub {
                  owner = "zhichaoh";
                  repo = "catppuccin-wallpapers";
                  rev = "1023077979591cdeca76aae94e0359da1707a60e";
                  sha256 = "0rd6hfd88bsprjg68saxxlgf2c2lv1ldyr6a8i7m4lgg6nahbrw7";
                };
              in
              "${wallpapers}/patterns/line_icons.png";
            blur_passes = 0;
            color = "$base";
          }
        ];
        label = [
          {
            monitor = "";
            text = "$TIME";
            color = "$text";
            font_size = 90;
            font_family = "$font";
            position = "-30, 0";
            halign = "right";
            valign = "top";
          }
          {
            monitor = "";
            text = ''cmd[update:43200000] date +"%A, %d %B %Y"'';
            color = "$text";
            font_size = 25;
            font_family = "$font";
            position = "-30, -150";
            halign = "right";
            valign = "top";
          }
        ];
        image = [
          {
            monitor = "";
            path = "$HOME/.face";
            size = 100;
            border_color = "$accent";
            position = "0, 75";
            halign = "center";
            valign = "center";
          }
        ];
        input-field = [
          {
            monitor = "";
            size = "300, 60";
            outline_thickness = 4;
            dots_size = "0.2";
            dots_spacing = "0.2";
            dots_center = true;
            outer_color = "$overlay0";
            inner_color = "$surface0";
            font_color = "$text";
            fade_on_empty = false;
            placeholder_text = ''<span foreground="##$textAlpha"><i>󰌾 Logged in as </i><span foreground="##$accentAlpha">$USER</span></span>'';
            hide_input = false;
            check_color = "$accent";
            fail_color = "$red";
            fail_text = "<i>$FAIL <b>($ATTEMPTS)</b></i>";
            capslock_color = "$yellow";
            position = "0, -47";
            halign = "center";
            valign = "center";
          }
        ];
        auth = {
          "fingerprint:enabled" = true;
        };
      };
    };
    # }}} hyprlock

    # {{{ hypridle
    services.hypridle = {
      enable = true;
      settings = {
        general = {
          lock_cmd = "hyprlock";
          before_sleep_cmd = "loginctl lock-session";
          after_sleep_cmd = "${afterSleepScript}";
          ignore_dbus_inhibit = false;
          ignore_systemd_inhibit = false;
        };
        listener = [
          {
            timeout = 150; # 2.5min.
            on-timeout = "brightnessctl -s set 0"; # set monitor backlight to minimum
            on-resume = "brightnessctl -r"; # monitor backlight restore.
          }
          {
            timeout = 300;
            on-timeout = "loginctl lock-session";
          }
          {
            timeout = 330;
            on-timeout = "${dpmsOff}";
            on-resume = "${dpmsOn}";
          }
          {
            timeout = 1800;
            on-timeout = "systemcctl suspend-then-hibernate";
          }
        ];
      };
    };
    # }}}
  };
}
