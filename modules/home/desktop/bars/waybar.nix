{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.t11s.desktop;
in
lib.mkIf (cfg.enable && (cfg.bar == "waybar")) {
  home.packages =
    with pkgs;
    [
      nerd-fonts.ubuntu
      nerd-fonts.jetbrains-mono
    ]
    ++ (lib.optionals cfg.networkManager.enable [ networkmanagerapplet ]);
  services.blueman-applet.enable = cfg.bluetoothSupport.enable;
  programs.waybar = {
    enable = true;
    systemd = {
      enable = true;
      target = "graphical-session.target";
    };
    # {{{ waybar.settings
    settings = {
      mainBar = {
        layer = "top";
        position = "top";
        modules-left = [
          "hyprland/workspaces"
          "hyprland/submap"
          "niri/workspaces"
        ];
        modules-right = [
          "tray"
          "idle_inhibitor"
          "battery"
          "pulseaudio"
          "clock"
        ];
        modules-center = [
          "hyprland/window"
          "niri/window"
        ];
        clock = {
          format = "  {:%H:%M   %e %b}";
          today-format = "<b>{}</b>";
          tooltip-format = ''
            <big>{:%Y %B}</big>
            <tt><small>{calendar}</small></tt>'';
        };
        "hyprland/submap" = {
          format = ''<span style="italic">{}</span>'';
        };
        "hyprland/window" = {
          format = "{}";
          max-length = 80;
          min-length = 80;
          tooltip = false;
        };
        "niri/window" = {
          format = "{}";
          max-length = 80;
          min-length = 80;
          tooltip = false;
        };
        idle_inhibitor = {
          format = "{icon}";
          format-icons = {
            activated = "";
            deactivated = "";
          };
        };
        cpu = {
          interval = 1;
          format = ''{max_frequency}GHz <span color="darkgray">| {usage}%</span>'';
          max-length = 15;
          min-length = 15;
          on-click = "kitty -e htop --sort-key PERCENT_CPU";
          tooltip = false;
        };
        network = {
          format-disconnected = "";
          format-ethernet = "{ifname} ";
          format-wifi = "{essid} ({signalStrength}%) ";
          max-length = 50;
          #on-click = "kitty -e 'nmtui'";
        };
        battery = {
          full-at = 90;
          states = {
            warning = 30;
            critical = 15;
          };
        };
        pulseaudio = {
          format = "{volume}% {icon} ";
          format-bluetooth = "{volume}% {icon} {format_source}";
          format-bluetooth-muted = "🔇  {format_source}";
          format-icons = {
            car = "";
            default = [
              ""
              ""
              ""
            ];
            hands-free = "";
            headphone = "";
            headset = "";
            phone = "";
            portable = "";
          };
          format-muted = "🔇 ";
          format-source = "{volume}% ";
          format-source-muted = "";
          on-click = "pavucontrol";
        };
        tray = {
          icon-size = 15;
          spacing = 10;
        };
      };
    };
    # }}} waybar.settings
    # {{{ waybar.style
    style = ''
      * {
        border: none;
        font-family: Ubuntu Nerd Font, Roboto, Arial, sans-serif;
        font-size: 13px;
        border-radius: 1rem;
      }

      window#waybar > box {
        margin: 3px;
      }
      window#waybar {
          background: transparent;
        color: @text;
      }
      /*-----module groups----*/
      .modules-right {
        background-color: @surface0;
        margin: 2px 5px 0 0;
        box-shadow: 0 0 2px #000;
      }
      .modules-center {
        background-color: @surface0;
        margin: 2px 0 0 0;
        box-shadow: 0 0 2px #000;
      }
      .modules-left {
        margin: 2px 0 0 5px;
        background-color: @surface0;
        box-shadow: 0 0 2px #000;
      }
      /*-----modules indv----*/
      #workspaces button {
        font-weight: bold;
        color: @text;
        padding: 1px 5px;
      }
      #workspaces button:hover {
        background: none;
        box-shadow: none;
        text-shadow: none;
        color: @sapphire;
      }

      #workspaces button.active {
        color: @green;
      }

      #workspaces button.urgent {
        color: @red;
      }

      #clock,
      #battery,
      #cpu,
      #memory,
      #temperature,
      #network,
      #pulseaudio,
      #custom-media,
      #tray,
      #mode,
      #submap,
      #custom-power,
      #custom-menu,
      #idle_inhibitor {
          padding: 0 10px;
      }
      #submap, #mode {
          font-weight: bold;
      }
      /*-----Indicators----*/
      #idle_inhibitor.activated {
          color: @green;
      }
      #pulseaudio.muted {
          color: #cc3436;
      }
      #battery {
        color: @teal;
      }
      #battery.charging {
          color: @green;
      }
      #battery.warning:not(.charging) {
        color: @yellow;
      }
      #battery.critical:not(.charging) {
          color: @red;
      }
      #temperature.critical {
          color: @peach;
      }
    '';
    # }}} waybar.style
  };
}
