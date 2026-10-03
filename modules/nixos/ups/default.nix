{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.t11s.ups;
  nut = config.power.ups.package;
  inherit (config.power.ups) upsmon;

  upsName = "ups";
  tag = "t11s-ups";
  timer = "onbatt-timer";
  shuttingDown = cfg.mode == "shutdown";
  logger = "${pkgs.util-linux}/bin/logger -t ${tag}";

  events = [
    "ONLINE"
    "ONBATT"
    "LOWBATT"
    "COMMOK"
    "COMMBAD"
    "NOCOMM"
    "FSD"
    "SHUTDOWN"
  ];

  # Run by upssched as the upsmon user, with the EXECUTE/timer name as $1.
  # Only $1 is trusted: a timer fires from the long-lived upssched daemon,
  # whose NOTIFYTYPE is whatever event happened to start it.
  upsschedCmd = pkgs.writeShellScript "upssched-cmd" ''
    case "$1" in
      ${timer})
        ${
          if shuttingDown then
            ''
              ${logger} -p daemon.crit "on battery for ${toString cfg.shutdownAfterSeconds}s: forcing shutdown (upsmon -c fsd)"
              ${nut}/sbin/upsmon -c fsd
            ''
          else
            ''
              ${logger} -p daemon.warning "on battery for ${toString cfg.shutdownAfterSeconds}s: monitor mode, would have run upsmon -c fsd"
            ''
        }
        ;;
      *)
        ${logger} -p daemon.notice "event: $1"
        ;;
    esac
  '';

  # upsmon also shuts down by itself when the UPS reports low battery, so in
  # monitor mode SHUTDOWNCMD has to be inert too.
  monitorShutdownCmd = pkgs.writeShellScript "ups-monitor-shutdown" ''
    ${logger} -p daemon.crit "monitor mode: upsmon ran SHUTDOWNCMD, not shutting down"
  '';

  upsschedConf = pkgs.writeText "upssched.conf" ''
    CMDSCRIPT ${upsschedCmd}
    PIPEFN /run/upssched/upssched.pipe
    LOCKFN /run/upssched/upssched.lock

    AT ONBATT * START-TIMER ${timer} ${toString cfg.shutdownAfterSeconds}
    AT ONLINE * CANCEL-TIMER ${timer}

    ${lib.concatMapStringsSep "\n" (event: "AT ${event} * EXECUTE ${event}") events}
  '';
in
with lib;
{
  options.t11s.ups = {
    enable = mkEnableOption "standalone NUT for a USB HID UPS, shutting down on a fixed on-battery timer";
    mode = mkOption {
      type = types.enum [
        "monitor"
        "shutdown"
      ];
      default = "monitor";
      description = ''
        "monitor" only logs events (journal tag ${tag}) and never shuts the
        host down. "shutdown" powers the host off once it has been on battery
        for shutdownAfterSeconds, or as soon as the UPS reports low battery.
      '';
    };
    shutdownAfterSeconds = mkOption {
      type = types.ints.positive;
      default = 180;
      description = "seconds on battery before shutdown; cancelled if mains returns first";
    };
    killpower = mkOption {
      type = types.bool;
      default = false;
      description = ''
        At the end of a UPS-initiated shutdown, tell the UPS to cut and then
        restore its output, so a BIOS set to power on after AC loss boots the
        host again. Only takes effect in "shutdown" mode.
      '';
    };
  };

  config = mkIf cfg.enable {
    age.secrets."upsmon.password".file = ../../../secrets/upsmon.password.age;

    power.ups = {
      enable = true;
      mode = "standalone";

      # Goldenmate 1000VA LiFePO4 "Pro". The unit enumerates as 06da:ffff
      # (Phoenixtec), which usbhid-ups claims with its liebert subdriver; other
      # revisions are reported as 075d:0300 (idowell subdriver). Neither ID is
      # pinned here so either one is picked up.
      #
      # battery.runtime from this UPS is bogus. Do not add runtime-based
      # thresholds (ignorelb + override.battery.runtime.low and friends); the
      # on-battery timer below is the shutdown trigger.
      #
      # killpower does nothing on the 06da:ffff unit: its firmware accepts
      # writes to DelayBeforeShutdown/DelayBeforeStartup and ignores them (they
      # read back as the constants 1 and 257), so the output is never cut.
      ups.${upsName} = {
        driver = "usbhid-ups";
        port = "auto";
        description = "Goldenmate 1000VA LiFePO4";
      };

      upsd.listen = [
        { address = "127.0.0.1"; }
        { address = "::1"; }
      ];

      users.upsmon = {
        passwordFile = config.age.secrets."upsmon.password".path;
        upsmon = "primary";
      };

      upsmon.monitor.${upsName} = {
        system = "${upsName}@localhost";
        user = "upsmon";
        type = "primary";
      };

      upsmon.settings = {
        NOTIFYFLAG = map (event: [
          event
          "SYSLOG+EXEC"
        ]) events;
        SHUTDOWNCMD = mkIf (!shuttingDown) "${monitorShutdownCmd}";
        # The flag is what arms ups-killpower.service at shutdown. Leaving it
        # unset removes that unit, so a flag left behind by a monitor-mode
        # "shutdown" can never power-cycle the UPS on a later reboot.
        POWERDOWNFLAG = if shuttingDown && cfg.killpower then "/run/killpower" else null;
      };

      schedulerRules = "${upsschedConf}";
    };

    # upssched runs as the upsmon user and needs somewhere to keep its
    # pipe, lock and pid file; /run/nut and /var/lib/nut are root-only.
    systemd.tmpfiles.rules = [
      "d /run/upssched 0750 ${upsmon.user} ${upsmon.group} -"
    ];
    systemd.services.upsmon.environment.NUT_ALTPIDPATH = "/run/upssched";
  };
}
