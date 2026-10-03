{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.t11s.flakeUpdateBot;
  secret = name: config.age.secrets.${name}.path;
in
with lib;
{
  options.t11s.flakeUpdateBot = {
    enable = mkEnableOption "weekly flake.lock update PRs, gated on Hydra, with a Claude Code fix loop";
    repo = mkOption {
      type = types.str;
      example = "burk3/all-the-nix";
      description = "GitHub owner/name of the flake to update";
    };
    hosts = mkOption {
      type = types.listOf types.str;
      description = "hosts whose hydraJobs.nixos.<host> build gates the PR";
    };
    schedule = mkOption {
      type = types.str;
      default = "Sat 04:00";
      description = "systemd OnCalendar expression for the run";
    };
    maxFixAttempts = mkOption {
      type = types.ints.unsigned;
      default = 3;
      description = "how many times Claude Code may try to fix a failing build";
    };
  };

  config = mkIf cfg.enable {
    age.secrets."flake-update-bot-gh-token".file = ../../../secrets/flake-update-bot-gh-token.age;
    age.secrets."claude-oauth-token".file = ../../../secrets/claude-oauth-token.age;
    age.secrets."pushover-user-key".file = ../../../secrets/pushover-user-key.age;
    age.secrets."pushover-api-token".file = ../../../secrets/pushover-api-token.age;

    systemd.services.flake-update-bot = {
      description = "Weekly flake.lock update PR, gated on Hydra";
      wants = [ "network-online.target" ];
      after = [
        "network-online.target"
        "hydra-server.service"
      ];
      startAt = cfg.schedule;
      # The system profile supplies Determinate Nix and the shell tools Claude
      # Code's Bash tool expects.
      path = [ "/run/current-system/sw" ];
      environment = {
        FUB_REPO = cfg.repo;
        FUB_HOSTS = concatStringsSep " " cfg.hosts;
        FUB_MAX_FIX_ATTEMPTS = toString cfg.maxFixAttempts;
        FUB_HYDRA_URL = "http://127.0.0.1:${toString config.services.hydra.port}";
        FUB_HYDRA_PUBLIC_URL = config.services.hydra.hydraURL;
        # Outside the home directory on purpose: Claude is denied all of home,
        # which would otherwise include the clone it works in. The path is
        # also named in packages/flake-update-bot/claude-settings.json.
        FUB_STATE_DIR = "/var/lib/flake-update-bot";
      };
      serviceConfig = {
        Type = "oneshot";
        # Runs as the main user on purpose: it works in a clone under their
        # home and commits as them. systemd reads the secrets as root and
        # hands them over through the credentials directory.
        User = config.t11s.mainUser.name;
        ExecStart = getExe pkgs.t11s.flake-update-bot;
        TimeoutStartSec = "24h";
        StateDirectory = "flake-update-bot";
        LoadCredential = [
          "gh-token:${secret "flake-update-bot-gh-token"}"
          "claude-token:${secret "claude-oauth-token"}"
          "pushover-user:${secret "pushover-user-key"}"
          "pushover-token:${secret "pushover-api-token"}"
        ];
      };
    };
    systemd.timers.flake-update-bot.timerConfig.Persistent = true;

    # Claude Code launches its sandbox by running `bwrap` (and `socat`) from
    # the Bash tool's shell. That shell re-reads the login environment, which
    # resets PATH to the system profile and drops the package's own PATH, so
    # these must be installed system-wide.
    environment.systemPackages = [
      pkgs.bubblewrap
      pkgs.socat
    ];
  };
}
