{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) mkIf mkEnableOption getExe;
  cfg = config.t11s.desktop;
  brightnessctl = getExe pkgs.brightnessctl;
in
{
  # noctalia answers logind Lock/Unlock, inhibits sleep to lock first, and drives
  # screen power via each compositor's IPC -- nothing compositor-specific needed.
  options.t11s.desktop.lockAndIdle.enable = mkEnableOption "noctalia lock screen and idle daemon";

  config = mkIf (cfg.enable && cfg.lockAndIdle.enable) {
    programs.noctalia.settings = {
      lockscreen = {
        enabled = true;
        # drives fprintd itself over D-Bus; modules/nixos/base keeps
        # pam_fprintd out of the login stack so they do not fight over the sensor
        fingerprint = true;
        lock_before_suspend = true;
      };

      idle = {
        # ported from the hypridle listener chain this module used to define
        behavior_order = [
          "dim"
          "lock"
          "screen-off"
          "suspend"
        ];
        # timeouts must be floats; ints fail `noctalia config validate`
        behavior = {
          dim = {
            action = "command";
            # no PATH on the unit, so absolute
            command = "${brightnessctl} -s set 0";
            resume_command = "${brightnessctl} -r";
            enabled = true;
            timeout = 150.0;
          };
          lock = {
            action = "lock";
            enabled = true;
            timeout = 300.0;
          };
          "screen-off" = {
            action = "screen_off";
            enabled = true;
            timeout = 330.0;
          };
          suspend = {
            action = "lock_and_suspend";
            enabled = true;
            timeout = 1800.0;
          };
        };
      };

      # noctalia only auto-detects plain `systemctl suspend`, no hibernate path
      shell.session.power.suspend = "systemctl suspend-then-hibernate";
    };
  };
}
