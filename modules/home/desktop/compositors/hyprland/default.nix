# vim: foldmethod=marker
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.t11s.desktop.compositor.hyprland;
  hyprctl = "${pkgs.hyprland}/bin/hyprctl";
  jq = "${pkgs.jq}/bin/jq";
  # called when lid is closed
  lidSwitchOnScript = pkgs.writers.writeBash "lid-switch-on" ''
    log() {
      echo $(date --rfc-3339=seconds) lid-switch-on: "$@" >> /tmp/lid.log
    }
    # if this is running while the suspend target is still active, do nothing
    if systemctl is-active suspend ; then
      log suspend target active, exiting
      exit 0
    fi
    # if there is only one monitor, suspend the system
    # if there's more, just disable the internal monitor
    monitors_json=$(${hyprctl} -j monitors all)
    num_exts=$(${jq} 'map(select(.name != "eDP-1")) | length' <<< "$monitors_json")
    internal_enabled=$(${jq} -r '.[] | select(.name == "eDP-1") | .disabled==false' <<< "$monitors_json")
    log "$internal_enabled-$num_exts"
    case "$internal_enabled-$num_exts" in
      false-*)
        log 'false-*'
        log no internal monitor detected, assuming this is a delayed event and ignoring
        ;;
      true-0)
        log true-0
        systemctl suspend-then-hibernate
        ;;
      true-[1-9]*)
        log 'true-[1-9]*'
        log external monitors detected, disabling internal monitor
        ${hyprctl} keyword monitor "eDP-1, disable"
        ;;
      *)
        log 'fallback'
        ;;
    esac
  '';
  # called when lid is opened
  lidSwitchOffScript = pkgs.writers.writeBash "lid-switch-off" ''
    # if the internal monitor is disabled, enable it
    log() {
      echo $(date --rfc-3339=seconds) lid-switch-off: "$@" >> /tmp/lid.log
    }
    internal_disabled=$(${hyprctl} -j monitors all | ${jq} -r '.[] | select(.name == "eDP-1") | .disabled')
    log internal_disabled=$internal_disabled
    if [[ $internal_disabled != "false" ]]; then
      log enabling internal monitor
      ${hyprctl} keyword monitor "eDP-1,preferred,auto,auto"
    fi
  '';
  # UNWIRED: was hypridle's after_sleep_cmd; noctalia has no resume hook.
  afterSleepScript = pkgs.writers.writeBash "after-sleep" ''
    # handles waking up from sleep for various lid/monitor states
    # lid open,   intMon off, any number of extMons -> enable intMon
    # lid open,   intMon on,  any number of extMons -> do nothing
    # lid closed, intMon off, extMons == 0 -> enable intMon, suspend
    # lid closed, intMon on,  extMons == 0 -> suspend
    # lid closed, intMon off, extMons >= 1 -> noop
    # lid closed, intMon on,  extMons >= 1 -> disable intMon
    # FALLBACK -> turn on the internal monitor and dpms on

    lid_state=$(</proc/acpi/button/lid/LID0/state)
    lid=''${lid_state##* }
    monitors_json=$(${hyprctl} -j monitors all)
    internal_enabled=$(${jq} -r '.[] | select(.name == "eDP-1") | .disabled==false' <<< "$monitors_json")
    num_monitors=$(${jq} length <<< "$monitors_json")

    log() {
      echo $(date --rfc-3339=seconds) after-sleep: "$@" >> /tmp/lid.log
    }
    _enable_int() {
      log hyprctl keyword monitor "eDP-1,preferred,auto,auto"
      ${hyprctl} keyword monitor "eDP-1,preferred,auto,auto"
    }
    _disable_int() {
      log hyprctl keyword monitor "eDP-1, disable"
      ${hyprctl} keyword monitor "eDP-1, disable"
    }
    _dpms_on() {
      log hyprctl dispatch dpms on
      ${hyprctl} dispatch dpms on
    }
    _suspend() {
      log systemctl suspend-then-hibernate
      systemctl suspend-then-hibernate
    }

    log "$lid-$internal_enabled-$num_monitors"
    case "$lid-$internal_enabled-$num_monitors" in
      open-false-[1-9]*)
        log 'open-false-[1-9]*'
        _enable_int
        _dpms_on
        ;;
      open-true-[1-9]*)
        log 'open-true-[1-9]*'
        _dpms_on
        ;;
      closed-false-1)
        log 'closed-false-1'
        _enable_int
        _suspend
        ;;
      closed-true-1)
        log 'closed-true-1'
        _suspend
        ;;
      closed-false-[1-9]*)
        log 'closed-false-[1-9]*'
        ;;
      closed-true-[1-9]*)
        log 'closed-true-[1-9]*'
        _disable_int
        ;;
      *)
        log 'fallback'
        _enable_int
        _dpms_on
        ;;
    esac
  '';
in
with lib;
{
  options.t11s.desktop.compositor.hyprland.enable = mkEnableOption "enable hyprland config";
  config = mkIf cfg.enable {
    home.packages = with pkgs; [
      brightnessctl
      # hy3's tab bars render with this; nothing else here needs a nerd font
      nerd-fonts.ubuntu
    ];

    programs.fuzzel.enable = true;

    # {{{ hyprland
    wayland.windowManager.hyprland = {
      enable = true;
      # lua configType breaks hy3: HM 26.05 loads plugins after the config parses,
      # so hl.plugin.hy3.* is nil. Fixed on HM master (PR #9517), not backported.
      configType = "hyprlang";
      # uwsm owns the session targets; this would fight it with an exec-once
      # that restarts hyprland-session.target. Only the uwsm session works now.
      systemd.enable = false;
      # hyprexpo is gone from nixpkgs; it was gesture-only here anyway.
      # hyprspace/hycov are the packaged overview alternatives.
      plugins = with pkgs.hyprlandPlugins; [
        hy3
      ];
      settings =
        let
          terminal = "ghostty";
          fileManager = "nautilus";
          menu = config.t11s.desktop._launcherCmd;
          lock = "loginctl lock-session";
          # via noctalia IPC rather than wpctl/brightnessctl directly, for the OSD
          noctaliaMsg = "${lib.getExe config.programs.noctalia.package} msg";
        in
        {
          # {{{ hyprland.settings
          # (dropped exec-once nm-applet; noctalia has a network widget)
          monitor = ",preferred,auto,auto";
          env = [
            "XCURSOR_SIZE,32"
            "HYPRCURSOR_SIZE,32"
            "HYPRCURSOR_THEME,Posy_Cursor_Black"
          ];
          ecosystem.no_update_news = true;
          general = {
            gaps_in = 5;
            gaps_out = "11,15,15,15";
            border_size = 2;
            # Rosé Pine Moon, matching niri. Was $blueAlpha/etc from the
            # long-gone catppuccin module, which hyprlang could not resolve.
            "col.active_border" = "rgba(ea9a97ee) rgba(eb6f92ee) 45deg"; # rose -> love
            "col.inactive_border" = "rgba(56526eaa)"; # highlight high
            resize_on_border = false;
            allow_tearing = false;
            #layout = "dwindle";
            layout = "hy3";
          };
          decoration = {
            rounding = 5;
            active_opacity = "1.0";
            inactive_opacity = "1.0";
            shadow = {
              enabled = true;
              range = 4;
              render_power = 3;
              color = "rgba(1a1a1aee)";
            };
            blur = {
              enabled = true;
              size = 3;
              passes = 1;
              vibrancy = "0.1696";
            };
          };
          # inert under layout = hy3; kept for switching back. pseudotile was
          # dropped upstream with no replacement.
          dwindle = {
            preserve_split = true;
          };
          plugin.hy3 = {
            node_collapse_policy = 0;
            autotile = {
              enable = true;
              trigger_width = 800;
              trigger_height = 500;
            };
            tabs = {
              text_font = "Ubuntu Nerd Font";
              "col.focused" = "rgba(9ccfd8ee)"; # foam
              "col.urgent" = "rgba(eb6f92ee)"; # love
            };
          };
          master = {
            new_status = "master";
          };
          misc = {
            force_default_wallpaper = 0;
            disable_hyprland_logo = true;
          };
          input = {
            numlock_by_default = true;
            kb_layout = "us";
            follow_mouse = 1;
            sensitivity = 0;
            touchpad = {
              natural_scroll = true;
              tap-to-click = false; # thank god
              tap-and-drag = false;
              clickfinger_behavior = true; # click with 2/3 fingers for right/middle
              scroll_factor = "0.5"; # sloooow down
            };
          };
          # replaces gestures.workspace_swipe: <fingers>, <direction>, <action>.
          # 3-finger horizontal was the old default. bless up, fam
          gesture = [ "3, horizontal, workspace" ];
          # windowrulev2 -> windowrule: snake_case `<prop> = <val>` pairs with
          # matchers behind `match:`. Note match:float and match:pin, not -ing/-ned.
          windowrule = [
            # Ignore maximize requests from apps. You'll probably like this.
            "suppress_event = maximize, match:class = .*"
            # Fix some dragging issues with XWayland
            "no_focus = true, match:class = ^$, match:title = ^$, match:xwayland = true, match:float = true, match:fullscreen = false, match:pin = false"
            # mpv should just float i guess
            "float = true, match:class = mpv"
            "float = true, match:class = mame"
          ];
          "$mainMod" = "SUPER";
          bind = [
            "$mainMod, Return, exec, ${terminal}"
            "$mainMod SHIFT, C, hy3:killactive,"
            "$mainMod CONTROL, Q, exit,"
            "$mainMod, E, exec, ${fileManager}"
            "$mainMod, V, togglefloating,"
            "$mainMod, R, exec, ${menu}"
            "$mainMod, P, pseudo," # dwindle
            # togglesplit moved behind layoutmsg; inert under hy3 regardless
            "$mainMod, S, layoutmsg, togglesplit"
            "$mainMod SHIFT, Z, exec, ${lock}"
            "$mainMod, F, fullscreen"
            "$mainMod SHIFT, F, togglefloating"
            "$mainMod SHIFT, S, exec, ${noctaliaMsg} screenshot-region"
            # noctalia has no per-window capture, so hyprshot stays for this one
            "$mainMod CONTROL, S, exec, ${lib.getExe pkgs.hyprshot} -m window"
            "$mainMod ALT , S, exec, ${noctaliaMsg} screenshot-fullscreen"
            # Move focus with mainMod + vi move keys
            "$mainMod, H, hy3:movefocus, l"
            "$mainMod, L, hy3:movefocus, r"
            "$mainMod, K, hy3:movefocus, u"
            "$mainMod, J, hy3:movefocus, d"
            # and toggle focus for floats w/ mod+tab
            "$mainMod, Tab, hy3:togglefocuslayer, nowarp"
            # hy3 stuff
            "$mainMod+SHIFT, T, hy3:makegroup, tab"
            "$mainMod+SHIFT, E, hy3:makegroup, v"
            "$mainMod+SHIFT, W, hy3:makegroup, h"
            "$mainMod, A, hy3:changefocus, raise"
            "$mainMod+SHIFT, A, hy3:changefocus, lower"
            "$mainMod, D, hy3:expand, expand"
            "$mainMod+SHIFT, D, hy3:expand, base"
            "$mainMod+SHIFT, X, hy3:changegroup, opposite"
            "$mainMod+CONTROL, H, hy3:movefocus, l, visible, nowarp"
            "$mainMod+CONTROL, L, hy3:movefocus, r, visible, nowarp"
            "$mainMod+CONTROL, K, hy3:movefocus, u, visible, nowarp"
            "$mainMod+CONTROL, J, hy3:movefocus, d, visible, nowarp"
            "$mainMod+SHIFT, H, hy3:movewindow, l, once"
            "$mainMod+SHIFT, L, hy3:movewindow, r, once"
            "$mainMod+SHIFT, K, hy3:movewindow, u, once"
            "$mainMod+SHIFT, J, hy3:movewindow, d, once"
            "$mainMod+CONTROL+SHIFT, H, hy3:movewindow, l, once, visible"
            "$mainMod+CONTROL+SHIFT, L, hy3:movewindow, r, once, visible"
            "$mainMod+CONTROL+SHIFT, K, hy3:movewindow, u, once, visible"
            "$mainMod+CONTROL+SHIFT, J, hy3:movewindow, d, once, visible"
            "$mainMod+CONTROL, 1, hy3:focustab, 1"
            "$mainMod+CONTROL, 2, hy3:focustab, 2"
            "$mainMod+CONTROL, 3, hy3:focustab, 3"
            "$mainMod+CONTROL, 4, hy3:focustab, 4"
            "$mainMod+CONTROL, 5, hy3:focustab, 5"
            "$mainMod+CONTROL, 6, hy3:focustab, 6"
            "$mainMod+CONTROL, 7, hy3:focustab, 7"
            "$mainMod+CONTROL, 8, hy3:focustab, 8"
            "$mainMod+CONTROL, 9, hy3:focustab, 9"
            "$mainMod+CONTROL, 0, hy3:focustab, 10"
            # Switch workspaces with mainMod + [0-9]
            "$mainMod, 1, workspace, 1"
            "$mainMod, 2, workspace, 2"
            "$mainMod, 3, workspace, 3"
            "$mainMod, 4, workspace, 4"
            "$mainMod, 5, workspace, 5"
            "$mainMod, 6, workspace, 6"
            "$mainMod, 7, workspace, 7"
            "$mainMod, 8, workspace, 8"
            "$mainMod, 9, workspace, 9"
            "$mainMod, 0, workspace, 10"
            # Move active window to a workspace with mainMod + SHIFT + [0-9]
            "$mainMod SHIFT, 1, hy3:movetoworkspace, 1"
            "$mainMod SHIFT, 2, hy3:movetoworkspace, 2"
            "$mainMod SHIFT, 3, hy3:movetoworkspace, 3"
            "$mainMod SHIFT, 4, hy3:movetoworkspace, 4"
            "$mainMod SHIFT, 5, hy3:movetoworkspace, 5"
            "$mainMod SHIFT, 6, hy3:movetoworkspace, 6"
            "$mainMod SHIFT, 7, hy3:movetoworkspace, 7"
            "$mainMod SHIFT, 8, hy3:movetoworkspace, 8"
            "$mainMod SHIFT, 9, hy3:movetoworkspace, 9"
            "$mainMod SHIFT, 0, hy3:movetoworkspace, 10"
            # Example special workspace (scratchpad)
            "$mainMod, backslash, togglespecialworkspace, magic"
            "$mainMod SHIFT, backslash, hy3:movetoworkspace, special:magic"
            # Scroll through existing workspaces with mainMod + scroll
            "$mainMod, mouse_down, workspace, e+1"
            "$mainMod, mouse_up, workspace, e-1"
          ];
          bindm = [
            # Move/resize windows with mainMod + LMB/RMB and dragging
            "$mainMod, mouse:272, movewindow"
            "$mainMod, mouse:273, resizewindow"
          ];
          bindel = [
            # Laptop multimedia keys for volume and LCD brightness
            ",XF86AudioRaiseVolume, exec, ${noctaliaMsg} volume-up"
            ",XF86AudioLowerVolume, exec, ${noctaliaMsg} volume-down"
            ",XF86AudioMute, exec, ${noctaliaMsg} volume-mute"
            ",XF86AudioMicMute, exec, ${noctaliaMsg} mic-mute"
            ",XF86MonBrightnessUp, exec, ${noctaliaMsg} brightness-up"
            ",XF86MonBrightnessDown, exec, ${noctaliaMsg} brightness-down"
          ];
          bindl = [
            ", XF86AudioNext, exec, ${noctaliaMsg} media next"
            ", XF86AudioPause, exec, ${noctaliaMsg} media toggle"
            ", XF86AudioPlay, exec, ${noctaliaMsg} media toggle"
            ", XF86AudioPrev, exec, ${noctaliaMsg} media previous"
            # go to sleep when shut
            #", switch:on:Lid Switch, exec, systemctl suspend-then-hibernate"
            ", switch:on:Lid Switch, exec, ${lidSwitchOnScript}"
            ", switch:off:Lid Switch, exec, ${lidSwitchOffScript}"
          ];
          # }}} hyprland.settings
        };
    };
    # }}} hyprland
  };
}
